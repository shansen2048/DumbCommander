import Foundation
import Darwin

enum FileSystemEntryKind: String, Sendable {
    case regularFile
    case directory
    case symbolicLink
    case other
}

struct FileSystemEntryInfo: Sendable {
    let url: URL
    let kind: FileSystemEntryKind
    let size: Int64
    var identity: FileIdentity? = nil
}

struct MountedVolume: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String

    var id: URL { url }
}

enum FileSystemMutation: Sendable {
    case copy(
        source: URL,
        destination: URL,
        replaceExisting: Bool,
        mergeDirectories: Bool
    )
    case move(
        source: URL,
        destination: URL,
        replaceExisting: Bool,
        mergeDirectories: Bool
    )
    case rename(source: URL, destination: URL, replaceExisting: Bool)
    case createDirectory(destination: URL)
    case trash(source: URL)
}

struct FileSystemMutationIssue: Sendable {
    let source: URL
    let destination: URL?
    let message: String
    let isSkippedConflict: Bool
}

struct FileSystemMutationResult: Sendable {
    let destination: URL?
    var issues: [FileSystemMutationIssue] = []
}

enum FileSystemServiceError: LocalizedError, Sendable {
    case symbolicLinkTraversalDenied(URL)
    case symbolicLinkCycle(URL)
    case symbolicLinkResolutionLimit(URL)
    case symbolicLinkTargetUnavailable(link: URL, reason: String)
    case notDirectory(URL)
    case destinationExists(URL)
    case sourceMissing(URL)
    case unsupportedOperation
    case partialMove(source: URL, destination: URL, reason: String)

    var errorDescription: String? {
        switch self {
        case let .symbolicLinkTraversalDenied(url):
            return "Symbolische Links werden nicht als Verzeichnis geöffnet: \(url.path)"
        case let .symbolicLinkCycle(url):
            return "Das Linkziel enthält einen Zyklus: \(url.path)"
        case let .symbolicLinkResolutionLimit(url):
            return "Das Linkziel konnte nach zu vielen Verweisen nicht bestimmt werden: \(url.path)"
        case let .symbolicLinkTargetUnavailable(link, reason):
            return "Das Ziel des symbolischen Links ist nicht verfügbar (\(link.path)): \(reason)"
        case let .notDirectory(url):
            return "Der Pfad ist kein Verzeichnis: \(url.path)"
        case let .destinationExists(url):
            return "Das Ziel existiert bereits: \(url.path)"
        case let .sourceMissing(url):
            return "Die Quelle existiert nicht mehr: \(url.path)"
        case .unsupportedOperation:
            return "Diese Dateisystemoperation wird von der Testimplementierung nicht unterstützt."
        case let .partialMove(source, destination, reason):
            return "Das Ziel wurde erstellt, aber die Quelle konnte nicht entfernt werden (\(source.path) → \(destination.path)): \(reason)"
        }
    }
}

protocol FileSystemServing: Sendable {
    func contents(of directory: URL, showHiddenFiles: Bool) async throws -> [FileItem]
    func mountedVolumes() async -> [MountedVolume]
    func entryInfo(at url: URL) async throws -> FileSystemEntryInfo
    func entryTree(at url: URL) async throws -> [String: FileIdentity]
    func resolvedEntry(at url: URL) async throws -> FileSystemEntryInfo
    func estimatedSize(at url: URL) async throws -> Int64
    func itemExists(at url: URL) async throws -> Bool
    func uniqueDestination(for proposedURL: URL, isDirectory: Bool) async throws -> URL
    func perform(
        _ mutation: FileSystemMutation,
        expectation: MutationExpectation?,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws -> FileSystemMutationResult
}

extension FileSystemServing {
    func entryTree(at url: URL) async throws -> [String: FileIdentity] {
        if let identity = try await entryInfo(at: url).identity { return ["": identity] }
        return [:]
    }
    func mountedVolumes() async -> [MountedVolume] {
        [MountedVolume(url: URL(fileURLWithPath: "/", isDirectory: true), name: "Macintosh")]
    }

    func entryInfo(at url: URL) async throws -> FileSystemEntryInfo {
        throw FileSystemServiceError.unsupportedOperation
    }

    func resolvedEntry(at url: URL) async throws -> FileSystemEntryInfo {
        try await entryInfo(at: url)
    }

    func estimatedSize(at url: URL) async throws -> Int64 {
        throw FileSystemServiceError.unsupportedOperation
    }

    func itemExists(at url: URL) async throws -> Bool {
        false
    }

    func uniqueDestination(for proposedURL: URL, isDirectory: Bool) async throws -> URL {
        proposedURL
    }

    func perform(
        _ mutation: FileSystemMutation,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws -> FileSystemMutationResult {
        try await perform(mutation, expectation: nil, progress: progress)
    }

    func perform(
        _ mutation: FileSystemMutation,
        expectation: MutationExpectation?,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws -> FileSystemMutationResult {
        throw FileSystemServiceError.unsupportedOperation
    }

}

actor LocalFileSystemService: FileSystemServing {
    typealias TrashHandler = @Sendable (URL) throws -> Void
    typealias MoveHandler = @Sendable (URL, URL) throws -> Void

    private let fileManager: FileManager
    private let trashHandler: TrashHandler?
    private let moveHandler: MoveHandler?
    private let copyChunkSize: Int
    private let copyChunkDelay: Duration?
    private let hooks: FileMutationHooks

    init(
        fileManager: FileManager = .default,
        trashHandler: TrashHandler? = nil,
        moveHandler: MoveHandler? = nil,
        copyChunkSize: Int = 1_048_576,
        copyChunkDelay: Duration? = nil,
        hooks: FileMutationHooks = FileMutationHooks()
    ) {
        self.fileManager = fileManager
        self.trashHandler = trashHandler
        self.moveHandler = moveHandler
        let slowUITest = ProcessInfo.processInfo.environment["DUMBCOMMANDER_UI_TESTING"] == "1"
            && ProcessInfo.processInfo.environment["DUMBCOMMANDER_TEST_SLOW_COPY"] == "1"
        self.copyChunkSize = slowUITest ? 65_536 : max(4_096, copyChunkSize)
        self.copyChunkDelay = slowUITest ? .milliseconds(100) : copyChunkDelay
        self.hooks = hooks
    }

    func contents(of directory: URL, showHiddenFiles: Bool) async throws -> [FileItem] {
        let directoryInfo = try entryInfoSync(at: directory)
        guard directoryInfo.kind != .symbolicLink else {
            throw FileSystemServiceError.symbolicLinkTraversalDenied(directory)
        }
        guard directoryInfo.kind == .directory else {
            throw FileSystemServiceError.notDirectory(directory)
        }

        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .isHiddenKey,
            .isPackageKey,
            .isAliasFileKey,
            .isSymbolicLinkKey
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: []
        )

        return try urls.compactMap { url in
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: keys)
            let info = try entryInfoSync(at: url)
            let isSymbolicLink = info.kind == .symbolicLink
            let isHidden = url.lastPathComponent.hasPrefix(".") || values.isHidden == true
            if isHidden && !showHiddenFiles {
                return nil
            }

            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let permissions = Self.permissionsString(from: attributes?[.posixPermissions] as? NSNumber)

            return FileItem(
                url: url.standardizedFileURL,
                name: url.lastPathComponent,
                pathExtension: url.pathExtension,
                size: info.size,
                modificationDate: values.contentModificationDate,
                permissions: permissions,
                isDirectory: info.kind == .directory,
                isPackage: values.isPackage == true,
                isSymbolicLink: isSymbolicLink,
                isAlias: values.isAliasFile == true,
                isHidden: isHidden
            )
        }
    }

    func mountedVolumes() async -> [MountedVolume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey]
        let urls = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? [URL(fileURLWithPath: "/", isDirectory: true)]

        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let fallback = url.path == "/" ? "Startvolume" : url.lastPathComponent
            return MountedVolume(
                url: url.standardizedFileURL,
                name: values?.volumeName ?? fallback
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func entryInfo(at url: URL) async throws -> FileSystemEntryInfo {
        try entryInfoSync(at: url)
    }

    func entryTree(at url: URL) async throws -> [String: FileIdentity] {
        try SafeDirectory(url: url.deletingLastPathComponent()).tree(url.lastPathComponent)
    }

    func resolvedEntry(at url: URL) async throws -> FileSystemEntryInfo {
        let original = url.standardizedFileURL
        var candidate = original
        var visitedPaths: Set<String> = []

        for _ in 0..<40 {
            try Task.checkCancellation()
            guard visitedPaths.insert(candidate.path).inserted else {
                throw FileSystemServiceError.symbolicLinkCycle(original)
            }

            let info: FileSystemEntryInfo
            do {
                info = try entryInfoSync(at: candidate)
            } catch {
                guard candidate != original else { throw error }
                throw FileSystemServiceError.symbolicLinkTargetUnavailable(
                    link: original,
                    reason: error.localizedDescription
                )
            }
            guard info.kind == .symbolicLink else { return info }

            do {
                let destination = try fileManager.destinationOfSymbolicLink(atPath: candidate.path)
                if (destination as NSString).isAbsolutePath {
                    candidate = URL(fileURLWithPath: destination).standardizedFileURL
                } else {
                    candidate = candidate.deletingLastPathComponent()
                        .appendingPathComponent(destination)
                        .standardizedFileURL
                }
            } catch {
                throw FileSystemServiceError.symbolicLinkTargetUnavailable(
                    link: original,
                    reason: error.localizedDescription
                )
            }
        }

        throw FileSystemServiceError.symbolicLinkResolutionLimit(original)
    }

    func estimatedSize(at url: URL) async throws -> Int64 {
        try Task.checkCancellation()
        let info = try entryInfoSync(at: url)
        switch info.kind {
        case .symbolicLink:
            return max(1, info.size)
        case .directory:
            var total: Int64 = 0
            for child in try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            ) {
                total += try await estimatedSize(at: child)
            }
            return max(1, total)
        case .regularFile:
            return max(1, info.size)
        case .other:
            throw SafeFileError.unsupported(url)
        }
    }

    func itemExists(at url: URL) async throws -> Bool {
        try entryIfPresent(at: url) != nil
    }

    func uniqueDestination(for proposedURL: URL, isDirectory: Bool) async throws -> URL {
        if try entryIfPresent(at: proposedURL) == nil {
            return proposedURL
        }

        let parent = proposedURL.deletingLastPathComponent()
        let originalName = proposedURL.lastPathComponent
        let pathExtension = isDirectory ? "" : proposedURL.pathExtension
        let baseName: String
        if pathExtension.isEmpty {
            baseName = originalName
        } else {
            baseName = String(originalName.dropLast(pathExtension.count + 1))
        }

        var counter = 1
        while true {
            let suffix = counter == 1 ? " Kopie" : " Kopie \(counter)"
            let candidateName = pathExtension.isEmpty
                ? baseName + suffix
                : baseName + suffix + "." + pathExtension
            let candidate = parent.appendingPathComponent(candidateName)
            if try entryIfPresent(at: candidate) == nil {
                return candidate
            }
            counter += 1
        }
    }

    func perform(
        _ mutation: FileSystemMutation,
        expectation: MutationExpectation?,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws -> FileSystemMutationResult {
        try Task.checkCancellation()
        let transfer = SafeTransfer(hooks: hooks, chunkSize: copyChunkSize,
                                    chunkDelay: copyChunkDelay, moveHandler: moveHandler)
        switch mutation {
        case let .copy(source, destination, replacing, merging),
             let .move(source, destination, replacing, merging):
            let moving: Bool
            if case .move = mutation { moving = true } else { moving = false }
            if merging {
                return FileSystemMutationResult(destination: destination, issues: try await mergeDirectory(
                    source: source, destination: destination, moving: moving,
                    expectation: expectation, transfer: transfer, progress: progress
                ))
            }
            try await transfer.transfer(source: source, destination: destination, moving: moving,
                                        replacing: replacing, expectation: expectation, progress: progress)
            return FileSystemMutationResult(destination: destination)
        case let .rename(source, destination, replacing):
            try await transfer.transfer(source: source, destination: destination, moving: true,
                                        replacing: replacing, expectation: expectation, progress: progress)
            return FileSystemMutationResult(destination: destination)
        case let .createDirectory(destination):
            let parent = try SafeDirectory(url: destination.deletingLastPathComponent())
            if let expected = expectation?.destinationParent,
               try !parent.descriptor.identity.sameObject(as: expected) { throw SafeFileError.changed(parent.url) }
            try hooks.beforePublish?(destination)
            try parent.makeDirectory(destination.lastPathComponent, mode: 0o755)
            await progress(1)
            return FileSystemMutationResult(destination: destination)
        case let .trash(source):
            let parent = try SafeDirectory(url: source.deletingLastPathComponent())
            _ = try parent.require(source.lastPathComponent, expected: expectation?.source)
            if let trashHandler { try trashHandler(source) }
            else { try fileManager.trashItem(at: source, resultingItemURL: nil) }
            await progress(1)
            return FileSystemMutationResult(destination: nil)
        }
    }

    private func mergeDirectory(
        source: URL, destination: URL, moving: Bool, expectation: MutationExpectation?,
        transfer: SafeTransfer, progress: @escaping @Sendable (Int64) async -> Void
    ) async throws -> [FileSystemMutationIssue] {
        try Task.checkCancellation()
        let sourceInfo = try entryInfoSync(at: source)
        let targetInfo = try entryInfoSync(at: destination)
        guard sourceInfo.kind == .directory, targetInfo.kind == .directory else {
            throw FileSystemServiceError.notDirectory(destination)
        }
        if let expected = expectation?.source, sourceInfo.identity != expected { throw SafeFileError.changed(source) }
        if let expected = expectation?.destination, targetInfo.identity != expected { throw SafeFileError.changed(destination) }
        if let expected = expectation?.sourceTree, try await entryTree(at: source) != expected { throw SafeFileError.changed(source) }
        if let expected = expectation?.destinationTree, try await entryTree(at: destination) != expected { throw SafeFileError.changed(destination) }
        let from = try SafeDirectory(url: source)
        let to = try SafeDirectory(url: destination)
        guard try from.descriptor.identity.sameObject(as: sourceInfo.identity!),
              try to.descriptor.identity.sameObject(as: targetInfo.identity!) else { throw SafeFileError.changed(destination) }
        // The service also enforces self-copy protection when called without a coordinator.
        let sourcePath = from.url.path
        guard to.url.path != sourcePath, !to.url.path.hasPrefix(sourcePath + "/") else { throw SafeFileError.changed(destination) }
        var issues: [FileSystemMutationIssue] = []
        for name in try from.names() {
            try Task.checkCancellation()
            let child = from.url.appendingPathComponent(name)
            let target = to.url.appendingPathComponent(name)
            do {
                let childInfo = try from.require(name)
                let targetInfo = try to.identity(name)
                let expected = MutationExpectation(source: childInfo, destination: targetInfo,
                    sourceParent: try from.descriptor.identity, destinationParent: try to.descriptor.identity)
                if targetInfo == nil {
                    try await transfer.transfer(source: child, destination: target, moving: moving,
                                                replacing: false, expectation: expected, progress: progress)
                } else if childInfo.kind == .directory, targetInfo?.kind == .directory {
                    issues += try await mergeDirectory(source: child, destination: target, moving: moving,
                                                       expectation: expected, transfer: transfer, progress: progress)
                } else {
                    issues.append(FileSystemMutationIssue(source: child, destination: target,
                        message: "Bestehendes Ziel beim Zusammenführen übersprungen.", isSkippedConflict: true))
                }
            } catch is CancellationError { throw CancellationError() }
            catch {
                issues.append(FileSystemMutationIssue(source: child, destination: target,
                    message: error.localizedDescription, isSkippedConflict: false))
            }
        }
        if moving, try from.names().isEmpty {
            let parent = try SafeDirectory(url: source.deletingLastPathComponent())
            guard try parent.require(source.lastPathComponent).sameObject(as: sourceInfo.identity!) else {
                throw SafeFileError.changed(source)
            }
            // rmdir cannot delete a directory that gained another entry in the meantime.
            guard unlinkat(parent.descriptor.raw, source.lastPathComponent, AT_REMOVEDIR) == 0 else {
                throw SafeDirectory.posixError()
            }
        }
        return issues
    }

    private func entryIfPresent(at url: URL) throws -> FileSystemEntryInfo? {
        if url.standardizedFileURL.path == "/" {
            let directory = try SafeDirectory(url: url)
            let identity = try directory.descriptor.identity
            return FileSystemEntryInfo(url: url, kind: identity.kind, size: identity.size, identity: identity)
        }
        let parent = try SafeDirectory(url: url.deletingLastPathComponent())
        guard let identity = try parent.identity(url.lastPathComponent) else { return nil }
        return FileSystemEntryInfo(url: url.standardizedFileURL, kind: identity.kind,
                                   size: identity.size, identity: identity)
    }

    private func entryInfoSync(at url: URL) throws -> FileSystemEntryInfo {
        guard let info = try entryIfPresent(at: url) else { throw FileSystemServiceError.sourceMissing(url) }
        return info
    }

    private static func permissionsString(from number: NSNumber?) -> String {
        guard let permissions = number?.uint16Value else { return "N/A" }
        let owner = (permissions & S_IRWXU) >> 6
        let group = (permissions & S_IRWXG) >> 3
        let others = permissions & S_IRWXO

        func rwx(_ value: UInt16) -> String {
            let read = (value & 0b100) != 0 ? "r" : "-"
            let write = (value & 0b010) != 0 ? "w" : "-"
            let execute = (value & 0b001) != 0 ? "x" : "-"
            return read + write + execute
        }

        return rwx(owner) + rwx(group) + rwx(others)
    }

}
