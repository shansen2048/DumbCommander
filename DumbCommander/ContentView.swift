import SwiftUI
import Foundation
import AppKit

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
    @State private var pendingRenameURL: URL?
    @State private var showNewFolderSheet = false
    @State private var newFolderInput = "Neuer Ordner"
    @State private var pendingNewFolderParent: URL?
    @State private var pendingDeleteTargets: [URL] = []
    @State private var showDeleteConfirmation = false
    @State private var viewerSelection: ViewerSelection?
    @State private var gotoPanelSide: ActivePanel = .left
    @State private var toolPanelSide: ActivePanel = .left
    @State private var showSearchSheet = false
    @State private var showComparisonSheet = false
    @State private var showBatchRenameSheet = false
    @State private var showChecksumSheet = false
    @State private var showArchiveSheet = false
    @State private var batchRenameSources: [URL] = []
    @State private var checksumSources: [URL] = []
    @State private var archiveSources: [URL] = []
    @State private var contentComparison: ContentComparisonSelection?
    @State private var commandTask: Task<Void, Never>?
    @FocusState private var focusedDialogField: DialogField?
    @FocusState private var isCommandFieldFocused: Bool

    private let commandRegistry = CommandRegistry.shared

    @AppStorage("editorChoice") private var editorChoice: String = "system"
    @AppStorage("customEditorPath") private var customEditorPath: String = ""
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete: Bool = true
    @AppStorage("showStatusBar") private var showStatusBar: Bool = true
    @AppStorage("showFunctionBar") private var showFunctionBar: Bool = true
    @AppStorage("showHiddenFiles") private var showHiddenFiles: Bool = false
    @AppStorage("showCustomButtonBar") private var showCustomButtonBar = true
    @AppStorage("customCommanderCommands") private var customCommandsJSON = "[]"

    private var customCommands: [CustomCommanderCommand] {
        guard let data = customCommandsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([CustomCommanderCommand].self, from: data)) ?? []
    }

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
        guard !item.isAlias else {
            showInfo("Finder-Aliase werden nicht automatisch geöffnet oder aufgelöst.")
            return
        }
        Task {
            do {
                let info = item.isSymbolicLink
                    ? try await fileSystem.resolvedEntry(at: item.url)
                    : FileSystemEntryInfo(
                        url: item.url,
                        kind: item.isDirectory ? .directory : .regularFile,
                        size: item.size
                    )
                guard info.kind != .directory else {
                    showInfo("Für Verzeichnisse steht der interne Viewer nicht zur Verfügung.")
                    return
                }
                viewerSelection = ViewerSelection(url: info.url)
            } catch {
                showInfo("Linkziel kann nicht angezeigt werden: \(error.localizedDescription)")
            }
        }
    }

    private func handleOpenFiles(_ requestedURLs: [URL]) {
        guard !requestedURLs.isEmpty else {
            showInfo("Keine Datei zum Öffnen ausgewählt.")
            return
        }

        Task {
            var files: [URL] = []
            var skippedDirectories: [String] = []
            var resolutionFailures: [String] = []

            for requestedURL in requestedURLs {
                do {
                    let info = try await fileSystem.resolvedEntry(at: requestedURL)
                    if info.kind == .directory {
                        skippedDirectories.append(requestedURL.lastPathComponent)
                    } else {
                        files.append(info.url)
                    }
                } catch {
                    resolutionFailures.append(
                        "\(requestedURL.lastPathComponent): \(error.localizedDescription)"
                    )
                }
            }

            if ProcessInfo.processInfo.environment["DUMBCOMMANDER_CAPTURE_EXTERNAL_OPEN"] == "1" {
                if !files.isEmpty {
                    showInfo("Mit Standard-App öffnen: \(files.map(\.lastPathComponent).joined(separator: ", "))")
                } else {
                    showInfo("Keine Datei konnte mit einer Standard-App geöffnet werden.")
                }
                return
            }

            var messages: [String] = []
            let workspace = NSWorkspace.shared
            var filesByApplication: [URL: [URL]] = [:]
            var withoutAssociatedApplication: [URL] = []
            for file in files {
                if let applicationURL = workspace.urlForApplication(toOpen: file) {
                    filesByApplication[applicationURL, default: []].append(file)
                } else {
                    withoutAssociatedApplication.append(file)
                }
            }
            for (applicationURL, applicationFiles) in filesByApplication {
                workspace.open(
                    applicationFiles,
                    withApplicationAt: applicationURL,
                    configuration: NSWorkspace.OpenConfiguration()
                ) { _, error in
                    guard let error else { return }
                    Task { @MainActor in
                        showInfo(
                            "Dateien konnten nicht mit \(applicationURL.lastPathComponent) geöffnet werden: \(error.localizedDescription)"
                        )
                    }
                }
            }
            if !withoutAssociatedApplication.isEmpty {
                messages.append(
                    "Keine verknüpfte App verfügbar für: \(withoutAssociatedApplication.map(\.lastPathComponent).joined(separator: ", "))"
                )
            }
            if !skippedDirectories.isEmpty {
                messages.append(
                    "Ordner wurden nicht extern geöffnet: \(skippedDirectories.joined(separator: ", "))"
                )
            }
            if !resolutionFailures.isEmpty {
                messages.append("Nicht auflösbar: \(resolutionFailures.joined(separator: "\n"))")
            }
            if !messages.isEmpty {
                showInfo(messages.joined(separator: "\n\n"))
            }
        }
    }

    private func handleEdit() {
        guard let item = appState.activePanelState.selectedItem else {
            showInfo("Keine Datei zum Bearbeiten ausgewählt.")
            return
        }
        guard !item.isAlias else {
            showInfo("Finder-Aliase werden nicht automatisch geöffnet oder aufgelöst.")
            return
        }
        Task {
            do {
                let info = item.isSymbolicLink
                    ? try await fileSystem.resolvedEntry(at: item.url)
                    : FileSystemEntryInfo(
                        url: item.url,
                        kind: item.isDirectory ? .directory : .regularFile,
                        size: item.size
                    )
                guard info.kind != .directory else {
                    showInfo("Ein Verzeichnis kann nicht im Editor geöffnet werden.")
                    return
                }
                openInConfiguredEditor(info.url)
            } catch {
                showInfo("Linkziel kann nicht bearbeitet werden: \(error.localizedDescription)")
            }
        }
    }

    private func openInConfiguredEditor(_ file: URL) {
        switch editorChoice {
        case "system":
            if !NSWorkspace.shared.open(file) {
                showInfo("Für \(file.lastPathComponent) ist keine passende Standard-App verfügbar.")
            }
        case "vscode":
            open(file, withApplicationAtPath: "/Applications/Visual Studio Code.app")
        case "xcode":
            open(file, withApplicationAtPath: "/Applications/Xcode.app")
        case "textedit":
            open(file, withApplicationAtPath: "/System/Applications/TextEdit.app")
        case "custom":
            let path = customEditorPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else {
                showInfo("Es ist kein benutzerdefinierter Editor ausgewählt.")
                return
            }
            open(file, withApplicationAtPath: path)
        default:
            showInfo("Die gespeicherte Editor-Auswahl ist ungültig. Bitte prüfen Sie die Einstellungen.")
        }
    }

    private func open(_ file: URL, withApplicationAtPath path: String) {
        let applicationURL = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: applicationURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            showInfo("Der konfigurierte Editor wurde nicht gefunden: \(applicationURL.path)")
            return
        }

        NSWorkspace.shared.open(
            [file],
            withApplicationAt: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            guard let error else { return }
            Task { @MainActor in
                showInfo("Der Editor konnte nicht geöffnet werden: \(error.localizedDescription)")
            }
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

    private var toolbarCommands: [CommanderCommand] {
        [.view, .edit, .copy, .move, .createDirectory, .trash]
    }

    private var hasOpenDialog: Bool {
        showRenameSheet
            || showNewFolderSheet
            || showDeleteConfirmation
            || appState.showGotoDirectoryPrompt
            || viewerSelection != nil
            || showSearchSheet
            || showComparisonSheet
            || showBatchRenameSheet
            || showChecksumSheet
            || showArchiveSheet
            || contentComparison != nil
            || operations.currentConflict != nil
            || operations.report != nil
    }

    private func dispatch(_ command: CommanderCommand) {
        switch command {
        case .activateLeftPanel:
            appState.activate(.left)
        case .activateRightPanel:
            appState.activate(.right)
        case .showLeftFavorites:
            appState.showLeftFavoritesPopover = true
        case .showRightFavorites:
            appState.showRightFavoritesPopover = true
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
        case .createDirectory:
            handleNewFolder()
        case .trash:
            handleDelete()
        case .quit:
            handleQuit()
        case .goToDirectory:
            gotoPanelSide = appState.activePanel
            goToDirectoryInput = appState.activePanelState.directory.path
            appState.showGotoDirectoryPrompt = true
        case .goBack:
            appState.activePanelState.goBack()
        case .goForward:
            appState.activePanelState.goForward()
        case .goHome:
            appState.activePanelState.goHome()
        case .goRoot:
            appState.activePanelState.goRoot()
        case .focusFilter:
            appState.focusFilterRequest = appState.activePanel
        case .reload:
            Task { await refreshPanels() }
        case .newTab:
            appState.addTab(in: appState.activePanel)
        case .closeTab:
            appState.closeTab(
                appState.selectedTabIndex(for: appState.activePanel),
                in: appState.activePanel
            )
        case .searchFiles:
            toolPanelSide = appState.activePanel
            showSearchSheet = true
        case .compareDirectories:
            guard !appState.leftPanel.isVirtual, !appState.rightPanel.isVirtual else {
                showInfo("Virtuelle Suchergebnisse können nicht als Verzeichnis verglichen werden.")
                return
            }
            showComparisonSheet = true
        case .batchRename:
            batchRenameSources = operationTargets()
            guard !batchRenameSources.isEmpty else {
                showInfo("Bitte wählen Sie mindestens ein Element für die Mehrfachumbenennung aus.")
                return
            }
            showBatchRenameSheet = true
        case .checksums:
            checksumSources = operationTargets()
            guard !checksumSources.isEmpty else {
                showInfo("Bitte wählen Sie mindestens eine Datei für die Prüfsumme aus.")
                return
            }
            showChecksumSheet = true
        case .compareContents:
            prepareContentComparison()
        case .archive:
            archiveSources = operationTargets()
            guard !archiveSources.isEmpty else {
                showInfo("Bitte wählen Sie mindestens ein Archiv oder zu packendes Element aus.")
                return
            }
            guard !appState.targetPanelState.isVirtual else {
                showInfo("Ein virtuelles Suchpanel kann nicht als Archivziel verwendet werden.")
                return
            }
            showArchiveSheet = true
        }
    }

    private func prepareContentComparison() {
        guard let left = appState.activePanelState.selectedItem else {
            showInfo("Bitte wählen Sie im aktiven Panel eine Datei aus.")
            return
        }
        guard !left.isDirectory else {
            showInfo("Der Inhaltsvergleich unterstützt nur Dateien und symbolische Links.")
            return
        }
        let targetPanel = appState.targetPanelState
        let right = targetPanel.selectedItem
            ?? targetPanel.items.first { $0.name == left.name && !$0.isDirectory }
        guard let right else {
            showInfo("Wählen Sie im Zielpanel eine Vergleichsdatei aus oder öffnen Sie dort eine Datei gleichen Namens.")
            return
        }
        guard !right.isDirectory else {
            showInfo("Der Inhaltsvergleich unterstützt keine Verzeichnisse.")
            return
        }
        contentComparison = ContentComparisonSelection(left: left.url, right: right.url)
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
        guard !appState.targetPanelState.isVirtual else {
            showInfo("Ein virtuelles Suchpanel kann nicht als Kopierziel verwendet werden.")
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
        guard !appState.targetPanelState.isVirtual else {
            showInfo("Ein virtuelles Suchpanel kann nicht als Verschiebeziel verwendet werden.")
            return
        }
        startOperation(.move(targets, to: appState.targetPanelState.directory))
    }

    func handleRename() {
        guard let file = appState.selectedFile else {
            showInfo("Bitte wählen Sie eine Datei zum Umbenennen aus.")
            return
        }
        pendingRenameURL = file
        renameInput = file.lastPathComponent
        showRenameSheet = true
    }

    private func performRename() {
        guard let file = pendingRenameURL else { return }
        let newName = renameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != file.lastPathComponent else { return }

        startOperation(.rename(file, to: newName))
        pendingRenameURL = nil
    }

    func handleNewFolder() {
        guard !appState.activePanelState.isVirtual else {
            showInfo("In einem virtuellen Suchpanel kann kein Ordner angelegt werden.")
            return
        }
        pendingNewFolderParent = appState.activePanelState.directory
        newFolderInput = "Neuer Ordner"
        showNewFolderSheet = true
    }

    private func performNewFolder() {
        guard let parent = pendingNewFolderParent else { return }
        let name = newFolderInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        startOperation(.createDirectory(in: parent, named: name))
        pendingNewFolderParent = nil
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

    private var functionBar: some View {
        HStack(spacing: 4) {
            ForEach(commandRegistry.functionBarDescriptors) { descriptor in
                Button {
                    dispatch(descriptor.command)
                } label: {
                    HStack(spacing: 3) {
                        if let functionKey = descriptor.functionKeyNumber {
                            Text("F\(functionKey)")
                                .fontWeight(.bold)
                        }
                        Text(descriptor.compactTitle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(descriptor.title)
            }
        }
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
                    onOpenFiles: handleOpenFiles,
                    onEdit: handleEdit,
                    onCopy: { handleCopy() },
                    onMove: { handleMove() },
                    onNewFolder: { handleNewFolder() },
                    onDelete: { handleDelete() },
                    onDropFiles: { urls, destination in
                        startOperation(.copy(urls, to: destination))
                    },
                    onError: showInfo
                )

                FileListView(
                    panelState: appState.rightPanel,
                    commanderState: appState,
                    fileSystem: fileSystem,
                    panelSide: .right,
                    showFavoritesPopover: $appState.showRightFavoritesPopover,
                    onOpenFiles: handleOpenFiles,
                    onEdit: handleEdit,
                    onCopy: { handleCopy() },
                    onMove: { handleMove() },
                    onNewFolder: { handleNewFolder() },
                    onDelete: { handleDelete() },
                    onDropFiles: { urls, destination in
                        startOperation(.copy(urls, to: destination))
                    },
                    onError: showInfo
                )
            }
            .frame(minWidth: 800, minHeight: 600)
            .frame(idealWidth: 1280, idealHeight: 720)
            .background(Color(NSColor.windowBackgroundColor)) // Updated to use NSColor
            .cornerRadius(12)
            .padding()
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    ForEach(toolbarCommands, id: \.self) { command in
                        let descriptor = commandRegistry.descriptor(for: command)
                        Button {
                            dispatch(command)
                        } label: {
                            Label(descriptor.title, systemImage: descriptor.systemImage)
                        }
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        dispatch(.quit)
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
                let textInputActive = appState.textInputActive
                    || appState.commandShortcutsBlocked
                    || NSApp.keyWindow?.firstResponder is NSTextView
                guard let command = commandRegistry.command(
                    keyCode: event.keyCode,
                    modifiers: event.modifierFlags,
                    textInputActive: textInputActive
                ) else { return false }
                dispatch(command)
                return true
            }
            .frame(width: 0, height: 0)

            if isCommandPromptExpanded {
                Divider()

                VStack(alignment: .leading) {
                    HStack {
                        TextField("Befehl eingeben …", text: $command)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("commandField")
                            .focused($isCommandFieldFocused)
                            .onSubmit {
                                executeCommand(command)
                            }
                        Button("Ausführen") {
                            executeCommand(command)
                        }
                        .buttonStyle(ModernButtonStyle())
                        if commandTask != nil {
                            Button("Abbrechen", role: .cancel) {
                                commandTask?.cancel()
                            }
                        }
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
                functionBar
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.underPageBackgroundColor))
            }

            if showCustomButtonBar, !customCommands.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(customCommands) { customCommand in
                            Button(customCommand.title) {
                                execute(customCommand)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .accessibilityLabel("Benutzerdefinierte Buttonleiste")
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
                    if operations.queuedCount > 0 {
                        Button("Warteschlange: \(operations.queuedCount) – alle abbrechen") {
                            operations.cancelAll()
                        }
                        .buttonStyle(.plain)
                        .font(.caption2)
                    }
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
        .onChange(of: appState.pendingCommand) { _, command in
            guard let command else { return }
            appState.pendingCommand = nil
            dispatch(command)
        }
        .onChange(of: hasOpenDialog) { _, isOpen in
            appState.commandShortcutsBlocked = isOpen
        }
        .onChange(of: isCommandFieldFocused) { _, isFocused in
            appState.textInputActive = isFocused
        }
        .onChange(of: isCommandPromptExpanded) { _, isExpanded in
            if !isExpanded { isCommandFieldFocused = false }
        }
        .task {
            await appState.restoreSession(using: fileSystem)
        }
        .sheet(isPresented: $appState.showGotoDirectoryPrompt) {
            VStack {
                Text("Verzeichnis öffnen")
                    .font(.headline)
                    .padding()
                TextField("Verzeichnispfad", text: $goToDirectoryInput)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .focused($focusedDialogField, equals: .gotoPath)
                    .onSubmit {
                        gotoDirectory()
                        appState.showGotoDirectoryPrompt = false
                    }
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
            .onAppear {
                appState.textInputActive = true
                focusedDialogField = .gotoPath
            }
            .onDisappear {
                focusedDialogField = nil
                appState.textInputActive = false
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Element umbenennen")
                    .font(.headline)
                TextField("Neuer Name", text: $renameInput)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("renameField")
                    .focused($focusedDialogField, equals: .rename)
                    .onSubmit {
                        performRename()
                        showRenameSheet = false
                    }
                HStack {
                    Button("Abbrechen", role: .cancel) {
                        pendingRenameURL = nil
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
            .onAppear {
                appState.textInputActive = true
                focusedDialogField = .rename
            }
            .onDisappear {
                focusedDialogField = nil
                appState.textInputActive = false
                pendingRenameURL = nil
            }
        }
        .sheet(isPresented: $showNewFolderSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ordner anlegen")
                    .font(.headline)
                TextField("Ordnername", text: $newFolderInput)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("newFolderNameField")
                    .focused($focusedDialogField, equals: .newFolder)
                    .onSubmit {
                        performNewFolder()
                        showNewFolderSheet = false
                    }
                HStack {
                    Button("Abbrechen", role: .cancel) {
                        pendingNewFolderParent = nil
                        showNewFolderSheet = false
                    }
                    Spacer()
                    Button("Anlegen") {
                        performNewFolder()
                        showNewFolderSheet = false
                    }
                    .disabled(newFolderInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 420)
            .onAppear {
                appState.textInputActive = true
                focusedDialogField = .newFolder
            }
            .onDisappear {
                focusedDialogField = nil
                appState.textInputActive = false
                pendingNewFolderParent = nil
            }
        }
        .sheet(item: $viewerSelection) { selection in
            FileViewerView(url: selection.url) {
                viewerSelection = nil
            }
        }
        .sheet(isPresented: $showSearchSheet) {
            let side = toolPanelSide
            FileSearchView(
                root: appState.panel(for: side).directory,
                fileSystem: fileSystem,
                onShowResults: { results, title, root in
                    appState.addTab(in: side, directory: root)
                    appState.panel(for: side).showSearchResults(results, title: title, root: root)
                },
                onClose: { showSearchSheet = false }
            )
        }
        .sheet(isPresented: $showComparisonSheet) {
            DirectoryComparisonView(
                leftDirectory: appState.leftPanel.directory,
                rightDirectory: appState.rightPanel.directory,
                fileSystem: fileSystem,
                showHiddenFiles: showHiddenFiles,
                onMark: { left, right in
                    appState.leftPanel.setMarks(left)
                    appState.rightPanel.setMarks(right)
                },
                onSynchronize: { sources, destination in
                    showComparisonSheet = false
                    guard !sources.isEmpty else { return }
                    startOperation(.copy(sources, to: destination))
                },
                onClose: { showComparisonSheet = false }
            )
        }
        .sheet(isPresented: $showBatchRenameSheet) {
            BatchRenameView(
                sources: batchRenameSources,
                fileSystem: fileSystem,
                onChanged: { await refreshPanels() },
                onClose: { showBatchRenameSheet = false }
            )
        }
        .sheet(isPresented: $showChecksumSheet) {
            ChecksumView(urls: checksumSources) { showChecksumSheet = false }
        }
        .sheet(item: $contentComparison) { comparison in
            ContentComparisonView(left: comparison.left, right: comparison.right) {
                contentComparison = nil
            }
        }
        .sheet(isPresented: $showArchiveSheet) {
            ArchiveToolView(
                sources: archiveSources,
                targetDirectory: appState.targetPanelState.directory,
                onChanged: { await refreshPanels() },
                onClose: { showArchiveSheet = false }
            )
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
            let components = try CommandLineParser.parse(command)
            guard let executable = components.first else { return }
            commandTask?.cancel()
            commandOutput = "Befehl läuft …"
            let workingDirectory = appState.activePanelState.directory
            commandTask = Task {
                defer { commandTask = nil }
                do {
                    let result = try await CommandRunner().run(
                        executable: executable.contains("/")
                            ? URL(fileURLWithPath: executable)
                            : URL(fileURLWithPath: "/usr/bin/env"),
                        arguments: executable.contains("/")
                            ? Array(components.dropFirst())
                            : components,
                        workingDirectory: workingDirectory
                    )
                    commandOutput = [result.standardOutput, result.standardError]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                } catch is CancellationError {
                    commandOutput = "Befehl abgebrochen."
                } catch {
                    commandOutput = "Fehler: \(error.localizedDescription)"
                }
            }
        } catch {
            showInfo("Befehl kann nicht gelesen werden: \(error.localizedDescription)")
        }
    }

    private func execute(_ customCommand: CustomCommanderCommand) {
        let directory = appState.activePanelState.directory
        let executable = URL(fileURLWithPath: customCommand.executablePath)
        let arguments = customCommand.expandedArguments(
            panelDirectory: directory,
            selectedFile: appState.selectedFile
        )
        commandTask?.cancel()
        commandOutput = "\(customCommand.title) läuft …"
        isCommandPromptExpanded = true
        commandTask = Task {
            defer { commandTask = nil }
            do {
                let result = try await CommandRunner().run(
                    executable: executable,
                    arguments: arguments,
                    workingDirectory: directory
                )
                commandOutput = [result.standardOutput, result.standardError]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            } catch is CancellationError {
                commandOutput = "Befehl abgebrochen."
            } catch {
                commandOutput = "Fehler: \(error.localizedDescription)"
            }
        }
    }

    func gotoDirectory() {
        let expandedPath = NSString(string: goToDirectoryInput).expandingTildeInPath
        let newDirectoryURL = URL(fileURLWithPath: expandedPath, isDirectory: true)
            .standardizedFileURL
        let panel = appState.panel(for: gotoPanelSide)
        Task {
            do {
                try await panel.navigateResolvingLinks(to: newDirectoryURL, using: fileSystem)
            } catch {
                showInfo("Verzeichnis kann nicht geöffnet werden: \(error.localizedDescription)")
            }
        }
    }

}

private enum DialogField: Hashable {
    case gotoPath
    case rename
    case newFolder
}

private struct ViewerSelection: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ContentComparisonSelection: Identifiable {
    let id = UUID()
    let left: URL
    let right: URL
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
