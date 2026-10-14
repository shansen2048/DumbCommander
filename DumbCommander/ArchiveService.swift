import Foundation
import Darwin
import SystemArchive

struct ArchiveLimits: Sendable {
    var entries = 100_000
    var expandedBytes: Int64 = 20 * 1_024 * 1_024 * 1_024
    var pathBytes = 4_096
}

struct ArchiveSafetyError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct ArchiveMember: Equatable {
    let path: String
    let kind: FileSystemEntryKind
    let size: Int64
    let link: String?
    let permissions: mode_t
    let modified: timespec

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.path == rhs.path && lhs.kind == rhs.kind && lhs.size == rhs.size && lhs.link == rhs.link
    }
}

private final class ArchiveReader {
    let handle: OpaquePointer
    let file: FileDescriptor

    init(_ url: URL) throws {
        let parent = try SafeDirectory(url: url.deletingLastPathComponent())
        file = try parent.openFile(url.lastPathComponent, flags: O_RDONLY)
        guard try file.identity.kind == .regularFile else { throw SafeFileError.unsupported(url) }
        guard let reader = archive_read_new() else { throw ArchiveSafetyError(message: "Archivleser konnte nicht angelegt werden.") }
        handle = reader
        archive_read_support_filter_none(reader)
        archive_read_support_format_zip(reader)
        archive_read_support_format_tar(reader)
        guard archive_read_open_fd(reader, file.raw, 65_536) == 0 else {
            let message = archive_error_string(reader).map { String(cString: $0) } ?? "Archiv konnte nicht gelesen werden."
            throw ArchiveSafetyError(message: message)
        }
    }

    deinit { archive_read_free(handle) }

    func check(_ status: Int32) throws {
        guard status == 0 else {
            throw ArchiveSafetyError(message: archive_error_string(handle).map { String(cString: $0) } ?? "Ungültiges Archiv.")
        }
    }

    func next() throws -> ArchiveMember? {
        var entry: OpaquePointer?
        let status = archive_read_next_header(handle, &entry)
        if status == 1 { return nil }
        try check(status)
        guard let entry, let raw = archive_entry_pathname(entry), let path = String(validatingCString: raw) else {
            throw ArchiveSafetyError(message: "Archiv enthält einen ungültigen Dateinamen.")
        }
        guard archive_entry_hardlink(entry) == nil else {
            throw ArchiveSafetyError(message: "Hardlinks im Archiv werden aus Sicherheitsgründen nicht entpackt: \(path)")
        }
        let kind: FileSystemEntryKind
        switch archive_entry_filetype(entry) {
        case S_IFREG: kind = .regularFile
        case S_IFDIR: kind = .directory
        case S_IFLNK: kind = .symbolicLink
        default: throw ArchiveSafetyError(message: "Nicht unterstützter Archiveintrag: \(path)")
        }
        return ArchiveMember(path: try ArchiveService.safePath(path), kind: kind,
            size: archive_entry_size(entry), link: archive_entry_symlink(entry).map { String(cString: $0) },
            permissions: archive_entry_perm(entry),
            modified: timespec(tv_sec: archive_entry_mtime(entry), tv_nsec: archive_entry_mtime_nsec(entry)))
    }
}

actor ArchiveService {
    private let fileSystem: any FileSystemServing
    private let limits: ArchiveLimits

    init(fileSystem: any FileSystemServing = LocalFileSystemService(), limits: ArchiveLimits = ArchiveLimits()) {
        self.fileSystem = fileSystem
        self.limits = limits
    }

    func list(_ archive: URL) async throws -> [ArchiveEntry] {
        try manifest(archive).map { ArchiveEntry(path: $0.path + ($0.kind == .directory ? "/" : "")) }
    }

    @discardableResult
    func extract(
        _ archive: URL, to destination: URL,
        progress: @escaping @Sendable (Int64) async -> Void = { _ in }
    ) async throws -> FileOperationReport {
        let members = try manifest(archive)
        let parent = try SafeDirectory(url: destination.deletingLastPathComponent())
        let destinationInfo = try parent.identity(destination.lastPathComponent)
        let destinationDirectory: SafeDirectory?
        if let destinationInfo {
            guard destinationInfo.kind == .directory else { throw FileSystemServiceError.notDirectory(destination) }
            destinationDirectory = try SafeDirectory(parent: parent, name: destination.lastPathComponent)
        } else { destinationDirectory = nil }
        let roots = Set(members.map { String($0.path.split(separator: "/")[0]) }).sorted()
        if let destinationDirectory {
            for name in roots where try destinationDirectory.identity(name) != nil {
                throw FileSystemServiceError.destinationExists(destination.appendingPathComponent(name))
            }
        }
        let workspace = try FileWorkspace(in: parent)
        do {
            try workspace.directory.makeDirectory("unpacked")
            let payload = try SafeDirectory(parent: workspace.directory, name: "unpacked")
            try await unpack(archive, members: members, into: payload, progress: progress)
            try Task.checkCancellation()
            // Use the same plan/execution boundary as direct moves. No implicit replace or merge.
            let coordinator = FileOperationCoordinator(fileSystem: fileSystem)
            let request: FileOperationRequest
            if let destinationDirectory {
                guard try SafeDirectory(url: destination).descriptor.identity.sameObject(as: destinationDirectory.descriptor.identity) else {
                    throw SafeFileError.changed(destination)
                }
                request = .move(roots.map { payload.url.appendingPathComponent($0) }, to: destination)
            } else {
                // Rename the complete staged directory to the requested, previously absent name.
                if destination.lastPathComponent != "unpacked" {
                    try workspace.directory.move("unpacked", to: workspace.directory, named: destination.lastPathComponent)
                }
                request = .move([workspace.directory.url.appendingPathComponent(destination.lastPathComponent)], to: parent.url)
            }
            let plan = await coordinator.plan(request)
            let report = await coordinator.execute(plan, decisions: [:], progress: { value in await progress(value.completedUnits) })
            try workspace.finish()
            return report
        } catch { try workspace.finish(after: error); throw error }
    }

    @discardableResult
    func create(
        format: ArchiveFormat, sources: [URL], destination: URL,
        progress: @escaping @Sendable (Int64) async -> Void = { _ in }
    ) async throws -> FileOperationReport {
        guard !sources.isEmpty else { throw ArchiveSafetyError(message: "Keine Archivquellen ausgewählt.") }
        try SafeDirectory.validate(destination.lastPathComponent)
        let parent = try SafeDirectory(url: destination.deletingLastPathComponent())
        guard try parent.identity(destination.lastPathComponent) == nil else { throw FileSystemServiceError.destinationExists(destination) }
        let workspace = try FileWorkspace(in: parent)
        do {
            try workspace.directory.makeDirectory("input")
            let input = try SafeDirectory(parent: workspace.directory, name: "input")
            let coordinator = FileOperationCoordinator(fileSystem: fileSystem)
            let copyPlan = await coordinator.plan(.copy(sources, to: input.url))
            let copyReport = await coordinator.execute(copyPlan, decisions: [:], progress: { value in await progress(value.completedUnits) })
            guard copyReport.failedCount == 0, !copyReport.cancelled,
                  copyReport.succeededCount == sources.count else {
                throw ArchiveSafetyError(message: "Archivquellen konnten nicht vollständig gesichert werden: " +
                    copyReport.items.compactMap(\.message).joined(separator: "; "))
            }
            try Task.checkCancellation()
            let staged = workspace.directory.url.appendingPathComponent(destination.lastPathComponent)
            let names = try input.names().map { "./" + $0 }
            let arguments = format == .zip
                ? ["-q", "-r", "-y", staged.path, "--"] + names
                : ["-cf", staged.path, "--"] + names
            _ = try await CommandRunner().run(executable: URL(fileURLWithPath: format == .zip ? "/usr/bin/zip" : "/usr/bin/tar"),
                                              arguments: arguments, workingDirectory: input.url)
            try Task.checkCancellation()
            let plan = await coordinator.plan(.move([staged], to: parent.url))
            let report = await coordinator.execute(plan, decisions: [:], progress: { value in await progress(value.completedUnits) })
            try workspace.finish()
            return report
        } catch { try workspace.finish(after: error); throw error }
    }

    static func safePath(_ raw: String) throws -> String {
        guard !raw.hasPrefix("/"), !raw.contains("\\"), !raw.contains("\0") else {
            throw ArchiveSafetyError(message: "Unsicherer Archivpfad: \(raw)")
        }
        let parts = raw.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.contains("..") else { throw ArchiveSafetyError(message: "Unsicherer Archivpfad: \(raw)") }
        let normalized = parts.filter { $0 != "." }
        guard !normalized.isEmpty, !(normalized[0].count >= 2 && normalized[0].dropFirst().first == ":") else {
            throw ArchiveSafetyError(message: "Unsicherer Archivpfad: \(raw)")
        }
        return normalized.joined(separator: "/")
    }

    private func manifest(_ archive: URL) throws -> [ArchiveMember] {
        let reader = try ArchiveReader(archive)
        var members: [ArchiveMember] = []
        var paths: Set<String> = []
        var total: Int64 = 0
        while let member = try reader.next() {
            try Task.checkCancellation()
            guard members.count < limits.entries, member.path.utf8.count <= limits.pathBytes,
                  member.size >= 0, member.size <= limits.expandedBytes - total else {
                throw ArchiveSafetyError(message: "Das Archiv überschreitet die Grenze für Einträge, Pfadlänge oder entpackte Größe.")
            }
            // Canonical Unicode and folded case avoid aliases on common macOS target volumes.
            let key = member.path.precomposedStringWithCanonicalMapping.lowercased()
            guard paths.insert(key).inserted else { throw ArchiveSafetyError(message: "Doppelter Archivpfad: \(member.path)") }
            total += member.size
            members.append(member)
            try reader.check(archive_read_data_skip(reader.handle))
        }
        let byPath = Dictionary(uniqueKeysWithValues: members.map { ($0.path.precomposedStringWithCanonicalMapping.lowercased(), $0) })
        for member in members {
            let parts = member.path.split(separator: "/")
            for end in 1..<parts.count {
                let parent = parts.prefix(end).joined(separator: "/").precomposedStringWithCanonicalMapping.lowercased()
                if let entry = byPath[parent], entry.kind != .directory {
                    throw ArchiveSafetyError(message: "Archivpfad führt durch eine Datei oder einen Link: \(member.path)")
                }
            }
            if member.kind == .symbolicLink {
                var visited: Set<String> = [member.path]
                var current = member
                for _ in 0..<40 {
                    let target = try safeLink(current)
                    guard visited.insert(target).inserted else { throw ArchiveSafetyError(message: "Linkzyklus im Archiv: \(member.path)") }
                    guard let next = byPath[target.lowercased()], next.kind == .symbolicLink else { break }
                    current = next
                    guard visited.count < 40 else { throw ArchiveSafetyError(message: "Zu viele Linkverweise im Archiv.") }
                }
            }
        }
        return members
    }

    private func safeLink(_ member: ArchiveMember) throws -> String {
        guard let link = member.link, !link.isEmpty, !link.hasPrefix("/"), !link.contains("\\"),
              !link.split(separator: "/").contains("..") else {
            throw ArchiveSafetyError(message: "Unsicheres Archiv-Linkziel: \(member.path)")
        }
        var path = member.path.split(separator: "/").dropLast().map(String.init)
        for part in link.split(separator: "/") {
            if part == ".." {
                guard !path.isEmpty else { throw ArchiveSafetyError(message: "Archivlink verlässt den Zielordner: \(member.path)") }
                path.removeLast()
            } else if part != "." { path.append(String(part)) }
        }
        return path.joined(separator: "/")
    }

    private func unpack(
        _ archive: URL, members: [ArchiveMember], into payload: SafeDirectory,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws {
        let reader = try ArchiveReader(archive)
        let original = try reader.file.identity
        var index = 0
        var total: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while let member = try reader.next() {
            try Task.checkCancellation()
            guard index < members.count, member == members[index] else { throw SafeFileError.changed(archive) }
            index += 1
            let parts = member.path.split(separator: "/").map(String.init)
            var parent = payload
            for name in parts.dropLast() {
                if try parent.identity(name) == nil { try parent.makeDirectory(name) }
                parent = try SafeDirectory(parent: parent, name: name)
            }
            let name = parts.last!
            if member.kind == .directory {
                if try parent.identity(name) == nil { try parent.makeDirectory(name, mode: 0o755) }
            } else if member.kind == .regularFile {
                let output = try parent.openFile(name, flags: O_WRONLY | O_CREAT | O_EXCL)
                var count: Int64 = 0
                while true {
                    try Task.checkCancellation()
                    let read = archive_read_data(reader.handle, &buffer, buffer.count)
                    guard read >= 0 else { try reader.check(Int32(read)); break }
                    if read == 0 { break }
                    guard Int64(read) <= limits.expandedBytes - total, Int64(read) <= member.size - count else {
                        throw ArchiveSafetyError(message: "Entpackte Daten überschreiten die angekündigte Größe.")
                    }
                    count += Int64(read); total += Int64(read)
                    try buffer.withUnsafeBytes { bytes in
                        var offset = 0
                        while offset < read {
                            let written = Darwin.write(output.raw, bytes.baseAddress!.advanced(by: offset), read - offset)
                            if written < 0, errno == EINTR { continue }
                            guard written > 0 else { throw SafeDirectory.posixError() }
                            offset += written
                        }
                    }
                    await progress(total)
                }
                guard count == member.size else { throw ArchiveSafetyError(message: "Unvollständiger Archiveintrag: \(member.path)") }
                guard fchmod(output.raw, 0o600 | (member.permissions & 0o177)) == 0 else { throw SafeDirectory.posixError() }
                var times = [member.modified, member.modified]
                guard futimens(output.raw, &times) == 0, fsync(output.raw) == 0 else { throw SafeDirectory.posixError() }
            }
        }
        guard index == members.count, try reader.file.identity == original else { throw SafeFileError.changed(archive) }
        // Links are materialized last and can never be a parent of another archive entry.
        for member in members where member.kind == .symbolicLink {
            let parts = member.path.split(separator: "/").map(String.init)
            var parent = payload
            for name in parts.dropLast() { parent = try SafeDirectory(parent: parent, name: name) }
            try parent.makeLink(parts.last!, target: member.link!)
        }
    }
}
