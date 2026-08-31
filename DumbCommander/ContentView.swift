import SwiftUI
import Foundation
import AppKit // Import AppKit for NSColor

// ActivePanel Enum to track which side of the panel is active
enum ActivePanel {
    case left, right
}

enum AppAction {
    case view, edit, copy, move, rename, newFolder, delete
}

class AppState: ObservableObject {
    @Published var leftDirectory: URL
    @Published var rightDirectory: URL
    @Published var activePanel: ActivePanel = .left
    @Published var showGotoDirectoryPrompt: Bool = false
    @Published var selectedFile: URL?
    @Published var markedFiles: [URL] = []
    @Published var pendingAction: AppAction?
    @Published var showLeftFavoritesPopover: Bool = false
    @Published var showRightFavoritesPopover: Bool = false
    @Published var showDirectoryAccessAlert: Bool = false
    @Published var deniedDirectory: URL?
    @Published var directoryAccessErrorMessage: String = ""
    // Incremented after file operations so both panels reload their contents
    @Published var refreshTrigger: Int = 0

    init(defaultDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let homeDirectory = defaultDirectory.standardizedFileURL
        leftDirectory = homeDirectory
        rightDirectory = homeDirectory
    }
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
    @State private var showRenameSheet: Bool = false
    @State private var renameInput: String = ""

    @AppStorage("editorChoice") private var editorChoice: String = "system"
    @AppStorage("customEditorPath") private var customEditorPath: String = ""
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete: Bool = true
    @AppStorage("showStatusBar") private var showStatusBar: Bool = true
    @AppStorage("showFunctionBar") private var showFunctionBar: Bool = true

    private func showInfo(_ message: String) {
        alertMessage = message
        showAlert = true
    }

    private func openPrivacySettings() {
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        ]

        for settingsURL in settingsURLs {
            guard let url = URL(string: settingsURL) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func directoryAccessMessage() -> String {
        let path = appState.deniedDirectory?.path ?? "das Verzeichnis"
        let detail = appState.directoryAccessErrorMessage
        return "DumbCommander kann nicht auf \(path) zugreifen. Gewähre der App in Datenschutz & Sicherheit Zugriff auf Dateien und Ordner oder Full Disk Access.\(detail.isEmpty ? "" : "\n\nFehler: \(detail)")"
    }

    private func handleView() {
        if let file = appState.selectedFile {
            NSWorkspace.shared.open(file)
        }
    }

    private func handleEdit() {
        guard let file = appState.selectedFile else {
            showInfo("Keine Datei zum Bearbeiten ausgewählt.")
            return
        }

        func openWithApp(_ appPath: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", appPath, file.path]
            do { try process.run() } catch { print("Failed to open file with \(appPath): \(error)") }
        }

        switch editorChoice {
        case "system":
            NSWorkspace.shared.open(file)
        case "vscode":
            openWithApp("/Applications/Visual Studio Code.app")
        case "xcode":
            openWithApp("/Applications/Xcode.app")
        case "textedit":
            openWithApp("/System/Applications/TextEdit.app")
        case "custom":
            let path = customEditorPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                openWithApp(path)
            } else {
                print("Custom editor path not set.")
                NSWorkspace.shared.open(file)
            }
        default:
            NSWorkspace.shared.open(file)
        }
    }

    // MARK: - F-Key Handlers

    // Marked files take precedence, otherwise the cursor selection is used
    private func operationTargets() -> [URL] {
        if !appState.markedFiles.isEmpty {
            return appState.markedFiles
        }
        if let selected = appState.selectedFile {
            return [selected]
        }
        return []
    }

    // Reload both panels after a file operation
    private func refreshPanels() {
        appState.markedFiles = []
        appState.refreshTrigger += 1
    }

    private func goUpInActivePanel() {
        switch appState.activePanel {
        case .left:
            if let parent = appState.leftDirectory.parent, parent != appState.leftDirectory {
                appState.leftDirectory = parent
            }
        case .right:
            if let parent = appState.rightDirectory.parent, parent != appState.rightDirectory {
                appState.rightDirectory = parent
            }
        }
        appState.selectedFile = nil
        appState.markedFiles = []
    }

    private func summary(succeeded: Int, verb: String, errors: [String]) -> String {
        var lines: [String] = []
        if succeeded > 0 {
            lines.append("\(succeeded) Element(e) \(verb).")
        }
        lines.append(contentsOf: errors)
        return lines.joined(separator: "\n")
    }

    func handleCopy() {
        let targets = operationTargets()
        guard !targets.isEmpty else {
            showInfo("Bitte wählen Sie mindestens eine Datei zum Kopieren aus.")
            return
        }
        let destinationDir = appState.activePanel == .left ? appState.rightDirectory : appState.leftDirectory

        var copied = 0
        var errors: [String] = []
        for source in targets {
            let destination = destinationDir.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                errors.append("Ziel existiert bereits: \(destination.lastPathComponent)")
                continue
            }
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                copied += 1
            } catch {
                errors.append("Fehler bei \(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        refreshPanels()
        showInfo(summary(succeeded: copied, verb: "kopiert", errors: errors))
    }

    func handleMove() {
        let targets = operationTargets()
        guard !targets.isEmpty else {
            showInfo("Bitte wählen Sie mindestens eine Datei zum Verschieben aus.")
            return
        }
        let destinationDir = appState.activePanel == .left ? appState.rightDirectory : appState.leftDirectory

        var moved = 0
        var errors: [String] = []
        for source in targets {
            let destination = destinationDir.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                errors.append("Ziel existiert bereits: \(destination.lastPathComponent)")
                continue
            }
            do {
                try FileManager.default.moveItem(at: source, to: destination)
                moved += 1
            } catch {
                errors.append("Fehler bei \(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        appState.selectedFile = nil
        refreshPanels()
        showInfo(summary(succeeded: moved, verb: "verschoben", errors: errors))
    }

    func handleRename() {
        guard let file = appState.selectedFile else {
            showInfo("Bitte wählen Sie eine Datei zum Umbenennen aus.")
            return
        }
        renameInput = file.lastPathComponent
        showRenameSheet = true
    }

    private func performRename() {
        guard let file = appState.selectedFile else { return }
        let newName = renameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != file.lastPathComponent else { return }
        guard !newName.contains("/") else {
            showInfo("Der Name darf keinen Schrägstrich enthalten.")
            return
        }
        let destination = file.deletingLastPathComponent().appendingPathComponent(newName)
        if FileManager.default.fileExists(atPath: destination.path) {
            showInfo("Es existiert bereits ein Element mit dem Namen: \(newName)")
            return
        }
        do {
            try FileManager.default.moveItem(at: file, to: destination)
            appState.selectedFile = destination
            refreshPanels()
        } catch {
            showInfo("Fehler beim Umbenennen: \(error.localizedDescription)")
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
            refreshPanels()
        } catch {
            showInfo("Fehler beim Erstellen des Ordners: \(error.localizedDescription)")
        }
    }

    func handleDelete() {
        let targets = operationTargets()
        guard !targets.isEmpty else {
            showInfo("Bitte wählen Sie mindestens eine Datei oder einen Ordner zum Löschen aus.")
            return
        }

        func performDelete() {
            var deleted = 0
            var errors: [String] = []
            for target in targets {
                do {
                    // Prefer moving to trash; fall back to hard delete (e.g. volumes without trash)
                    do {
                        try FileManager.default.trashItem(at: target, resultingItemURL: nil)
                    } catch {
                        try FileManager.default.removeItem(at: target)
                    }
                    deleted += 1
                } catch {
                    errors.append("Fehler bei \(target.lastPathComponent): \(error.localizedDescription)")
                }
            }
            appState.selectedFile = nil
            refreshPanels()
            if !errors.isEmpty || deleted > 1 {
                showInfo(summary(succeeded: deleted, verb: "in den Papierkorb verschoben", errors: errors))
            }
        }

        if confirmBeforeDelete {
            let alert = NSAlert()
            alert.messageText = "Wirklich löschen?"
            if targets.count == 1 {
                alert.informativeText = "\(targets[0].lastPathComponent) wird in den Papierkorb verschoben."
            } else {
                alert.informativeText = "\(targets.count) Elemente werden in den Papierkorb verschoben."
            }
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Löschen")
            alert.addButton(withTitle: "Abbrechen")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                performDelete()
            }
        } else {
            performDelete()
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
                    onView: handleView,
                    onEdit: handleEdit,
                    onCopy: { handleCopy() },
                    onMove: { handleMove() },
                    onNewFolder: { handleNewFolder() },
                    onDelete: { handleDelete() },
                    onTab: {
                        if appState.activePanel != .right { appState.activePanel = .right }
                    },
                    panelSide: .left,
                    showFavoritesPopover: $appState.showLeftFavoritesPopover
                )
                // Removed onTapGesture to prevent direct activePanel state changes here - Endlosschleifen-Prävention

                FileListView(
                    currentDirectory: $appState.rightDirectory,
                    isActive: appState.activePanel == .right,
                    appState: appState,
                    onView: handleView,
                    onEdit: handleEdit,
                    onCopy: { handleCopy() },
                    onMove: { handleMove() },
                    onNewFolder: { handleNewFolder() },
                    onDelete: { handleDelete() },
                    onTab: {
                        if appState.activePanel != .left { appState.activePanel = .left }
                    },
                    panelSide: .right,
                    showFavoritesPopover: $appState.showRightFavoritesPopover
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
                        handleView()
                    } label: {
                        Label("Anzeigen", systemImage: "eye")
                    }
                    Button {
                        handleEdit()
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
                // Do not intercept Command+Q
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

                if event.keyCode == 12 && modifiers.contains(.command) {
                    return false
                }
                // Handle Ctrl+PageUp globally: navigate one directory up in the active panel
                if modifiers.contains(.control), event.keyCode == 116 {
                    goUpInActivePanel()
                    return true
                }

                // Handle Option+F1 / Option+F2 globally: open the corresponding favorites popover (no panel focus change)
                if modifiers.contains(.option) {
                    switch event.keyCode {
                    case 122: // F1
                        appState.showLeftFavoritesPopover = true
                        return true
                    case 120: // F2
                        appState.showRightFavoritesPopover = true
                        return true
                    default:
                        return false
                    }
                }

                let plainKeyBlockers: NSEvent.ModifierFlags = [.command, .control, .shift]
                if !modifiers.intersection(plainKeyBlockers).isEmpty {
                    return false
                }

                var handled = false
                switch event.keyCode {
                case 122: // F1
                    appState.activePanel = .left
                    handled = true
                case 120: // F2
                    appState.activePanel = .right
                    handled = true
                case 99: // F3
                    handleView()
                    handled = true
                case 118: // F4
                    handleEdit()
                    handled = true
                case 96: // F5
                    handleCopy()
                    handled = true
                case 97: // F6
                    handleMove()
                    handled = true
                case 98: // F7
                    handleNewFolder()
                    handled = true
                case 100: // F8
                    handleDelete()
                    handled = true
                case 109: // F10
                    handleQuit()
                    handled = true
                default:
                    handled = false
                }
                return handled
            }
            .frame(width: 0, height: 0)

            if isCommandPromptExpanded {
                Divider()

                VStack(alignment: .leading) {
                    HStack {
                        TextField("Enter command...", text: $command)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                executeCommand(command)
                            }
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

            if showFunctionBar {
                Divider()
                HStack(spacing: 8) {
                    Button("F1 Links aktiv") {
                        if appState.activePanel != .left { appState.activePanel = .left }
                    }
                    .buttonStyle(ModernButtonStyle(width: 130, height: 28, backgroundColor: .blue.opacity(0.2), foregroundColor: .primary))

                    Button("F2 Rechts aktiv") {
                        if appState.activePanel != .right { appState.activePanel = .right }
                    }
                    .buttonStyle(ModernButtonStyle(width: 130, height: 28, backgroundColor: .blue.opacity(0.2), foregroundColor: .primary))

                    Button("F3 Anzeigen") { handleView() }
                        .buttonStyle(ModernButtonStyle(width: 130, height: 28, backgroundColor: .green.opacity(0.2), foregroundColor: .primary))

                    Button("F4 Bearbeiten") { handleEdit() }
                        .buttonStyle(ModernButtonStyle(width: 130, height: 28, backgroundColor: .green.opacity(0.2), foregroundColor: .primary))

                    Button("F5 Kopieren") { handleCopy() }
                        .buttonStyle(ModernButtonStyle(width: 130, height: 28, backgroundColor: .orange.opacity(0.2), foregroundColor: .primary))

                    Button("F6 Verschieben") { handleMove() }
                        .buttonStyle(ModernButtonStyle(width: 130, height: 28, backgroundColor: .orange.opacity(0.2), foregroundColor: .primary))

                    Button("F7 Neuer Ordner") { handleNewFolder() }
                        .buttonStyle(ModernButtonStyle(width: 150, height: 28, backgroundColor: .purple.opacity(0.2), foregroundColor: .primary))

                    Button("F8 Löschen") { handleDelete() }
                        .buttonStyle(ModernButtonStyle(width: 130, height: 28, backgroundColor: .red.opacity(0.2), foregroundColor: .primary))

                    Button("F10 Beenden") { handleQuit() }
                        .buttonStyle(ModernButtonStyle(width: 130, height: 28, backgroundColor: .gray.opacity(0.2), foregroundColor: .primary))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.underPageBackgroundColor))
            }

            if showStatusBar {
                Divider()
                HStack(spacing: 16) {
                    // Active panel indicator
                    Text(appState.activePanel == .left ? "Links aktiv" : "Rechts aktiv")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    // Left dir
                    Text("L: \(appState.leftDirectory.path)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    // Right dir
                    Text("R: \(appState.rightDirectory.path)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let sel = appState.selectedFile {
                        Text("Ausgewählt: \(sel.lastPathComponent)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Keine Auswahl")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.underPageBackgroundColor))
            }
        }
        .onChange(of: appState.pendingAction) { oldValue, newValue in
            guard let action = newValue else { return }
            switch action {
            case .view:
                handleView()
            case .edit:
                handleEdit()
            case .copy:
                handleCopy()
            case .move:
                handleMove()
            case .rename:
                handleRename()
            case .newFolder:
                handleNewFolder()
            case .delete:
                handleDelete()
            }
            // Reset asynchronously to avoid publishing during view updates
            DispatchQueue.main.async {
                appState.pendingAction = nil
            }
        }
        .sheet(isPresented: $appState.showGotoDirectoryPrompt) {
            VStack {
                Text("Go to Directory")
                    .font(.headline)
                    .padding()
                TextField("Enter directory path:", text: $goToDirectoryInput)
                    .textFieldStyle(.roundedBorder)
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
        .alert("Zugriff verweigert", isPresented: $appState.showDirectoryAccessAlert) {
            Button("Systemeinstellungen öffnen") {
                openPrivacySettings()
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(directoryAccessMessage())
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
            showInfo("Fehler: \(error.localizedDescription)")
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
                showInfo("Der Pfad ist kein Verzeichnis: \(goToDirectoryInput)")
            }
        } else {
            showInfo("Verzeichnis existiert nicht: \(goToDirectoryInput)")
        }
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

