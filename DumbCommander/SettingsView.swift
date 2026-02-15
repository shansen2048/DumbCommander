import SwiftUI
import AppKit

struct PreferencesView: View {
    @AppStorage("editorChoice") private var editorChoice: String = "system"
    @AppStorage("customEditorPath") private var customEditorPath: String = ""
    @AppStorage("showHiddenFiles") private var showHiddenFiles: Bool = false
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete: Bool = true
    
    var body: some View {
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
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button("Auswählen…") {
                            let panel = NSOpenPanel()
                            panel.allowedFileTypes = ["app"]
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
            
            Section(header: Text("Allgemein")) {
                Toggle("Versteckte Dateien anzeigen", isOn: $showHiddenFiles)
                Toggle("Löschen bestätigen", isOn: $confirmBeforeDelete)
            }
        }
        .padding()
        .frame(minWidth: 400)
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
