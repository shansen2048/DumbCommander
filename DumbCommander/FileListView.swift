import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers

enum PanelSide { case left, right }

let commanderActivePanelColor = Color(NSColor.controlBackgroundColor)
let commanderInactivePanelColor = Color(NSColor.controlBackgroundColor)
let commanderSelectedRowColor = Color.accentColor.opacity(0.2)
let commanderHeaderColor = Color(NSColor.underPageBackgroundColor)
let commanderHeaderTextColor = Color.primary
let commanderTextColor = Color.primary

struct FileListView: View {
    @Binding var currentDirectory: URL
    @State private var files: [URL] = []
    @State private var currentFile: URL?
    @State private var columnWidths: [CGFloat] = [200, 60, 80, 80]
    @State private var selectedIndex: Int?
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
    var panelSide: PanelSide = .left
    @Binding var showFavoritesPopover: Bool

    @FocusState private var isFocused: Bool

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
                                selectedIndex = nil
                                appState.activePanel = (panelSide == .left) ? .left : .right
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
                            appState.activePanel = (panelSide == .left) ? .left : .right
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

            // Column Headers
            HStack(spacing: 0) {
                Text("Name")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(commanderHeaderTextColor)
                    .frame(width: columnWidths[0], alignment: .leading)
                    .padding(.leading, 5)
                
                Text("Type")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(commanderHeaderTextColor)
                    .frame(width: columnWidths[1], alignment: .leading)
                
                Text("Size")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(commanderHeaderTextColor)
                    .frame(width: columnWidths[2], alignment: .leading)
                
                Text("Permissions")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(commanderHeaderTextColor)
                    .frame(width: columnWidths[3], alignment: .leading)
            }
            .overlay(
                Rectangle()
                    .frame(height: 1), alignment: .bottom
            )
            .foregroundColor(Color(NSColor.separatorColor))
            .overlay(GridLinesOverlay(columnWidths: columnWidths))
            
            List {
                if currentDirectory.path != FileManager.default.homeDirectoryForCurrentUser.path {
                    UpDirectoryRowView(
                        selectedIndex: selectedIndex,
                        commanderSelectedRowColor: commanderSelectedRowColor,
                        isActive: isActive,
                        columnWidths: columnWidths
                    ) {
                        goUpOneDirectory()
                    }
                }

                ForEach(Array(files.enumerated()), id: \.element) { index, file in
                    FileRowView(
                        file: file,
                        index: index,
                        selectedIndex: selectedIndex,
                        columnWidths: columnWidths,
                        commanderTextColor: commanderTextColor,
                        commanderSelectedRowColor: commanderSelectedRowColor,
                        isActive: isActive
                    ) {
                        selectFile(at: index)
                    }
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
            .background(isActive ? commanderActivePanelColor : commanderInactivePanelColor)
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
                    // Do not intercept Command+Q
                    if event.keyCode == 12 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
                        return false
                    }
                    // Control + PageUp/PageDown for directory navigation
                    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control {
                        switch event.keyCode {
                        case 116: // Page Up
                            goUpOneDirectory()
                            return true
                        case 121: // Page Down
                            goIntoSelectedDirectoryIfPossible()
                            return true
                        default:
                            break
                        }
                    }
                    // Only consume keys we handle here (navigation)
                    switch event.keyCode {
                    case 126, // Up arrow
                         125, // Down arrow
                         36,  // Enter/Return
                         48,  // Tab
                         123, // Left arrow (if used later)
                         124: // Right arrow (if used later)
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
        .background(isActive ? commanderActivePanelColor : commanderInactivePanelColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.blue : Color.gray, lineWidth: isActive ? 4 : 1)
        )
        .cornerRadius(8)
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .task {
            loadFiles()
        }
    }
    
    func onKeyDown(_ event: NSEvent) {
        switch event.keyCode {
        case 126: // Up arrow
            moveSelection(up: true)
        case 125: // Down arrow
            moveSelection(up: false)
        case 36: // Enter
            if let selectedIdx = selectedIndex {
                if selectedIdx == -1 {
                    goUpOneDirectory()
                } else if selectedIdx >= 0 && selectedIdx < files.count {
                    let selectedFile = files[selectedIdx]
                    if selectedFile.hasDirectoryPath {
                        currentDirectory = selectedFile
                        loadFiles()
                        selectedIndex = nil
                    } else {
                        currentFile = selectedFile
                        appState.selectedFile = currentFile
                        onView()
                    }
                }
            }
        case 48: // Tab
            onTab?()
        case 123: // Left arrow
            // Optional: handle left arrow if needed
            break
        case 124: // Right arrow
            // Optional: handle right arrow if needed
            break
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
        } catch {
            print("Error loading files: \(error)")
        }
    }
    
    func goUpOneDirectory() {
        if let parentDirectory = currentDirectory.parent {
            currentDirectory = parentDirectory
            loadFiles()
            selectedIndex = nil
        }
    }
    
    func goIntoSelectedDirectoryIfPossible() {
        if let idx = selectedIndex, idx >= 0, idx < files.count {
            let candidate = files[idx]
            if candidate.hasDirectoryPath {
                currentDirectory = candidate
                loadFiles()
                selectedIndex = nil
            }
        }
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
                
                let ownerPermissions = rwxString(owner)
                let groupPermissions = rwxString(group)
                let othersPermissions = rwxString(others)
                
                return "\(ownerPermissions)\(groupPermissions)\(othersPermissions)"
            }
        } catch {
            print("Error retrieving file permissions: \(error)")
        }
        return "N/A"
    }
    
    func selectFile(at index: Int) {
        guard index >= 0 && index < files.count else { return }
        currentFile = files[index]
        appState.selectedFile = currentFile
        selectedIndex = index
    }
    
    func moveSelection(up: Bool) {
        guard !files.isEmpty else { return }
        if selectedIndex == nil {
            selectedIndex = up ? files.count - 1 : 0
        } else {
            if up {
                if selectedIndex == 0 {
                    selectedIndex = -1
                } else if selectedIndex == -1 {
                    selectedIndex = files.count - 1
                } else {
                    selectedIndex = max(-1, selectedIndex! - 1)
                }
            } else {
                if selectedIndex == -1 {
                    selectedIndex = 0
                } else {
                    selectedIndex = min(files.count - 1, selectedIndex! + 1)
                }
            }
        }
        if let selectedIdx = selectedIndex, selectedIdx >= 0 {
            selectFile(at: selectedIdx)
        }
    }
    
    private struct FileRowView: View {
        let file: URL
        let index: Int
        let selectedIndex: Int?
        let columnWidths: [CGFloat]
        let commanderTextColor: Color
        let commanderSelectedRowColor: Color
        let isActive: Bool
        let onTap: () -> Void
        
        var body: some View {
            HStack(spacing: 0) {
                Text(file.lastPathComponent)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(commanderTextColor)
                    .frame(width: columnWidths[0], alignment: .leading)
                    .padding(.leading, 5)
                Spacer(minLength: 0)
                if file.hasDirectoryPath {
                    Text("Folder")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(commanderTextColor)
                        .frame(width: columnWidths[1], alignment: .leading)
                } else {
                    Text(file.pathExtension)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(commanderTextColor)
                        .frame(width: columnWidths[1], alignment: .leading)
                }
                Spacer(minLength: 0)
                Text(fileSizeString(for: file))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(commanderTextColor)
                    .frame(width: columnWidths[2], alignment: .leading)
                Spacer(minLength: 0)
                Text(filePermissions(for: file))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(commanderTextColor)
                    .frame(width: columnWidths[3], alignment: .leading)
            }
            .frame(minHeight: 28)
            .background(index == selectedIndex ? commanderSelectedRowColor : Color.clear)
            .listRowBackground(isActive ? commanderActivePanelColor : commanderInactivePanelColor)
            .onTapGesture {
                onTap()
            }
            .overlay(GridLinesOverlay(columnWidths: columnWidths))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(NSColor.separatorColor)), alignment: .bottom
            )
        }
        
        private func fileSizeString(for file: URL) -> String {
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
        
        private func filePermissions(for file: URL) -> String {
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
                    
                    let ownerPermissions = rwxString(owner)
                    let groupPermissions = rwxString(group)
                    let othersPermissions = rwxString(others)
                    
                    return "\(ownerPermissions)\(groupPermissions)\(othersPermissions)"
                }
            } catch {
                print("Error retrieving file permissions: \(error)")
            }
            return "N/A"
        }
    }
    
    private struct UpDirectoryRowView: View {
        let selectedIndex: Int?
        let commanderSelectedRowColor: Color
        let isActive: Bool
        let columnWidths: [CGFloat]
        let onTap: () -> Void
        
        var body: some View {
            HStack(spacing: 0) {
                Text("..")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(commanderTextColor)
                    .frame(width: columnWidths[0], alignment: .leading)
                    .padding(.leading, 5)
                Spacer()
            }
            .frame(minHeight: 28)
            .background(selectedIndex == -1 ? commanderSelectedRowColor : Color.clear)
            .listRowBackground(isActive ? commanderActivePanelColor : commanderInactivePanelColor)
            .onTapGesture {
                onTap()
            }
            .overlay(GridLinesOverlay(columnWidths: columnWidths))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(NSColor.separatorColor)), alignment: .bottom
            )
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

// VisualEffectBlur for macOS
// Since SwiftUI on macOS does not have a built-in blur view with material style, this helper is commonly used
struct VisualEffectBlur: NSViewRepresentable {
    var blurStyle: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = blurStyle
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = blurStyle
    }
}
