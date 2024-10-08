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
    // Zustand für die linken und rechten Verzeichnisse, initialisiert mit dem Heimatverzeichnis des Benutzers
    @State private var leftDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var rightDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    //@State private var selectedFile: URL?
    @State private var selectedFile: URL?
    fileprivate func HandleView() {
        // F3 key code
        if let file = selectedFile {
            NSWorkspace.shared.open(file)
        }
    }
    
    var body: some View {
        HStack {
            // Linke Dateiliste
            FileListView(currentDirectory: $leftDirectory)
            // Rechte Dateiliste
            FileListView(currentDirectory: $rightDirectory)
        }
        // Minimale Größe des Fensters
        .frame(minWidth: 800, minHeight: 600)
        .frame(idealWidth: 1280, idealHeight: 720)
        HStack {
            Button("F1 - left panel") {
            }
            Button("F2 - right panel") {
            }
            Button("F3 - View") {
                HandleView()
            }
        }
        // Key event handling view
        KeyEventHandlingView { event in
            switch event.keyCode {
            case 122: // F1 key code
                print("F1 key pressed")
                // Add your F1 action here
            case 120: // F2 key code
                print("F2 key pressed")
                // Add your F2 action here
            case 99: HandleView()
            case 118: // F4 key code
                print("F4 key pressed")
                // Add your F4 action here
            case 96: // F5 key code
                print("F5 key pressed")
                // Add your F5 action here
            case 97: // F6 key code
                print("F6 key pressed")
                // Add your F6 action here
            case 98: // F7 key code
                print("F7 key pressed")
                // Add your F7 action here
            case 100: // F8 key code
                print("F8 key pressed")
                // Add your F8 action here
            case 101: // F9 key code
                print("F9 key pressed")
                // Add your F9 action here
            case 109: // F10 key code
                print("F10 key pressed")
                // Add your F10 action here
            default:
                break
            }
        }
        .frame(width: 0, height: 0)
    }
}

// Ansicht für die Dateiliste eines Verzeichnisses
struct FileListView: View {
    // Binding zum aktuellen Verzeichnis
    @Binding var currentDirectory: URL
    // Zustand für die Liste der Dateien im aktuellen Verzeichnis
    @State private var files: [URL] = []
    // Zustand für die aktuell ausgewählte Datei
    @State private var currentFile: URL?

    var body: some View {
        VStack {
            // Anzeige des aktuellen Verzeichnispfades
            Text(currentDirectory.path)
                .font(.headline)
                .padding()
        
            // Liste der Dateien im aktuellen Verzeichnis
            List {
                ForEach(Array(files.enumerated()), id: \.element) { index, file in
                    HStack {
                        // Dateiname
                        Text(file.lastPathComponent)
                        Spacer()
                        // Anzeige ob Datei oder Ordner
                        if file.hasDirectoryPath {
                            Text("Folder")
                        } else {
                            Text(file.pathExtension)
                        }
                        Spacer()
                        // Dateigröße
                        Text(fileSizeString(for: file))
                        Spacer()
                        // Dateirechte
                        Text(filePermissions(for: file))
                    }
                    .background(file == currentFile ? Color.blue.opacity(0.3) : (index % 2 == 0 ? Color.gray.opacity(0.1) : Color.clear))
                    // Wenn auf einen Ordner getippt wird, wechsle in diesen Ordner
                    .onTapGesture {
                        currentFile = file
                        if file.pathExtension == "app" {
                            // Execute the application
                            NSWorkspace.shared.open(file)
                        } else if file.hasDirectoryPath {
                            currentDirectory = file
                            loadFiles()
                        }
                    }
                }
            }
            // Dateien laden, wenn die Ansicht erscheint
            .onAppear(perform: loadFiles)

            HStack {
                // Knopf um ins übergeordnete Verzeichnis zu wechseln
                Button("Up") {
                    if let parentDirectory = currentDirectory.parent {
                        currentDirectory = parentDirectory
                        loadFiles()
                    }
                }
                .padding()
                
                Spacer()
            }
        }
    }
    
    // Funktion zum Laden der Dateien im aktuellen Verzeichnis
    func loadFiles() {
        do {
            // Inhalte des aktuellen Verzeichnisses abrufen
            files = try FileManager.default.contentsOfDirectory(at: currentDirectory, includingPropertiesForKeys: [.fileSizeKey, .isReadableKey])
        } catch {
            print("Error loading files: \(error)")
        }
    }
    
    // Funktion zum Abrufen der Dateigröße als String
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
    
    // Funktion zum Abrufen der Dateirechte als String
    func filePermissions(for file: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            if let posixPermissions = attributes[.posixPermissions] as? NSNumber {
                let permissions = posixPermissions.uint16Value
                let owner = (permissions & S_IRWXU) >> 6
                let group = (permissions & S_IRWXG) >> 3
                let others = permissions & S_IRWXO
                return String(format: "%o%o%o", owner, group, others)
            }
        } catch {
            print("Error retrieving file permissions: \(error)")
        }
        return "N/A"
    }
}

// Erweiterung um den übergeordneten Ordner einer URL zu erhalten
extension URL {
    var parent: URL? {
        return self.deletingLastPathComponent()
    }
}

// Vorschau für die Entwicklungsumgebung
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
