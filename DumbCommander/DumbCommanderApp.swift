import SwiftUI
import AppKit
import Foundation

@main
struct DumbCommanderApp: App {
    @NSApplicationDelegateAdaptor(CommanderApplicationDelegate.self) private var applicationDelegate
    @StateObject private var appState: CommanderState
    @AppStorage("showStatusBar", store: CommanderPreferences.defaults) private var showStatusBar: Bool = true
    @AppStorage("favoriteDirectories", store: CommanderPreferences.defaults) private var favoriteDirectoriesJSON: String = "[]"
    @AppStorage("appearanceOverride", store: CommanderPreferences.defaults) private var appearanceOverride: String = "system"
    private let fileSystem = LocalFileSystemService()
    private let commandRegistry = CommandRegistry.shared

    init() {
        let isUITesting = CommanderPreferences.isTesting
        // Prepopulate favorite directories with HOME and root if empty
        let key = "favoriteDirectories"
        let json = CommanderPreferences.defaults.string(forKey: key) ?? "[]"
        let existing = (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
        if existing.isEmpty, !isUITesting {
            let defaults = [FileManager.default.homeDirectoryForCurrentUser.path, "/"]
            if let data = try? JSONEncoder().encode(defaults), let encoded = String(data: data, encoding: .utf8) {
                CommanderPreferences.defaults.set(encoded, forKey: key)
            }
        }
        _appState = StateObject(
            wrappedValue: CommanderState(
                defaultDirectory: CommanderPreferences.initialDirectory,
                sessionStore: UserDefaultsCommanderSessionStore(defaults: CommanderPreferences.defaults)
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
                            openFavorite(path, in: appState.leftPanel)
                        }
                    }
                    Divider()
                    Text("Rechts").font(.headline)
                    ForEach(favs, id: \.self) { path in
                        Button("\(URL(fileURLWithPath: path).lastPathComponent)") {
                            openFavorite(path, in: appState.rightPanel)
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

    private func openFavorite(_ path: String, in panel: PanelState) {
        let requestedURL = URL(fileURLWithPath: path, isDirectory: true)
        Task {
            do {
                try await panel.navigateResolvingLinks(to: requestedURL, using: fileSystem)
            } catch {
                appState.deniedDirectory = requestedURL
                appState.directoryAccessErrorMessage = error.localizedDescription
                appState.showDirectoryAccessAlert = true
            }
        }
    }
}
