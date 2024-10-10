//
//  FileListView.swift
//  DumbCommander
//
//  Created by Sascha Hansen on 10.10.24.
//


import SwiftUI
import Foundation
import AppKit // Import AppKit for NSColor

struct FileListView: View {
    @Binding var currentDirectory: URL
    @State private var files: [URL] = []
    @State private var currentFile: URL?
    @State private var columnWidths: [CGFloat] = [200, 60, 80, 80]
    @State private var selectedIndex: Int?
    var isActive: Bool
    @ObservedObject var appState: AppState

    // Added function handlers as closures
    var onView: () -> Void
    var onEdit: () -> Void

    var body: some View {
        VStack {
            Text(currentDirectory.path)
                .font(.headline)
                .padding(.bottom, 5)

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
                    HStack {
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
                    .onTapGesture(count: 2) {
                        selectFile(at: index)
                        if file.pathExtension == "app" {
                            NSWorkspace.shared.open(file)
                        } else if file.hasDirectoryPath {
                            currentDirectory = file
                            loadFiles()
                        }
                    }
                    .onTapGesture {
                        selectFile(at: index)
                    }
                    .contextMenu {
                        Button("View") {
                            appState.selectedFile = file
                            onView()
                        }
                        Button("Edit with VS Code") {
                            appState.selectedFile = file
                            onEdit()
                        }
                        Button("Copy") {
                            print("Copy command triggered")
                        }
                        Button("Move") {
                            print("Move command triggered")
                        }
                        Button("New Folder") {
                            print("New Folder command triggered")
                        }
                        Button("Delete") {
                            print("Delete command triggered")
                        }
                        Button("Menu") {
                            print("Menu command triggered")
                        }
                        Button("Quit") {
                            print("Quit command triggered")
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
            .onAppear(perform: loadFiles)
            .background(Color(NSColor.windowBackgroundColor)) // Modern background color with fixed reference
            .cornerRadius(10)
            
            if isActive {
                KeyEventHandlingView { event in
                    switch event.keyCode {
                    case 126: // Up arrow key
                        moveSelection(up: true)
                    case 125: // Down arrow key
                        moveSelection(up: false)
                    default:
                        break
                    }
                }
                .frame(width: 0, height: 0)
            }
        }
        .padding(.horizontal)
        
        // Resizable column handler
        HStack {
            ResizableColumn(width: $columnWidths[0])
            ResizableColumn(width: $columnWidths[1])
            ResizableColumn(width: $columnWidths[2])
            ResizableColumn(width: $columnWidths[3])
        }
        .frame(height: 5)
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
