import Foundation

enum ActivePanel: String, Codable, Hashable, Sendable {
    case left
    case right

    var opposite: ActivePanel {
        self == .left ? .right : .left
    }
}

@MainActor
final class PanelState: ObservableObject {
    let id = UUID()
    @Published private(set) var directory: URL
    @Published private(set) var items: [FileItem] = []
    @Published var cursor: PanelCursor?
    @Published private(set) var markedURLs: Set<URL> = []
    @Published private(set) var sort = PanelSort()
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    @Published private(set) var backHistory: [URL] = []
    @Published private(set) var forwardHistory: [URL] = []
    @Published private(set) var filterText = ""
    @Published private(set) var virtualTitle: String?

    private var loadGeneration = 0
    var onDirectoryChanged: (() -> Void)?

    init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    var selectedItem: FileItem? {
        guard let selectedURL = cursor?.itemURL else { return nil }
        return items.first { $0.url == selectedURL }
    }

    var isVirtual: Bool { virtualTitle != nil }

    var displayTitle: String {
        virtualTitle ?? (directory.lastPathComponent.isEmpty ? directory.path : directory.lastPathComponent)
    }

    var operationTargets: [URL] {
        if !markedURLs.isEmpty {
            return visibleItems.map(\.url).filter(markedURLs.contains)
        }
        return selectedItem.map { [$0.url] } ?? []
    }

    func openingTargets(for item: FileItem, includeMarkedItems: Bool) -> [URL] {
        if includeMarkedItems, !markedURLs.isEmpty {
            return visibleItems.map(\.url).filter(markedURLs.contains)
        }
        return [item.url]
    }

    var visibleItems: [FileItem] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var selectableCursors: [PanelCursor] {
        var values: [PanelCursor] = [.currentDirectory]
        if directory.deletingLastPathComponent() != directory {
            values.append(.parentDirectory)
        }
        values.append(contentsOf: visibleItems.map { .item($0.url) })
        return values
    }

    var canGoBack: Bool { !backHistory.isEmpty }
    var canGoForward: Bool { !forwardHistory.isEmpty }

    func navigate(to newDirectory: URL, recordHistory: Bool = true) {
        let normalized = newDirectory.standardizedFileURL
        guard normalized != directory || isVirtual else { return }
        if recordHistory {
            backHistory.append(directory)
            forwardHistory.removeAll()
        }
        directory = normalized
        virtualTitle = nil
        clearSelection()
        invalidatePendingLoad()
        onDirectoryChanged?()
    }

    func navigateResolvingLinks(
        to requestedDirectory: URL,
        using fileSystem: any FileSystemServing,
        recordHistory: Bool = true
    ) async throws {
        let info = try await fileSystem.resolvedEntry(at: requestedDirectory)
        guard info.kind == .directory else {
            throw FileSystemServiceError.notDirectory(requestedDirectory)
        }
        navigate(to: info.url, recordHistory: recordHistory)
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
        onDirectoryChanged?()
    }

    func goForward() {
        guard let next = forwardHistory.popLast() else { return }
        backHistory.append(directory)
        directory = next
        clearSelection()
        invalidatePendingLoad()
        onDirectoryChanged?()
    }

    func goHome() {
        navigate(to: FileManager.default.homeDirectoryForCurrentUser)
    }

    func goRoot() {
        navigate(to: URL(fileURLWithPath: "/", isDirectory: true))
    }

    func setFilter(_ value: String) {
        filterText = value
        if let cursorURL = cursor?.itemURL,
           !visibleItems.contains(where: { $0.url == cursorURL }) {
            cursor = nil
        }
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

    func setMarks(_ urls: Set<URL>) {
        let available = Set(items.map(\.url))
        markedURLs = urls.intersection(available)
    }

    func markItems(matching wildcard: String) {
        markedURLs = Set(
            visibleItems.filter { FileSearchService.matches($0.name, wildcard: wildcard) }.map(\.url)
        )
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
        guard !isVirtual else { return }
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

    func showSearchResults(_ results: [FileItem], title: String, root: URL) {
        directory = root.standardizedFileURL
        virtualTitle = title
        filterText = ""
        clearSelection()
        invalidatePendingLoad()
        apply(results)
    }

    private func invalidatePendingLoad() {
        loadGeneration += 1
        isLoading = false
    }
}

@MainActor
final class CommanderState: ObservableObject {
    @Published private(set) var leftTabs: [PanelState]
    @Published private(set) var rightTabs: [PanelState]
    @Published private(set) var selectedLeftTabIndex = 0
    @Published private(set) var selectedRightTabIndex = 0

    @Published var activePanel: ActivePanel {
        didSet {
            if oldValue != activePanel { persistSession() }
        }
    }
    @Published var showGotoDirectoryPrompt = false
    @Published var pendingCommand: CommanderCommand?
    @Published var showLeftFavoritesPopover = false
    @Published var showRightFavoritesPopover = false
    @Published var showDirectoryAccessAlert = false
    @Published var deniedDirectory: URL?
    @Published var directoryAccessErrorMessage = ""
    @Published var focusFilterRequest: ActivePanel?
    @Published var textInputActive = false
    @Published var commandShortcutsBlocked = false

    private let sessionStore: (any CommanderSessionStoring)?
    private var pendingRestoredSession: CommanderSession?
    private var isRestoringSession = false

    init(
        defaultDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        sessionStore: (any CommanderSessionStoring)? = nil
    ) {
        self.sessionStore = sessionStore
        let fallback = defaultDirectory.standardizedFileURL
        let session = sessionStore?.load()
        pendingRestoredSession = session
        let initialLeft = PanelState(directory: fallback)
        let initialRight = PanelState(directory: fallback)
        leftTabs = [initialLeft]
        rightTabs = [initialRight]
        activePanel = session
            .flatMap { ActivePanel(rawValue: $0.activePanel) }
            ?? .left

        configure(initialLeft)
        configure(initialRight)
    }

    var leftPanel: PanelState { leftTabs[selectedLeftTabIndex] }
    var rightPanel: PanelState { rightTabs[selectedRightTabIndex] }

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

    func tabs(for side: ActivePanel) -> [PanelState] {
        side == .left ? leftTabs : rightTabs
    }

    func selectedTabIndex(for side: ActivePanel) -> Int {
        side == .left ? selectedLeftTabIndex : selectedRightTabIndex
    }

    func selectTab(_ index: Int, in side: ActivePanel) {
        guard tabs(for: side).indices.contains(index) else { return }
        if side == .left {
            selectedLeftTabIndex = index
        } else {
            selectedRightTabIndex = index
        }
        activate(side)
        persistSession()
    }

    func addTab(in side: ActivePanel, directory: URL? = nil) {
        let panel = PanelState(directory: directory ?? self.panel(for: side).directory)
        configure(panel)
        if side == .left {
            leftTabs.append(panel)
            selectedLeftTabIndex = leftTabs.count - 1
        } else {
            rightTabs.append(panel)
            selectedRightTabIndex = rightTabs.count - 1
        }
        activate(side)
    }

    func closeTab(_ index: Int, in side: ActivePanel) {
        guard tabs(for: side).count > 1, tabs(for: side).indices.contains(index) else { return }
        if side == .left {
            leftTabs.remove(at: index)
            selectedLeftTabIndex = min(selectedLeftTabIndex, leftTabs.count - 1)
        } else {
            rightTabs.remove(at: index)
            selectedRightTabIndex = min(selectedRightTabIndex, rightTabs.count - 1)
        }
        persistSession()
    }

    func activate(_ side: ActivePanel) {
        activePanel = side
    }

    func toggleActivePanel() {
        activePanel = activePanel.opposite
    }

    func dispatch(_ command: CommanderCommand) {
        pendingCommand = command
    }

    func persistSession() {
        guard !isRestoringSession else { return }
        sessionStore?.save(
            CommanderSession(
                leftDirectoryPath: leftPanel.directory.path,
                rightDirectoryPath: rightPanel.directory.path,
                activePanel: activePanel.rawValue
            )
        )
    }

    func restoreSession(using fileSystem: any FileSystemServing) async {
        guard let session = pendingRestoredSession else { return }
        pendingRestoredSession = nil

        async let validatedLeft = Self.validatedDirectory(
            path: session.leftDirectoryPath,
            using: fileSystem
        )
        async let validatedRight = Self.validatedDirectory(
            path: session.rightDirectoryPath,
            using: fileSystem
        )
        let (left, right) = await (validatedLeft, validatedRight)

        isRestoringSession = true
        if let left { leftPanel.navigate(to: left, recordHistory: false) }
        if let right { rightPanel.navigate(to: right, recordHistory: false) }
        activePanel = ActivePanel(rawValue: session.activePanel) ?? .left
        isRestoringSession = false
        persistSession()
    }

    private static func validatedDirectory(
        path: String,
        using fileSystem: any FileSystemServing
    ) async -> URL? {
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        guard let info = try? await fileSystem.resolvedEntry(at: url),
              info.kind == .directory else {
            return nil
        }
        return info.url
    }

    private func configure(_ panel: PanelState) {
        panel.onDirectoryChanged = { [weak self] in self?.persistSession() }
    }
}
