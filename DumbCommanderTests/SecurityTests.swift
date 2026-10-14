import XCTest
import Darwin
@testable import DumbCommander

final class SecurityTests: XCTestCase {
    func testMoveAcrossDisposableAPFSVolumePreservesMetadata() async throws {
        let fixture = try TemporaryDirectory()
        let mount = try fixture.createDirectory(named: "mounted")
        let image = fixture.url.appendingPathComponent("test.sparseimage")
        func diskImage(_ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = arguments
            process.currentDirectoryURL = fixture.url
            process.standardOutput = FileHandle.nullDevice
            let error = Pipe()
            process.standardError = error
            try process.run()
            let message = try error.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "DumbCommanderDiskImageTest", code: Int(process.terminationStatus),
                              userInfo: [NSLocalizedDescriptionKey: String(decoding: message, as: UTF8.self)])
            }
        }
        try diskImage(["create", "-quiet", "-size", "64m", "-fs", "APFS", "-type", "SPARSE",
                       "-volname", "DumbCommanderTest", image.path])
        try diskImage(["attach", "-quiet", "-nobrowse", "-noverify", "-mountpoint", mount.path, image.path])
        defer {
            do { try diskImage(["detach", "-quiet", mount.path]) }
            catch { XCTFail("Temporäres Testvolume konnte nicht ausgehängt werden: \(error)") }
        }
        let source = try fixture.createFile(named: "source", contents: "volume transfer")
        let bytes = Array("resource fork".utf8)
        XCTAssertEqual(bytes.withUnsafeBytes { setxattr(source.path, "com.apple.ResourceFork", $0.baseAddress, bytes.count, 0, 0) }, 0)
        let parent = try SafeDirectory(url: fixture.url)
        let input = try parent.openFile("source", flags: O_RDONLY)
        let mounted = try SafeDirectory(url: mount)
        XCTAssertNotEqual(try input.identity.device, try mounted.descriptor.identity.device)
        let target = mount.appendingPathComponent("moved")
        _ = try await LocalFileSystemService().perform(
            .move(source: source, destination: target, replaceExisting: false, mergeDirectories: false), progress: { _ in })
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: target), "volume transfer")
        do {
            let output = try mounted.openFile("moved", flags: O_RDONLY)
            XCTAssertEqual(try FileMetadata.attributes(input), try FileMetadata.attributes(output))
            XCTAssertEqual(try input.identity.birthSeconds, try output.identity.birthSeconds)
        }
    }

    @MainActor
    func testJobLifecycleWaitsForRecoveryAndKeepsAllReports() {
        let activity = MutationActivity()
        var cancelled = 0
        var finished = false
        let first = activity.begin("Kopieren") { cancelled += 1 }
        let second = activity.begin("Wiederherstellung") { cancelled += 1 }
        activity.whenIdle { finished = true }
        activity.cancelAll()
        XCTAssertEqual(cancelled, 2)
        XCTAssertFalse(finished)
        activity.finish(first, summary: "Abgebrochen", details: ["Quelle erhalten"])
        XCTAssertFalse(finished)
        activity.finish(second, summary: "Wiederhergestellt", details: ["Originalpfad"])
        XCTAssertTrue(finished)
        XCTAssertEqual(activity.reports.count, 2)
        XCTAssertFalse(activity.isRunning)
    }
    func testCopyPreservesExtendedAttributesResourceForkACLAndMode() async throws {
        let fixture = try TemporaryDirectory()
        let source = try fixture.createFile(named: "source", contents: "data")
        let target = fixture.url.appendingPathComponent("target")
        for (name, text) in [("test.dumbcommander", "attribute"), ("com.apple.ResourceFork", "resource data")] {
            let bytes = Array(text.utf8)
            XCTAssertEqual(bytes.withUnsafeBytes { setxattr(source.path, name, $0.baseAddress, bytes.count, 0, 0) }, 0)
        }
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+a", "everyone allow read,readattr,readextattr,readsecurity", source.path]
        try chmod.run(); chmod.waitUntilExit()
        XCTAssertEqual(chmod.terminationStatus, 0)
        try FileManager.default.setAttributes([.posixPermissions: 0o640, .modificationDate: Date(timeIntervalSince1970: 1_600_000_000)],
                                              ofItemAtPath: source.path)
        _ = try await LocalFileSystemService().perform(.copy(source: source, destination: target,
            replaceExisting: false, mergeDirectories: false), progress: { _ in })
        let parent = try SafeDirectory(url: fixture.url)
        let input = try parent.openFile("source", flags: O_RDONLY)
        let output = try parent.openFile("target", flags: O_RDONLY)
        XCTAssertEqual(try FileMetadata.attributes(input), try FileMetadata.attributes(output))
        XCTAssertEqual(try FileMetadata.acl(input), try FileMetadata.acl(output))
        XCTAssertEqual(try input.identity.mode, try output.identity.mode)
        XCTAssertEqual(try input.identity.modifiedSeconds, try output.identity.modifiedSeconds)
        XCTAssertEqual(try input.identity.birthSeconds, try output.identity.birthSeconds)
        XCTAssertEqual(try Data(contentsOf: source), try Data(contentsOf: target))
        let moved = fixture.url.appendingPathComponent("moved")
        _ = try await LocalFileSystemService(moveHandler: { _, _ in throw POSIXError(.EXDEV) }).perform(
            .move(source: target, destination: moved, replaceExisting: false, mergeDirectories: false), progress: { _ in })
        let movedHandle = try parent.openFile("moved", flags: O_RDONLY)
        XCTAssertEqual(try FileMetadata.attributes(input), try FileMetadata.attributes(movedHandle))
        XCTAssertEqual(try FileMetadata.acl(input), try FileMetadata.acl(movedHandle))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testMetadataFailureKeepsMoveSourceAndExistingTarget() async throws {
        let fixture = try TemporaryDirectory()
        let source = try fixture.createFile(named: "source", contents: "original")
        let target = try fixture.createFile(named: "target", contents: "existing")
        let service = LocalFileSystemService(hooks: FileMutationHooks(beforeMetadata: { _ in throw POSIXError(.ENOTSUP) }))
        do {
            _ = try await service.perform(.move(source: source, destination: target, replaceExisting: true, mergeDirectories: false), progress: { _ in })
            XCTFail("Metadata failure must stop publication")
        } catch {}
        XCTAssertEqual(try String(contentsOf: source), "original")
        XCTAssertEqual(try String(contentsOf: target), "existing")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.url.path).sorted(), ["source", "target"])
    }

    func testRacingCopyDestinationIsNeverOverwrittenOrCleanedUp() async throws {
        let fixture = try TemporaryDirectory()
        let source = try fixture.createDirectory(named: "source")
        try Data("copy".utf8).write(to: source.appendingPathComponent("file"))
        let target = fixture.url.appendingPathComponent("target")
        let service = LocalFileSystemService(hooks: FileMutationHooks(beforePublish: { url in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            try Data("foreign".utf8).write(to: url.appendingPathComponent("sentinel"))
        }))
        do {
            _ = try await service.perform(.copy(source: source, destination: target, replaceExisting: false, mergeDirectories: false), progress: { _ in })
            XCTFail("Race must fail exclusively")
        } catch {}
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("sentinel")), "foreign")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("file").path))
    }

    func testReplaceRetainsPreviousDataWhenRacingTargetBlocksRestore() async throws {
        let fixture = try TemporaryDirectory()
        let source = try fixture.createFile(named: "source", contents: "new")
        let target = try fixture.createFile(named: "target", contents: "previous")
        let service = LocalFileSystemService(hooks: FileMutationHooks(afterTargetCapture: { url in
            try Data("foreign".utf8).write(to: url)
        }))
        do {
            _ = try await service.perform(.copy(source: source, destination: target,
                replaceExisting: true, mergeDirectories: false), progress: { _ in })
            XCTFail("Must preserve blocked recovery")
        } catch SafeFileError.recovery(let directory, _) {
            XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("previous")), "previous")
            XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("new")), "new")
        }
        XCTAssertEqual(try String(contentsOf: target), "foreign")
        XCTAssertEqual(try String(contentsOf: source), "new")
    }

    func testCrossVolumeFailureNeverRemovesRacingTarget() async throws {
        let fixture = try TemporaryDirectory()
        let source = try fixture.createFile(named: "source")
        let target = fixture.url.appendingPathComponent("target")
        let service = LocalFileSystemService(moveHandler: { _, destination in
            try Data("foreign".utf8).write(to: destination)
            throw POSIXError(.EXDEV)
        })
        do {
            _ = try await service.perform(.move(source: source, destination: target, replaceExisting: false, mergeDirectories: false), progress: { _ in })
            XCTFail("Race must fail")
        } catch {}
        XCTAssertEqual(try String(contentsOf: target), "foreign")
        XCTAssertEqual(try String(contentsOf: source), "test")
    }

    func testReplacementDecisionRejectsChangedTargetAndSource() async throws {
        let fixture = try TemporaryDirectory()
        let input = try fixture.createDirectory(named: "in")
        let output = try fixture.createDirectory(named: "out")
        let source = input.appendingPathComponent("item")
        let target = output.appendingPathComponent("item")
        try Data("source".utf8).write(to: source)
        try Data("old".utf8).write(to: target)
        let coordinator = FileOperationCoordinator(fileSystem: LocalFileSystemService())
        let plan = await coordinator.plan(.copy([source], to: output))
        try Data("new foreign destination".utf8).write(to: target, options: .atomic)
        let report = await coordinator.execute(plan, decisions: [plan.conflicts[0].id: .replace], progress: { _ in })
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertEqual(try String(contentsOf: target), "new foreign destination")
        let next = await coordinator.plan(.copy([source], to: output))
        try Data("replacement source".utf8).write(to: source, options: .atomic)
        let nextReport = await coordinator.execute(next, decisions: [next.conflicts[0].id: .replace], progress: { _ in })
        XCTAssertEqual(nextReport.failedCount, 1)
        XCTAssertEqual(try String(contentsOf: target), "new foreign destination")
    }

    func testChangedMoveSourceIsNotDeletedAfterCopy() async throws {
        let fixture = try TemporaryDirectory()
        let source = try fixture.createFile(named: "source", contents: "original")
        let target = fixture.url.appendingPathComponent("target")
        let service = LocalFileSystemService(moveHandler: { _, _ in throw POSIXError(.EXDEV) },
            hooks: FileMutationHooks(beforeSourceRemoval: { source in
                try Data("new source".utf8).write(to: source, options: .atomic)
            }))
        do {
            _ = try await service.perform(.move(source: source, destination: target, replaceExisting: false, mergeDirectories: false), progress: { _ in })
            XCTFail("Must report partial move")
        } catch FileSystemServiceError.partialMove {}
        XCTAssertEqual(try String(contentsOf: source), "new source")
        XCTAssertEqual(try String(contentsOf: target), "original")
    }

    func testReplaceRejectsNestedTargetChangesSincePlanning() async throws {
        let fixture = try TemporaryDirectory()
        let input = try fixture.createDirectory(named: "input")
        let output = try fixture.createDirectory(named: "output")
        let source = try fixture.createDirectory(named: "input/folder")
        let nested = try fixture.createDirectory(named: "output/folder/nested")
        try Data("new".utf8).write(to: source.appendingPathComponent("file"))
        let coordinator = FileOperationCoordinator(fileSystem: LocalFileSystemService())
        let plan = await coordinator.plan(.copy([input.appendingPathComponent("folder")], to: output))
        try Data("foreign".utf8).write(to: nested.appendingPathComponent("arrived-after-decision"))
        let result = await coordinator.execute(plan, decisions: [plan.conflicts[0].id: .replace], progress: { _ in })
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(try String(contentsOf: nested.appendingPathComponent("arrived-after-decision")), "foreign")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("file").path))
    }

    func testDestinationParentSwapDoesNotWriteThroughLink() async throws {
        let fixture = try TemporaryDirectory()
        let source = try fixture.createFile(named: "source")
        let targetParent = try fixture.createDirectory(named: "target")
        let guardian = try fixture.createDirectory(named: "guardian")
        let old = fixture.url.appendingPathComponent("old")
        let service = LocalFileSystemService(hooks: FileMutationHooks(beforePublish: { _ in
            try FileManager.default.moveItem(at: targetParent, to: old)
            try FileManager.default.createSymbolicLink(at: targetParent, withDestinationURL: guardian)
        }))
        do {
            _ = try await service.perform(.copy(source: source, destination: targetParent.appendingPathComponent("file"), replaceExisting: false, mergeDirectories: false), progress: { _ in })
            XCTFail("Must reject redirected parent")
        } catch {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: guardian.path).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: old.path).isEmpty)
    }

    func testFIFOIsRejectedBeforeOpeningDataStream() async throws {
        let fixture = try TemporaryDirectory()
        let source = fixture.url.appendingPathComponent("pipe")
        XCTAssertEqual(mkfifo(source.path, 0o600), 0)
        do {
            _ = try await LocalFileSystemService().perform(.copy(source: source,
                destination: fixture.url.appendingPathComponent("target"), replaceExisting: false, mergeDirectories: false), progress: { _ in })
            XCTFail("FIFO must be rejected")
        } catch SafeFileError.unsupported {}
    }

    func testInaccessibleParentIsNotReportedAsMissing() async throws {
        let fixture = try TemporaryDirectory()
        let parent = try fixture.createDirectory(named: "private")
        XCTAssertEqual(chmod(parent.path, 0), 0)
        defer { chmod(parent.path, 0o700) }
        do {
            _ = try await LocalFileSystemService().itemExists(at: parent.appendingPathComponent("missing"))
            XCTFail("Access error must propagate")
        } catch let error as POSIXError { XCTAssertEqual(error.code, .EACCES) }
    }

    func testBatchRenameCycleAndCaseOnlyRenameCanBeUndone() async throws {
        let fixture = try TemporaryDirectory()
        let a = try fixture.createFile(named: "a", contents: "A")
        let b = try fixture.createFile(named: "b", contents: "B")
        let service = BatchRenameService(fileSystem: LocalFileSystemService())
        let result = await service.execute([
            BatchRenamePreview(source: a, proposedName: "b", validationError: nil),
            BatchRenamePreview(source: b, proposedName: "a", validationError: nil)
        ])
        XCTAssertTrue(result.errors.isEmpty, result.errors.description)
        XCTAssertEqual(try String(contentsOf: a), "B")
        XCTAssertEqual(try String(contentsOf: b), "A")
        let undone = await service.undo(result.mappings)
        XCTAssertTrue(undone.errors.isEmpty, undone.errors.description)
        XCTAssertEqual(try String(contentsOf: a), "A")
        let caseOnly = await service.execute([BatchRenamePreview(source: a, proposedName: "A", validationError: nil)])
        XCTAssertTrue(caseOnly.errors.isEmpty, caseOnly.errors.description)
        XCTAssertEqual(try String(contentsOf: fixture.url.appendingPathComponent("A")), "A")
    }

    func testBatchRenameRollbackHandlesCycleAfterPartialPublication() async throws {
        let fixture = try TemporaryDirectory()
        let a = try fixture.createFile(named: "a", contents: "A")
        let b = try fixture.createFile(named: "b", contents: "B")
        let c = try fixture.createFile(named: "c", contents: "C")
        let injected = FaultFileSystem(failures: [6])
        let result = await BatchRenameService(fileSystem: injected).execute([
            .init(source: a, proposedName: "b", validationError: nil),
            .init(source: b, proposedName: "c", validationError: nil),
            .init(source: c, proposedName: "a", validationError: nil)
        ])
        XCTAssertFalse(result.errors.isEmpty)
        XCTAssertTrue(result.items.allSatisfy { $0.current == $0.original })
        for (url, value) in [(a, "A"), (b, "B"), (c, "C")] { XCTAssertEqual(try String(contentsOf: url), value) }
    }

    func testCancelledBatchRenameRecoversOutsideCancelledTask() async throws {
        let fixture = try TemporaryDirectory()
        let a = try fixture.createFile(named: "a")
        let b = try fixture.createFile(named: "b")
        let injected = FaultFileSystem(cancelAt: 2)
        let result = await BatchRenameService(fileSystem: injected).execute([
            .init(source: a, proposedName: "new-a", validationError: nil),
            .init(source: b, proposedName: "new-b", validationError: nil)
        ])
        XCTAssertTrue(result.cancelled)
        XCTAssertTrue(result.items.allSatisfy { $0.current == $0.original })
        XCTAssertEqual(try String(contentsOf: a), "test")
        XCTAssertEqual(try String(contentsOf: b), "test")
    }

    func testRollbackFailureReportsRecoverableActualPathWithoutOverwriting() async throws {
        let fixture = try TemporaryDirectory()
        let a = try fixture.createFile(named: "a", contents: "original")
        let injected = FaultFileSystem(failures: [2], occupiedOriginal: a)
        let service = BatchRenameService(fileSystem: injected)
        let result = await service.execute([.init(source: a, proposedName: "renamed", validationError: nil)])
        let item = try XCTUnwrap(result.items.first)
        XCTAssertEqual(item.outcome, .recoveryRequired)
        let remaining = try XCTUnwrap(item.current)
        let journal = try XCTUnwrap(result.recoveryJournal)
        let saved = try String(contentsOf: journal)
        XCTAssertTrue(saved.contains("original"))
        XCTAssertTrue(saved.contains(remaining.lastPathComponent))
        XCTAssertNotEqual(remaining, a)
        XCTAssertEqual(try String(contentsOf: remaining), "original")
        XCTAssertEqual(try String(contentsOf: a), "foreign")
        let retry = await service.recover(result.items, previousJournal: journal)
        let retryPath = try XCTUnwrap(retry.items.first?.current)
        let retryJournal = try XCTUnwrap(retry.recoveryJournal)
        XCTAssertEqual(retry.items.first?.outcome, .recoveryRequired)
        XCTAssertTrue(try String(contentsOf: retryJournal).contains(retryPath.lastPathComponent))
        XCTAssertEqual(try String(contentsOf: retryPath), "original")
        XCTAssertEqual(try String(contentsOf: a), "foreign")
        try FileManager.default.moveItem(at: a, to: fixture.url.appendingPathComponent("foreign-kept"))
        let recovered = await service.recover(retry.items, previousJournal: retryJournal)
        XCTAssertEqual(recovered.items[0].current, a)
        XCTAssertNil(recovered.recoveryJournal)
        XCTAssertEqual(try String(contentsOf: a), "original")
        XCTAssertEqual(try String(contentsOf: fixture.url.appendingPathComponent("foreign-kept")), "foreign")
    }

    func testUndoRejectsReplacedFile() async throws {
        let fixture = try TemporaryDirectory()
        let source = try fixture.createFile(named: "source")
        let service = BatchRenameService(fileSystem: LocalFileSystemService())
        let result = await service.execute([.init(source: source, proposedName: "renamed", validationError: nil)])
        let renamed = fixture.url.appendingPathComponent("renamed")
        try Data("foreign".utf8).write(to: renamed, options: .atomic)
        let undone = await service.undo(result.mappings)
        XCTAssertFalse(undone.errors.isEmpty)
        XCTAssertEqual(try String(contentsOf: renamed), "foreign")
    }
}

private actor FaultFileSystem: FileSystemServing {
    let base = LocalFileSystemService()
    let failures: Set<Int>
    let cancelAt: Int?
    let occupiedOriginal: URL?
    var calls = 0
    init(failures: Set<Int> = [], cancelAt: Int? = nil, occupiedOriginal: URL? = nil) {
        self.failures = failures; self.cancelAt = cancelAt; self.occupiedOriginal = occupiedOriginal
    }
    func contents(of directory: URL, showHiddenFiles: Bool) async throws -> [FileItem] {
        try await base.contents(of: directory, showHiddenFiles: showHiddenFiles)
    }
    func entryInfo(at url: URL) async throws -> FileSystemEntryInfo { try await base.entryInfo(at: url) }
    func itemExists(at url: URL) async throws -> Bool { try await base.itemExists(at: url) }
    func perform(_ mutation: FileSystemMutation, expectation: MutationExpectation?,
                 progress: @escaping @Sendable (Int64) async -> Void) async throws -> FileSystemMutationResult {
        calls += 1
        if calls == cancelAt {
            withUnsafeCurrentTask { $0?.cancel() }
            throw CancellationError()
        }
        if failures.contains(calls) {
            if let occupiedOriginal { try Data("foreign".utf8).write(to: occupiedOriginal) }
            throw POSIXError(.EIO)
        }
        return try await base.perform(mutation, expectation: expectation, progress: progress)
    }
}

extension SecurityTests {
    func testArchivesRejectTraversalAbsolutePathsDuplicatesAndLinkParents() async throws {
        let fixture = try TemporaryDirectory()
        let guardian = try fixture.createFile(named: "guardian", contents: "unchanged")
        let cases: [[ArchiveFixtureEntry]] = [
            [.init("../guardian", "attack")],
            [.init(guardian.path, "attack")],
            [.init("safe/../../guardian", "attack")],
            [.init("duplicate", "one"), .init("duplicate", "two")],
            [.init("Case", "one"), .init("case", "two")],
            [.init("jump", "../guardian", type: .link)],
            [.init("jump", "internal", type: .link), .init("jump/file", "attack")],
            [.init("d/a", "b/../../guardian", type: .link), .init("d/b", "..", type: .link)],
            [.init("a", "b", type: .link), .init("b", "a", type: .link)]
        ]
        for format in ArchiveFormat.allCases {
            for (index, members) in cases.enumerated() {
                let archive = fixture.url.appendingPathComponent("bad-\(index).\(format.rawValue)")
                try archiveFixture(members, format: format).write(to: archive)
                let destination = fixture.url.appendingPathComponent("extracted-\(format)-\(index)")
                do {
                    try await ArchiveService().extract(archive, to: destination)
                    XCTFail("Unsafe archive accepted: \(format) case \(index)")
                } catch {}
                XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
                XCTAssertEqual(try String(contentsOf: guardian), "unchanged")
            }
        }
    }

    func testArchivesRejectExistingIntermediateAndDanglingLinks() async throws {
        let fixture = try TemporaryDirectory()
        let guardian = try fixture.createDirectory(named: "guardian")
        for format in ArchiveFormat.allCases {
            let archive = fixture.url.appendingPathComponent("data.\(format.rawValue)")
            try archiveFixture([.init("link/attack", "bad")], format: format).write(to: archive)
            for broken in [false, true] {
                let target = try fixture.createDirectory(named: "\(format)-\(broken)")
                let link = target.appendingPathComponent("link")
                let expected = broken ? guardian.appendingPathComponent("missing") : guardian
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: expected)
                do { try await ArchiveService().extract(archive, to: target); XCTFail("Existing link must be a conflict") }
                catch {}
                XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), expected.path)
            }
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: guardian.path).isEmpty)
    }

    func testArchiveSafeLinksAndUnusualNamesRoundTrip() async throws {
        let fixture = try TemporaryDirectory()
        for format in ArchiveFormat.allCases {
            let archive = fixture.url.appendingPathComponent("safe.\(format.rawValue)")
            try archiveFixture([.init("folder/file", "data"), .init("folder/link", "file", type: .link),
                                .init("-option", "safe"), .init("line\nbreak", "newline")], format: format).write(to: archive)
            let target = fixture.url.appendingPathComponent(format.rawValue)
            let result = try await ArchiveService().extract(archive, to: target)
            XCTAssertEqual(result.failedCount, 0, result.items.compactMap(\.message).description)
            XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("folder/file")), "data")
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: target.appendingPathComponent("folder/link").path), "file")
            XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("-option")), "safe")
            XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("line\nbreak")), "newline")
        }
    }

    func testArchiveLimitsAndTruncationLeaveNoPartialTargets() async throws {
        let fixture = try TemporaryDirectory()
        for format in ArchiveFormat.allCases {
            let archive = fixture.url.appendingPathComponent("limits.\(format.rawValue)")
            let data = archiveFixture([.init("first", "12345"), .init("second", "67890")], format: format)
            try data.write(to: archive)
            let target = fixture.url.appendingPathComponent("target-\(format)")
            for limits in [ArchiveLimits(entries: 1), ArchiveLimits(expandedBytes: 9)] {
                do { try await ArchiveService(limits: limits).extract(archive, to: target); XCTFail("Limit must fail") }
                catch {}
                XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
            }
            try data.prefix(50).write(to: archive)
            do { try await ArchiveService().extract(archive, to: target); XCTFail("Truncation must fail") }
            catch {}
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        }
    }

    func testArchiveCancellationDiscardsStaging() async throws {
        let fixture = try TemporaryDirectory()
        let archive = fixture.url.appendingPathComponent("cancel.zip")
        try archiveFixture([.init("large", String(repeating: "x", count: 200_000))], format: .zip).write(to: archive)
        let target = fixture.url.appendingPathComponent("target")
        let task = Task {
            try await ArchiveService().extract(archive, to: target, progress: { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            })
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.url.path), ["cancel.zip"])
    }

    func testArchivePublicationReportsLateConflictWithoutRemovingForeignFile() async throws {
        let fixture = try TemporaryDirectory()
        let archive = fixture.url.appendingPathComponent("race.zip")
        try archiveFixture([.init("file", "archive data")], format: .zip).write(to: archive)
        let target = try fixture.createDirectory(named: "target")
        let service = LocalFileSystemService(hooks: FileMutationHooks(beforePublish: { destination in
            try Data("foreign".utf8).write(to: destination)
        }))
        let result = try await ArchiveService(fileSystem: service).extract(archive, to: target)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("file")), "foreign")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
    }

    func testTarRejectsHardLinksAndSpecialFiles() async throws {
        let fixture = try TemporaryDirectory()
        for type: UInt8 in [49, 54] {
            let archive = fixture.url.appendingPathComponent("special-\(type).tar")
            try tarFixture([ArchiveFixtureEntry("entry", "", type: .file)], overrideType: type).write(to: archive)
            do { _ = try await ArchiveService().list(archive); XCTFail("Unsupported entry accepted") } catch {}
        }
    }

    func testArchiveCreationTreatsOptionLikeNamesAsOperandsAndKeepsExistingArchive() async throws {
        let fixture = try TemporaryDirectory()
        let sources = try ["-option", "@archive", "line\nbreak"].map { try fixture.createFile(named: $0) }
        for format in ArchiveFormat.allCases {
            let archive = fixture.url.appendingPathComponent("created.\(format.rawValue)")
            let result = try await ArchiveService().create(format: format, sources: sources, destination: archive)
            XCTAssertEqual(result.failedCount, 0, result.items.compactMap(\.message).description)
            let listed = try await ArchiveService().list(archive)
            XCTAssertEqual(Set(listed.map(\.path)), Set(sources.map(\.lastPathComponent)))
            let previous = try Data(contentsOf: archive)
            do { try await ArchiveService().create(format: format, sources: sources, destination: archive); XCTFail("No silent update") }
            catch {}
            XCTAssertEqual(try Data(contentsOf: archive), previous)
        }
    }
}

private struct ArchiveFixtureEntry {
    enum Kind { case file, link }
    let path: String
    let text: String
    let type: Kind
    init(_ path: String, _ text: String, type: Kind = .file) { self.path = path; self.text = text; self.type = type }
}

private func archiveFixture(_ entries: [ArchiveFixtureEntry], format: ArchiveFormat) -> Data {
    if format == .tar { return tarFixture(entries) }
    var data = Data()
    var directory = Data()
    func crc(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xffff_ffff
        for byte in data {
            value ^= UInt32(byte)
            for _ in 0..<8 { value = (value >> 1) ^ ((value & 1) == 1 ? 0xedb8_8320 : 0) }
        }
        return ~value
    }
    func append(_ value: UInt32, bytes: Int, to data: inout Data) {
        for shift in 0..<bytes { data.append(UInt8(truncatingIfNeeded: value >> (shift * 8))) }
    }
    for entry in entries {
        let name = Data(entry.path.utf8)
        let payload = Data(entry.text.utf8)
        let offset = UInt32(data.count)
        let checksum = crc(payload)
        append(0x04034b50, bytes: 4, to: &data)
        for value: UInt32 in [20, 0x800, 0, 0, 0] { append(value, bytes: 2, to: &data) }
        for value in [checksum, UInt32(payload.count), UInt32(payload.count)] { append(value, bytes: 4, to: &data) }
        append(UInt32(name.count), bytes: 2, to: &data); append(0, bytes: 2, to: &data)
        data += name; data += payload
        append(0x02014b50, bytes: 4, to: &directory)
        for value: UInt32 in [0x0314, 20, 0x800, 0, 0, 0] { append(value, bytes: 2, to: &directory) }
        for value in [checksum, UInt32(payload.count), UInt32(payload.count)] { append(value, bytes: 4, to: &directory) }
        for value in [UInt32(name.count), 0, 0, 0, 0] { append(value, bytes: 2, to: &directory) }
        append(UInt32(entry.type == .link ? 0o120777 : 0o100644) << 16, bytes: 4, to: &directory)
        append(offset, bytes: 4, to: &directory); directory += name
    }
    let offset = data.count
    data += directory
    append(0x06054b50, bytes: 4, to: &data)
    for value in [UInt32(0), 0, UInt32(entries.count), UInt32(entries.count)] { append(value, bytes: 2, to: &data) }
    append(UInt32(directory.count), bytes: 4, to: &data); append(UInt32(offset), bytes: 4, to: &data)
    append(0, bytes: 2, to: &data)
    return data
}

private func tarFixture(_ entries: [ArchiveFixtureEntry], overrideType: UInt8? = nil) -> Data {
    var archive = Data()
    for entry in entries {
        var header = [UInt8](repeating: 0, count: 512)
        func field(_ value: String, _ start: Int, _ count: Int) {
            for (offset, byte) in value.utf8.prefix(count).enumerated() { header[start + offset] = byte }
        }
        let payload = entry.type == .link ? Data() : Data(entry.text.utf8)
        field(entry.path, 0, 100)
        field("0000644", 100, 8); field("0000000", 108, 8); field("0000000", 116, 8)
        field(String(format: "%011o", payload.count), 124, 12)
        field("00000000000", 136, 12)
        for index in 148..<156 { header[index] = 32 }
        header[156] = overrideType ?? (entry.type == .link ? 50 : 48)
        if entry.type == .link { field(entry.text, 157, 100) }
        field("ustar", 257, 6); field("00", 263, 2)
        let sum = header.reduce(0) { $0 + Int($1) }
        field(String(format: "%06o", sum) + "\0 ", 148, 8)
        archive += Data(header); archive += payload
        if payload.count % 512 != 0 { archive += Data(repeating: 0, count: 512 - payload.count % 512) }
    }
    archive += Data(repeating: 0, count: 1024)
    return archive
}
