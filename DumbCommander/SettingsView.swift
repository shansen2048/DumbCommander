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
    @AppStorage("appearanceOverride") private var appearanceOverride: String = "system"
    
    @AppStorage("favoriteDirectories") private var favoriteDirectoriesJSON: String = "[]"
    @State private var favorites: [String] = []
    @State private var selectedFavorite: String?

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
        }
        .padding()
        .frame(minWidth: 480, minHeight: 360)
        .onAppear { refreshFavoritesFromStorage() }
        .onChange(of: favoriteDirectoriesJSON) { oldValue, newValue in
            refreshFavoritesFromStorage()
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
