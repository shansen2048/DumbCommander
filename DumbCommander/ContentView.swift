import SwiftUI
import Foundation

var selectedFile: URL?

struct KeyEventHandlingView: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            self.onKeyDown(event)
            return event
        }
        context.coordinator.keyDownMonitor = keyDownMonitor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let keyDownMonitor = coordinator.keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var keyDownMonitor: Any?
    }
}

// Hauptansicht der App
struct ContentView: View {
    @State private var leftDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var rightDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var activePanel: ActivePanel = .left

    fileprivate func HandleView() {
        if let file = selectedFile {
            NSWorkspace.shared.open(file)
        }
    }
    
    var body: some View {
        VStack {
            HStack {
                FileListView(currentDirectory: $leftDirectory, isActive: activePanel == .left)
                    .onTapGesture {
                        activePanel = .left
                    }
                FileListView(currentDirectory: $rightDirectory, isActive: activePanel == .right)
                    .onTapGesture {
                        activePanel = .right
                    }
            }
            .frame(minWidth: 800, minHeight: 600)
            .frame(idealWidth: 1280, idealHeight: 720)
            
            HStack {
                Button("F1 - left panel") {
                    activePanel = .left
                    print("F1 key pressed")
                }
                Button("F2 - right panel") {
                    activePanel = .right
                    print("F2 key pressed")
                }
                Button("F3 - View") {
                    HandleView()
                }
                Button("F4 - Edit") {
                    print("F4 key pressed")
                }
                Button("F5 - Copy") {
                    print("F5 key pressed")
                }
                Button("F6 - Move") {
                    print("F6 key pressed")
                }
                Button("F7 - New Folder") {
                    print("F7 key pressed")
                }
                Button("F8 - Delete") {
                    print("F8 key pressed")
                }
                Button("F9 - Menu") {
                    print("F9 key pressed")
                }
                Button("F10 - Quit") {
                    print("F10 key pressed")
                }
            }
            
            KeyEventHandlingView { event in
                switch event.keyCode {
                case 122:
                    print("F1 key pressed")
                    activePanel = .left
                case 120:
                    print("F2 key pressed")
                    activePanel = .right
                case 99:
                    HandleView()
                case 118:
                    print("F4 key pressed")
                case 96:
                    print("F5 key pressed")
                case 97:
                    print("F6 key pressed")
                case 98:
                    print("F7 key pressed")
                case 100:
                    print("F8 key pressed")
                case 101:
                    print("F9 key pressed")
                case 109:
                    print("F10 key pressed")
                default:
                    break
                }
            }
            .frame(width: 0, height: 0)
        }
    }
    
    enum ActivePanel {
        case left, right
    }
}

struct FileListView: View {
    @Binding var currentDirectory: URL
    @State private var files: [URL] = []
    @State private var currentFile: URL?
    @State private var columnWidths: [CGFloat] = [200, 60, 80, 80]
    @State private var selectedIndex: Int?
    var isActive: Bool

    var body: some View {
        VStack {
            Text(currentDirectory.path)
                .font(.headline)

            HStack {
                Button("..") {
                    if let parentDirectory = currentDirectory.parent {
                        currentDirectory = parentDirectory
                        loadFiles()
                    }
                }
                Spacer()
            }
            
            List {
                ForEach(Array(files.enumerated()), id: \.element) { index, file in
                    HStack {
                        Text(file.lastPathComponent)
                            .frame(width: columnWidths[0], alignment: .leading)
                        Spacer(minLength: 0)
                        if file.hasDirectoryPath {
                            Text("Folder")
                                .frame(width: columnWidths[1], alignment: .leading)
                        } else {
                            Text(file.pathExtension)
                                .frame(width: columnWidths[1], alignment: .leading)
                        }
                        Spacer(minLength: 0)
                        Text(fileSizeString(for: file))
                            .frame(width: columnWidths[2], alignment: .leading)
                        Spacer(minLength: 0)
                        Text(filePermissions(for: file))
                            .frame(width: columnWidths[3], alignment: .leading)
                    }
                    .background(index == selectedIndex ? Color.blue.opacity(0.3) : (index % 2 == 0 ? Color.gray.opacity(0.1) : Color.clear))
                    .onTapGesture(count: 2) {
                        selectFile(at: index)
                        if file.pathExtension == "app" {
                            NSWorkspace.shared.open(file)
                        } else if file.hasDirectoryPath {
                            currentDirectory = file
                            loadFiles()
                        }
                    }
                    .onTapGesture {
                        selectFile(at: index)
                    }
                }
            }
            .onAppear(perform: loadFiles)
            
            if isActive {
                KeyEventHandlingView { event in
                    switch event.keyCode {
                    case 126: // Up arrow key
                        moveSelection(up: true)
                    case 125: // Down arrow key
                        moveSelection(up: false)
                    default:
                        break
                    }
                }
                .frame(width: 0, height: 0)
            }
        }
        
        // Resizable column handler
        HStack {
            ResizableColumn(width: $columnWidths[0])
            ResizableColumn(width: $columnWidths[1])
            ResizableColumn(width: $columnWidths[2])
            ResizableColumn(width: $columnWidths[3])
        }
        .frame(height: 5) // Keep the resizable control minimal in height
    }
    
    func loadFiles() {
        do {
            files = try FileManager.default.contentsOfDirectory(at: currentDirectory, includingPropertiesForKeys: [.fileSizeKey, .isReadableKey])
            selectedIndex = nil
        } catch {
            print("Error loading files: \(error)")
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
        selectedFile = currentFile
        selectedIndex = index
    }
    
    func moveSelection(up: Bool) {
        guard !files.isEmpty else { return }
        if selectedIndex == nil {
            selectedIndex = up ? files.count - 1 : 0
        } else {
            if up {
                selectedIndex = max(0, selectedIndex! - 1)
            } else {
                selectedIndex = min(files.count - 1, selectedIndex! + 1)
            }
        }
        if let selectedIndex = selectedIndex {
            selectFile(at: selectedIndex)
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

extension URL {
    var parent: URL? {
        return self.deletingLastPathComponent()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
