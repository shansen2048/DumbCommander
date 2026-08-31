import Foundation

struct FileOperationFailure: Equatable, Sendable {
    let source: URL
    let message: String
}

struct FileOperationResult: Equatable, Sendable {
    var succeeded: [URL] = []
    var failures: [FileOperationFailure] = []

    var isEmpty: Bool {
        succeeded.isEmpty && failures.isEmpty
    }
}

protocol FileSystemServing: Sendable {
    func contents(of directory: URL, showHiddenFiles: Bool) async throws -> [FileItem]
    func copy(_ sources: [URL], to destinationDirectory: URL) async -> FileOperationResult
    func move(_ sources: [URL], to destinationDirectory: URL) async -> FileOperationResult
    func rename(_ source: URL, to newName: String) async -> FileOperationResult
    func createDirectory(in parent: URL, preferredName: String) async -> FileOperationResult
    func moveToTrash(_ sources: [URL]) async -> FileOperationResult
}

actor LocalFileSystemService: FileSystemServing {
    typealias TrashHandler = @Sendable (URL) throws -> Void

    private let fileManager: FileManager
    private let trashHandler: TrashHandler?

    init(
        fileManager: FileManager = .default,
        trashHandler: TrashHandler? = nil
    ) {
        self.fileManager = fileManager
        self.trashHandler = trashHandler
    }

    func contents(of directory: URL, showHiddenFiles: Bool) async throws -> [FileItem] {
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
            let values = try url.resourceValues(forKeys: keys)
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
                size: Int64(values.fileSize ?? 0),
                modificationDate: values.contentModificationDate,
                permissions: permissions,
                isDirectory: values.isDirectory == true,
                isPackage: values.isPackage == true,
                isSymbolicLink: values.isSymbolicLink == true,
                isHidden: isHidden
            )
        }
    }

    func copy(_ sources: [URL], to destinationDirectory: URL) async -> FileOperationResult {
        performTransfer(sources, to: destinationDirectory, operation: fileManager.copyItem)
    }

    func move(_ sources: [URL], to destinationDirectory: URL) async -> FileOperationResult {
        performTransfer(sources, to: destinationDirectory, operation: fileManager.moveItem)
    }

    func rename(_ source: URL, to newName: String) async -> FileOperationResult {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedName.contains("/") else {
            return FileOperationResult(failures: [
                FileOperationFailure(source: source, message: "Der neue Name ist ungültig.")
            ])
        }

        let destination = source.deletingLastPathComponent().appendingPathComponent(trimmedName)
        guard !fileManager.fileExists(atPath: destination.path) else {
            return FileOperationResult(failures: [
                FileOperationFailure(source: source, message: "Das Ziel existiert bereits: \(trimmedName)")
            ])
        }

        do {
            try fileManager.moveItem(at: source, to: destination)
            return FileOperationResult(succeeded: [destination])
        } catch {
            return failureResult(for: source, error: error)
        }
    }

    func createDirectory(in parent: URL, preferredName: String) async -> FileOperationResult {
        var destination = parent.appendingPathComponent(preferredName)
        var suffix = 1
        while fileManager.fileExists(atPath: destination.path) {
            destination = parent.appendingPathComponent("\(preferredName) \(suffix)")
            suffix += 1
        }

        do {
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: false,
                attributes: nil
            )
            return FileOperationResult(succeeded: [destination])
        } catch {
            return failureResult(for: destination, error: error)
        }
    }

    func moveToTrash(_ sources: [URL]) async -> FileOperationResult {
        var result = FileOperationResult()
        for source in sources {
            do {
                if let trashHandler {
                    try trashHandler(source)
                } else {
                    try fileManager.trashItem(at: source, resultingItemURL: nil)
                }
                result.succeeded.append(source)
            } catch {
                result.failures.append(
                    FileOperationFailure(source: source, message: error.localizedDescription)
                )
            }
        }
        return result
    }

    private func performTransfer(
        _ sources: [URL],
        to destinationDirectory: URL,
        operation: (URL, URL) throws -> Void
    ) -> FileOperationResult {
        var result = FileOperationResult()

        for source in sources {
            let normalizedSource = source.standardizedFileURL
            let destination = destinationDirectory
                .appendingPathComponent(source.lastPathComponent)
                .standardizedFileURL

            if Self.isSameOrDescendant(destination, of: normalizedSource) {
                result.failures.append(
                    FileOperationFailure(
                        source: source,
                        message: "Ein Verzeichnis kann nicht in sich selbst kopiert oder verschoben werden."
                    )
                )
                continue
            }

            if fileManager.fileExists(atPath: destination.path) {
                result.failures.append(
                    FileOperationFailure(
                        source: source,
                        message: "Das Ziel existiert bereits: \(destination.lastPathComponent)"
                    )
                )
                continue
            }

            do {
                try operation(source, destination)
                result.succeeded.append(destination)
            } catch {
                result.failures.append(
                    FileOperationFailure(source: source, message: error.localizedDescription)
                )
            }
        }

        return result
    }

    private func failureResult(for source: URL, error: Error) -> FileOperationResult {
        FileOperationResult(failures: [
            FileOperationFailure(source: source, message: error.localizedDescription)
        ])
    }

    private static func isSameOrDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        let directoryPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath == directoryPath || candidatePath.hasPrefix(directoryPath + "/")
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
