import SwiftUI
import AppKit
import Foundation

@main
struct DumbCommanderApp: App {
    @StateObject private var appState: CommanderState
    @AppStorage("showStatusBar") private var showStatusBar: Bool = true
    @AppStorage("favoriteDirectories") private var favoriteDirectoriesJSON: String = "[]"
    @AppStorage("appearanceOverride") private var appearanceOverride: String = "system"
    private let fileSystem = LocalFileSystemService()
    private let commandRegistry = CommandRegistry.shared

    init() {
        let environment = ProcessInfo.processInfo.environment
        let isUITesting = environment["DUMBCOMMANDER_UI_TESTING"] == "1"
        // Prepopulate favorite directories with HOME and root if empty
        let key = "favoriteDirectories"
        let json = UserDefaults.standard.string(forKey: key) ?? "[]"
        let existing = (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
        if existing.isEmpty, !isUITesting {
            let defaults = [FileManager.default.homeDirectoryForCurrentUser.path, "/"]
            if let data = try? JSONEncoder().encode(defaults), let encoded = String(data: data, encoding: .utf8) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
        let defaultDirectory = environment["DUMBCOMMANDER_UI_TEST_DIRECTORY"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        _appState = StateObject(
            wrappedValue: CommanderState(
                defaultDirectory: defaultDirectory,
                sessionStore: isUITesting ? nil : UserDefaultsCommanderSessionStore()
            )
        )
    }

    private func decodeFavorites() -> [String] {
        let data = Data(favoriteDirectoriesJSON.utf8)
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState, fileSystem: fileSystem)
                .preferredColorScheme(appearanceOverride == "light" ? .light : appearanceOverride == "dark" ? .dark : nil)
        }
        .commands {
            CommandMenu("Commander") {
                ForEach(commandRegistry.descriptors) { descriptor in
                    if let key = commandRegistry.keyEquivalent(for: descriptor) {
                        Button(descriptor.title) {
                            appState.dispatch(descriptor.command)
                        }
                        .keyboardShortcut(
                            key,
                            modifiers: commandRegistry.swiftUIModifiers(for: descriptor)
                        )
                        .disabled(
                            appState.textInputActive || appState.commandShortcutsBlocked
                        )
                    } else {
                        Button(descriptor.title) {
                            appState.dispatch(descriptor.command)
                        }
                        .disabled(
                            appState.textInputActive || appState.commandShortcutsBlocked
                        )
                    }
                }
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
                            appState.leftPanel.navigate(to: URL(fileURLWithPath: path))
                        }
                    }
                    Divider()
                    Text("Rechts").font(.headline)
                    ForEach(favs, id: \.self) { path in
                        Button("\(URL(fileURLWithPath: path).lastPathComponent)") {
                            appState.rightPanel.navigate(to: URL(fileURLWithPath: path))
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
