import SwiftUI

// Hauptansicht der App
struct ContentView: View {
    // Zustand für die linken und rechten Verzeichnisse, initialisiert mit dem Heimatverzeichnis des Benutzers
    @State private var leftDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var rightDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    
    var body: some View {
        HStack {
            // Linke Dateiliste
            FileListView(currentDirectory: $leftDirectory)
            // Rechte Dateiliste
            FileListView(currentDirectory: $rightDirectory)
        }
        // Minimale Größe des Fensters
        .frame(minWidth: 800, minHeight: 600)
    }
}

// Ansicht für die Dateiliste eines Verzeichnisses
struct FileListView: View {
    // Binding zum aktuellen Verzeichnis
    @Binding var currentDirectory: URL
    // Zustand für die Liste der Dateien im aktuellen Verzeichnis
    @State private var files: [URL] = []
    
    var body: some View {
        VStack {
            // Anzeige des aktuellen Verzeichnispfades
            Text(currentDirectory.path)
                .font(.headline)
                .padding()
            
            // Liste der Dateien im aktuellen Verzeichnis
            List(files, id: \.self) { file in
                HStack {
                    // Dateiname
                    Text(file.lastPathComponent)
                    Spacer()
                    // Anzeige ob Datei oder Ordner
                    if file.hasDirectoryPath {
                        Text("Folder")
                    } else {
                        Text(file.pathExtension)
                    }
                }
                // Wenn auf einen Ordner getippt wird, wechsle in diesen Ordner
                .onTapGesture {
                    if file.hasDirectoryPath {
                        currentDirectory = file
                        loadFiles()
                    }
                }
            }
            // Dateien laden, wenn die Ansicht erscheint
            .onAppear(perform: loadFiles)
            
            HStack {
                // Knopf um ins übergeordnete Verzeichnis zu wechseln
                Button("Up") {
                    if let parentDirectory = currentDirectory.parent {
                        currentDirectory = parentDirectory
                        loadFiles()
                    }
                }
                .padding()
                
                Spacer()
            }
        }
    }
    
    // Funktion zum Laden der Dateien im aktuellen Verzeichnis
    func loadFiles() {
        do {
            // Inhalte des aktuellen Verzeichnisses abrufen
            files = try FileManager.default.contentsOfDirectory(at: currentDirectory, includingPropertiesForKeys: nil)
        } catch {
            print("Error loading files: \(error)")
        }
    }
}

// Erweiterung um den übergeordneten Ordner einer URL zu erhalten
extension URL {
    var parent: URL? {
        return self.deletingLastPathComponent()
    }
}

// Vorschau für die Entwicklungsumgebung
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
