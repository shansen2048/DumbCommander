import XCTest
@testable import DumbCommander

final class DumbCommanderTests: XCTestCase {
    @MainActor
    func testPanelSelectionsRemainIndependent() {
        let root = URL(fileURLWithPath: "/tmp/commander-state-test")
        let leftItem = makeItem(root.appendingPathComponent("left.txt"))
        let rightItem = makeItem(root.appendingPathComponent("right.txt"))
        let state = CommanderState(defaultDirectory: root)

        state.leftPanel.apply([leftItem])
        state.rightPanel.apply([rightItem])
        state.leftPanel.select(.item(leftItem.url))
        state.rightPanel.select(.item(rightItem.url))

        state.activate(.left)
        XCTAssertEqual(state.selectedFile, leftItem.url)
        XCTAssertEqual(state.activePanelState.operationTargets, [leftItem.url])

        state.activate(.right)
        XCTAssertEqual(state.selectedFile, rightItem.url)
        XCTAssertEqual(state.activePanelState.operationTargets, [rightItem.url])
    }

    @MainActor
    func testMarkedItemsTakePrecedenceAndFollowVisibleOrder() {
        let root = URL(fileURLWithPath: "/tmp/commander-mark-test")
        let alpha = makeItem(root.appendingPathComponent("alpha.txt"))
        let beta = makeItem(root.appendingPathComponent("beta.txt"))
        let panel = PanelState(directory: root)
        panel.apply([beta, alpha])
        panel.select(.item(alpha.url))

        panel.toggleMark(for: beta.url)

        XCTAssertEqual(panel.operationTargets, [beta.url])
    }

    func testSortingKeepsDirectoriesFirstAndHasStableDirection() {
        let root = URL(fileURLWithPath: "/tmp/commander-sort-test")
        let directory = makeItem(root.appendingPathComponent("z-folder"), isDirectory: true)
        let alpha = makeItem(root.appendingPathComponent("alpha.txt"), size: 10)
        let beta = makeItem(root.appendingPathComponent("beta.txt"), size: 20)
        let items = [beta, directory, alpha]

        let ascending = items.sorted(using: PanelSort(key: .name, ascending: true))
        XCTAssertEqual(ascending.map(\.name), ["z-folder", "alpha.txt", "beta.txt"])

        let descending = items.sorted(using: PanelSort(key: .name, ascending: false))
        XCTAssertEqual(descending.map(\.name), ["z-folder", "beta.txt", "alpha.txt"])
    }

    func testLocalServiceFiltersHiddenFiles() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        try temporaryDirectory.createFile(named: "visible.txt")
        try temporaryDirectory.createFile(named: ".hidden.txt")
        let service = LocalFileSystemService()

        let visibleItems = try await service.contents(
            of: temporaryDirectory.url,
            showHiddenFiles: false
        )
        XCTAssertEqual(visibleItems.map(\.name), ["visible.txt"])

        let allItems = try await service.contents(
            of: temporaryDirectory.url,
            showHiddenFiles: true
        )
        XCTAssertEqual(Set(allItems.map(\.name)), ["visible.txt", ".hidden.txt"])
    }

    func testSymbolicLinkDirectoryIsNotNavigableOrEnumerated() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let target = try temporaryDirectory.createDirectory(named: "target")
        try Data("target content".utf8).write(
            to: target.appendingPathComponent("inside.txt")
        )
        let link = temporaryDirectory.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: target.path
        )
        let service = LocalFileSystemService()

        let items = try await service.contents(
            of: temporaryDirectory.url,
            showHiddenFiles: true
        )
        let linkItem = try XCTUnwrap(items.first { $0.name == "link" })

        XCTAssertTrue(linkItem.isSymbolicLink)
        XCTAssertFalse(linkItem.isDirectory)
        XCTAssertFalse(linkItem.isNavigableDirectory)

        do {
            _ = try await service.contents(of: link, showHiddenFiles: true)
            XCTFail("Ein symbolischer Link darf nicht als Verzeichnis gelesen werden.")
        } catch let error as FileSystemServiceError {
            guard case .symbolicLinkTraversalDenied = error else {
                return XCTFail("Unerwarteter Fehler: \(error)")
            }
        }
    }

    func testCopyPreservesSymbolicLinkWithoutFollowingTarget() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let target = try temporaryDirectory.createDirectory(named: "target")
        let destinationDirectory = target.appendingPathComponent("destination")
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: false
        )
        let targetFile = target.appendingPathComponent("inside.txt")
        try Data("unchanged".utf8).write(to: targetFile)
        let link = temporaryDirectory.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: target.path
        )
        let service = LocalFileSystemService()

        let (_, result) = await execute(
            .copy([link], to: destinationDirectory),
            using: service
        )
        let copiedLink = destinationDirectory.appendingPathComponent("link")

        XCTAssertEqual(result.succeededCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: copiedLink.path),
            target.path
        )
        XCTAssertEqual(try String(contentsOf: targetFile, encoding: .utf8), "unchanged")
    }

    func testCopyDoesNotOverwriteExistingDestination() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let sourceDirectory = try temporaryDirectory.createDirectory(named: "source")
        let destinationDirectory = try temporaryDirectory.createDirectory(named: "destination")
        let source = sourceDirectory.appendingPathComponent("example.txt")
        let destination = destinationDirectory.appendingPathComponent("example.txt")
        try Data("source".utf8).write(to: source)
        try Data("destination".utf8).write(to: destination)
        let service = LocalFileSystemService()

        let coordinator = FileOperationCoordinator(fileSystem: service)
        let plan = await coordinator.plan(.copy([source], to: destinationDirectory))
        let conflict = try XCTUnwrap(plan.conflicts.first)
        let result = await coordinator.execute(
            plan,
            decisions: [conflict.id: .skip],
            progress: { _ in }
        )

        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "destination")
    }

    func testCopyRejectsDestinationInsideSourceDirectory() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let source = try temporaryDirectory.createDirectory(named: "source")
        let child = source.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let service = LocalFileSystemService()

        let (_, result) = await execute(.copy([source], to: child), using: service)

        XCTAssertEqual(result.succeededCount, 0)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: child.appendingPathComponent("source").path
            )
        )
    }

    func testTrashFailureNeverFallsBackToPermanentDeletion() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let source = try temporaryDirectory.createFile(named: "keep-me.txt")
        let service = LocalFileSystemService(trashHandler: { _ in
            throw CocoaError(.fileWriteNoPermission)
        })

        let (_, result) = await execute(.trash([source]), using: service)

        XCTAssertEqual(result.succeededCount, 0)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testPlanningOffersOnlySensibleConflictOptions() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let sourceDirectory = try temporaryDirectory.createDirectory(named: "source")
        let destinationDirectory = try temporaryDirectory.createDirectory(named: "destination")
        let sourceFile = sourceDirectory.appendingPathComponent("same.txt")
        let destinationFile = destinationDirectory.appendingPathComponent("same.txt")
        try Data("source".utf8).write(to: sourceFile)
        try Data("destination".utf8).write(to: destinationFile)
        let coordinator = FileOperationCoordinator(fileSystem: LocalFileSystemService())

        let plan = await coordinator.plan(.copy([sourceFile], to: destinationDirectory))
        let conflict = try XCTUnwrap(plan.conflicts.first)

        XCTAssertEqual(
            Set(conflict.allowedResolutions),
            Set([.replace, .keepBoth, .skip, .cancel])
        )
        XCTAssertFalse(conflict.allowedResolutions.contains(.merge))
    }

    func testApplyToAllRuleOnlyAffectsMatchingConflictKinds() {
        let root = URL(fileURLWithPath: "/tmp/conflict-rules")
        let directoryConflict = FileOperationConflict(
            id: UUID(),
            source: root.appendingPathComponent("source-folder"),
            destination: root.appendingPathComponent("target-folder"),
            sourceKind: .directory,
            destinationKind: .directory,
            allowedResolutions: [.merge, .replace, .keepBoth, .skip, .cancel]
        )
        let fileConflict = FileOperationConflict(
            id: UUID(),
            source: root.appendingPathComponent("source.txt"),
            destination: root.appendingPathComponent("target.txt"),
            sourceKind: .regularFile,
            destinationKind: .regularFile,
            allowedResolutions: [.replace, .keepBoth, .skip, .cancel]
        )
        var rules = FileConflictRuleSet()

        rules.record(
            FileConflictDecision(resolution: .merge, applyToAll: true),
            for: directoryConflict
        )

        XCTAssertEqual(rules.resolution(for: directoryConflict), .merge)
        XCTAssertNil(rules.resolution(for: fileConflict))
    }

    func testExplicitReplaceOverwritesOnlyAfterDecision() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let sourceDirectory = try temporaryDirectory.createDirectory(named: "source")
        let destinationDirectory = try temporaryDirectory.createDirectory(named: "destination")
        let source = sourceDirectory.appendingPathComponent("same.txt")
        let destination = destinationDirectory.appendingPathComponent("same.txt")
        try Data("new content".utf8).write(to: source)
        try Data("old content".utf8).write(to: destination)

        let (_, report) = await execute(
            .copy([source], to: destinationDirectory),
            using: LocalFileSystemService(),
            resolution: .replace
        )

        XCTAssertEqual(report.succeededCount, 1)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "new content")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "new content")
    }

    func testExplicitDirectoryReplaceRemovesOldTreeOnlyAfterCopyCompletes() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let sourceRoot = try temporaryDirectory.createDirectory(named: "source")
        let destinationRoot = try temporaryDirectory.createDirectory(named: "destination")
        let source = sourceRoot.appendingPathComponent("folder")
        let destination = destinationRoot.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: source.appendingPathComponent("new.txt"))
        try Data("old".utf8).write(to: destination.appendingPathComponent("old.txt"))

        let (_, report) = await execute(
            .copy([source], to: destinationRoot),
            using: LocalFileSystemService(),
            resolution: .replace
        )

        XCTAssertEqual(report.succeededCount, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("old.txt").path
            )
        )
        XCTAssertEqual(
            try String(
                contentsOf: destination.appendingPathComponent("new.txt"),
                encoding: .utf8
            ),
            "new"
        )
    }

    func testKeepBothUsesDeterministicNewName() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let sourceDirectory = try temporaryDirectory.createDirectory(named: "source")
        let destinationDirectory = try temporaryDirectory.createDirectory(named: "destination")
        let source = sourceDirectory.appendingPathComponent("same.txt")
        try Data("new".utf8).write(to: source)
        try Data("old".utf8).write(
            to: destinationDirectory.appendingPathComponent("same.txt")
        )

        let (_, report) = await execute(
            .copy([source], to: destinationDirectory),
            using: LocalFileSystemService(),
            resolution: .keepBoth
        )

        let keptCopy = destinationDirectory.appendingPathComponent("same Kopie.txt")
        XCTAssertEqual(report.succeededCount, 1)
        XCTAssertEqual(try String(contentsOf: keptCopy, encoding: .utf8), "new")
    }

    func testMergeDirectoriesPreservesNestedConflicts() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let sourceRoot = try temporaryDirectory.createDirectory(named: "source")
        let destinationRoot = try temporaryDirectory.createDirectory(named: "destination")
        let sourceDirectory = sourceRoot.appendingPathComponent("folder")
        let destinationDirectory = destinationRoot.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: sourceDirectory.appendingPathComponent("new.txt"))
        try Data("source conflict".utf8).write(
            to: sourceDirectory.appendingPathComponent("conflict.txt")
        )
        let existing = destinationDirectory.appendingPathComponent("conflict.txt")
        try Data("destination conflict".utf8).write(to: existing)

        let (_, report) = await execute(
            .copy([sourceDirectory], to: destinationRoot),
            using: LocalFileSystemService(),
            resolution: .merge
        )

        XCTAssertEqual(report.succeededCount, 1)
        XCTAssertEqual(report.skippedCount, 1)
        XCTAssertEqual(
            try String(contentsOf: existing, encoding: .utf8),
            "destination conflict"
        )
        XCTAssertEqual(
            try String(
                contentsOf: destinationDirectory.appendingPathComponent("new.txt"),
                encoding: .utf8
            ),
            "new"
        )
    }

    func testMissingSourceProducesPartialStructuredResult() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let sourceDirectory = try temporaryDirectory.createDirectory(named: "source")
        let destinationDirectory = try temporaryDirectory.createDirectory(named: "destination")
        let existing = sourceDirectory.appendingPathComponent("existing.txt")
        let missing = sourceDirectory.appendingPathComponent("missing.txt")
        try Data("content".utf8).write(to: existing)

        let (_, report) = await execute(
            .copy([existing, missing], to: destinationDirectory),
            using: LocalFileSystemService()
        )

        XCTAssertEqual(report.succeededCount, 1)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destinationDirectory.appendingPathComponent("existing.txt").path
            )
        )
    }

    func testMoveFallsBackToCopyAndRemoveForDifferentVolumeSemantics() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let sourceDirectory = try temporaryDirectory.createDirectory(named: "source")
        let destinationDirectory = try temporaryDirectory.createDirectory(named: "destination")
        let source = sourceDirectory.appendingPathComponent("move.txt")
        try Data("move me".utf8).write(to: source)
        let service = LocalFileSystemService(moveHandler: { _, _ in
            throw NSError(domain: NSPOSIXErrorDomain, code: 18)
        })

        let (_, report) = await execute(
            .move([source], to: destinationDirectory),
            using: service
        )

        XCTAssertEqual(report.succeededCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(
            try String(
                contentsOf: destinationDirectory.appendingPathComponent("move.txt"),
                encoding: .utf8
            ),
            "move me"
        )
    }

    func testMoveDoesNotFallbackForUnrelatedMoveError() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let sourceDirectory = try temporaryDirectory.createDirectory(named: "source")
        let destinationDirectory = try temporaryDirectory.createDirectory(named: "destination")
        let source = sourceDirectory.appendingPathComponent("blocked.txt")
        try Data("keep me".utf8).write(to: source)
        let service = LocalFileSystemService(moveHandler: { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        })

        let (_, report) = await execute(
            .move([source], to: destinationDirectory),
            using: service
        )

        XCTAssertEqual(report.failedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destinationDirectory.appendingPathComponent("blocked.txt").path
            )
        )
    }

    func testCancellationRemovesPartialDestinationAndKeepsSource() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let sourceDirectory = try temporaryDirectory.createDirectory(named: "source")
        let destinationDirectory = try temporaryDirectory.createDirectory(named: "destination")
        let source = sourceDirectory.appendingPathComponent("large.bin")
        try Data(repeating: 0x5A, count: 4 * 1_024 * 1_024).write(to: source)
        let service = LocalFileSystemService(
            copyChunkSize: 4_096,
            copyChunkDelay: .milliseconds(1)
        )
        let coordinator = FileOperationCoordinator(fileSystem: service)
        let plan = await coordinator.plan(.copy([source], to: destinationDirectory))

        let task = Task {
            await coordinator.execute(plan, decisions: [:], progress: { _ in })
        }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        let report = await task.value

        XCTAssertTrue(report.cancelled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destinationDirectory.appendingPathComponent("large.bin").path
            )
        )
    }

    func testRenameAndCreateDirectoryUseCoordinator() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let source = try temporaryDirectory.createFile(named: "old.txt")
        let service = LocalFileSystemService()

        let (_, renameReport) = await execute(
            .rename(source, to: "new.txt"),
            using: service
        )
        let (_, createReport) = await execute(
            .createDirectory(in: temporaryDirectory.url, named: "created"),
            using: service
        )

        XCTAssertEqual(renameReport.succeededCount, 1)
        XCTAssertEqual(createReport.succeededCount, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: temporaryDirectory.url.appendingPathComponent("new.txt").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: temporaryDirectory.url.appendingPathComponent("created").path
            )
        )
    }

    func testRenameConflictCanExplicitlyReplaceDestination() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let source = try temporaryDirectory.createFile(named: "old.txt", contents: "new")
        let destination = try temporaryDirectory.createFile(
            named: "new.txt",
            contents: "old"
        )

        let (_, report) = await execute(
            .rename(source, to: "new.txt"),
            using: LocalFileSystemService(),
            resolution: .replace
        )

        XCTAssertEqual(report.succeededCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "new")
    }

    func testCreateDirectoryConflictCanKeepBoth() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        _ = try temporaryDirectory.createDirectory(named: "folder")

        let (_, report) = await execute(
            .createDirectory(in: temporaryDirectory.url, named: "folder"),
            using: LocalFileSystemService(),
            resolution: .keepBoth
        )

        XCTAssertEqual(report.succeededCount, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: temporaryDirectory.url.appendingPathComponent("folder Kopie").path
            )
        )
    }

    func testTrashSuccessUsesOnlyInjectedTemporaryTrash() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let temporaryTrash = try temporaryDirectory.createDirectory(named: "trash")
        let source = try temporaryDirectory.createFile(named: "trash-me.txt")
        let service = LocalFileSystemService(trashHandler: { source in
            try FileManager.default.moveItem(
                at: source,
                to: temporaryTrash.appendingPathComponent(source.lastPathComponent)
            )
        })

        let (_, report) = await execute(.trash([source]), using: service)

        XCTAssertEqual(report.succeededCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: temporaryTrash.appendingPathComponent("trash-me.txt").path
            )
        )
    }

    func testWritePermissionFailureIsReportedWithoutChangingSource() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let sourceDirectory = try temporaryDirectory.createDirectory(named: "source")
        let destinationDirectory = try temporaryDirectory.createDirectory(named: "destination")
        let source = sourceDirectory.appendingPathComponent("protected.txt")
        try Data("protected".utf8).write(to: source)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o500))],
            ofItemAtPath: destinationDirectory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o700))],
                ofItemAtPath: destinationDirectory.path
            )
        }

        let (_, report) = await execute(
            .copy([source], to: destinationDirectory),
            using: LocalFileSystemService()
        )

        XCTAssertEqual(report.failedCount, 1)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "protected")
    }

    @MainActor
    func testStaleDirectoryLoadCannotReplaceNewerResult() async throws {
        let slowDirectory = URL(fileURLWithPath: "/tmp/slow")
        let fastDirectory = URL(fileURLWithPath: "/tmp/fast")
        let slowItem = makeItem(slowDirectory.appendingPathComponent("slow.txt"))
        let fastItem = makeItem(fastDirectory.appendingPathComponent("fast.txt"))
        let service = DelayedFileSystemService(
            responses: [
                slowDirectory: (.milliseconds(150), [slowItem]),
                fastDirectory: (.zero, [fastItem])
            ]
        )
        let panel = PanelState(directory: slowDirectory)

        let slowLoad = Task {
            await panel.reload(using: service, showHiddenFiles: false)
        }
        try await Task.sleep(for: .milliseconds(10))
        panel.navigate(to: fastDirectory)
        await panel.reload(using: service, showHiddenFiles: false)
        await slowLoad.value

        XCTAssertEqual(panel.directory, fastDirectory)
        XCTAssertEqual(panel.items.map(\.name), ["fast.txt"])
    }

    private func makeItem(
        _ url: URL,
        size: Int64 = 0,
        isDirectory: Bool = false
    ) -> FileItem {
        FileItem(
            url: url,
            name: url.lastPathComponent,
            pathExtension: url.pathExtension,
            size: size,
            modificationDate: nil,
            permissions: "rw-r--r--",
            isDirectory: isDirectory,
            isPackage: false,
            isSymbolicLink: false,
            isHidden: false
        )
    }

    private func execute(
        _ request: FileOperationRequest,
        using service: any FileSystemServing,
        resolution: FileConflictResolution? = nil
    ) async -> (FileOperationPlan, FileOperationReport) {
        let coordinator = FileOperationCoordinator(fileSystem: service)
        let plan = await coordinator.plan(request)
        var decisions: [UUID: FileConflictResolution] = [:]
        if let resolution {
            for conflict in plan.conflicts where conflict.allowedResolutions.contains(resolution) {
                decisions[conflict.id] = resolution
            }
        }
        let report = await coordinator.execute(
            plan,
            decisions: decisions,
            progress: { _ in }
        )
        return (plan, report)
    }
}

private actor DelayedFileSystemService: FileSystemServing {
    typealias Response = (delay: Duration, items: [FileItem])
    private let responses: [URL: Response]

    init(responses: [URL: Response]) {
        self.responses = responses
    }

    func contents(of directory: URL, showHiddenFiles: Bool) async throws -> [FileItem] {
        guard let response = responses[directory] else { return [] }
        try await Task.sleep(for: response.delay)
        return response.items
    }

}
