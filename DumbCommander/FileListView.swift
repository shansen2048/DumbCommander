import SwiftUI
import Foundation
import AppKit

let commanderActivePanelColor = Color(red: 0.09, green: 0.16, blue: 0.35)
let commanderInactivePanelColor = Color(red: 0.18, green: 0.18, blue: 0.18)
let commanderSelectedRowColor = Color.yellow.opacity(0.5)
let commanderHeaderColor = Color(red: 0.15, green: 0.22, blue: 0.43)
let commanderHeaderTextColor = Color.white
let commanderTextColor = Color(red: 0.92, green: 0.95, blue: 1.0)

struct FileListView: View {
    @Binding var currentDirectory: URL
    @State private var files: [URL] = []
    @State private var currentFile: URL?
    @State private var columnWidths: [CGFloat] = [200, 60, 80, 80]
    @State private var selectedIndex: Int?
    var isActive: Bool
    @ObservedObject var appState: AppState
    var onView: () -> Void
    var onEdit: () -> Void
    var onCopy: () -> Void
    var onMove: () -> Void
    var onNewFolder: () -> Void
    var onDelete: () -> Void
    var onTab: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(currentDirectory.path)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(commanderTextColor)
                .padding(.bottom, 2)
                .padding(.leading, 4)

            // Column Headers
            HStack(spacing: 0) {
                Text("Name")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(commanderHeaderTextColor)
                    .frame(width: columnWidths[0], alignment: .leading)
                    .padding(.leading, 5)
                    .background(commanderHeaderColor)
                
                Text("Type")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(commanderHeaderTextColor)
                    .frame(width: columnWidths[1], alignment: .leading)
                    .background(commanderHeaderColor)
                
                Text("Size")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(commanderHeaderTextColor)
                    .frame(width: columnWidths[2], alignment: .leading)
                    .background(commanderHeaderColor)
                
                Text("Permissions")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(commanderHeaderTextColor)
                    .frame(width: columnWidths[3], alignment: .leading)
                    .background(commanderHeaderColor)
            }
            
            List {
                if currentDirectory.path != FileManager.default.homeDirectoryForCurrentUser.path {
                    UpDirectoryRowView(
                        selectedIndex: selectedIndex,
                        commanderSelectedRowColor: commanderSelectedRowColor,
                        isActive: isActive
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
            .listStyle(PlainListStyle())
            .onChange(of: currentDirectory) { _ in
                loadFiles()
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
            
            if isActive {
                KeyEventHandlingView { event in
                    if event.keyCode == 12 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
                        return false
                    }
                    onKeyDown(event)
                    return true
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
            files = try FileManager.default.contentsOfDirectory(at: currentDirectory, includingPropertiesForKeys: [.fileSizeKey, .isReadableKey])
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
        let onTap: () -> Void
        
        var body: some View {
            HStack(spacing: 0) {
                Text("..")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(commanderTextColor)
                    .frame(width: 200, alignment: .leading) // fixed width for Name column
                    .padding(.leading, 5)
                Spacer()
            }
            .frame(minHeight: 28)
            .background(selectedIndex == -1 ? commanderSelectedRowColor : Color.clear)
            .listRowBackground(isActive ? commanderActivePanelColor : commanderInactivePanelColor)
            .onTapGesture {
                onTap()
            }
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
