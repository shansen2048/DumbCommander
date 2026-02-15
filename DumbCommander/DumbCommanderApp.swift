import SwiftUI
import SwiftData
import AppKit
import Foundation

@main
struct DumbCommanderApp: App {
    init() {
        // Prepopulate favorite directories with HOME and root if empty
        let key = "favoriteDirectories"
        if let json = UserDefaults.standard.string(forKey: key), let data = json.data(using: .utf8) {
            let arr = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            if arr.isEmpty {
                let defaults = [FileManager.default.homeDirectoryForCurrentUser.path, "/"]
                if let d = try? JSONEncoder().encode(defaults), let s = String(data: d, encoding: .utf8) {
                    UserDefaults.standard.set(s, forKey: key)
                }
            }
        } else {
            let defaults = [FileManager.default.homeDirectoryForCurrentUser.path, "/"]
            if let d = try? JSONEncoder().encode(defaults), let s = String(data: d, encoding: .utf8) {
                UserDefaults.standard.set(s, forKey: key)
            }
        }
    }

    @StateObject var appState = AppState()  // Create an instance of AppState
    @AppStorage("showStatusBar") var showStatusBar: Bool = true

    @AppStorage("favoriteDirectories") var favoriteDirectoriesJSON: String = "[]"

    private func decodeFavorites() -> [String] {
        let data = Data(favoriteDirectoriesJSON.utf8)
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    @AppStorage("showHiddenFiles") var showHiddenFiles: Bool = false
    @AppStorage("appearanceOverride") var appearanceOverride: String = "system" // system, light, dark

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    private func configureFunctionKeyShortcuts() {
        guard let mainMenu = NSApp.mainMenu else { return }
        guard let navItem = mainMenu.items.first(where: { $0.title == "Navigation" }), let submenu = navItem.submenu else { return }
        func fKeyString(_ n: Int) -> String { String(Character(UnicodeScalar(0xF704 + (n - 1))!)) }
        func setShortcut(title: String, f: Int) {
            if let item = submenu.items.first(where: { $0.title == title }) {
                item.keyEquivalent = fKeyString(f)
                item.keyEquivalentModifierMask = []
            }
        }
        setShortcut(title: "Linkes Panel aktivieren (F1)", f: 1)
        setShortcut(title: "Rechtes Panel aktivieren (F2)", f: 2)
        setShortcut(title: "Anzeigen (F3)", f: 3)
        setShortcut(title: "Bearbeiten (F4)", f: 4)
        setShortcut(title: "Kopieren (F5)", f: 5)
        setShortcut(title: "Verschieben (F6)", f: 6)
        setShortcut(title: "Neuer Ordner (F7)", f: 7)
        setShortcut(title: "Löschen (F8)", f: 8)
        setShortcut(title: "Beenden (F10)", f: 10)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .preferredColorScheme(appearanceOverride == "light" ? .light : appearanceOverride == "dark" ? .dark : nil)
                .onAppear { configureFunctionKeyShortcuts() }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandMenu("Navigation") {
                Button("Linkes Panel aktivieren (F1)") { appState.activePanel = .left }
                Button("Rechtes Panel aktivieren (F2)") { appState.activePanel = .right }
                Button("Anzeigen (F3)") { appState.pendingAction = .view }
                Button("Bearbeiten (F4)") { appState.pendingAction = .edit }
                Button("Kopieren (F5)") { appState.pendingAction = .copy }
                Button("Verschieben (F6)") { appState.pendingAction = .move }
                Button("Neuer Ordner (F7)") { appState.pendingAction = .newFolder }
                Button("Löschen (F8)") { appState.pendingAction = .delete }
                Button("Beenden (F10)") { NSApp.terminate(nil) }
                Divider()
                Button("Verzeichnis hoch (Ctrl+Bild↑)") { }
                    .keyboardShortcut(.pageUp, modifiers: [.control])
                Button("In Verzeichnis wechseln (Ctrl+Bild↓)") { }
                    .keyboardShortcut(.pageDown, modifiers: [.control])
                Divider()
                Button("Go to Directory (⌘G)") { appState.showGotoDirectoryPrompt = true }
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
                    Divider()
                    Button("Einstellungen …") {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }
            }
        }
        Settings {
            SettingsView()
        }
    }
}

