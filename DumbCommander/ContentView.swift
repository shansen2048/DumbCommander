import SwiftUI
import Foundation
import AppKit // Import AppKit for NSColor

// ActivePanel Enum to track which side of the panel is active
enum ActivePanel {
    case left, right
}

class AppState: ObservableObject {
    @Published var leftDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var rightDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var activePanel: ActivePanel = .left
    @Published var showGotoDirectoryPrompt: Bool = false
    @Published var selectedFile: URL?
}

func shell(_ command: String) throws -> String {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/bash")

    try task.run()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    return output
}

struct ContentView: View {
    @ObservedObject var appState: AppState
    @State private var command: String = ""
    @State private var commandOutput: String = ""
    @State private var isCommandPromptExpanded: Bool = false
    @State private var goToDirectoryInput: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

    fileprivate func HandleView() {
        if let file = appState.selectedFile {
            NSWorkspace.shared.open(file)
        }
    }

    fileprivate func HandleEdit() {
        if let file = appState.selectedFile {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "/Applications/Visual Studio Code.app", file.path]

            do {
                try process.run()
                // Removed waitUntilExit() to avoid blocking UI
            } catch {
                print("Failed to open file with Visual Studio Code: \(error)")
            }
        } else {
            showNoFileSelectedAlert()
        }
    }

    // MARK: - F-Key Handlers

    func handleCopy() {
        guard let source = appState.selectedFile else {
            alertMessage = "Bitte wählen Sie eine Datei zum Kopieren aus."
            showAlert = true
            return
        }
        let destinationDir = appState.activePanel == .left ? appState.rightDirectory : appState.leftDirectory
        let destination = destinationDir.appendingPathComponent(source.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                alertMessage = "Zieldatei existiert bereits: \(destination.lastPathComponent)"
                showAlert = true
                return
            }
            try FileManager.default.copyItem(at: source, to: destination)
            alertMessage = "Datei kopiert: \(source.lastPathComponent)"
            showAlert = true
        } catch {
            alertMessage = "Fehler beim Kopieren: \(error.localizedDescription)"
            showAlert = true
        }
    }

    func handleMove() {
        guard let source = appState.selectedFile else {
            alertMessage = "Bitte wählen Sie eine Datei zum Verschieben aus."
            showAlert = true
            return
        }
        let destinationDir = appState.activePanel == .left ? appState.rightDirectory : appState.leftDirectory
        let destination = destinationDir.appendingPathComponent(source.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                alertMessage = "Zieldatei existiert bereits: \(destination.lastPathComponent)"
                showAlert = true
                return
            }
            try FileManager.default.moveItem(at: source, to: destination)
            alertMessage = "Datei verschoben: \(source.lastPathComponent)"
            showAlert = true
            // Update selected file reference after move
            appState.selectedFile = destination
        } catch {
            alertMessage = "Fehler beim Verschieben: \(error.localizedDescription)"
            showAlert = true
        }
    }

    func handleNewFolder() {
        let dir = appState.activePanel == .left ? appState.leftDirectory : appState.rightDirectory
        let newFolderName = "Neuer Ordner"
        var newFolderURL = dir.appendingPathComponent(newFolderName)
        var counter = 1

        while FileManager.default.fileExists(atPath: newFolderURL.path) {
            newFolderURL = dir.appendingPathComponent("\(newFolderName) \(counter)")
            counter += 1
        }

        do {
            try FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: false, attributes: nil)
            alertMessage = "Neuer Ordner erstellt: \(newFolderURL.lastPathComponent)"
            showAlert = true
        } catch {
            alertMessage = "Fehler beim Erstellen des Ordners: \(error.localizedDescription)"
            showAlert = true
        }
    }

    func handleDelete() {
        guard let target = appState.selectedFile else {
            alertMessage = "Bitte wählen Sie eine Datei oder einen Ordner zum Löschen aus."
            showAlert = true
            return
        }

        do {
            try FileManager.default.removeItem(at: target)
            alertMessage = "Datei/Ordner gelöscht: \(target.lastPathComponent)"
            showAlert = true
            appState.selectedFile = nil
        } catch {
            alertMessage = "Fehler beim Löschen: \(error.localizedDescription)"
            showAlert = true
        }
    }

    func handleQuit() {
        NSApp.terminate(nil)
    }

    var body: some View {
        VStack {
            HStack {
                FileListView(
                    currentDirectory: $appState.leftDirectory,
                    isActive: appState.activePanel == .left,
                    appState: appState,
                    onView: HandleView,
                    onEdit: HandleEdit,
                    onCopy: { handleCopy() },
                    onMove: { handleMove() },
                    onNewFolder: { handleNewFolder() },
                    onDelete: { handleDelete() }
                )
                // Removed onTapGesture to prevent direct activePanel state changes here - Endlosschleifen-Prävention

                FileListView(
                    currentDirectory: $appState.rightDirectory,
                    isActive: appState.activePanel == .right,
                    appState: appState,
                    onView: HandleView,
                    onEdit: HandleEdit,
                    onCopy: { handleCopy() },
                    onMove: { handleMove() },
                    onNewFolder: { handleNewFolder() },
                    onDelete: { handleDelete() }
                )
                // Removed onTapGesture to prevent direct activePanel state changes here - Endlosschleifen-Prävention
            }
            .frame(minWidth: 800, minHeight: 600)
            .frame(idealWidth: 1280, idealHeight: 720)
            .background(Color(NSColor.windowBackgroundColor)) // Updated to use NSColor
            .cornerRadius(12)
            .padding()
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        HandleView()
                    } label: {
                        Label("Anzeigen", systemImage: "eye")
                    }
                    Button {
                        HandleEdit()
                    } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }
                }
                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        handleCopy()
                    } label: {
                        Label("Kopieren", systemImage: "doc.on.doc")
                    }
                    Button {
                        handleMove()
                    } label: {
                        Label("Verschieben", systemImage: "arrowshape.turn.up.right")
                    }
                }
                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        handleNewFolder()
                    } label: {
                        Label("Neuer Ordner", systemImage: "folder.badge.plus")
                    }
                    Button {
                        handleDelete()
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        handleQuit()
                    } label: {
                        Label("Beenden", systemImage: "xmark.circle")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        isCommandPromptExpanded.toggle()
                    } label: {
                        Label(isCommandPromptExpanded ? "Eingabe schließen" : "Kommandozeile", systemImage: "terminal.fill")
                    }
                }
            }
            
            KeyEventHandlingView { event in
                if event.keyCode == 12 && event.modifierFlags.contains(.command) {
                    return false
                }
                switch event.keyCode {
                case 122: // F1
                    // Set activePanel only here, avoid duplicate updates elsewhere - Endlosschleifen-Prävention
                    if appState.activePanel != .left {
                        appState.activePanel = .left
                    }
                case 120: // F2
                    // Set activePanel only here, avoid duplicate updates elsewhere - Endlosschleifen-Prävention
                    if appState.activePanel != .right {
                        appState.activePanel = .right
                    }
                case 99: // F3
                    HandleView()
                case 118: // F4
                    HandleEdit()
                case 96: // F5
                    handleCopy()
                case 97: // F6
                    handleMove()
                case 98: // F7
                    handleNewFolder()
                case 100: // F8
                    handleDelete()
                case 101: // F9
                    print("F9 key pressed")
                case 109: // F10
                    handleQuit()
                default:
                    break
                }
                return true
            }
            .frame(width: 0, height: 0)
            
            if isCommandPromptExpanded {
                Divider()
                
                VStack(alignment: .leading) {
                    HStack {
                        TextField("Enter command...", text: $command)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button("Execute") {
                            executeCommand(command)
                        }
                        .buttonStyle(ModernButtonStyle())
                    }
                    .padding(.horizontal)

                    ScrollView {
                        Text(commandOutput)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(height: 150)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(5)
                    .padding(.horizontal)
                }
                .padding(.bottom)
            }
        }
        .sheet(isPresented: $appState.showGotoDirectoryPrompt) {
            VStack {
                Text("Go to Directory")
                    .font(.headline)
                    .padding()
                TextField("Enter directory path:", text: $goToDirectoryInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                HStack {
                    Button("Cancel") {
                        appState.showGotoDirectoryPrompt = false
                    }
                    .buttonStyle(ModernButtonStyle())
                    Spacer()
                    Button("Go") {
                        gotoDirectory()
                        appState.showGotoDirectoryPrompt = false
                    }
                    .buttonStyle(ModernButtonStyle())
                }
                .padding()
            }
            .frame(width: 400, height: 200)
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Info"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    func executeCommand(_ command: String) {
        do {
            let output = try shell(command)
            commandOutput = output
        } catch {
            alertMessage = "Error: \(error.localizedDescription)"
            showAlert = true
        }
    }

    func gotoDirectory() {
        let newDirectoryURL = URL(fileURLWithPath: goToDirectoryInput)

        if FileManager.default.fileExists(atPath: newDirectoryURL.path) {
            if newDirectoryURL.isDirectory {
                // Set directory only here to prevent cascaded updates - Endlosschleifen-Prävention
                switch appState.activePanel {
                case .left:
                    if appState.leftDirectory != newDirectoryURL {
                        appState.leftDirectory = newDirectoryURL
                    }
                case .right:
                    if appState.rightDirectory != newDirectoryURL {
                        appState.rightDirectory = newDirectoryURL
                    }
                }
            } else {
                alertMessage = "The path is not a directory: \(goToDirectoryInput)"
                showAlert = true
            }
        } else {
            alertMessage = "Directory does not exist: \(goToDirectoryInput)"
            showAlert = true
        }
    }

    func showNoFileSelectedAlert() {
        alertMessage = "No file selected for editing."
        showAlert = true
    }
}

struct ModernButtonStyle: ButtonStyle {
    var width: CGFloat = 100
    var height: CGFloat = 40
    var backgroundColor: Color = .gray
    var foregroundColor: Color = .white
    var cornerRadius: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: width, height: height)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(cornerRadius)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

extension URL {
    var parent: URL? {
        return self.deletingLastPathComponent()
    }

    var isDirectory: Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: self.path, isDirectory: &isDir)
        return isDir.boolValue
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(appState: AppState())
    }
}

