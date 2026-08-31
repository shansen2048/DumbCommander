import SwiftUI
import Foundation
import AppKit

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
    @ObservedObject var appState: CommanderState
    let fileSystem: any FileSystemServing
    @StateObject private var operations: FileOperationViewModel
    @State private var command: String = ""
    @State private var commandOutput: String = ""
    @State private var isCommandPromptExpanded: Bool = false
    @State private var goToDirectoryInput: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showRenameSheet: Bool = false
    @State private var renameInput: String = ""
    @State private var pendingDeleteTargets: [URL] = []
    @State private var showDeleteConfirmation = false

    @AppStorage("editorChoice") private var editorChoice: String = "system"
    @AppStorage("customEditorPath") private var customEditorPath: String = ""
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete: Bool = true
    @AppStorage("showStatusBar") private var showStatusBar: Bool = true
    @AppStorage("showFunctionBar") private var showFunctionBar: Bool = true
    @AppStorage("showHiddenFiles") private var showHiddenFiles: Bool = false

    init(
        appState: CommanderState,
        fileSystem: any FileSystemServing = LocalFileSystemService()
    ) {
        self.appState = appState
        self.fileSystem = fileSystem
        _operations = StateObject(
            wrappedValue: FileOperationViewModel(
                coordinator: FileOperationCoordinator(fileSystem: fileSystem)
            )
        )
    }

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
        return "DumbCommander kann nicht auf \(path) zugreifen. Prüfe die Zugriffsrechte und die macOS-Einstellungen unter Datenschutz & Sicherheit.\(detail.isEmpty ? "" : "\n\nFehler: \(detail)")"
    }

    private func handleView() {
        guard let item = appState.activePanelState.selectedItem else {
            showInfo("Keine Datei zum Anzeigen ausgewählt.")
            return
        }
        guard !item.isSymbolicLink else {
            showInfo("Symbolische Links werden nicht geöffnet oder verfolgt.")
            return
        }
        NSWorkspace.shared.open(item.url)
    }

    private func handleEdit() {
        guard let item = appState.activePanelState.selectedItem else {
            showInfo("Keine Datei zum Bearbeiten ausgewählt.")
            return
        }
        guard !item.isSymbolicLink else {
            showInfo("Symbolische Links werden nicht geöffnet oder verfolgt.")
            return
        }
        let file = item.url

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

    private func operationTargets() -> [URL] {
        appState.activePanelState.operationTargets
    }

    private func refreshPanels() async {
        async let left: Void = appState.leftPanel.reload(
            using: fileSystem,
            showHiddenFiles: showHiddenFiles
        )
        async let right: Void = appState.rightPanel.reload(
            using: fileSystem,
            showHiddenFiles: showHiddenFiles
        )
        _ = await (left, right)
    }

    private func goUpInActivePanel() {
        appState.activePanelState.goUp()
    }

    private func startOperation(_ request: FileOperationRequest) {
        operations.start(request) {
            await refreshPanels()
        }
    }

    func handleCopy() {
        let targets = operationTargets()
        guard !targets.isEmpty else {
            showInfo("Bitte wählen Sie mindestens eine Datei zum Kopieren aus.")
            return
        }
        startOperation(.copy(targets, to: appState.targetPanelState.directory))
    }

    func handleMove() {
        let targets = operationTargets()
        guard !targets.isEmpty else {
            showInfo("Bitte wählen Sie mindestens eine Datei zum Verschieben aus.")
            return
        }
        startOperation(.move(targets, to: appState.targetPanelState.directory))
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

        startOperation(.rename(file, to: newName))
    }

    func handleNewFolder() {
        startOperation(
            .createDirectory(in: appState.activePanelState.directory, named: "Neuer Ordner")
        )
    }

    func handleDelete() {
        let targets = operationTargets()
        guard !targets.isEmpty else {
            showInfo("Bitte wählen Sie mindestens eine Datei oder einen Ordner zum Löschen aus.")
            return
        }

        if confirmBeforeDelete {
            pendingDeleteTargets = targets
            showDeleteConfirmation = true
        } else {
            startOperation(.trash(targets))
        }
    }

    func handleQuit() {
        NSApp.terminate(nil)
    }

    var body: some View {
        VStack {
            HStack {
                FileListView(
                    panelState: appState.leftPanel,
                    commanderState: appState,
                    fileSystem: fileSystem,
                    panelSide: .left,
                    showFavoritesPopover: $appState.showLeftFavoritesPopover,
                    onView: handleView,
                    onEdit: handleEdit,
                    onCopy: { handleCopy() },
                    onMove: { handleMove() },
                    onNewFolder: { handleNewFolder() },
                    onDelete: { handleDelete() }
                )

                FileListView(
                    panelState: appState.rightPanel,
                    commanderState: appState,
                    fileSystem: fileSystem,
                    panelSide: .right,
                    showFavoritesPopover: $appState.showRightFavoritesPopover,
                    onView: handleView,
                    onEdit: handleEdit,
                    onCopy: { handleCopy() },
                    onMove: { handleMove() },
                    onNewFolder: { handleNewFolder() },
                    onDelete: { handleDelete() }
                )
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
                        Label(
                            isCommandPromptExpanded
                                ? "Experimentelle Kommandozeile schließen"
                                : "Experimentelle Kommandozeile",
                            systemImage: "terminal.fill"
                        )
                    }
                    .accessibilityIdentifier("experimentalCommandPromptButton")
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
                        TextField("Befehl eingeben …", text: $command)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                executeCommand(command)
                            }
                        Button("Ausführen") {
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
                    Text("L: \(appState.leftPanel.directory.path)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    // Right dir
                    Text("R: \(appState.rightPanel.directory.path)")
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
            Task { @MainActor in
                appState.pendingAction = nil
            }
        }
        .sheet(isPresented: $appState.showGotoDirectoryPrompt) {
            VStack {
                Text("Verzeichnis öffnen")
                    .font(.headline)
                    .padding()
                TextField("Verzeichnispfad", text: $goToDirectoryInput)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                HStack {
                    Button("Abbrechen") {
                        appState.showGotoDirectoryPrompt = false
                    }
                    .buttonStyle(ModernButtonStyle())
                    Spacer()
                    Button("Öffnen") {
                        gotoDirectory()
                        appState.showGotoDirectoryPrompt = false
                    }
                    .buttonStyle(ModernButtonStyle())
                }
                .padding()
            }
            .frame(width: 400, height: 200)
        }
        .sheet(isPresented: $showRenameSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Element umbenennen")
                    .font(.headline)
                TextField("Neuer Name", text: $renameInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        performRename()
                        showRenameSheet = false
                    }
                HStack {
                    Button("Abbrechen", role: .cancel) {
                        showRenameSheet = false
                    }
                    Spacer()
                    Button("Umbenennen") {
                        performRename()
                        showRenameSheet = false
                    }
                    .disabled(renameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 420)
        }
        .sheet(item: Binding(
            get: { operations.currentConflict },
            set: { value in
                if value == nil, operations.currentConflict != nil {
                    operations.resolveConflict(.cancel, applyToAll: false)
                }
            }
        )) { conflict in
            FileConflictView(conflict: conflict) { resolution, applyToAll in
                operations.resolveConflict(resolution, applyToAll: applyToAll)
            }
        }
        .sheet(item: $operations.report) { report in
            FileOperationReportView(report: report) {
                operations.report = nil
            }
        }
        .confirmationDialog(
            "In den Papierkorb bewegen?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("In den Papierkorb", role: .destructive) {
                let targets = pendingDeleteTargets
                pendingDeleteTargets = []
                startOperation(.trash(targets))
            }
            Button("Abbrechen", role: .cancel) {
                pendingDeleteTargets = []
            }
        } message: {
            Text(
                pendingDeleteTargets.count == 1
                    ? "\(pendingDeleteTargets[0].lastPathComponent) wird in den Papierkorb bewegt."
                    : "\(pendingDeleteTargets.count) Elemente werden in den Papierkorb bewegt."
            )
        }
        .overlay {
            if operations.isRunning, let progress = operations.progress,
               operations.currentConflict == nil {
                FileOperationProgressView(progress: progress) {
                    operations.cancel()
                }
            }
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
                appState.activePanelState.navigate(to: newDirectoryURL)
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
        ContentView(appState: CommanderState())
    }
}

private struct FileConflictView: View {
    let conflict: FileOperationConflict
    let onDecision: (FileConflictResolution, Bool) -> Void
    @State private var applyToAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Zielkonflikt")
                .font(.title2.bold())
            Text(conflict.destination.path)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Text("Am Ziel existiert bereits ein Element. Es wird nichts ohne Ihre Entscheidung überschrieben.")
                .foregroundStyle(.secondary)

            if conflict.supportsApplyToAll {
                Toggle("Für alle passenden Konflikte anwenden", isOn: $applyToAll)
            }

            HStack {
                ForEach(conflict.allowedResolutions, id: \.self) { resolution in
                    Button(resolution.title, role: resolution == .cancel ? .cancel : nil) {
                        onDecision(resolution, applyToAll)
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 560)
    }
}

private struct FileOperationProgressView: View {
    let progress: FileOperationProgress
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(progress.kind.title)
                .font(.headline)
            ProgressView(value: progress.fractionCompleted)
            Text(progress.currentItem?.path ?? "Operation wird vorbereitet …")
                .font(.caption.monospaced())
                .lineLimit(2)
                .truncationMode(.middle)
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel, action: onCancel)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 12)
        .accessibilityIdentifier("fileOperationProgress")
    }
}

private struct FileOperationReportView: View {
    let report: FileOperationReport
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Operationsbericht: \(report.kind.title)")
                .font(.title2.bold())
            Text(report.summary)
                .foregroundStyle(report.failedCount > 0 ? Color.red : Color.secondary)

            List(report.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(symbol(for: item.outcome)) \(item.source.lastPathComponent)")
                        .fontWeight(.semibold)
                    if let destination = item.destination {
                        Text(destination.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let message = item.message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(item.outcome == .failed ? Color.red : Color.secondary)
                    }
                }
            }
            .frame(minHeight: 240)

            HStack {
                Spacer()
                Button("Schließen", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 380)
    }

    private func symbol(for outcome: FileOperationOutcome) -> String {
        switch outcome {
        case .succeeded: return "✓"
        case .skipped: return "↷"
        case .failed: return "✕"
        case .cancelled: return "■"
        }
    }
}
