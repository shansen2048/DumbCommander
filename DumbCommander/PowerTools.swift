import CryptoKit
import Foundation

struct FileSearchRequest: Sendable, Equatable {
    let root: URL
    var namePattern: String
    var contentText: String
    var includesHidden: Bool
    var maximumResults: Int = 10_000
}

struct FileSearchProgress: Sendable {
    let visitedCount: Int
    let currentDirectory: URL
}

actor FileSearchService {
    private let fileSystem: any FileSystemServing
    private let maximumContentBytes = 4 * 1_024 * 1_024

    init(fileSystem: any FileSystemServing) {
        self.fileSystem = fileSystem
    }

    func search(
        _ request: FileSearchRequest,
        progress: @escaping @Sendable (FileSearchProgress) async -> Void = { _ in }
    ) async throws -> [FileItem] {
        var directories = [request.root.standardizedFileURL]
        var results: [FileItem] = []
        var visited = 0

        while let directory = directories.popLast() {
            try Task.checkCancellation()
            let items = try await fileSystem.contents(
                of: directory,
                showHiddenFiles: request.includesHidden
            )
            visited += items.count
            await progress(FileSearchProgress(visitedCount: visited, currentDirectory: directory))

            for item in items {
                try Task.checkCancellation()
                if item.isNavigableDirectory, !item.isPackage {
                    directories.append(item.url)
                }
                guard Self.matches(item.name, wildcard: request.namePattern) else { continue }
                guard try matchesContent(item, text: request.contentText) else { continue }
                results.append(item)
                if results.count >= max(1, request.maximumResults) {
                    return results
                }
            }
        }
        return results
    }

    private func matchesContent(_ item: FileItem, text: String) throws -> Bool {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        guard !item.isDirectory, !item.isSymbolicLink, item.size <= maximumContentBytes else {
            return false
        }
        let data = try Data(contentsOf: item.url, options: [.mappedIfSafe])
        guard let content = String(data: data, encoding: .utf8) else { return false }
        return content.localizedCaseInsensitiveContains(needle)
    }

    static func matches(_ name: String, wildcard rawPattern: String) -> Bool {
        let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty, pattern != "*" else { return true }
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: #"\*"#, with: ".*")
            .replacingOccurrences(of: #"\?"#, with: ".")
        return name.range(of: "^\(escaped)$", options: [.regularExpression, .caseInsensitive]) != nil
    }
}

enum DirectoryDifference: String, Sendable, CaseIterable {
    case onlyLeft
    case onlyRight
    case different
    case identical

    var title: String {
        switch self {
        case .onlyLeft: return "Nur links"
        case .onlyRight: return "Nur rechts"
        case .different: return "Unterschiedlich"
        case .identical: return "Identisch"
        }
    }
}

struct DirectoryComparisonEntry: Identifiable, Sendable {
    let name: String
    let left: FileItem?
    let right: FileItem?
    let difference: DirectoryDifference

    var id: String { name.lowercased() }
}

actor DirectoryComparisonService {
    private let fileSystem: any FileSystemServing

    init(fileSystem: any FileSystemServing) {
        self.fileSystem = fileSystem
    }

    func compare(left: URL, right: URL, showHiddenFiles: Bool) async throws
        -> [DirectoryComparisonEntry]
    {
        async let leftItems = fileSystem.contents(of: left, showHiddenFiles: showHiddenFiles)
        async let rightItems = fileSystem.contents(of: right, showHiddenFiles: showHiddenFiles)
        let (loadedLeft, loadedRight) = try await (leftItems, rightItems)
        let leftByName = Dictionary(uniqueKeysWithValues: loadedLeft.map { ($0.name, $0) })
        let rightByName = Dictionary(uniqueKeysWithValues: loadedRight.map { ($0.name, $0) })
        let names = Set(leftByName.keys).union(rightByName.keys)

        return names.map { name in
            let leftItem = leftByName[name]
            let rightItem = rightByName[name]
            let difference: DirectoryDifference
            switch (leftItem, rightItem) {
            case (.some, .none): difference = .onlyLeft
            case (.none, .some): difference = .onlyRight
            case let (.some(lhs), .some(rhs)):
                difference = Self.isEquivalent(lhs, rhs) ? .identical : .different
            case (.none, .none): difference = .identical
            }
            return DirectoryComparisonEntry(
                name: name,
                left: leftItem,
                right: rightItem,
                difference: difference
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func isEquivalent(_ lhs: FileItem, _ rhs: FileItem) -> Bool {
        guard lhs.isDirectory == rhs.isDirectory,
              lhs.isSymbolicLink == rhs.isSymbolicLink,
              lhs.size == rhs.size else { return false }
        switch (lhs.modificationDate, rhs.modificationDate) {
        case let (.some(left), .some(right)):
            return abs(left.timeIntervalSince(right)) < 1
        case (.none, .none):
            return true
        default:
            return false
        }
    }
}

enum RenameCaseMode: String, CaseIterable, Codable, Sendable {
    case unchanged
    case lowercase
    case uppercase

    var title: String {
        switch self {
        case .unchanged: return "Unverändert"
        case .lowercase: return "klein"
        case .uppercase: return "GROSS"
        }
    }
}

struct BatchRenameRule: Equatable, Sendable {
    var template = "[N]_[C]"
    var find = ""
    var replacement = ""
    var startIndex = 1
    var caseMode: RenameCaseMode = .unchanged
}

struct BatchRenamePreview: Identifiable, Sendable {
    let source: URL
    let proposedName: String
    let validationError: String?

    var id: URL { source }
    var destination: URL { source.deletingLastPathComponent().appendingPathComponent(proposedName) }
}

struct BatchRenameMapping: Sendable {
    let original: URL
    let renamed: URL
}

struct BatchRenameResult: Sendable {
    let mappings: [BatchRenameMapping]
    let errors: [String]
}

enum BatchRenamePlanner {
    static func previews(for sources: [URL], rule: BatchRenameRule) -> [BatchRenamePreview] {
        let sourceSet = Set(sources.map { $0.standardizedFileURL })
        var names: [String: Int] = [:]
        var provisional: [(URL, String)] = []

        for (offset, source) in sources.enumerated() {
            let extensionPart = source.pathExtension
            var stem = source.deletingPathExtension().lastPathComponent
            if !rule.find.isEmpty {
                stem = stem.replacingOccurrences(of: rule.find, with: rule.replacement)
            }
            switch rule.caseMode {
            case .unchanged: break
            case .lowercase: stem = stem.lowercased()
            case .uppercase: stem = stem.uppercased()
            }
            var name = rule.template
                .replacingOccurrences(of: "[N]", with: stem)
                .replacingOccurrences(of: "[E]", with: extensionPart)
                .replacingOccurrences(of: "[C]", with: String(rule.startIndex + offset))
            if !rule.template.contains("[E]"), !extensionPart.isEmpty {
                name += ".\(extensionPart)"
            }
            provisional.append((source, name))
            names[name, default: 0] += 1
        }

        return provisional.map { source, name in
            let destination = source.deletingLastPathComponent().appendingPathComponent(name)
            var error: String?
            if name.isEmpty || name == "." || name == ".." || name.contains("/") {
                error = "Ungültiger Dateiname"
            } else if names[name, default: 0] > 1 {
                error = "Der Zielname kommt mehrfach vor"
            } else if destination.standardizedFileURL != source.standardizedFileURL,
                      FileManager.default.fileExists(atPath: destination.path),
                      !sourceSet.contains(destination.standardizedFileURL) {
                error = "Das Ziel existiert bereits"
            }
            return BatchRenamePreview(source: source, proposedName: name, validationError: error)
        }
    }
}

actor BatchRenameService {
    private let fileSystem: any FileSystemServing

    init(fileSystem: any FileSystemServing) {
        self.fileSystem = fileSystem
    }

    func execute(_ previews: [BatchRenamePreview]) async -> BatchRenameResult {
        guard previews.allSatisfy({ $0.validationError == nil }) else {
            return BatchRenameResult(mappings: [], errors: ["Die Vorschau enthält ungültige Zielnamen."])
        }

        var staged: [(preview: BatchRenamePreview, temporary: URL)] = []
        var completed: [BatchRenameMapping] = []
        var errors: [String] = []

        for preview in previews where preview.source.lastPathComponent != preview.proposedName {
            do {
                try Task.checkCancellation()
                let temporary = preview.source.deletingLastPathComponent()
                    .appendingPathComponent(".dumbcommander-rename-\(UUID().uuidString)")
                _ = try await fileSystem.perform(
                    .rename(source: preview.source, destination: temporary, replaceExisting: false),
                    progress: { _ in }
                )
                staged.append((preview, temporary))
            } catch {
                errors.append("\(preview.source.lastPathComponent): \(error.localizedDescription)")
                break
            }
        }

        if errors.isEmpty {
            for entry in staged {
                do {
                    try Task.checkCancellation()
                    _ = try await fileSystem.perform(
                        .rename(
                            source: entry.temporary,
                            destination: entry.preview.destination,
                            replaceExisting: false
                        ),
                        progress: { _ in }
                    )
                    completed.append(
                        BatchRenameMapping(
                            original: entry.preview.source,
                            renamed: entry.preview.destination
                        )
                    )
                } catch {
                    errors.append("\(entry.preview.proposedName): \(error.localizedDescription)")
                    break
                }
            }
        }

        if !errors.isEmpty {
            await rollback(staged: staged, completed: completed)
            return BatchRenameResult(mappings: [], errors: errors)
        }
        return BatchRenameResult(mappings: completed, errors: [])
    }

    func undo(_ mappings: [BatchRenameMapping]) async -> BatchRenameResult {
        let previews = mappings.reversed().map {
            BatchRenamePreview(
                source: $0.renamed,
                proposedName: $0.original.lastPathComponent,
                validationError: nil
            )
        }
        return await execute(previews)
    }

    private func rollback(
        staged: [(preview: BatchRenamePreview, temporary: URL)],
        completed: [BatchRenameMapping]
    ) async {
        for mapping in completed.reversed() {
            _ = try? await fileSystem.perform(
                .rename(source: mapping.renamed, destination: mapping.original, replaceExisting: false),
                progress: { _ in }
            )
        }
        let completedOriginals = Set(completed.map(\.original))
        for entry in staged.reversed() where !completedOriginals.contains(entry.preview.source) {
            _ = try? await fileSystem.perform(
                .rename(source: entry.temporary, destination: entry.preview.source, replaceExisting: false),
                progress: { _ in }
            )
        }
    }
}

struct FileChecksum: Identifiable, Sendable {
    let url: URL
    let value: String
    var id: URL { url }
}

actor ChecksumService {
    func sha256(for urls: [URL]) async throws -> [FileChecksum] {
        var results: [FileChecksum] = []
        for url in urls {
            try Task.checkCancellation()
            var digest = SHA256()
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isDirectory != true else { continue }
            if values.isSymbolicLink == true {
                let destination = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                digest.update(data: Data(destination.utf8))
            } else {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                    try Task.checkCancellation()
                    digest.update(data: data)
                }
            }
            results.append(
                FileChecksum(url: url, value: digest.finalize().map { String(format: "%02x", $0) }.joined())
            )
        }
        return results
    }
}

struct ContentComparisonResult: Sendable {
    let identical: Bool
    let firstDifferenceOffset: UInt64?
}

actor ContentComparisonService {
    func compare(_ left: URL, _ right: URL) async throws -> ContentComparisonResult {
        let leftValues = try left.resourceValues(forKeys: [.isSymbolicLinkKey])
        let rightValues = try right.resourceValues(forKeys: [.isSymbolicLinkKey])
        if leftValues.isSymbolicLink == true || rightValues.isSymbolicLink == true {
            let lhs = leftValues.isSymbolicLink == true
                ? try FileManager.default.destinationOfSymbolicLink(atPath: left.path)
                : "\0regular:\(left.path)"
            let rhs = rightValues.isSymbolicLink == true
                ? try FileManager.default.destinationOfSymbolicLink(atPath: right.path)
                : "\0regular:\(right.path)"
            if lhs == rhs {
                return ContentComparisonResult(identical: true, firstDifferenceOffset: nil)
            }
            let leftBytes = Array(lhs.utf8)
            let rightBytes = Array(rhs.utf8)
            let count = min(leftBytes.count, rightBytes.count)
            let difference = (0..<count).first { leftBytes[$0] != rightBytes[$0] } ?? count
            return ContentComparisonResult(
                identical: false,
                firstDifferenceOffset: UInt64(difference)
            )
        }
        let leftHandle = try FileHandle(forReadingFrom: left)
        let rightHandle = try FileHandle(forReadingFrom: right)
        defer {
            try? leftHandle.close()
            try? rightHandle.close()
        }
        var offset: UInt64 = 0
        while true {
            try Task.checkCancellation()
            let lhs = try leftHandle.read(upToCount: 1_048_576) ?? Data()
            let rhs = try rightHandle.read(upToCount: 1_048_576) ?? Data()
            if lhs != rhs {
                let count = min(lhs.count, rhs.count)
                let difference = (0..<count).first { lhs[$0] != rhs[$0] } ?? count
                return ContentComparisonResult(
                    identical: false,
                    firstDifferenceOffset: offset + UInt64(difference)
                )
            }
            if lhs.isEmpty { return ContentComparisonResult(identical: true, firstDifferenceOffset: nil) }
            offset += UInt64(lhs.count)
        }
    }
}

enum CommandLineParserError: LocalizedError {
    case unfinishedQuote

    var errorDescription: String? {
        "Ein Anführungszeichen wurde nicht geschlossen."
    }
}

enum CommandLineParser {
    /// Zerlegt eine Befehlszeile ohne Shell-Auswertung. Dadurch werden weder
    /// Umleitungen noch Variablen oder Substitutionen unbemerkt ausgeführt.
    static func parse(_ input: String) throws -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var hasToken = false

        for character in input {
            if escaped {
                current.append(character)
                hasToken = true
                escaped = false
            } else if character == "\\" && quote != "'" {
                escaped = true
                hasToken = true
            } else if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                    hasToken = true
                } else {
                    current.append(character)
                }
            } else if character.isWhitespace, quote == nil {
                if hasToken {
                    result.append(current)
                    current = ""
                    hasToken = false
                }
            } else {
                current.append(character)
                hasToken = true
            }
        }
        if escaped { current.append("\\") }
        guard quote == nil else { throw CommandLineParserError.unfinishedQuote }
        if hasToken { result.append(current) }
        return result
    }
}

struct ProcessExecutionResult: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

enum ProcessExecutionError: LocalizedError {
    case couldNotStart(String)
    case failed(ProcessExecutionResult)

    var errorDescription: String? {
        switch self {
        case let .couldNotStart(message): return message
        case let .failed(result):
            return result.standardError.isEmpty
                ? "Prozess beendet mit Status \(result.exitCode)."
                : result.standardError
        }
    }
}

actor CommandRunner {
    func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL
    ) async throws -> ProcessExecutionResult {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            throw ProcessExecutionError.couldNotStart(error.localizedDescription)
        }

        return try await withTaskCancellationHandler {
            async let outputData = output.fileHandleForReading.readToEnd() ?? Data()
            async let errorData = error.fileHandleForReading.readToEnd() ?? Data()
            let exitCode: Int32 = await withCheckedContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            }
            let (capturedOutput, capturedError) = try await (outputData, errorData)
            let result = ProcessExecutionResult(
                exitCode: exitCode,
                standardOutput: String(decoding: capturedOutput, as: UTF8.self),
                standardError: String(decoding: capturedError, as: UTF8.self)
            )
            guard result.exitCode == 0 else { throw ProcessExecutionError.failed(result) }
            return result
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

enum ArchiveFormat: String, CaseIterable, Sendable {
    case zip
    case tar

    var title: String { rawValue.uppercased() }
}

struct ArchiveEntry: Identifiable, Sendable {
    let path: String
    var id: String { path }
    var isDirectory: Bool { path.hasSuffix("/") }
}

actor ArchiveService {
    private let runner = CommandRunner()

    func list(_ archive: URL) async throws -> [ArchiveEntry] {
        let result: ProcessExecutionResult
        switch archive.pathExtension.lowercased() {
        case "zip":
            result = try await runner.run(
                executable: URL(fileURLWithPath: "/usr/bin/unzip"),
                arguments: ["-Z1", archive.path],
                workingDirectory: archive.deletingLastPathComponent()
            )
        case "tar":
            result = try await runner.run(
                executable: URL(fileURLWithPath: "/usr/bin/tar"),
                arguments: ["-tf", archive.path],
                workingDirectory: archive.deletingLastPathComponent()
            )
        default:
            throw ProcessExecutionError.couldNotStart("Dieses Archivformat wird nicht unterstützt.")
        }
        return result.standardOutput.split(whereSeparator: \.isNewline).map {
            ArchiveEntry(path: String($0))
        }
    }

    func extract(_ archive: URL, to destination: URL) async throws {
        let entries = try await list(archive)
        guard entries.allSatisfy({ Self.isSafeArchivePath($0.path) }) else {
            throw ProcessExecutionError.couldNotStart("Das Archiv enthält unsichere Pfade.")
        }
        let existingTargets = entries.compactMap { entry -> String? in
            let target = destination.appendingPathComponent(entry.path).standardizedFileURL
            return FileManager.default.fileExists(atPath: target.path) ? entry.path : nil
        }
        guard existingTargets.isEmpty else {
            let preview = existingTargets.prefix(5).joined(separator: ", ")
            throw ProcessExecutionError.couldNotStart(
                "Entpacken abgebrochen: Ziele existieren bereits (\(preview))."
            )
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        if archive.pathExtension.lowercased() == "zip" {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", archive.path, destination.path],
                workingDirectory: destination
            )
        } else {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/usr/bin/tar"),
                arguments: ["-xf", archive.path, "-C", destination.path],
                workingDirectory: destination
            )
        }
    }

    func create(format: ArchiveFormat, sources: [URL], destination: URL) async throws {
        guard let first = sources.first else { return }
        let parent = first.deletingLastPathComponent()
        guard sources.allSatisfy({ $0.deletingLastPathComponent() == parent }) else {
            throw ProcessExecutionError.couldNotStart("Alle Quellen müssen im selben Verzeichnis liegen.")
        }
        switch format {
        case .zip:
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/usr/bin/zip"),
                arguments: ["-r", "-y", destination.path] + sources.map(\.lastPathComponent),
                workingDirectory: parent
            )
        case .tar:
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/usr/bin/tar"),
                arguments: ["-cf", destination.path] + sources.map(\.lastPathComponent),
                workingDirectory: parent
            )
        }
    }

    private static func isSafeArchivePath(_ path: String) -> Bool {
        guard !path.hasPrefix("/") else { return false }
        let components = NSString(string: path).standardizingPath.split(separator: "/")
        return components.first != ".."
    }
}

struct StoredSearchPattern: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var filePattern: String
    var contentText: String

    init(id: UUID = UUID(), name: String, filePattern: String, contentText: String) {
        self.id = id
        self.name = name
        self.filePattern = filePattern
        self.contentText = contentText
    }
}

struct CustomCommanderCommand: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var executablePath: String
    var arguments: [String]

    init(id: UUID = UUID(), title: String, executablePath: String, arguments: [String]) {
        self.id = id
        self.title = title
        self.executablePath = executablePath
        self.arguments = arguments
    }

    func expandedArguments(panelDirectory: URL, selectedFile: URL?) -> [String] {
        arguments.map {
            $0.replacingOccurrences(of: "%P", with: panelDirectory.path)
                .replacingOccurrences(of: "%F", with: selectedFile?.path ?? "")
        }
    }
}
