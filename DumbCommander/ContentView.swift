import SwiftUI
import Foundation
import AppKit // Import AppKit for NSColor

// ActivePanel Enum to track which side of the panel is active
enum ActivePanel {
    case left, right
}

class AppState: ObservableObject {
    @Published var leftDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var rightDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var activePanel: ActivePanel = .left
    @Published var showGotoDirectoryPrompt: Bool = false
    @Published var selectedFile: URL?
}

struct ContentView: View {
    @ObservedObject var appState: AppState
    @State private var command: String = ""
    @State private var commandOutput: String = ""
    @State private var isCommandPromptExpanded: Bool = false
    @State private var goToDirectoryInput: String = ""

    fileprivate func HandleView() {
        if let file = appState.selectedFile {
            NSWorkspace.shared.open(file)
        }
    }

    fileprivate func HandleEdit() {
        if let file = appState.selectedFile {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "/Applications/Visual Studio Code.app", file.path]

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("Failed to open file with Visual Studio Code: \(error)")
            }
        } else {
            print("No file selected for editing.")
        }
    }

    var body: some View {
        VStack {
            HStack {
                FileListView(
                    currentDirectory: appState.activePanel == .left ? $appState.leftDirectory : $appState.rightDirectory,
                    isActive: appState.activePanel == .left,
                    appState: appState,
                    onView: HandleView,
                    onEdit: HandleEdit
                )
                .onTapGesture {
                    appState.activePanel = .left
                }
                
                FileListView(
                    currentDirectory: appState.activePanel == .right ? $appState.rightDirectory : $appState.leftDirectory,
                    isActive: appState.activePanel == .right,
                    appState: appState,
                    onView: HandleView,
                    onEdit: HandleEdit
                )
                .onTapGesture {
                    appState.activePanel = .right
                }
            }
            .frame(minWidth: 800, minHeight: 600)
            .frame(idealWidth: 1280, idealHeight: 720)
            .background(Color(NSColor.windowBackgroundColor)) // Updated to use NSColor
            .cornerRadius(10)
            .padding()

            HStack {
                Button("F1 - left panel") {
                    appState.activePanel = .left
                }
                Button("F2 - right panel") {
                    appState.activePanel = .right
                }
                Button("F3 - View") {
                    HandleView()
                }
                Button("F4 - Edit") {
                    HandleEdit()
                }
                Button("F5 - Copy") {
                    print("F5 key pressed")
                }
                Button("F6 - Move") {
                    print("F6 key pressed")
                }
                Button("F7 - New Folder") {
                    print("F7 key pressed")
                }
                Button("F8 - Delete") {
                    print("F8 key pressed")
                }
                Button("F9 - Menu") {
                    print("F9 key pressed")
                }
                Button("F10 - Quit") {
                    print("F10 key pressed")
                }
                Spacer()
                Button(isCommandPromptExpanded ? "Hide Command Prompt" : "Show Command Prompt") {
                    isCommandPromptExpanded.toggle()
                }
            }
            .buttonStyle(ModernButtonStyle())
            .padding()
            
            KeyEventHandlingView { event in
                switch event.keyCode {
                case 122: // F1
                    appState.activePanel = .left
                case 120: // F2
                    appState.activePanel = .right
                case 99: // F3
                    HandleView()
                case 118: // F4
                    HandleEdit()
                case 96: // F5
                    print("F5 key pressed")
                case 97: // F6
                    print("F6 key pressed")
                case 98: // F7
                    print("F7 key pressed")
                case 100: // F8
                    print("F8 key pressed")
                case 101: // F9
                    print("F9 key pressed")
                case 109: // F10
                    print("F10 key pressed")
                default:
                    break
                }
            }
            .frame(width: 0, height: 0)
            
            if isCommandPromptExpanded {
                Divider()
                
                VStack(alignment: .leading) {
                    HStack {
                        TextField("Enter command...", text: $command)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button("Execute") {
                            executeCommand()
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
        }
        .sheet(isPresented: $appState.showGotoDirectoryPrompt) {
            VStack {
                Text("Go to Directory")
                    .font(.headline)
                    .padding()
                TextField("Enter directory path:", text: $goToDirectoryInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                HStack {
                    Button("Cancel") {
                        appState.showGotoDirectoryPrompt = false
                    }
                    .buttonStyle(ModernButtonStyle())
                    Spacer()
                    Button("Go") {
                        gotoDirectory()
                        appState.showGotoDirectoryPrompt = false
                    }
                    .buttonStyle(ModernButtonStyle())
                }
                .padding()
            }
            .frame(width: 400, height: 200)
        }
    }

    func executeCommand() {
        guard !command.isEmpty else { return }
        
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                commandOutput = output
            } else {
                commandOutput = "Error reading command output."
            }
        } catch {
            commandOutput = "Error: \(error.localizedDescription)"
        }
    }

    func gotoDirectory() {
        let newDirectoryURL = URL(fileURLWithPath: goToDirectoryInput)

        if FileManager.default.fileExists(atPath: newDirectoryURL.path) {
            if appState.activePanel == .left {
                appState.leftDirectory = newDirectoryURL
            } else {
                appState.rightDirectory = newDirectoryURL
            }
        } else {
            commandOutput = "Directory does not exist: \(goToDirectoryInput)"
        }
    }
}



struct ModernButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 100, height: 40) // Größe festlegen
            .background(Color.gray) // Hintergrundfarbe auf Grau ändern
            .foregroundColor(.white) // Schriftfarbe auf Weiß setzen
            .cornerRadius(0) // Ecken abgerundet auf 0 setzen (rechteckig)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}
struct ResizableColumn: View {
    @Binding var width: CGFloat

    var body: some View {
        Rectangle()
            .foregroundColor(.clear)
            .frame(width: 5)
            .background(Color.gray.opacity(0.5))
            .gesture(DragGesture()
                .onChanged { value in
                    self.width = max(50, self.width + value.translation.width)
                }
            )
    }
}

extension URL {
    var parent: URL? {
        return self.deletingLastPathComponent()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(appState: AppState())
    }
}
