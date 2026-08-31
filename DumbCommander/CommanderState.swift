import Foundation

enum ActivePanel: Sendable {
    case left
    case right

    var opposite: ActivePanel {
        self == .left ? .right : .left
    }
}

enum AppAction: Sendable {
    case view
    case edit
    case copy
    case move
    case rename
    case newFolder
    case delete
}

@MainActor
final class PanelState: ObservableObject {
    @Published private(set) var directory: URL
    @Published private(set) var items: [FileItem] = []
    @Published var cursor: PanelCursor?
    @Published private(set) var markedURLs: Set<URL> = []
    @Published private(set) var sort = PanelSort()
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    @Published private(set) var backHistory: [URL] = []
    @Published private(set) var forwardHistory: [URL] = []

    private var loadGeneration = 0

    init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    var selectedItem: FileItem? {
        guard let selectedURL = cursor?.itemURL else { return nil }
        return items.first { $0.url == selectedURL }
    }

    var operationTargets: [URL] {
        if !markedURLs.isEmpty {
            return items.map(\.url).filter(markedURLs.contains)
        }
        return selectedItem.map { [$0.url] } ?? []
    }

    var selectableCursors: [PanelCursor] {
        var values: [PanelCursor] = [.currentDirectory]
        if directory.deletingLastPathComponent() != directory {
            values.append(.parentDirectory)
        }
        values.append(contentsOf: items.map { .item($0.url) })
        return values
    }

    func navigate(to newDirectory: URL, recordHistory: Bool = true) {
        let normalized = newDirectory.standardizedFileURL
        guard normalized != directory else { return }
        if recordHistory {
            backHistory.append(directory)
            forwardHistory.removeAll()
        }
        directory = normalized
        clearSelection()
        invalidatePendingLoad()
    }

    func goUp() {
        let parent = directory.deletingLastPathComponent()
        guard parent != directory else { return }
        navigate(to: parent)
    }

    func goBack() {
        guard let previous = backHistory.popLast() else { return }
        forwardHistory.append(directory)
        directory = previous
        clearSelection()
        invalidatePendingLoad()
    }

    func goForward() {
        guard let next = forwardHistory.popLast() else { return }
        backHistory.append(directory)
        directory = next
        clearSelection()
        invalidatePendingLoad()
    }

    func select(_ cursor: PanelCursor?) {
        self.cursor = cursor
    }

    func toggleMark(for url: URL) {
        guard items.contains(where: { $0.url == url }) else { return }
        if markedURLs.contains(url) {
            markedURLs.remove(url)
        } else {
            markedURLs.insert(url)
        }
    }

    func clearSelection() {
        cursor = nil
        markedURLs.removeAll()
    }

    func setSort(key: FileSortKey) {
        if sort.key == key {
            sort.ascending.toggle()
        } else {
            sort = PanelSort(key: key, ascending: true)
        }
        items = items.sorted(using: sort)
    }

    func moveCursor(up: Bool) {
        let cursors = selectableCursors
        guard !cursors.isEmpty else {
            cursor = nil
            return
        }

        guard let cursor, let currentIndex = cursors.firstIndex(of: cursor) else {
            self.cursor = up ? cursors.last : cursors.first
            return
        }

        let offset = up ? -1 : 1
        let nextIndex = (currentIndex + offset + cursors.count) % cursors.count
        self.cursor = cursors[nextIndex]
    }

    func reload(using fileSystem: any FileSystemServing, showHiddenFiles: Bool) async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedDirectory = directory
        isLoading = true
        loadError = nil

        do {
            let loadedItems = try await fileSystem.contents(
                of: requestedDirectory,
                showHiddenFiles: showHiddenFiles
            )
            guard generation == loadGeneration, requestedDirectory == directory else { return }
            apply(loadedItems)
            isLoading = false
        } catch {
            guard generation == loadGeneration, requestedDirectory == directory else { return }
            items = []
            clearSelection()
            loadError = error.localizedDescription
            isLoading = false
        }
    }

    func apply(_ newItems: [FileItem]) {
        items = newItems.sorted(using: sort)
        let availableURLs = Set(items.map(\.url))
        markedURLs.formIntersection(availableURLs)
        if let selectedURL = cursor?.itemURL, !availableURLs.contains(selectedURL) {
            cursor = nil
        }
    }

    private func invalidatePendingLoad() {
        loadGeneration += 1
        isLoading = false
    }
}

@MainActor
final class CommanderState: ObservableObject {
    let leftPanel: PanelState
    let rightPanel: PanelState

    @Published var activePanel: ActivePanel = .left
    @Published var showGotoDirectoryPrompt = false
    @Published var pendingAction: AppAction?
    @Published var showLeftFavoritesPopover = false
    @Published var showRightFavoritesPopover = false
    @Published var showDirectoryAccessAlert = false
    @Published var deniedDirectory: URL?
    @Published var directoryAccessErrorMessage = ""

    init(defaultDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let directory = defaultDirectory.standardizedFileURL
        leftPanel = PanelState(directory: directory)
        rightPanel = PanelState(directory: directory)
    }

    var activePanelState: PanelState {
        panel(for: activePanel)
    }

    var targetPanelState: PanelState {
        panel(for: activePanel.opposite)
    }

    var selectedFile: URL? {
        activePanelState.selectedItem?.url
    }

    func panel(for side: ActivePanel) -> PanelState {
        side == .left ? leftPanel : rightPanel
    }

    func activate(_ side: ActivePanel) {
        activePanel = side
    }

    func toggleActivePanel() {
        activePanel = activePanel.opposite
    }
}
