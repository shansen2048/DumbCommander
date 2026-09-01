import Foundation
import Combine

enum FileOperationKind: String, Sendable {
    case copy
    case move
    case rename
    case createDirectory
    case trash

    var title: String {
        switch self {
        case .copy: return "Kopieren"
        case .move: return "Verschieben"
        case .rename: return "Umbenennen"
        case .createDirectory: return "Ordner anlegen"
        case .trash: return "In den Papierkorb bewegen"
        }
    }
}

enum FileConflictResolution: String, CaseIterable, Hashable, Sendable {
    case replace
    case skip
    case keepBoth
    case merge
    case cancel

    var title: String {
        switch self {
        case .replace: return "Ersetzen"
        case .skip: return "Überspringen"
        case .keepBoth: return "Beide behalten"
        case .merge: return "Zusammenführen"
        case .cancel: return "Abbrechen"
        }
    }
}

struct FileOperationRequest: Sendable {
    let kind: FileOperationKind
    let sources: [URL]
    let destinationDirectory: URL?
    let proposedName: String?

    static func copy(_ sources: [URL], to destination: URL) -> Self {
        Self(kind: .copy, sources: sources, destinationDirectory: destination, proposedName: nil)
    }

    static func move(_ sources: [URL], to destination: URL) -> Self {
        Self(kind: .move, sources: sources, destinationDirectory: destination, proposedName: nil)
    }

    static func rename(_ source: URL, to newName: String) -> Self {
        Self(kind: .rename, sources: [source], destinationDirectory: nil, proposedName: newName)
    }

    static func createDirectory(in parent: URL, named name: String) -> Self {
        Self(kind: .createDirectory, sources: [parent], destinationDirectory: parent, proposedName: name)
    }

    static func trash(_ sources: [URL]) -> Self {
        Self(kind: .trash, sources: sources, destinationDirectory: nil, proposedName: nil)
    }
}

struct FileOperationConflict: Identifiable, Sendable {
    let id: UUID
    let source: URL
    let destination: URL
    let sourceKind: FileSystemEntryKind
    let destinationKind: FileSystemEntryKind
    let allowedResolutions: [FileConflictResolution]

    var supportsApplyToAll: Bool {
        allowedResolutions.contains { $0 != .cancel }
    }
}

struct PlannedFileOperationItem: Identifiable, Sendable {
    let id: UUID
    let source: URL
    let destination: URL?
    let sourceInfo: FileSystemEntryInfo?
    let estimatedUnits: Int64
    let conflict: FileOperationConflict?
    let validationError: String?
}

struct FileOperationPlan: Sendable {
    let request: FileOperationRequest
    let items: [PlannedFileOperationItem]

    var conflicts: [FileOperationConflict] {
        items.compactMap(\.conflict)
    }
}

enum FileOperationOutcome: String, Sendable {
    case succeeded
    case skipped
    case failed
    case cancelled
}

struct FileOperationItemReport: Identifiable, Sendable {
    let id = UUID()
    let source: URL
    let destination: URL?
    let outcome: FileOperationOutcome
    let message: String?
}

struct FileOperationReport: Identifiable, Sendable {
    let id = UUID()
    let kind: FileOperationKind
    let startedAt: Date
    let finishedAt: Date
    let items: [FileOperationItemReport]
    let cancelled: Bool

    var succeededCount: Int { items.filter { $0.outcome == .succeeded }.count }
    var skippedCount: Int { items.filter { $0.outcome == .skipped }.count }
    var failedCount: Int { items.filter { $0.outcome == .failed }.count }

    var summary: String {
        var parts = ["\(succeededCount) erfolgreich"]
        if skippedCount > 0 { parts.append("\(skippedCount) übersprungen") }
        if failedCount > 0 { parts.append("\(failedCount) fehlgeschlagen") }
        if cancelled { parts.append("abgebrochen") }
        return parts.joined(separator: ", ")
    }
}

struct FileOperationProgress: Sendable {
    let kind: FileOperationKind
    let completedUnits: Int64
    let totalUnits: Int64
    let currentItem: URL?

    var fractionCompleted: Double {
        guard totalUnits > 0 else { return 0 }
        return min(1, Double(completedUnits) / Double(totalUnits))
    }
}

struct FileConflictDecision: Sendable {
    let resolution: FileConflictResolution
    let applyToAll: Bool
}

struct FileConflictRuleSet {
    private var rules: [Rule] = []

    mutating func record(
        _ decision: FileConflictDecision,
        for conflict: FileOperationConflict
    ) {
        guard decision.applyToAll, decision.resolution != .cancel else { return }
        rules.removeAll {
            $0.sourceKind == conflict.sourceKind
                && $0.destinationKind == conflict.destinationKind
        }
        rules.append(
            Rule(
                sourceKind: conflict.sourceKind,
                destinationKind: conflict.destinationKind,
                resolution: decision.resolution
            )
        )
    }

    func resolution(for conflict: FileOperationConflict) -> FileConflictResolution? {
        rules.last {
            $0.sourceKind == conflict.sourceKind
                && $0.destinationKind == conflict.destinationKind
                && conflict.allowedResolutions.contains($0.resolution)
        }?.resolution
    }

    private struct Rule {
        let sourceKind: FileSystemEntryKind
        let destinationKind: FileSystemEntryKind
        let resolution: FileConflictResolution
    }
}

actor FileOperationCoordinator {
    typealias ProgressHandler = @Sendable (FileOperationProgress) async -> Void

    private let fileSystem: any FileSystemServing

    init(fileSystem: any FileSystemServing) {
        self.fileSystem = fileSystem
    }

    func plan(_ request: FileOperationRequest) async -> FileOperationPlan {
        switch request.kind {
        case .copy, .move:
            return await planTransfer(request)
        case .rename:
            return await planRename(request)
        case .createDirectory:
            return await planCreateDirectory(request)
        case .trash:
            return await planTrash(request)
        }
    }

    func execute(
        _ plan: FileOperationPlan,
        decisions: [UUID: FileConflictResolution],
        progress: @escaping ProgressHandler
    ) async -> FileOperationReport {
        let startedAt = Date()
        let totalUnits = max(1, plan.items.reduce(0) { $0 + max(1, $1.estimatedUnits) })
        var completedUnits: Int64 = 0
        var reports: [FileOperationItemReport] = []
        var wasCancelled = false

        await progress(
            FileOperationProgress(
                kind: plan.request.kind,
                completedUnits: 0,
                totalUnits: totalUnits,
                currentItem: nil
            )
        )

        for item in plan.items {
            let itemUnits = max(1, item.estimatedUnits)
            do {
                try Task.checkCancellation()
                await progress(
                    FileOperationProgress(
                        kind: plan.request.kind,
                        completedUnits: completedUnits,
                        totalUnits: totalUnits,
                        currentItem: item.source
                    )
                )

                if let validationError = item.validationError {
                    reports.append(
                        report(for: item, outcome: .failed, message: validationError)
                    )
                    completedUnits += itemUnits
                    continue
                }

                var destination = item.destination
                var replaceExisting = false
                var mergeDirectories = false

                if let conflict = item.conflict {
                    guard let resolution = decisions[conflict.id] else {
                        reports.append(
                            report(
                                for: item,
                                outcome: .failed,
                                message: "Für den Zielkonflikt wurde keine Entscheidung getroffen."
                            )
                        )
                        completedUnits += itemUnits
                        continue
                    }
                    guard conflict.allowedResolutions.contains(resolution) else {
                        reports.append(
                            report(
                                for: item,
                                outcome: .failed,
                                message: "Die gewählte Konfliktlösung ist hier nicht zulässig."
                            )
                        )
                        completedUnits += itemUnits
                        continue
                    }

                    switch resolution {
                    case .cancel:
                        wasCancelled = true
                        reports.append(report(for: item, outcome: .cancelled, message: nil))
                        break
                    case .skip:
                        reports.append(
                            report(for: item, outcome: .skipped, message: "Zielkonflikt übersprungen.")
                        )
                        completedUnits += itemUnits
                        continue
                    case .keepBoth:
                        if let proposedDestination = destination {
                            destination = await fileSystem.uniqueDestination(
                                for: proposedDestination,
                                isDirectory: item.sourceInfo?.kind == .directory
                            )
                        }
                    case .replace:
                        replaceExisting = true
                    case .merge:
                        mergeDirectories = true
                    }
                }

                if wasCancelled { break }

                let mutation = try mutation(
                    for: plan.request.kind,
                    item: item,
                    destination: destination,
                    replaceExisting: replaceExisting,
                    mergeDirectories: mergeDirectories
                )
                let baseUnits = completedUnits
                let mutationResult = try await fileSystem.perform(mutation) { copiedUnits in
                    await progress(
                        FileOperationProgress(
                            kind: plan.request.kind,
                            completedUnits: min(totalUnits, baseUnits + copiedUnits),
                            totalUnits: totalUnits,
                            currentItem: item.source
                        )
                    )
                }

                reports.append(
                    FileOperationItemReport(
                        source: item.source,
                        destination: mutationResult.destination ?? destination,
                        outcome: .succeeded,
                        message: nil
                    )
                )
                reports.append(contentsOf: mutationResult.issues.map {
                    FileOperationItemReport(
                        source: $0.source,
                        destination: $0.destination,
                        outcome: $0.isSkippedConflict ? .skipped : .failed,
                        message: $0.message
                    )
                })
                completedUnits += itemUnits
            } catch is CancellationError {
                wasCancelled = true
                reports.append(report(for: item, outcome: .cancelled, message: nil))
                break
            } catch {
                reports.append(
                    report(for: item, outcome: .failed, message: error.localizedDescription)
                )
                completedUnits += itemUnits
            }
        }

        await progress(
            FileOperationProgress(
                kind: plan.request.kind,
                completedUnits: min(totalUnits, completedUnits),
                totalUnits: totalUnits,
                currentItem: nil
            )
        )

        return FileOperationReport(
            kind: plan.request.kind,
            startedAt: startedAt,
            finishedAt: Date(),
            items: reports,
            cancelled: wasCancelled
        )
    }

    private func planTransfer(_ request: FileOperationRequest) async -> FileOperationPlan {
        guard let destinationDirectory = request.destinationDirectory else {
            return invalidPlan(request, message: "Das Zielverzeichnis fehlt.")
        }

        let normalizedDestination = destinationDirectory.standardizedFileURL
        let destinationError: String?
        do {
            let destinationInfo = try await fileSystem.entryInfo(at: normalizedDestination)
            if destinationInfo.kind == .symbolicLink {
                destinationError = "Ein symbolischer Link darf nicht als Zielverzeichnis verwendet werden."
            } else if destinationInfo.kind != .directory {
                destinationError = "Das Ziel ist kein Verzeichnis."
            } else {
                destinationError = nil
            }
        } catch {
            destinationError = "Das Zielverzeichnis ist nicht verfügbar: \(error.localizedDescription)"
        }

        var items: [PlannedFileOperationItem] = []
        for source in request.sources {
            let normalizedSource = source.standardizedFileURL
            let destination = normalizedDestination
                .appendingPathComponent(normalizedSource.lastPathComponent)
                .standardizedFileURL

            do {
                let sourceInfo = try await fileSystem.entryInfo(at: normalizedSource)
                let estimatedUnits = max(1, try await fileSystem.estimatedSize(at: normalizedSource))
                var validationError = destinationError

                if normalizedSource == destination {
                    validationError = "Quelle und Ziel sind identisch."
                } else if sourceInfo.kind == .directory,
                          Self.isSameOrDescendant(destination, of: normalizedSource) {
                    validationError = "Ein Verzeichnis kann nicht in sich selbst kopiert oder verschoben werden."
                }

                let conflict = validationError == nil
                    ? await makeConflictIfNeeded(
                        source: normalizedSource,
                        destination: destination,
                        sourceKind: sourceInfo.kind,
                        kind: request.kind
                    )
                    : nil

                items.append(
                    PlannedFileOperationItem(
                        id: UUID(),
                        source: normalizedSource,
                        destination: destination,
                        sourceInfo: sourceInfo,
                        estimatedUnits: estimatedUnits,
                        conflict: conflict,
                        validationError: validationError
                    )
                )
            } catch {
                items.append(
                    PlannedFileOperationItem(
                        id: UUID(),
                        source: normalizedSource,
                        destination: destination,
                        sourceInfo: nil,
                        estimatedUnits: 1,
                        conflict: nil,
                        validationError: "Die Quelle ist nicht verfügbar: \(error.localizedDescription)"
                    )
                )
            }
        }
        return FileOperationPlan(request: request, items: items)
    }

    private func planRename(_ request: FileOperationRequest) async -> FileOperationPlan {
        guard let source = request.sources.first else {
            return invalidPlan(request, message: "Die Quelle fehlt.")
        }
        let name = request.proposedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let invalidName = name.isEmpty || name == "." || name == ".." || name.contains("/")
        let normalizedSource = source.standardizedFileURL
        let destination = normalizedSource
            .deletingLastPathComponent()
            .appendingPathComponent(name)
            .standardizedFileURL

        do {
            let sourceInfo = try await fileSystem.entryInfo(at: normalizedSource)
            let error = invalidName
                ? "Der neue Name ist ungültig."
                : (destination == normalizedSource ? "Der Name wurde nicht geändert." : nil)
            let conflict = error == nil
                ? await makeConflictIfNeeded(
                    source: normalizedSource,
                    destination: destination,
                    sourceKind: sourceInfo.kind,
                    kind: .rename
                )
                : nil
            return FileOperationPlan(
                request: request,
                items: [
                    PlannedFileOperationItem(
                        id: UUID(),
                        source: normalizedSource,
                        destination: destination,
                        sourceInfo: sourceInfo,
                        estimatedUnits: 1,
                        conflict: conflict,
                        validationError: error
                    )
                ]
            )
        } catch {
            return invalidPlan(request, source: normalizedSource, destination: destination, message: error.localizedDescription)
        }
    }

    private func planCreateDirectory(_ request: FileOperationRequest) async -> FileOperationPlan {
        guard let parent = request.destinationDirectory ?? request.sources.first else {
            return invalidPlan(request, message: "Das Zielverzeichnis fehlt.")
        }
        let normalizedParent = parent.standardizedFileURL
        let name = request.proposedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let destination = normalizedParent
            .appendingPathComponent(name)
            .standardizedFileURL
        var validationError: String?
        if name.isEmpty || name == "." || name == ".." || name.contains("/") {
            validationError = "Der Ordnername ist ungültig."
        } else {
            do {
                let parentInfo = try await fileSystem.entryInfo(at: normalizedParent)
                if parentInfo.kind != .directory {
                    validationError = "Das Ziel ist kein Verzeichnis."
                }
            } catch {
                validationError = error.localizedDescription
            }
        }

        var conflict: FileOperationConflict?
        if validationError == nil, await fileSystem.itemExists(at: destination) {
            let destinationInfo = try? await fileSystem.entryInfo(at: destination)
            conflict = FileOperationConflict(
                id: UUID(),
                source: normalizedParent,
                destination: destination,
                sourceKind: .directory,
                destinationKind: destinationInfo?.kind ?? .other,
                allowedResolutions: [.keepBoth, .skip, .cancel]
            )
        }

        return FileOperationPlan(
            request: request,
            items: [
                PlannedFileOperationItem(
                    id: UUID(),
                    source: normalizedParent,
                    destination: destination,
                    sourceInfo: FileSystemEntryInfo(
                        url: normalizedParent,
                        kind: .directory,
                        size: 0
                    ),
                    estimatedUnits: 1,
                    conflict: conflict,
                    validationError: validationError
                )
            ]
        )
    }

    private func planTrash(_ request: FileOperationRequest) async -> FileOperationPlan {
        var items: [PlannedFileOperationItem] = []
        for source in request.sources {
            let normalizedSource = source.standardizedFileURL
            do {
                let info = try await fileSystem.entryInfo(at: normalizedSource)
                let estimated = max(
                    1,
                    try await fileSystem.estimatedSize(at: normalizedSource)
                )
                items.append(
                    PlannedFileOperationItem(
                        id: UUID(),
                        source: normalizedSource,
                        destination: nil,
                        sourceInfo: info,
                        estimatedUnits: estimated,
                        conflict: nil,
                        validationError: nil
                    )
                )
            } catch {
                items.append(
                    PlannedFileOperationItem(
                        id: UUID(),
                        source: normalizedSource,
                        destination: nil,
                        sourceInfo: nil,
                        estimatedUnits: 1,
                        conflict: nil,
                        validationError: "Die Quelle ist nicht verfügbar: \(error.localizedDescription)"
                    )
                )
            }
        }
        return FileOperationPlan(request: request, items: items)
    }

    private func makeConflictIfNeeded(
        source: URL,
        destination: URL,
        sourceKind: FileSystemEntryKind,
        kind: FileOperationKind
    ) async -> FileOperationConflict? {
        guard await fileSystem.itemExists(at: destination) else { return nil }
        let destinationKind = (try? await fileSystem.entryInfo(at: destination))?.kind ?? .other
        var allowed: [FileConflictResolution] = [.replace, .keepBoth, .skip, .cancel]
        if sourceKind == .directory, destinationKind == .directory, kind != .rename {
            allowed.insert(.merge, at: 0)
        }
        return FileOperationConflict(
            id: UUID(),
            source: source,
            destination: destination,
            sourceKind: sourceKind,
            destinationKind: destinationKind,
            allowedResolutions: allowed
        )
    }

    private func mutation(
        for kind: FileOperationKind,
        item: PlannedFileOperationItem,
        destination: URL?,
        replaceExisting: Bool,
        mergeDirectories: Bool
    ) throws -> FileSystemMutation {
        switch kind {
        case .copy:
            guard let destination else { throw FileOperationCoordinatorError.missingDestination }
            return .copy(
                source: item.source,
                destination: destination,
                replaceExisting: replaceExisting,
                mergeDirectories: mergeDirectories
            )
        case .move:
            guard let destination else { throw FileOperationCoordinatorError.missingDestination }
            return .move(
                source: item.source,
                destination: destination,
                replaceExisting: replaceExisting,
                mergeDirectories: mergeDirectories
            )
        case .rename:
            guard let destination else { throw FileOperationCoordinatorError.missingDestination }
            return .rename(source: item.source, destination: destination, replaceExisting: replaceExisting)
        case .createDirectory:
            guard let destination else { throw FileOperationCoordinatorError.missingDestination }
            return .createDirectory(destination: destination)
        case .trash:
            return .trash(source: item.source)
        }
    }

    private func invalidPlan(
        _ request: FileOperationRequest,
        source: URL? = nil,
        destination: URL? = nil,
        message: String
    ) -> FileOperationPlan {
        let fallback = source ?? request.sources.first ?? URL(fileURLWithPath: "/")
        return FileOperationPlan(
            request: request,
            items: [
                PlannedFileOperationItem(
                    id: UUID(),
                    source: fallback,
                    destination: destination,
                    sourceInfo: nil,
                    estimatedUnits: 1,
                    conflict: nil,
                    validationError: message
                )
            ]
        )
    }

    private func report(
        for item: PlannedFileOperationItem,
        outcome: FileOperationOutcome,
        message: String?
    ) -> FileOperationItemReport {
        FileOperationItemReport(
            source: item.source,
            destination: item.destination,
            outcome: outcome,
            message: message
        )
    }

    private static func isSameOrDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        let directoryPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath == directoryPath || candidatePath.hasPrefix(directoryPath + "/")
    }
}

private enum FileOperationCoordinatorError: LocalizedError {
    case missingDestination

    var errorDescription: String? {
        "Das Ziel der Dateioperation fehlt."
    }
}

@MainActor
final class FileOperationViewModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var queuedCount = 0
    @Published private(set) var currentConflict: FileOperationConflict?
    @Published private(set) var progress: FileOperationProgress?
    @Published var report: FileOperationReport?

    private let coordinator: FileOperationCoordinator
    private var operationTask: Task<Void, Never>?
    private var conflictContinuation: CheckedContinuation<FileConflictDecision, Never>?
    private var queue: [QueuedOperation] = []

    init(coordinator: FileOperationCoordinator) {
        self.coordinator = coordinator
    }

    func start(
        _ request: FileOperationRequest,
        refresh: @escaping @MainActor () async -> Void
    ) {
        guard !isRunning else {
            queue.append(QueuedOperation(request: request, refresh: refresh))
            queuedCount = queue.count
            return
        }
        isRunning = true
        report = nil
        progress = FileOperationProgress(
            kind: request.kind,
            completedUnits: 0,
            totalUnits: 1,
            currentItem: nil
        )

        operationTask = Task { [weak self] in
            guard let self else { return }
            let plan = await coordinator.plan(request)
            var decisions: [UUID: FileConflictResolution] = [:]
            var rules = FileConflictRuleSet()
            var cancelledDuringPlanning = false

            for conflict in plan.conflicts {
                if Task.isCancelled {
                    cancelledDuringPlanning = true
                    break
                }
                if let resolution = rules.resolution(for: conflict) {
                    decisions[conflict.id] = resolution
                    continue
                }

                let decision = await waitForDecision(for: conflict)
                decisions[conflict.id] = decision.resolution
                rules.record(decision, for: conflict)
                if decision.resolution == .cancel {
                    cancelledDuringPlanning = true
                    break
                }
            }

            if cancelledDuringPlanning {
                report = FileOperationReport(
                    kind: request.kind,
                    startedAt: Date(),
                    finishedAt: Date(),
                    items: plan.items.first.map {
                        [
                            FileOperationItemReport(
                                source: $0.source,
                                destination: $0.destination,
                                outcome: .cancelled,
                                message: nil
                            )
                        ]
                    } ?? [],
                    cancelled: true
                )
                currentConflict = nil
                progress = nil
                isRunning = false
                operationTask = nil
                startNextQueuedOperation()
                return
            }

            let result = await coordinator.execute(plan, decisions: decisions) { value in
                await self.updateProgress(value)
            }
            let refreshTask = Task { @MainActor in
                await refresh()
            }
            await refreshTask.value
            report = result
            currentConflict = nil
            progress = nil
            isRunning = false
            operationTask = nil
            startNextQueuedOperation()
        }
    }

    func resolveConflict(_ resolution: FileConflictResolution, applyToAll: Bool) {
        guard let continuation = conflictContinuation else { return }
        conflictContinuation = nil
        currentConflict = nil
        continuation.resume(
            returning: FileConflictDecision(resolution: resolution, applyToAll: applyToAll)
        )
    }

    func cancel() {
        if conflictContinuation != nil {
            resolveConflict(.cancel, applyToAll: false)
        } else {
            operationTask?.cancel()
        }
    }

    func cancelAll() {
        queue.removeAll()
        queuedCount = 0
        cancel()
    }

    private func startNextQueuedOperation() {
        guard !queue.isEmpty else {
            queuedCount = 0
            return
        }
        let next = queue.removeFirst()
        queuedCount = queue.count
        start(next.request, refresh: next.refresh)
    }

    private func waitForDecision(
        for conflict: FileOperationConflict
    ) async -> FileConflictDecision {
        await withCheckedContinuation { continuation in
            currentConflict = conflict
            conflictContinuation = continuation
        }
    }

    private func updateProgress(_ value: FileOperationProgress) {
        progress = value
    }

    private struct QueuedOperation {
        let request: FileOperationRequest
        let refresh: @MainActor () async -> Void
    }
}
