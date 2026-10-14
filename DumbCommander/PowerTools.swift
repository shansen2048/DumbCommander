import CryptoKit
import Foundation
import Darwin

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
    var identity: FileIdentity? = nil
}

enum BatchRenameOutcome: String, Sendable {
    case unchanged, renamed, restored, recoveryRequired, unavailable
}

struct BatchRenameItemResult: Identifiable, Sendable {
    let original: URL
    let requested: URL
    var current: URL?
    var identity: FileIdentity?
    var outcome: BatchRenameOutcome
    var messages: [String] = []
    var id: URL { original }
}

struct BatchRenameResult: Sendable {
    let items: [BatchRenameItemResult]
    let cancelled: Bool
    var recoveryJournal: URL? = nil
    var mappings: [BatchRenameMapping] {
        items.filter { $0.outcome == .renamed }.compactMap { item in
            item.current.map { BatchRenameMapping(original: item.original, renamed: $0, identity: item.identity) }
        }
    }
    var errors: [String] { items.flatMap { item in item.messages.map { item.original.lastPathComponent + ": " + $0 } } }
}

/// The write-ahead candidate list survives a crash between rename and result recording.
/// Recovery never follows this file automatically; inode identities must be checked again.
private final class BatchRenameJournal: @unchecked Sendable {
    private let workspace: FileWorkspace
    private var records: [String: [String: Any]] = [:]
    private var candidates: [String: Set<String>] = [:]
    var url: URL { workspace.directory.url.appendingPathComponent("recovery.json") }

    init(items: [BatchRenameItemResult]) throws {
        guard let first = items.first else { throw SafeFileError.invalidName("") }
        workspace = try FileWorkspace(in: SafeDirectory(url: first.original.deletingLastPathComponent()))
        for item in items { try record(item, next: item.current ?? item.original) }
    }

    func record(_ item: BatchRenameItemResult, next: URL) throws {
        let key = item.original.path
        candidates[key, default: []].formUnion([item.original.path, item.requested.path, next.path])
        if let current = item.current { candidates[key, default: []].insert(current.path) }
        records[key] = [
            "original": key, "requested": item.requested.path, "current": item.current?.path ?? "",
            "candidates": candidates[key, default: []].sorted(),
            "device": item.identity.map { String($0.device) } ?? "",
            "inode": item.identity.map { String($0.inode) } ?? "",
            "messages": item.messages
        ]
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1, "entries": records.keys.sorted().compactMap { records[$0] },
            "instruction": "Pfade nur nach Vergleich von device/inode verwenden. Keine fremden Ziele überschreiben."
        ], options: [.prettyPrinted, .sortedKeys])
        let name = UUID().uuidString + ".json"
        let file = try workspace.directory.openFile(name, flags: O_WRONLY | O_CREAT | O_EXCL)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(file.raw, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw SafeDirectory.posixError() }
                offset += written
            }
        }
        guard fsync(file.raw) == 0,
              renameat(workspace.directory.descriptor.raw, name, workspace.directory.descriptor.raw, "recovery.json") == 0,
              fsync(workspace.directory.descriptor.raw) == 0 else { throw SafeDirectory.posixError() }
    }

    func finish() throws { try workspace.finish() }
}

enum BatchRenamePlanner {
    static func previews(for sources: [URL], rule: BatchRenameRule) -> [BatchRenamePreview] {
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
            var error: String?
            if name.isEmpty || name == "." || name == ".." || (name.contains("/") || name.contains("\0")) {
                error = "Ungültiger Dateiname"
            } else if names[name, default: 0] > 1 {
                error = "Der Zielname kommt mehrfach vor"

            }
            return BatchRenamePreview(source: source, proposedName: name, validationError: error)
        }
    }
}

actor BatchRenameService {
    private let fileSystem: any FileSystemServing

    init(fileSystem: any FileSystemServing) { self.fileSystem = fileSystem }

    func execute(_ previews: [BatchRenamePreview]) async -> BatchRenameResult {
        var items = previews.map {
            BatchRenameItemResult(original: $0.source, requested: $0.destination,
                                  current: $0.source, outcome: .unchanged)
        }
        var currentIndex: Int?
        var journal: BatchRenameJournal?
        do {
            var destinations: Set<String> = []
            var sources: Set<URL> = []
            for index in previews.indices {
                currentIndex = index
                try Task.checkCancellation()
                let preview = previews[index]
                try SafeDirectory.validate(preview.proposedName)
                guard preview.validationError == nil, sources.insert(preview.source.standardizedFileURL).inserted,
                      destinations.insert(preview.destination.path.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                    throw SafeFileError.invalidName(preview.proposedName)
                }
                items[index].identity = try await fileSystem.entryInfo(at: preview.source).identity
            }
            for item in items {
                guard !items.contains(where: { $0.original != item.original && item.original.path.hasPrefix($0.original.path + "/") }) else {
                    throw SafeFileError.changed(item.original)
                }
                if try await fileSystem.itemExists(at: item.requested) {
                    let target = try await fileSystem.entryInfo(at: item.requested)
                    guard items.contains(where: { candidate in
                        if candidate.original == item.requested { return true }
                        guard let actual = target.identity, let expected = candidate.identity else { return false }
                        return actual.sameObject(as: expected)
                    }) else { throw FileSystemServiceError.destinationExists(item.requested) }
                }
            }
            if !items.isEmpty { journal = try BatchRenameJournal(items: items) }
            for index in items.indices where items[index].original != items[index].requested {
                currentIndex = index
                try Task.checkCancellation()
                let temporary = items[index].original.deletingLastPathComponent()
                    .appendingPathComponent(".dumbcommander-rename-" + UUID().uuidString)
                try await Self.rename(&items[index], to: temporary, using: fileSystem, journal: journal)
            }
            for index in items.indices where items[index].original != items[index].requested {
                currentIndex = index
                try Task.checkCancellation()
                try await Self.rename(&items[index], to: items[index].requested, using: fileSystem, journal: journal)
                items[index].outcome = .renamed
            }
            do { try journal?.finish() }
            catch {
                items[0].messages.append(error.localizedDescription)
                return BatchRenameResult(items: items, cancelled: false, recoveryJournal: journal?.url)
            }
            return BatchRenameResult(items: items, cancelled: false)
        } catch {
            if let index = currentIndex ?? items.indices.last {
                items[index].messages.append(error is CancellationError ? "Abgebrochen; Wiederherstellung wurde ausgeführt." : error.localizedDescription)
            }
            let pending = items
            let service = fileSystem
            // A cancelled task must never cancel its own recovery operations.
            let recoveryLog = journal
            var restored = await Task.detached { await Self.restore(pending, using: service, journal: recoveryLog) }.value
            var retained = journal?.url
            if restored.allSatisfy({ $0.current == $0.original }) {
                do { try journal?.finish(); retained = nil }
                catch { restored[0].messages.append(error.localizedDescription) }
            }
            return BatchRenameResult(items: restored, cancelled: error is CancellationError, recoveryJournal: retained)
        }
    }

    func undo(_ mappings: [BatchRenameMapping]) async -> BatchRenameResult {
        for mapping in mappings {
            do {
                let actual = try await fileSystem.entryInfo(at: mapping.renamed)
                if let expected = mapping.identity, actual.identity != expected { throw SafeFileError.changed(mapping.renamed) }
            } catch {
                return BatchRenameResult(items: [BatchRenameItemResult(original: mapping.original,
                    requested: mapping.original, current: mapping.renamed, identity: mapping.identity,
                    outcome: .unchanged, messages: [error.localizedDescription])], cancelled: false)
            }
        }
        return await execute(mappings.reversed().map {
            BatchRenamePreview(source: $0.renamed, proposedName: $0.original.lastPathComponent, validationError: nil)
        })
    }

    func recover(_ items: [BatchRenameItemResult], previousJournal: URL? = nil) async -> BatchRenameResult {
        guard !items.isEmpty else { return BatchRenameResult(items: [], cancelled: false) }
        let service = fileSystem
        let pending = items.map { item -> BatchRenameItemResult in
            var retry = item
            retry.messages = []
            return retry
        }
        let journal: BatchRenameJournal
        do { journal = try BatchRenameJournal(items: pending) }
        catch {
            var unchanged = items
            unchanged[0].messages.append("Wiederherstellungsjournal: " + error.localizedDescription)
            return BatchRenameResult(items: unchanged, cancelled: false, recoveryJournal: previousJournal)
        }
        var restored = await Task.detached { await Self.restore(pending, using: service, journal: journal) }.value
        var retained: URL? = journal.url
        if restored.allSatisfy({ $0.current == $0.original }) {
            do { try journal.finish(); retained = nil }
            catch { restored[0].messages.append(error.localizedDescription) }
        }
        return BatchRenameResult(items: restored, cancelled: false, recoveryJournal: retained)
    }

    private static func rename(_ item: inout BatchRenameItemResult, to destination: URL,
                               using service: any FileSystemServing, journal: BatchRenameJournal? = nil) async throws {
        guard let current = item.current else { throw FileSystemServiceError.sourceMissing(item.original) }
        let actual = try await service.entryInfo(at: current)
        if let expected = item.identity, let identity = actual.identity, !identity.sameContents(as: expected) {
            throw SafeFileError.changed(current)
        }
        try journal?.record(item, next: destination)
        _ = try await service.perform(.rename(source: current, destination: destination, replaceExisting: false),
            expectation: MutationExpectation(source: actual.identity), progress: { _ in })
        item.current = destination
        item.identity = try await service.entryInfo(at: destination).identity
        try journal?.record(item, next: destination)
    }

    private static func restore(_ input: [BatchRenameItemResult], using service: any FileSystemServing,
                                journal: BatchRenameJournal? = nil) async -> [BatchRenameItemResult] {
        var items = input
        // Vacate all renamed destinations before restoring any original name (chains and cycles).
        for index in items.indices where items[index].current != nil && items[index].current != items[index].original {
            let temporary = items[index].original.deletingLastPathComponent()
                .appendingPathComponent(".dumbcommander-recovery-" + UUID().uuidString)
            do { try await rename(&items[index], to: temporary, using: service, journal: journal) }
            catch { items[index].messages.append("Sichern zur Wiederherstellung: " + error.localizedDescription) }
        }
        for index in items.indices where items[index].current != nil && items[index].current != items[index].original {
            do {
                try await rename(&items[index], to: items[index].original, using: service, journal: journal)
                items[index].outcome = .restored
            } catch {
                items[index].outcome = .recoveryRequired
                items[index].messages.append("Wiederherstellung: " + error.localizedDescription)
            }
        }
        // Report only paths that still refer to our entry, never a newly created foreign file.
        for index in items.indices {
            guard let current = items[index].current else { continue }
            do {
                let info = try await service.entryInfo(at: current)
                if let expected = items[index].identity, let actual = info.identity,
                   !actual.sameObject(as: expected) { throw SafeFileError.changed(current) }
                items[index].identity = info.identity
            } catch {
                items[index].current = nil
                items[index].outcome = .unavailable
                items[index].messages.append("Verbliebener Pfad nicht bestätigt: " + error.localizedDescription)
            }
        }
        return items
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
        try Task.checkCancellation()
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
            try Task.checkCancellation()
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
