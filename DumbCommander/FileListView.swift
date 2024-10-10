import SwiftUI
import Foundation
import AppKit

struct FileListView: View {
    @Binding var currentDirectory: URL
    @State private var files: [URL] = []
    @State private var currentFile: URL?
    @State private var columnWidths: [CGFloat] = [200, 60, 80, 80]
    @State private var selectedIndex: Int?
    var isActive: Bool
    @ObservedObject var appState: AppState
    var onView: () -> Void
    var onEdit: () -> Void

    var body: some View {
        VStack {
            Text(currentDirectory.path)
                .font(.headline)
                .padding(.bottom, 5)

            // Column Headers
            HStack(spacing: 0) {
                Text("Name")
                    .frame(width: columnWidths[0], alignment: .leading)
                    .padding(.leading, 5)
                    .background(Color.gray.opacity(0.2))
                
                Text("Type")
                    .frame(width: columnWidths[1], alignment: .leading)
                    .background(Color.gray.opacity(0.2))
                
                Text("Size")
                    .frame(width: columnWidths[2], alignment: .leading)
                    .background(Color.gray.opacity(0.2))
                
                Text("Permissions")
                    .frame(width: columnWidths[3], alignment: .leading)
                    .background(Color.gray.opacity(0.2))
            }
            
            List {
                if currentDirectory.path != FileManager.default.homeDirectoryForCurrentUser.path {
                    HStack {
                        Text("..")
                            .frame(width: columnWidths[0], alignment: .leading)
                        Spacer()
                    }
                    .background(selectedIndex == -1 ? Color.blue.opacity(0.3) : Color.clear)
                    .onTapGesture {
                        goUpOneDirectory()
                    }
                }

                ForEach(Array(files.enumerated()), id: \.element) { index, file in
                    HStack(spacing: 0) {
                        Text(file.lastPathComponent)
                            .frame(width: columnWidths[0], alignment: .leading)
                        Spacer(minLength: 0)
                        if file.hasDirectoryPath {
                            Text("Folder")
                                .frame(width: columnWidths[1], alignment: .leading)
                        } else {
                            Text(file.pathExtension)
                                .frame(width: columnWidths[1], alignment: .leading)
                        }
                        Spacer(minLength: 0)
                        Text(fileSizeString(for: file))
                            .frame(width: columnWidths[2], alignment: .leading)
                        Spacer(minLength: 0)
                        Text(filePermissions(for: file))
                            .frame(width: columnWidths[3], alignment: .leading)
                    }
                    .background(index == selectedIndex ? Color.blue.opacity(0.3) : Color.clear)
                    .onTapGesture {
                        selectFile(at: index)
                    }
                }
            }
            .listStyle(PlainListStyle())
            .onAppear(perform: loadFiles)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)

            // Resizable column handlers
            HStack(spacing: 0) {
                ResizableColumn(width: $columnWidths[0])
                ResizableColumn(width: $columnWidths[1])
                ResizableColumn(width: $columnWidths[2])
                ResizableColumn(width: $columnWidths[3])
            }
            .frame(height: 5)
        }
        .padding(.horizontal)
    }
    
    func loadFiles() {
        do {
            files = try FileManager.default.contentsOfDirectory(at: currentDirectory, includingPropertiesForKeys: [.fileSizeKey, .isReadableKey])
            selectedIndex = nil
        } catch {
            print("Error loading files: \(error)")
        }
    }
    
    func goUpOneDirectory() {
        if let parentDirectory = currentDirectory.parent {
            currentDirectory = parentDirectory
            loadFiles()
            selectedIndex = nil
        }
    }
    
    func fileSizeString(for file: URL) -> String {
        do {
            let resourceValues = try file.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = resourceValues.fileSize {
                return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
            }
        } catch {
            print("Error retrieving file size: \(error)")
        }
        return "N/A"
    }
    
    func filePermissions(for file: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            if let posixPermissions = attributes[.posixPermissions] as? NSNumber {
                let permissions = posixPermissions.uint16Value
                let owner = (permissions & S_IRWXU) >> 6
                let group = (permissions & S_IRWXG) >> 3
                let others = permissions & S_IRWXO
                
                func rwxString(_ value: UInt16) -> String {
                    let read = (value & 0b100) != 0 ? "r" : "-"
                    let write = (value & 0b010) != 0 ? "w" : "-"
                    let execute = (value & 0b001) != 0 ? "x" : "-"
                    return "\(read)\(write)\(execute)"
                }
                
                let ownerPermissions = rwxString(owner)
                let groupPermissions = rwxString(group)
                let othersPermissions = rwxString(others)
                
                return "\(ownerPermissions)\(groupPermissions)\(othersPermissions)"
            }
        } catch {
            print("Error retrieving file permissions: \(error)")
        }
        return "N/A"
    }
    
    func selectFile(at index: Int) {
        guard index >= 0 && index < files.count else { return }
        currentFile = files[index]
        appState.selectedFile = currentFile
        selectedIndex = index
    }
    
    func moveSelection(up: Bool) {
        guard !files.isEmpty else { return }
        if selectedIndex == nil {
            selectedIndex = up ? files.count - 1 : 0
        } else {
            if up {
                selectedIndex = max(0, selectedIndex! - 1)
            } else {
                selectedIndex = min(files.count - 1, selectedIndex! + 1)
            }
        }
        if let selectedIndex = selectedIndex {
            selectFile(at: selectedIndex)
        }
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
