import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("editorChoice") private var editorChoice: String = "system"
    @AppStorage("customEditorPath") private var customEditorPath: String = ""
    @AppStorage("showHiddenFiles") private var showHiddenFiles: Bool = false
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete: Bool = true
    @AppStorage("showStatusBar") private var showStatusBar: Bool = true
    @AppStorage("showFunctionBar") private var showFunctionBar: Bool = true
    @AppStorage("showCustomButtonBar") private var showCustomButtonBar: Bool = true
    @AppStorage("showTypeColumn") private var showTypeColumn: Bool = true
    @AppStorage("showSizeColumn") private var showSizeColumn: Bool = true
    @AppStorage("showPermissionsColumn") private var showPermissionsColumn: Bool = true
    @AppStorage("appearanceOverride") private var appearanceOverride: String = "system"
    @AppStorage("customCommanderCommands") private var customCommandsJSON: String = "[]"
    
    @AppStorage("favoriteDirectories") private var favoriteDirectoriesJSON: String = "[]"
    @State private var favorites: [String] = []
    @State private var selectedFavorite: String?
    @State private var customCommands: [CustomCommanderCommand] = []

    private func decodeFavorites() -> [String] {
        let data = Data(favoriteDirectoriesJSON.utf8)
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func encodeFavorites(_ paths: [String]) {
        if let data = try? JSONEncoder().encode(paths), let json = String(data: data, encoding: .utf8) {
            favoriteDirectoriesJSON = json
        }
    }

    private func refreshFavoritesFromStorage() {
        favorites = decodeFavorites()
        if !favorites.contains(where: { $0 == selectedFavorite }) { selectedFavorite = nil }
    }

    var body: some View {
        TabView {
            Form {
                Section(header: Text("Editor-Auswahl")) {
                    Picker("Editor", selection: $editorChoice) {
                        Text("Systemstandard").tag("system")
                        Text("Visual Studio Code").tag("vscode")
                        Text("Xcode").tag("xcode")
                        Text("TextEdit").tag("textedit")
                        Text("Benutzerdefiniert…").tag("custom")
                    }
                    .pickerStyle(RadioGroupPickerStyle())
                    
                    if editorChoice == "custom" {
                        HStack {
                            TextField("Pfad zum Editor", text: $customEditorPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Auswählen…") {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.application, .applicationBundle]
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = true
                                panel.allowsMultipleSelection = false
                                panel.title = "Benutzerdefinierten Editor wählen"
                                
                                if panel.runModal() == .OK, let url = panel.url {
                                    customEditorPath = url.path
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Erscheinungsbild")) {
                    Picker("Modus", selection: $appearanceOverride) {
                        Text("Systemstandard").tag("system")
                        Text("Hell").tag("light")
                        Text("Dunkel").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Allgemein")) {
                    Toggle("Versteckte Dateien anzeigen", isOn: $showHiddenFiles)
                    Toggle("Löschen bestätigen", isOn: $confirmBeforeDelete)
                    Toggle("Statusleiste anzeigen", isOn: $showStatusBar)
                    Toggle("Funktionsleiste anzeigen", isOn: $showFunctionBar)
                    Toggle("Benutzerdefinierte Buttonleiste anzeigen", isOn: $showCustomButtonBar)
                }

                Section(header: Text("Panelspalten")) {
                    Toggle("Typ", isOn: $showTypeColumn)
                    Toggle("Größe", isOn: $showSizeColumn)
                    Toggle("Rechte", isOn: $showPermissionsColumn)
                }
            }
            .tabItem { Label("Allgemein", systemImage: "gear") }
            
            Form {
                Section(header: Text("Favoriten")) {
                    VStack(alignment: .leading) {
                        List(selection: $selectedFavorite) {
                            ForEach(favorites, id: \.self) { path in
                                HStack {
                                    Image(systemName: "folder")
                                    Text(path)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .tag(path)
                            }
                            .onDelete { indexSet in
                                var newFavs = favorites
                                for index in indexSet {
                                    if index < newFavs.count { newFavs.remove(at: index) }
                                }
                                favorites = newFavs
                                encodeFavorites(newFavs)
                            }
                        }
                        .frame(minHeight: 160)

                        HStack {
                            Button("Hinzufügen…") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.allowsMultipleSelection = true
                                panel.title = "Favoriten-Verzeichnisse hinzufügen"
                                panel.allowedContentTypes = [.folder]
                                if panel.runModal() == .OK {
                                    var newFavs = favorites
                                    for url in panel.urls {
                                        let p = url.path
                                        if !newFavs.contains(p) { newFavs.append(p) }
                                    }
                                    favorites = newFavs
                                    encodeFavorites(newFavs)
                                }
                            }
                            Button("Bearbeiten…") {
                                guard let sel = selectedFavorite, let idx = favorites.firstIndex(of: sel) else { return }
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.allowsMultipleSelection = false
                                panel.title = "Favoriten-Verzeichnis ändern"
                                panel.allowedContentTypes = [.folder]
                                if panel.runModal() == .OK, let url = panel.url {
                                    var newFavs = favorites
                                    newFavs[idx] = url.path
                                    favorites = newFavs
                                    selectedFavorite = url.path
                                    encodeFavorites(newFavs)
                                }
                            }
                            .disabled(selectedFavorite == nil)
                            Button("Entfernen") {
                                guard let sel = selectedFavorite, let idx = favorites.firstIndex(of: sel) else { return }
                                var newFavs = favorites
                                newFavs.remove(at: idx)
                                favorites = newFavs
                                selectedFavorite = nil
                                encodeFavorites(newFavs)
                            }
                            .disabled(selectedFavorite == nil)
                            Spacer()
                        }
                    }
                }
            }
            .tabItem { Label("Favoriten", systemImage: "star") }

            VStack(alignment: .leading, spacing: 10) {
                Text("Benutzerdefinierte Befehle")
                    .font(.headline)
                Text("Jedes Argument steht in einer eigenen Zeile. %P wird durch den aktiven Panelpfad, %F durch die ausgewählte Datei ersetzt. Die Befehle laufen ohne Shell-Auswertung.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                List {
                    ForEach($customCommands) { $customCommand in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Beschriftung", text: $customCommand.title)
                            TextField("Absoluter Pfad zum Programm", text: $customCommand.executablePath)
                            TextField(
                                "Argumente, eines pro Zeile",
                                text: Binding(
                                    get: { customCommand.arguments.joined(separator: "\n") },
                                    set: { customCommand.arguments = $0.components(separatedBy: "\n") }
                                ),
                                axis: .vertical
                            )
                            .lineLimit(2...5)
                        }
                        .padding(.vertical, 5)
                    }
                    .onDelete { customCommands.remove(atOffsets: $0) }
                }
                HStack {
                    Button("Befehl hinzufügen") {
                        customCommands.append(
                            CustomCommanderCommand(
                                title: "Neuer Befehl",
                                executablePath: "/usr/bin/open",
                                arguments: ["%F"]
                            )
                        )
                    }
                    Spacer()
                    Button("Speichern") { encodeCustomCommands() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .tabItem { Label("Befehle", systemImage: "terminal") }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 360)
        .onAppear {
            refreshFavoritesFromStorage()
            decodeCustomCommands()
        }
        .onChange(of: favoriteDirectoriesJSON) { oldValue, newValue in
            refreshFavoritesFromStorage()
        }
    }

    private func decodeCustomCommands() {
        guard let data = customCommandsJSON.data(using: .utf8) else { return }
        customCommands = (try? JSONDecoder().decode([CustomCommanderCommand].self, from: data)) ?? []
    }

    private func encodeCustomCommands() {
        guard let data = try? JSONEncoder().encode(customCommands),
              let json = String(data: data, encoding: .utf8) else { return }
        customCommandsJSON = json
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
