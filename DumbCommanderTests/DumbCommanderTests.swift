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

    func testCopyDoesNotOverwriteExistingDestination() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let sourceDirectory = try temporaryDirectory.createDirectory(named: "source")
        let destinationDirectory = try temporaryDirectory.createDirectory(named: "destination")
        let source = sourceDirectory.appendingPathComponent("example.txt")
        let destination = destinationDirectory.appendingPathComponent("example.txt")
        try Data("source".utf8).write(to: source)
        try Data("destination".utf8).write(to: destination)
        let service = LocalFileSystemService()

        let result = await service.copy([source], to: destinationDirectory)

        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "destination")
    }

    func testCopyRejectsDestinationInsideSourceDirectory() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let source = try temporaryDirectory.createDirectory(named: "source")
        let child = source.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let service = LocalFileSystemService()

        let result = await service.copy([source], to: child)

        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: child.appendingPathComponent("source").path
            )
        )
    }

    func testTrashFailureNeverFallsBackToPermanentDeletion() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let source = try temporaryDirectory.createFile(named: "keep-me.txt")
        let service = LocalFileSystemService { _ in
            throw CocoaError(.fileWriteNoPermission)
        }

        let result = await service.moveToTrash([source])

        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
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

    func copy(_ sources: [URL], to destinationDirectory: URL) async -> FileOperationResult {
        FileOperationResult()
    }

    func move(_ sources: [URL], to destinationDirectory: URL) async -> FileOperationResult {
        FileOperationResult()
    }

    func rename(_ source: URL, to newName: String) async -> FileOperationResult {
        FileOperationResult()
    }

    func createDirectory(in parent: URL, preferredName: String) async -> FileOperationResult {
        FileOperationResult()
    }

    func moveToTrash(_ sources: [URL]) async -> FileOperationResult {
        FileOperationResult()
    }
}
