import SwiftUI
import AppKit
import Foundation

@main
struct DumbCommanderApp: App {
    @StateObject var appState = AppState()
    @AppStorage("showStatusBar") var showStatusBar: Bool = true
    @AppStorage("favoriteDirectories") var favoriteDirectoriesJSON: String = "[]"
    @AppStorage("appearanceOverride") var appearanceOverride: String = "system" // system, light, dark

    init() {
        // Prepopulate favorite directories with HOME and root if empty
        let key = "favoriteDirectories"
        let json = UserDefaults.standard.string(forKey: key) ?? "[]"
        let existing = (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
        if existing.isEmpty {
            let defaults = [FileManager.default.homeDirectoryForCurrentUser.path, "/"]
            if let data = try? JSONEncoder().encode(defaults), let encoded = String(data: data, encoding: .utf8) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }

    private func decodeFavorites() -> [String] {
        let data = Data(favoriteDirectoriesJSON.utf8)
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    // Key equivalent for function keys (F1 = U+F704, see NSF1FunctionKey)
    private func fKey(_ n: Int) -> KeyEquivalent {
        KeyEquivalent(Character(UnicodeScalar(0xF704 + (n - 1))!))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .preferredColorScheme(appearanceOverride == "light" ? .light : appearanceOverride == "dark" ? .dark : nil)
        }
        .commands {
            CommandMenu("Navigation") {
                Button("Linkes Panel aktivieren") { appState.activePanel = .left }
                    .keyboardShortcut(fKey(1), modifiers: [])
                Button("Rechtes Panel aktivieren") { appState.activePanel = .right }
                    .keyboardShortcut(fKey(2), modifiers: [])
                Button("Anzeigen") { appState.pendingAction = .view }
                    .keyboardShortcut(fKey(3), modifiers: [])
                Button("Bearbeiten") { appState.pendingAction = .edit }
                    .keyboardShortcut(fKey(4), modifiers: [])
                Button("Kopieren") { appState.pendingAction = .copy }
                    .keyboardShortcut(fKey(5), modifiers: [])
                Button("Verschieben") { appState.pendingAction = .move }
                    .keyboardShortcut(fKey(6), modifiers: [])
                Button("Neuer Ordner") { appState.pendingAction = .newFolder }
                    .keyboardShortcut(fKey(7), modifiers: [])
                Button("Löschen") { appState.pendingAction = .delete }
                    .keyboardShortcut(fKey(8), modifiers: [])
                Button("Beenden") { NSApp.terminate(nil) }
                    .keyboardShortcut(fKey(10), modifiers: [])
                Divider()
                Button("Gehe zu Verzeichnis …") { appState.showGotoDirectoryPrompt = true }
                    .keyboardShortcut("g", modifiers: [.command])
            }
            CommandMenu("Ansicht") {
                Toggle("Statusleiste anzeigen", isOn: $showStatusBar)
                    .keyboardShortcut("/", modifiers: [.command])
                Divider()
                Picker("Erscheinungsbild", selection: $appearanceOverride) {
                    Text("Systemstandard").tag("system")
                    Text("Hell").tag("light")
                    Text("Dunkel").tag("dark")
                }
            }
            CommandMenu("Favoriten") {
                let favs = decodeFavorites()
                if favs.isEmpty {
                    Text("Keine Favoriten vorhanden")
                } else {
                    Text("Links").font(.headline)
                    ForEach(favs, id: \.self) { path in
                        Button("\(URL(fileURLWithPath: path).lastPathComponent)") {
                            appState.leftDirectory = URL(fileURLWithPath: path)
                        }
                    }
                    Divider()
                    Text("Rechts").font(.headline)
                    ForEach(favs, id: \.self) { path in
                        Button("\(URL(fileURLWithPath: path).lastPathComponent)") {
                            appState.rightDirectory = URL(fileURLWithPath: path)
                        }
                    }
                }
                Divider()
                SettingsLink {
                    Text("Einstellungen …")
                }
            }
        }
        Settings {
            SettingsView()
        }
    }
}
