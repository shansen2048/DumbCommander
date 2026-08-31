import Foundation

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
    case notDirectory(URL)
    case destinationExists(URL)
    case sourceMissing(URL)
    case unsupportedOperation
    case partialMove(source: URL, destination: URL, reason: String)

    var errorDescription: String? {
        switch self {
        case let .symbolicLinkTraversalDenied(url):
            return "Symbolische Links werden nicht als Verzeichnis geöffnet: \(url.path)"
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
    func entryInfo(at url: URL) async throws -> FileSystemEntryInfo
    func estimatedSize(at url: URL) async throws -> Int64
    func itemExists(at url: URL) async -> Bool
    func uniqueDestination(for proposedURL: URL, isDirectory: Bool) async -> URL
    func perform(
        _ mutation: FileSystemMutation,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws -> FileSystemMutationResult
}

extension FileSystemServing {
    func entryInfo(at url: URL) async throws -> FileSystemEntryInfo {
        throw FileSystemServiceError.unsupportedOperation
    }

    func estimatedSize(at url: URL) async throws -> Int64 {
        throw FileSystemServiceError.unsupportedOperation
    }

    func itemExists(at url: URL) async -> Bool {
        false
    }

    func uniqueDestination(for proposedURL: URL, isDirectory: Bool) async -> URL {
        proposedURL
    }

    func perform(
        _ mutation: FileSystemMutation,
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

    init(
        fileManager: FileManager = .default,
        trashHandler: TrashHandler? = nil,
        moveHandler: MoveHandler? = nil,
        copyChunkSize: Int = 1_048_576,
        copyChunkDelay: Duration? = nil
    ) {
        self.fileManager = fileManager
        self.trashHandler = trashHandler
        self.moveHandler = moveHandler
        self.copyChunkSize = max(4_096, copyChunkSize)
        self.copyChunkDelay = copyChunkDelay
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
                isHidden: isHidden
            )
        }
    }

    func entryInfo(at url: URL) async throws -> FileSystemEntryInfo {
        try entryInfoSync(at: url)
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
        case .regularFile, .other:
            return max(1, info.size)
        }
    }

    func itemExists(at url: URL) async -> Bool {
        (try? entryInfoSync(at: url)) != nil
    }

    func uniqueDestination(for proposedURL: URL, isDirectory: Bool) async -> URL {
        if (try? entryInfoSync(at: proposedURL)) == nil {
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
            if (try? entryInfoSync(at: candidate)) == nil {
                return candidate
            }
            counter += 1
        }
    }

    func perform(
        _ mutation: FileSystemMutation,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws -> FileSystemMutationResult {
        let counter = ProgressCounter()
        switch mutation {
        case let .copy(source, destination, replaceExisting, mergeDirectories):
            if mergeDirectories {
                let issues = try await mergeDirectory(
                    source: source,
                    destination: destination,
                    moving: false,
                    counter: counter,
                    progress: progress
                )
                return FileSystemMutationResult(destination: destination, issues: issues)
            }
            try await copyWithPolicy(
                source: source,
                destination: destination,
                replaceExisting: replaceExisting,
                counter: counter,
                progress: progress
            )
            return FileSystemMutationResult(destination: destination)

        case let .move(source, destination, replaceExisting, mergeDirectories):
            if mergeDirectories {
                let issues = try await mergeDirectory(
                    source: source,
                    destination: destination,
                    moving: true,
                    counter: counter,
                    progress: progress
                )
                return FileSystemMutationResult(destination: destination, issues: issues)
            }
            try await moveWithPolicy(
                source: source,
                destination: destination,
                replaceExisting: replaceExisting,
                counter: counter,
                progress: progress
            )
            return FileSystemMutationResult(destination: destination)

        case let .rename(source, destination, replaceExisting):
            try Task.checkCancellation()
            guard (try? entryInfoSync(at: source)) != nil else {
                throw FileSystemServiceError.sourceMissing(source)
            }
            if replaceExisting {
                _ = try fileManager.replaceItemAt(destination, withItemAt: source)
            } else {
                guard (try? entryInfoSync(at: destination)) == nil else {
                    throw FileSystemServiceError.destinationExists(destination)
                }
                try fileManager.moveItem(at: source, to: destination)
            }
            await progress(1)
            return FileSystemMutationResult(destination: destination)

        case let .createDirectory(destination):
            try Task.checkCancellation()
            guard (try? entryInfoSync(at: destination)) == nil else {
                throw FileSystemServiceError.destinationExists(destination)
            }
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: false,
                attributes: nil
            )
            await progress(1)
            return FileSystemMutationResult(destination: destination)

        case let .trash(source):
            try Task.checkCancellation()
            guard (try? entryInfoSync(at: source)) != nil else {
                throw FileSystemServiceError.sourceMissing(source)
            }
            if let trashHandler {
                try trashHandler(source)
            } else {
                try fileManager.trashItem(at: source, resultingItemURL: nil)
            }
            await progress(1)
            return FileSystemMutationResult(destination: nil)
        }
    }

    private func copyWithPolicy(
        source: URL,
        destination: URL,
        replaceExisting: Bool,
        counter: ProgressCounter,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws {
        guard (try? entryInfoSync(at: source)) != nil else {
            throw FileSystemServiceError.sourceMissing(source)
        }

        if replaceExisting {
            let temporary = temporarySibling(of: destination)
            do {
                try await copyEntry(
                    source: source,
                    destination: temporary,
                    counter: counter,
                    progress: progress
                )
                try Task.checkCancellation()
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw error
            }
        } else {
            guard (try? entryInfoSync(at: destination)) == nil else {
                throw FileSystemServiceError.destinationExists(destination)
            }
            do {
                try await copyEntry(
                    source: source,
                    destination: destination,
                    counter: counter,
                    progress: progress
                )
            } catch {
                try? fileManager.removeItem(at: destination)
                throw error
            }
        }
    }

    private func moveWithPolicy(
        source: URL,
        destination: URL,
        replaceExisting: Bool,
        counter: ProgressCounter,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws {
        guard (try? entryInfoSync(at: source)) != nil else {
            throw FileSystemServiceError.sourceMissing(source)
        }

        if replaceExisting {
            try await copyWithPolicy(
                source: source,
                destination: destination,
                replaceExisting: true,
                counter: counter,
                progress: progress
            )
            do {
                try fileManager.removeItem(at: source)
            } catch {
                throw FileSystemServiceError.partialMove(
                    source: source,
                    destination: destination,
                    reason: error.localizedDescription
                )
            }
            return
        }

        guard (try? entryInfoSync(at: destination)) == nil else {
            throw FileSystemServiceError.destinationExists(destination)
        }

        do {
            if let moveHandler {
                try moveHandler(source, destination)
            } else {
                try fileManager.moveItem(at: source, to: destination)
            }
            let units = max(1, try await estimatedSize(at: destination))
            await progress(units)
        } catch let moveError {
            guard Self.isCrossDeviceMoveError(moveError) else {
                throw moveError
            }
            do {
                try await copyWithPolicy(
                    source: source,
                    destination: destination,
                    replaceExisting: false,
                    counter: counter,
                    progress: progress
                )
            } catch {
                try? fileManager.removeItem(at: destination)
                throw error
            }
            do {
                try fileManager.removeItem(at: source)
            } catch {
                throw FileSystemServiceError.partialMove(
                    source: source,
                    destination: destination,
                    reason: error.localizedDescription
                )
            }
        }
    }

    private func copyEntry(
        source: URL,
        destination: URL,
        counter: ProgressCounter,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws {
        try Task.checkCancellation()
        let info = try entryInfoSync(at: source)

        switch info.kind {
        case .symbolicLink:
            let linkDestination = try fileManager.destinationOfSymbolicLink(atPath: source.path)
            try fileManager.createSymbolicLink(
                atPath: destination.path,
                withDestinationPath: linkDestination
            )
            counter.value += max(1, info.size)
            await progress(counter.value)

        case .directory:
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: false,
                attributes: nil
            )
            for child in try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil
            ) {
                try await copyEntry(
                    source: child,
                    destination: destination.appendingPathComponent(child.lastPathComponent),
                    counter: counter,
                    progress: progress
                )
            }
            try copyAttributes(from: source, to: destination)

        case .regularFile, .other:
            guard fileManager.createFile(atPath: destination.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let sourceHandle = try FileHandle(forReadingFrom: source)
            let destinationHandle = try FileHandle(forWritingTo: destination)
            defer {
                try? sourceHandle.close()
                try? destinationHandle.close()
            }

            while true {
                try Task.checkCancellation()
                let data = try sourceHandle.read(upToCount: copyChunkSize) ?? Data()
                if data.isEmpty { break }
                try destinationHandle.write(contentsOf: data)
                counter.value += Int64(data.count)
                await progress(counter.value)
                if let copyChunkDelay {
                    try await Task.sleep(for: copyChunkDelay)
                }
            }
            try copyAttributes(from: source, to: destination)
        }
    }

    private func mergeDirectory(
        source: URL,
        destination: URL,
        moving: Bool,
        counter: ProgressCounter,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws -> [FileSystemMutationIssue] {
        try Task.checkCancellation()
        guard try entryInfoSync(at: source).kind == .directory,
              try entryInfoSync(at: destination).kind == .directory else {
            throw FileSystemServiceError.notDirectory(destination)
        }

        var issues: [FileSystemMutationIssue] = []
        for child in try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        ) {
            try Task.checkCancellation()
            let target = destination.appendingPathComponent(child.lastPathComponent)
            let childInfo = try entryInfoSync(at: child)
            let targetInfo = try? entryInfoSync(at: target)

            if targetInfo == nil {
                do {
                    if moving {
                        try await moveWithPolicy(
                            source: child,
                            destination: target,
                            replaceExisting: false,
                            counter: counter,
                            progress: progress
                        )
                    } else {
                        try await copyWithPolicy(
                            source: child,
                            destination: target,
                            replaceExisting: false,
                            counter: counter,
                            progress: progress
                        )
                    }
                } catch {
                    issues.append(
                        FileSystemMutationIssue(
                            source: child,
                            destination: target,
                            message: error.localizedDescription,
                            isSkippedConflict: false
                        )
                    )
                }
            } else if childInfo.kind == .directory, targetInfo?.kind == .directory {
                issues.append(contentsOf: try await mergeDirectory(
                    source: child,
                    destination: target,
                    moving: moving,
                    counter: counter,
                    progress: progress
                ))
            } else {
                issues.append(
                    FileSystemMutationIssue(
                        source: child,
                        destination: target,
                        message: "Bestehendes Ziel beim Zusammenführen übersprungen.",
                        isSkippedConflict: true
                    )
                )
            }
        }

        if moving {
            let remaining = try fileManager.contentsOfDirectory(atPath: source.path)
            if remaining.isEmpty {
                try fileManager.removeItem(at: source)
            }
        }
        return issues
    }

    private func entryInfoSync(at url: URL) throws -> FileSystemEntryInfo {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let attributeType = attributes[.type] as? FileAttributeType
            let kind: FileSystemEntryKind
            switch attributeType {
            case .typeSymbolicLink:
                kind = .symbolicLink
            case .typeDirectory:
                kind = .directory
            case .typeRegular:
                kind = .regularFile
            default:
                kind = .other
            }
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            return FileSystemEntryInfo(url: url.standardizedFileURL, kind: kind, size: size)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw FileSystemServiceError.sourceMissing(url)
        } catch {
            throw error
        }
    }

    private func copyAttributes(from source: URL, to destination: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: source.path)
        var preserved: [FileAttributeKey: Any] = [:]
        for key in [
            FileAttributeKey.posixPermissions,
            .modificationDate,
            .creationDate
        ] {
            if let value = attributes[key] {
                preserved[key] = value
            }
        }
        if !preserved.isEmpty {
            try fileManager.setAttributes(preserved, ofItemAtPath: destination.path)
        }
    }

    private func temporarySibling(of destination: URL) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(
            ".dumbcommander-\(UUID().uuidString)-\(destination.lastPathComponent)"
        )
    }

    private static func isCrossDeviceMoveError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EXDEV) {
            return true
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isCrossDeviceMoveError(underlyingError)
        }
        return false
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

    private final class ProgressCounter: @unchecked Sendable {
        var value: Int64 = 0
    }
}
