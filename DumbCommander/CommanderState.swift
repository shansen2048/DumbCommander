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

    private var loadGeneration = 0
    var onDirectoryChanged: (() -> Void)?

    init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    var selectedItem: FileItem? {
        guard let selectedURL = cursor?.itemURL else { return nil }
        return items.first { $0.url == selectedURL }
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
        guard normalized != directory else { return }
        if recordHistory {
            backHistory.append(directory)
            forwardHistory.removeAll()
        }
        directory = normalized
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
        leftPanel = PanelState(directory: fallback)
        rightPanel = PanelState(directory: fallback)
        activePanel = session
            .flatMap { ActivePanel(rawValue: $0.activePanel) }
            ?? .left

        leftPanel.onDirectoryChanged = { [weak self] in self?.persistSession() }
        rightPanel.onDirectoryChanged = { [weak self] in self?.persistSession() }
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
}
