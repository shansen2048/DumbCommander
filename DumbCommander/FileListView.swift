import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers

let commanderSelectedRowColor = Color.accentColor.opacity(0.25)
let commanderHeaderTextColor = Color.primary
let commanderTextColor = Color.primary
let commanderMarkedTextColor = Color.red

// Alternating row backgrounds (light/dark), adapts to system appearance
let commanderRowStripeColors: [Color] = {
    let colors = NSColor.alternatingContentBackgroundColors
    if colors.count >= 2 {
        return [Color(colors[0]), Color(colors[1])]
    }
    return [Color(NSColor.controlBackgroundColor), Color(NSColor.controlBackgroundColor)]
}()

enum FileSortKey {
    case name, type, size
}

struct FileListView: View {
    @Binding var currentDirectory: URL
    @State private var files: [URL] = []
    @State private var columnWidths: [CGFloat] = [200, 60, 80, 80]
    @State private var selectedIndex: Int?
    @State private var markedIndices: Set<Int> = []
    @State private var sortKey: FileSortKey = .name
    @State private var sortAscending: Bool = true
    @State private var favoritesFilter: String = ""
    @State private var popoverSelectionIndex: Int? = nil
    @AppStorage("showHiddenFiles") private var showHiddenFiles: Bool = false
    @AppStorage("favoriteDirectories") private var favoriteDirectoriesJSON: String = "[]"
    var isActive: Bool
    @ObservedObject var appState: AppState
    var onView: () -> Void
    var onEdit: () -> Void
    var onCopy: () -> Void
    var onMove: () -> Void
    var onNewFolder: () -> Void
    var onDelete: () -> Void
    var onTab: (() -> Void)?
    var panelSide: ActivePanel = .left
    @Binding var showFavoritesPopover: Bool

    @FocusState private var isFocused: Bool

    private var showsUpRow: Bool {
        guard let parent = currentDirectory.parent else { return false }
        return parent != currentDirectory
    }

    private var fileRowStripeOffset: Int {
        showsUpRow ? 2 : 1
    }

    private var lastSelectableIndex: Int {
        files.isEmpty ? (showsUpRow ? -1 : -2) : files.count - 1
    }

    private func decodeFavorites() -> [String] {
        let data = Data(favoriteDirectoriesJSON.utf8)
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func encodeFavorites(_ paths: [String]) {
        if let data = try? JSONEncoder().encode(paths), let json = String(data: data, encoding: .utf8) {
            favoriteDirectoriesJSON = json
        }
    }

    private var favoriteDirectories: [String] {
        decodeFavorites()
    }

    private var filteredFavorites: [String] {
        let f = favoritesFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = favoriteDirectories
        if f.isEmpty { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(f) }
    }

    // Row background: alternating stripes, selection wins
    private func rowBackground(stripe: Int, isSelected: Bool) -> Color {
        isSelected ? commanderSelectedRowColor : commanderRowStripeColors[stripe % 2]
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Button {
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
                        onSelect: { path in
                            let url = URL(fileURLWithPath: path)
                            if FileManager.default.fileExists(atPath: url.path), url.isDirectory {
                                currentDirectory = url
                                loadFiles()
                                appState.activePanel = panelSide
                                showFavoritesPopover = false
                            }
                        },
                        onEdit: { path in
                            var all = decodeFavorites()
                            if let realIdx = all.firstIndex(of: path) {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.allowsMultipleSelection = false
                                panel.title = "Favoriten-Verzeichnis ändern"
                                panel.allowedContentTypes = [.folder]
                                if panel.runModal() == .OK, let url = panel.url {
                                    all[realIdx] = url.path
                                    encodeFavorites(all)
                                }
                            }
                        },
                        onRemove: { path in
                            var all = decodeFavorites()
                            if let realIdx = all.firstIndex(of: path) {
                                all.remove(at: realIdx)
                                encodeFavorites(all)
                            }
                        },
                        onClose: {
                            showFavoritesPopover = false
                        },
                        currentPath: currentDirectory.path,
                        onAddCurrent: {
                            var all = decodeFavorites()
                            let p = currentDirectory.path
                            if !all.contains(p) {
                                all.append(p)
                                encodeFavorites(all)
                            }
                        },
                        onAddFromPanel: {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.allowsMultipleSelection = true
                            panel.title = "Favoriten-Verzeichnisse hinzufügen"
                            panel.allowedContentTypes = [.folder]
                            if panel.runModal() == .OK {
                                var all = decodeFavorites()
                                for url in panel.urls {
                                    let p = url.path
                                    if !all.contains(p) { all.append(p) }
                                }
                                encodeFavorites(all)
                            }
                        }
                    )
                }

                Picker("Favoriten", selection: Binding<String>(
                    get: { currentDirectory.path },
                    set: { newPath in
                        let url = URL(fileURLWithPath: newPath)
                        if FileManager.default.fileExists(atPath: url.path), url.isDirectory {
                            currentDirectory = url
                            loadFiles()
                            appState.activePanel = panelSide
                        }
                    })) {
                    Group {
                        Text(currentDirectory.path).tag(currentDirectory.path)
                        ForEach(favoriteDirectories, id: \.self) { path in
                            Text(path).tag(path)
                        }
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 280)
                .clipped()

                Text(currentDirectory.path)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .cornerRadius(6)

            // Column headers (clickable for sorting)
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
                    .foregroundColor(Color(NSColor.separatorColor)), alignment: .bottom
            )
            .overlay(GridLinesOverlay(columnWidths: columnWidths))

            List {
                DirectoryNavigationRowView(
                    name: ".",
                    columnWidths: columnWidths
                ) {
                    selectedIndex = -2
                    appState.selectedFile = currentDirectory
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(rowBackground(stripe: 0, isSelected: selectedIndex == -2))

                if showsUpRow {
                    DirectoryNavigationRowView(
                        name: "..",
                        columnWidths: columnWidths
                    ) {
                        goUpOneDirectory()
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(rowBackground(stripe: 1, isSelected: selectedIndex == -1))
                }

                ForEach(Array(files.enumerated()), id: \.element) { index, file in
                    FileRowView(
                        file: file,
                        isSelected: index == selectedIndex,
                        isMarked: markedIndices.contains(index),
                        columnWidths: columnWidths
                    ) {
                        // Cmd-click toggles the mark, plain click moves the cursor
                        if NSEvent.modifierFlags.contains(.command) {
                            toggleMark(at: index)
                        } else {
                            selectFile(at: index)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(rowBackground(stripe: index + fileRowStripeOffset, isSelected: index == selectedIndex))
                }
            }
            .listStyle(.plain)
            .onChange(of: currentDirectory) { oldValue, newValue in
                DispatchQueue.main.async {
                    loadFiles()
                }
            }
            .onChange(of: showHiddenFiles) { oldValue, newValue in
                DispatchQueue.main.async {
                    loadFiles()
                }
            }
            .onChange(of: appState.refreshTrigger) { oldValue, newValue in
                DispatchQueue.main.async {
                    loadFiles()
                }
            }
            .background(commanderRowStripeColors[0])
            .cornerRadius(10)

            // Resizable column handlers
            HStack(spacing: 0) {
                ResizableColumn(width: $columnWidths[0])
                ResizableColumn(width: $columnWidths[1])
                ResizableColumn(width: $columnWidths[2])
                ResizableColumn(width: $columnWidths[3])
            }
            .frame(height: 5)

            if isActive && !showFavoritesPopover {
                KeyEventHandlingView { event in
                    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

                    // While a text field is being edited (command prompt, rename, goto, search),
                    // let it receive Space/Enter/Tab/arrows instead of navigating the panel
                    if NSApp.keyWindow?.firstResponder is NSTextView {
                        return false
                    }

                    // Do not intercept Command+Q
                    if event.keyCode == 12 && modifiers.contains(.command) {
                        return false
                    }
                    // Control + PageUp/PageDown for directory navigation
                    if modifiers.contains(.control) {
                        switch event.keyCode {
                        case 116: // Page Up
                            goUpOneDirectory()
                            return true
                        case 121: // Page Down
                            goIntoSelectedDirectoryIfPossible()
                            return true
                        default:
                            return false
                        }
                    }

                    let plainKeyBlockers: NSEvent.ModifierFlags = [.command, .option, .shift]
                    if !modifiers.intersection(plainKeyBlockers).isEmpty {
                        return false
                    }

                    // Only consume keys we handle here (navigation and marking)
                    switch event.keyCode {
                    case 126, // Up arrow
                         125, // Down arrow
                         36,  // Enter/Return
                         48,  // Tab
                         49:  // Space (toggle mark)
                        onKeyDown(event)
                        return true
                    default:
                        return false
                    }
                }
                .frame(width: 0, height: 0)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(commanderRowStripeColors[0])
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.blue : Color.gray, lineWidth: isActive ? 4 : 1)
        )
        .cornerRadius(8)
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .onChange(of: isActive) { oldValue, newValue in
            // The active panel owns the marked-files list used by operations
            if newValue {
                syncMarkedFiles()
            }
        }
        .task {
            loadFiles()
        }
    }

    @ViewBuilder
    private func sortableHeader(_ title: String, key: FileSortKey) -> some View {
        Button {
            if sortKey == key {
                sortAscending.toggle()
            } else {
                sortKey = key
                sortAscending = true
            }
            sortFiles()
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(commanderHeaderTextColor)
                if sortKey == key {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    func onKeyDown(_ event: NSEvent) {
        switch event.keyCode {
        case 126: // Up arrow
            moveSelection(up: true)
        case 125: // Down arrow
            moveSelection(up: false)
        case 49: // Space: toggle mark on cursor row, then move down (classic commander behavior)
            if let idx = selectedIndex, idx >= 0, idx < files.count {
                toggleMark(at: idx)
                moveSelection(up: false)
            }
        case 36: // Enter
            if let selectedIdx = selectedIndex {
                if selectedIdx == -2 {
                    appState.selectedFile = currentDirectory
                } else if selectedIdx == -1 {
                    goUpOneDirectory()
                } else if selectedIdx >= 0 && selectedIdx < files.count {
                    let selectedFile = files[selectedIdx]
                    if selectedFile.hasDirectoryPath {
                        currentDirectory = selectedFile
                        loadFiles()
                    } else {
                        appState.selectedFile = selectedFile
                        onView()
                    }
                }
            }
        case 48: // Tab
            onTab?()
        default:
            break
        }
    }

    func loadFiles() {
        do {
            var items = try FileManager.default.contentsOfDirectory(at: currentDirectory, includingPropertiesForKeys: [.fileSizeKey, .isReadableKey, .isHiddenKey])
            if !showHiddenFiles {
                items = items.filter { url in
                    // filter dotfiles and NSURLIsHiddenKey
                    if url.lastPathComponent.hasPrefix(".") { return false }
                    let rv = try? url.resourceValues(forKeys: [.isHiddenKey])
                    if let hidden = rv?.isHidden, hidden { return false }
                    return true
                }
            }
            files = items
            selectedIndex = nil
            markedIndices = []
            syncMarkedFiles()
            sortFiles()
        } catch {
            files = []
            selectedIndex = nil
            markedIndices = []
            syncMarkedFiles()
            reportDirectoryAccessFailure(error)
            print("Error loading files: \(error)")
        }
    }

    private func reportDirectoryAccessFailure(_ error: Error) {
        guard isPermissionError(error) else { return }
        appState.deniedDirectory = currentDirectory
        appState.directoryAccessErrorMessage = error.localizedDescription
        appState.showDirectoryAccessAlert = true
    }

    private func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == CocoaError.fileReadNoPermission.rawValue ||
                nsError.code == CocoaError.fileWriteNoPermission.rawValue
        }
        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == Int(EACCES) || nsError.code == Int(EPERM)
        }
        return false
    }

    // Sort like a classic commander: directories always first, then by the chosen column
    func sortFiles() {
        files.sort { lhs, rhs in
            let lhsIsDir = lhs.hasDirectoryPath
            let rhsIsDir = rhs.hasDirectoryPath
            if lhsIsDir != rhsIsDir { return lhsIsDir }

            let ascending: Bool
            switch sortKey {
            case .name:
                ascending = lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            case .type:
                let lhsExt = lhs.pathExtension.lowercased()
                let rhsExt = rhs.pathExtension.lowercased()
                if lhsExt != rhsExt {
                    ascending = lhsExt < rhsExt
                } else {
                    ascending = lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
                }
            case .size:
                let lhsSize = fileSizeBytes(for: lhs)
                let rhsSize = fileSizeBytes(for: rhs)
                if lhsSize != rhsSize {
                    ascending = lhsSize < rhsSize
                } else {
                    ascending = lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
                }
            }
            return sortAscending ? ascending : !ascending
        }
    }

    func goUpOneDirectory() {
        if let parentDirectory = currentDirectory.parent {
            currentDirectory = parentDirectory
            loadFiles()
        }
    }

    func goIntoSelectedDirectoryIfPossible() {
        if let idx = selectedIndex, idx >= 0, idx < files.count {
            let candidate = files[idx]
            if candidate.hasDirectoryPath {
                currentDirectory = candidate
                loadFiles()
            }
        }
    }

    func selectFile(at index: Int) {
        guard index >= 0 && index < files.count else { return }
        appState.selectedFile = files[index]
        selectedIndex = index
    }

    func toggleMark(at index: Int) {
        guard index >= 0 && index < files.count else { return }
        if markedIndices.contains(index) {
            markedIndices.remove(index)
        } else {
            markedIndices.insert(index)
        }
        syncMarkedFiles()
    }

    // Publish this panel's marked files so operations in ContentView can use them
    private func syncMarkedFiles() {
        guard isActive else { return }
        appState.markedFiles = markedIndices.sorted().compactMap { idx in
            idx < files.count ? files[idx] : nil
        }
    }

    func moveSelection(up: Bool) {
        if selectedIndex == nil {
            selectedIndex = up ? lastSelectableIndex : -2
        } else if up {
            selectedIndex = previousSelectableIndex(from: selectedIndex!)
        } else {
            selectedIndex = nextSelectableIndex(from: selectedIndex!)
        }

        if let selectedIdx = selectedIndex {
            if selectedIdx == -2 {
                appState.selectedFile = currentDirectory
            } else if selectedIdx >= 0 {
                selectFile(at: selectedIdx)
            }
        }
    }

    private func previousSelectableIndex(from index: Int) -> Int {
        if index > 0 { return index - 1 }
        if index == 0 { return showsUpRow ? -1 : -2 }
        if index == -1 { return -2 }
        return lastSelectableIndex
    }

    private func nextSelectableIndex(from index: Int) -> Int {
        if index == -2 { return showsUpRow ? -1 : (files.isEmpty ? -2 : 0) }
        if index == -1 { return files.isEmpty ? -2 : 0 }
        if index >= 0 && index < files.count - 1 { return index + 1 }
        return -2
    }

    private struct FileRowView: View {
        let file: URL
        let isSelected: Bool
        let isMarked: Bool
        let columnWidths: [CGFloat]
        let onTap: () -> Void

        private var textColor: Color {
            isMarked ? commanderMarkedTextColor : commanderTextColor
        }

        var body: some View {
            HStack(spacing: 0) {
                Text(file.lastPathComponent)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(isMarked ? .semibold : .regular)
                    .foregroundColor(textColor)
                    .frame(width: columnWidths[0], alignment: .leading)
                    .padding(.leading, 5)
                Text(file.hasDirectoryPath ? "Ordner" : file.pathExtension)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(textColor)
                    .frame(width: columnWidths[1], alignment: .leading)
                Text(fileSizeString(for: file))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(textColor)
                    .frame(width: columnWidths[2], alignment: .leading)
                Text(filePermissions(for: file))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(textColor)
                    .frame(width: columnWidths[3], alignment: .leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            .overlay(GridLinesOverlay(columnWidths: columnWidths))
        }
    }

    private struct DirectoryNavigationRowView: View {
        let name: String
        let columnWidths: [CGFloat]
        let onTap: () -> Void

        var body: some View {
            HStack(spacing: 0) {
                Text(name)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(commanderTextColor)
                    .frame(width: columnWidths[0], alignment: .leading)
                    .padding(.leading, 5)
                Spacer()
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            .overlay(GridLinesOverlay(columnWidths: columnWidths))
        }
    }

    private struct FavoritesPopoverView: View {
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
                Text("Favoriten")
                    .font(.headline)
                TextField("Suchen…", text: $favoritesFilter)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                    .onChange(of: favoritesFilter) { oldValue, newValue in
                        if !favorites.isEmpty { popoverSelectionIndex = 0 } else { popoverSelectionIndex = nil }
                    }

                HStack(spacing: 6) {
                    Image(systemName: "location")
                    Text(currentPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Öffnen") { onSelect(currentPath) }
                    if !favorites.contains(currentPath) {
                        Button("Zu Favoriten hinzufügen") { onAddCurrent() }
                    } else {
                        Button("Aus Favoriten entfernen") { onRemove(currentPath) }
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 4)

                HStack {
                    Button("Favorit hinzufügen …") { onAddFromPanel() }
                    Spacer()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(favorites.enumerated()), id: \.offset) { idx, path in
                            Button {
                                onSelect(path)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                    Text(path)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .background((popoverSelectionIndex == idx) ? Color.accentColor.opacity(0.2) : Color.clear)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Ändern…") { onEdit(path) }
                                Button(role: .destructive) { onRemove(path) } label: { Text("Entfernen") }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                KeyEventHandlingView { event in
                    switch event.keyCode {
                    case 126: // Up
                        if let i = popoverSelectionIndex {
                            let newIndex = max(0, i - 1)
                            popoverSelectionIndex = newIndex
                        } else if !favorites.isEmpty {
                            popoverSelectionIndex = 0
                        }
                        return true
                    case 125: // Down
                        if let i = popoverSelectionIndex {
                            let newIndex = min(favorites.count - 1, i + 1)
                            popoverSelectionIndex = newIndex
                        } else if !favorites.isEmpty {
                            popoverSelectionIndex = 0
                        }
                        return true
                    case 36: // Enter
                        if let i = popoverSelectionIndex, i >= 0, i < favorites.count {
                            onSelect(favorites[i])
                        }
                        return true
                    case 51: // Delete key
                        if let i = popoverSelectionIndex, i >= 0, i < favorites.count {
                            onRemove(favorites[i])
                        }
                        return true
                    case 53: // Escape
                        onClose()
                        return true
                    default:
                        return false
                    }
                }
                .frame(width: 0, height: 0)
                HStack {
                    Spacer()
                    Button("Schließen") { onClose() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .onAppear {
                if let idx = favorites.firstIndex(of: currentPath) {
                    popoverSelectionIndex = idx
                } else if !favorites.isEmpty {
                    popoverSelectionIndex = 0
                } else {
                    popoverSelectionIndex = nil
                }
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            }
            .padding(10)
            .frame(minWidth: 380, minHeight: 220)
        }
    }

}

private struct GridLinesOverlay: View {
    let columnWidths: [CGFloat]
    var body: some View {
        GeometryReader { geo in
            let positions: [CGFloat] = [
                columnWidths[0],
                columnWidths[0] + columnWidths[1],
                columnWidths[0] + columnWidths[1] + columnWidths[2],
                columnWidths[0] + columnWidths[1] + columnWidths[2] + columnWidths[3]
            ]
            Path { path in
                for x in positions {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
            }
            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        }
    }
}

struct ResizableColumn: View {
    @Binding var width: CGFloat

    var body: some View {
        Rectangle()
            .foregroundColor(.clear)
            .frame(width: 5)
            .background(Color.gray.opacity(0.5))
            .gesture(DragGesture()
                .onChanged { value in
                    self.width = max(50, self.width + value.translation.width)
                }
            )
    }
}

// MARK: - Shared file attribute helpers

func fileSizeBytes(for file: URL) -> Int64 {
    let resourceValues = try? file.resourceValues(forKeys: [.fileSizeKey])
    return Int64(resourceValues?.fileSize ?? 0)
}

func fileSizeString(for file: URL) -> String {
    do {
        let resourceValues = try file.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = resourceValues.fileSize {
            return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
        }
    } catch {
        print("Error retrieving file size: \(error)")
    }
    return "N/A"
}

func filePermissions(for file: URL) -> String {
    do {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        if let posixPermissions = attributes[.posixPermissions] as? NSNumber {
            let permissions = posixPermissions.uint16Value
            let owner = (permissions & S_IRWXU) >> 6
            let group = (permissions & S_IRWXG) >> 3
            let others = permissions & S_IRWXO

            func rwxString(_ value: UInt16) -> String {
                let read = (value & 0b100) != 0 ? "r" : "-"
                let write = (value & 0b010) != 0 ? "w" : "-"
                let execute = (value & 0b001) != 0 ? "x" : "-"
                return "\(read)\(write)\(execute)"
            }

            return "\(rwxString(owner))\(rwxString(group))\(rwxString(others))"
        }
    } catch {
        print("Error retrieving file permissions: \(error)")
    }
    return "N/A"
}
