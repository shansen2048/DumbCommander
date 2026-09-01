import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let commanderSelectedRowColor = Color.accentColor.opacity(0.25)
private let commanderHeaderTextColor = Color.primary
private let commanderTextColor = Color.primary
private let commanderMarkedTextColor = Color.red

private let commanderRowStripeColors: [Color] = {
    let colors = NSColor.alternatingContentBackgroundColors
    if colors.count >= 2 {
        return [Color(colors[0]), Color(colors[1])]
    }
    return [Color(NSColor.controlBackgroundColor), Color(NSColor.controlBackgroundColor)]
}()

struct FileListView: View {
    @ObservedObject var panelState: PanelState
    @ObservedObject var commanderState: CommanderState
    let fileSystem: any FileSystemServing
    let panelSide: ActivePanel
    @Binding var showFavoritesPopover: Bool

    var onView: () -> Void
    var onEdit: () -> Void
    var onCopy: () -> Void
    var onMove: () -> Void
    var onNewFolder: () -> Void
    var onDelete: () -> Void

    @State private var columnWidths: [CGFloat] = [200, 70, 90, 90]
    @State private var favoritesFilter = ""
    @State private var popoverSelectionIndex: Int?
    @State private var pathInput = ""
    @State private var volumes: [MountedVolume] = []
    @AppStorage("showHiddenFiles") private var showHiddenFiles = false
    @AppStorage("favoriteDirectories") private var favoriteDirectoriesJSON = "[]"
    @FocusState private var focusedField: PanelField?
    @FocusState private var isListFocused: Bool

    private var isActive: Bool {
        commanderState.activePanel == panelSide
    }

    private var showsUpRow: Bool {
        panelState.directory.deletingLastPathComponent() != panelState.directory
    }

    private var reloadID: ReloadID {
        ReloadID(directory: panelState.directory, showHiddenFiles: showHiddenFiles)
    }

    private var favoriteDirectories: [String] {
        decodeFavorites()
    }

    private var filteredFavorites: [String] {
        let filter = favoritesFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty else { return favoriteDirectories }
        return favoriteDirectories.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 2) {
            panelHeader
            quickFilter
            columnHeader
            fileList
            columnResizers
            keyHandler
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(commanderRowStripeColors[0])
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.blue : Color.gray, lineWidth: isActive ? 4 : 1)
        )
        .cornerRadius(8)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                commanderState.activate(panelSide)
            }
        )
        .onAppear {
            pathInput = panelState.directory.path
            if isActive { isListFocused = true }
            Task { volumes = await fileSystem.mountedVolumes() }
        }
        .onChange(of: isActive) { _, active in
            if !active, focusedField != nil {
                focusedField = nil
                commanderState.textInputActive = false
            }
            if active, focusedField == nil { isListFocused = true }
        }
        .onChange(of: panelState.directory) { _, directory in
            pathInput = directory.path
        }
        .onChange(of: focusedField) { _, field in
            if isActive {
                commanderState.textInputActive = field != nil
            }
        }
        .onChange(of: commanderState.focusFilterRequest) { _, side in
            guard side == panelSide else { return }
            commanderState.activate(panelSide)
            focusedField = .filter
            commanderState.focusFilterRequest = nil
        }
        .onChange(of: panelState.loadError) { _, errorMessage in
            guard let errorMessage else { return }
            commanderState.deniedDirectory = panelState.directory
            commanderState.directoryAccessErrorMessage = errorMessage
            commanderState.showDirectoryAccessAlert = true
        }
        .task(id: reloadID) {
            await panelState.reload(using: fileSystem, showHiddenFiles: showHiddenFiles)
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Button {
                commanderState.activate(panelSide)
                panelState.goBack()
            } label: {
                Label("Zurück", systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)
            .disabled(!panelState.canGoBack)

            Button {
                commanderState.activate(panelSide)
                panelState.goForward()
            } label: {
                Label("Vorwärts", systemImage: "chevron.right")
            }
            .labelStyle(.iconOnly)
            .disabled(!panelState.canGoForward)

            Menu {
                Button("Benutzerordner") { navigate(to: FileManager.default.homeDirectoryForCurrentUser) }
                Button("Wurzelverzeichnis") { navigate(to: URL(fileURLWithPath: "/", isDirectory: true)) }
                Divider()
                ForEach(volumes) { volume in
                    Button(volume.name) { navigate(to: volume.url) }
                }
            } label: {
                Label("Volumes", systemImage: "externaldrive")
            }
            .labelStyle(.iconOnly)

            Button {
                commanderState.activate(panelSide)
                showFavoritesPopover.toggle()
            } label: {
                Label("Favoriten", systemImage: "star")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showFavoritesPopover, arrowEdge: .bottom) {
                FavoritesPopoverView(
                    favoritesFilter: $favoritesFilter,
                    popoverSelectionIndex: $popoverSelectionIndex,
                    favorites: filteredFavorites,
                    onSelect: navigateToFavorite,
                    onEdit: editFavorite,
                    onRemove: removeFavorite,
                    onClose: { showFavoritesPopover = false },
                    currentPath: panelState.directory.path,
                    onAddCurrent: addCurrentDirectoryToFavorites,
                    onAddFromPanel: addFavoritesFromPanel
                )
            }

            Picker(
                "Favoriten",
                selection: Binding(
                    get: { panelState.directory.path },
                    set: { navigateToFavorite($0) }
                )
            ) {
                Text(panelState.directory.path).tag(panelState.directory.path)
                ForEach(favoriteDirectories, id: \.self) { path in
                    Text(path).tag(path)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 180)
            .clipped()

            TextField("Pfad", text: $pathInput)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .focused($focusedField, equals: .path)
                .onSubmit { openPathInput() }
                .accessibilityIdentifier(panelSide == .left ? "leftPathField" : "rightPathField")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .cornerRadius(6)
    }

    private var quickFilter: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
            TextField(
                "Schnellfilter",
                text: Binding(
                    get: { panelState.filterText },
                    set: { panelState.setFilter($0) }
                )
            )
            .textFieldStyle(.plain)
            .focused($focusedField, equals: .filter)
            .accessibilityIdentifier(panelSide == .left ? "leftFilterField" : "rightFilterField")
            if !panelState.filterText.isEmpty {
                Text("\(panelState.visibleItems.count)/\(panelState.items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    panelState.setFilter("")
                } label: {
                    Label("Filter löschen", systemImage: "xmark.circle.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            sortableHeader("Name", key: .name)
                .frame(width: columnWidths[0], alignment: .leading)
                .padding(.leading, 5)
            sortableHeader("Typ", key: .type)
                .frame(width: columnWidths[1], alignment: .leading)
            sortableHeader("Größe", key: .size)
                .frame(width: columnWidths[2], alignment: .leading)
            Text("Rechte")
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(commanderHeaderTextColor)
                .frame(width: columnWidths[3], alignment: .leading)
            Spacer(minLength: 0)
        }
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
        .overlay(GridLinesOverlay(columnWidths: columnWidths))
    }

    private var fileList: some View {
        List {
            DirectoryNavigationRowView(
                name: ".",
                isCursor: panelState.cursor == .currentDirectory,
                columnWidths: columnWidths
            ) {
                activateAndSelect(.currentDirectory)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(rowBackground(stripe: 0, cursor: .currentDirectory))

            if showsUpRow {
                DirectoryNavigationRowView(
                    name: "..",
                    isCursor: panelState.cursor == .parentDirectory,
                    columnWidths: columnWidths
                ) {
                    activateAndSelect(.parentDirectory)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(rowBackground(stripe: 1, cursor: .parentDirectory))
            }

            ForEach(Array(panelState.visibleItems.enumerated()), id: \.element.id) { index, item in
                FileRowView(
                    item: item,
                    isMarked: panelState.markedURLs.contains(item.url),
                    isCursor: panelState.cursor == .item(item.url),
                    columnWidths: columnWidths
                ) {
                    commanderState.activate(panelSide)
                    if NSEvent.modifierFlags.contains(.command) {
                        panelState.toggleMark(for: item.url)
                    } else {
                        panelState.select(.item(item.url))
                    }
                    isListFocused = true
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(
                    rowBackground(
                        stripe: index + (showsUpRow ? 2 : 1),
                        cursor: .item(item.url)
                    )
                )
            }
        }
        .listStyle(.plain)
        .focusable()
        .focused($isListFocused)
        .background(commanderRowStripeColors[0])
        .cornerRadius(10)
        .overlay {
            if panelState.isLoading && panelState.items.isEmpty {
                ProgressView("Verzeichnis wird geladen …")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var columnResizers: some View {
        HStack(spacing: 0) {
            ResizableColumn(width: $columnWidths[0])
            ResizableColumn(width: $columnWidths[1])
            ResizableColumn(width: $columnWidths[2])
            ResizableColumn(width: $columnWidths[3])
        }
        .frame(height: 5)
    }

    @ViewBuilder
    private var keyHandler: some View {
        if isActive && !showFavoritesPopover && focusedField == nil {
            KeyEventHandlingView { event in
                handleKeyEvent(event)
            }
            .frame(width: 0, height: 0)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if NSApp.keyWindow?.firstResponder is NSTextView {
            return false
        }
        if event.keyCode == 12 && modifiers.contains(.command) {
            return false
        }
        if modifiers.contains(.control) {
            switch event.keyCode {
            case 116:
                panelState.goUp()
                return true
            case 121:
                openSelectedDirectoryIfPossible()
                return true
            default:
                return false
            }
        }

        let blockers: NSEvent.ModifierFlags = [.command, .option, .shift]
        guard modifiers.intersection(blockers).isEmpty else { return false }

        switch event.keyCode {
        case 126:
            panelState.moveCursor(up: true)
            return true
        case 125:
            panelState.moveCursor(up: false)
            return true
        case 49:
            if let url = panelState.cursor?.itemURL {
                panelState.toggleMark(for: url)
                panelState.moveCursor(up: false)
            }
            return true
        case 36:
            openCursor()
            return true
        case 48:
            commanderState.toggleActivePanel()
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func sortableHeader(_ title: String, key: FileSortKey) -> some View {
        Button {
            panelState.setSort(key: key)
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(commanderHeaderTextColor)
                if panelState.sort.key == key {
                    Image(systemName: panelState.sort.ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func rowBackground(stripe: Int, cursor: PanelCursor) -> Color {
        panelState.cursor == cursor
            ? commanderSelectedRowColor
            : commanderRowStripeColors[stripe % 2]
    }

    private func activateAndSelect(_ cursor: PanelCursor) {
        commanderState.activate(panelSide)
        panelState.select(cursor)
        isListFocused = true
    }

    private func navigate(to url: URL) {
        commanderState.activate(panelSide)
        panelState.navigate(to: url)
    }

    private func openPathInput() {
        let expanded = NSString(string: pathInput)
            .expandingTildeInPath
        let requestedURL = URL(fileURLWithPath: expanded, isDirectory: true)
            .standardizedFileURL
        Task {
            do {
                let info = try await fileSystem.entryInfo(at: requestedURL)
                guard info.kind == .directory else {
                    throw FileSystemServiceError.notDirectory(requestedURL)
                }
                panelState.navigate(to: requestedURL)
                focusedField = nil
            } catch {
                commanderState.deniedDirectory = requestedURL
                commanderState.directoryAccessErrorMessage = error.localizedDescription
                commanderState.showDirectoryAccessAlert = true
                pathInput = panelState.directory.path
            }
        }
    }

    private func openCursor() {
        guard let cursor = panelState.cursor else { return }
        switch cursor {
        case .currentDirectory:
            break
        case .parentDirectory:
            panelState.goUp()
        case let .item(url):
            guard let item = panelState.items.first(where: { $0.url == url }) else { return }
            if item.isNavigableDirectory {
                panelState.navigate(to: item.url)
            } else {
                onView()
            }
        }
    }

    private func openSelectedDirectoryIfPossible() {
        guard
            let url = panelState.cursor?.itemURL,
            let item = panelState.items.first(where: { $0.url == url }),
            item.isNavigableDirectory
        else { return }
        panelState.navigate(to: item.url)
    }

    private func decodeFavorites() -> [String] {
        let data = Data(favoriteDirectoriesJSON.utf8)
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func encodeFavorites(_ paths: [String]) {
        guard
            let data = try? JSONEncoder().encode(paths),
            let json = String(data: data, encoding: .utf8)
        else { return }
        favoriteDirectoriesJSON = json
    }

    private func navigateToFavorite(_ path: String) {
        commanderState.activate(panelSide)
        panelState.navigate(to: URL(fileURLWithPath: path))
        showFavoritesPopover = false
    }

    private func editFavorite(_ path: String) {
        var favorites = decodeFavorites()
        guard let index = favorites.firstIndex(of: path) else { return }
        let panel = directoryOpenPanel(title: "Favoriten-Verzeichnis ändern", multiple: false)
        if panel.runModal() == .OK, let url = panel.url {
            favorites[index] = url.path
            encodeFavorites(favorites)
        }
    }

    private func removeFavorite(_ path: String) {
        var favorites = decodeFavorites()
        favorites.removeAll { $0 == path }
        encodeFavorites(favorites)
    }

    private func addCurrentDirectoryToFavorites() {
        var favorites = decodeFavorites()
        let path = panelState.directory.path
        if !favorites.contains(path) {
            favorites.append(path)
            encodeFavorites(favorites)
        }
    }

    private func addFavoritesFromPanel() {
        let panel = directoryOpenPanel(title: "Favoriten-Verzeichnisse hinzufügen", multiple: true)
        guard panel.runModal() == .OK else { return }
        var favorites = decodeFavorites()
        for url in panel.urls where !favorites.contains(url.path) {
            favorites.append(url.path)
        }
        encodeFavorites(favorites)
    }

    private func directoryOpenPanel(title: String, multiple: Bool) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = multiple
        panel.title = title
        panel.allowedContentTypes = [.folder]
        return panel
    }
}

private extension FileListView {
    struct ReloadID: Hashable {
        let directory: URL
        let showHiddenFiles: Bool
    }

    enum PanelField: Hashable {
        case path
        case filter
    }

    struct FileRowView: View {
        let item: FileItem
        let isMarked: Bool
        let isCursor: Bool
        let columnWidths: [CGFloat]
        let onTap: () -> Void

        private var textColor: Color {
            isMarked ? commanderMarkedTextColor : commanderTextColor
        }

        var body: some View {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: isMarked ? "checkmark.square.fill" : (isCursor ? "arrowtriangle.right.fill" : "square"))
                        .font(.caption)
                        .foregroundStyle(isMarked ? Color.red : Color.secondary)
                    Text(item.name)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(isMarked ? .semibold : .regular)
                        .foregroundColor(textColor)
                }
                    .frame(width: columnWidths[0], alignment: .leading)
                    .padding(.leading, 5)
                Text(item.typeDescription)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(textColor)
                    .frame(width: columnWidths[1], alignment: .leading)
                Text(item.formattedSize)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(textColor)
                    .frame(width: columnWidths[2], alignment: .leading)
                Text(item.permissions)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(textColor)
                    .frame(width: columnWidths[3], alignment: .leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .overlay(GridLinesOverlay(columnWidths: columnWidths))
            .accessibilityLabel(item.name)
            .accessibilityValue(
                [isCursor ? "Cursor" : nil, isMarked ? "Markiert" : nil, item.typeDescription]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            )
        }
    }

    struct DirectoryNavigationRowView: View {
        let name: String
        var isCursor = false
        let columnWidths: [CGFloat]
        let onTap: () -> Void

        var body: some View {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: isCursor ? "arrowtriangle.right.fill" : "square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(commanderTextColor)
                }
                    .frame(width: columnWidths[0], alignment: .leading)
                    .padding(.leading, 5)
                Spacer()
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .overlay(GridLinesOverlay(columnWidths: columnWidths))
            .accessibilityValue(isCursor ? "Cursor" : "")
        }
    }

    struct FavoritesPopoverView: View {
        @Binding var favoritesFilter: String
        @Binding var popoverSelectionIndex: Int?
        let favorites: [String]
        let onSelect: (String) -> Void
        let onEdit: (String) -> Void
        let onRemove: (String) -> Void
        let onClose: () -> Void
        let currentPath: String
        let onAddCurrent: () -> Void
        let onAddFromPanel: () -> Void

        @FocusState private var isSearchFocused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Favoriten").font(.headline)
                TextField("Suchen …", text: $favoritesFilter)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                    .onChange(of: favoritesFilter) { _, _ in
                        popoverSelectionIndex = favorites.isEmpty ? nil : 0
                    }

                HStack(spacing: 6) {
                    Image(systemName: "location")
                    Text(currentPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Öffnen") { onSelect(currentPath) }
                    if favorites.contains(currentPath) {
                        Button("Aus Favoriten entfernen") { onRemove(currentPath) }
                    } else {
                        Button("Zu Favoriten hinzufügen") { onAddCurrent() }
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 4)

                Button("Favorit hinzufügen …") { onAddFromPanel() }

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(favorites.enumerated()), id: \.offset) { index, path in
                            Button {
                                onSelect(path)
                            } label: {
                                Label(path, systemImage: "folder")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .background(
                                popoverSelectionIndex == index
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear
                            )
                            .contextMenu {
                                Button("Ändern …") { onEdit(path) }
                                Button("Entfernen", role: .destructive) { onRemove(path) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                KeyEventHandlingView { event in
                    handleKey(event)
                }
                .frame(width: 0, height: 0)

                HStack {
                    Spacer()
                    Button("Schließen") { onClose() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .onAppear {
                popoverSelectionIndex = favorites.firstIndex(of: currentPath)
                    ?? (favorites.isEmpty ? nil : 0)
                isSearchFocused = true
            }
            .padding(10)
            .frame(minWidth: 380, minHeight: 220)
        }

        private func handleKey(_ event: NSEvent) -> Bool {
            switch event.keyCode {
            case 126:
                popoverSelectionIndex = max(0, (popoverSelectionIndex ?? 0) - 1)
                return true
            case 125:
                guard !favorites.isEmpty else { return true }
                popoverSelectionIndex = min(favorites.count - 1, (popoverSelectionIndex ?? -1) + 1)
                return true
            case 36:
                if let index = popoverSelectionIndex, favorites.indices.contains(index) {
                    onSelect(favorites[index])
                }
                return true
            case 51:
                if let index = popoverSelectionIndex, favorites.indices.contains(index) {
                    onRemove(favorites[index])
                }
                return true
            case 53:
                onClose()
                return true
            default:
                return false
            }
        }
    }
}

private struct GridLinesOverlay: View {
    let columnWidths: [CGFloat]

    var body: some View {
        GeometryReader { geometry in
            let positions = [
                columnWidths[0],
                columnWidths[0] + columnWidths[1],
                columnWidths[0] + columnWidths[1] + columnWidths[2],
                columnWidths.reduce(0, +)
            ]
            Path { path in
                for x in positions {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }
            }
            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        }
    }
}

private struct ResizableColumn: View {
    @Binding var width: CGFloat
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Rectangle()
            .foregroundColor(.clear)
            .frame(width: 5)
            .background(Color.gray.opacity(0.5))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let start = dragStartWidth ?? width
                        dragStartWidth = start
                        width = max(50, start + value.translation.width)
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
    }
}
