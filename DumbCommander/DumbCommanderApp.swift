import SwiftUI
import SwiftData

@main
struct DumbCommanderApp: App {
    @StateObject var appState = AppState()  // Create an instance of AppState

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

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)  // Pass the appState to ContentView
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandMenu("Navigation") {
                Button("Go to Directory") {
                    appState.showGotoDirectoryPrompt = true
                }
                .keyboardShortcut("g", modifiers: [.command])
            }
        }
    }
}
