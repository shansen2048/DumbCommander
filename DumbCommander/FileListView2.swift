//
//  FileListView.swift
//  DumbCommander
//
//  Created by Sascha Hansen on 10.10.24.
//

import Foundation
import SwiftUI
import AppKit // Import AppKit for NSColor

struct FileListView2: View {
    @Binding var currentDirectory: URL
    var isActive: Bool
    @ObservedObject var appState: AppState
    var onView: () -> Void
    var onEdit: () -> Void

    @State private var files: [URL] = []
    @State private var selectedIndex: Int?

    var body: some View {
        VStack {
            Text(currentDirectory.path)
                .font(.headline)
                .padding(.bottom, 5)

            List {
                ForEach(Array(files.enumerated()), id: \.element) { index, file in
                    HStack {
                        Text(file.lastPathComponent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(index == selectedIndex ? Color.blue.opacity(0.3) : Color.clear)
                    .onTapGesture(count: 2) {
                        // Handle double-click action
                        if file.pathExtension == "app" {
                            NSWorkspace.shared.open(file)
                        } else if file.hasDirectoryPath {
                            currentDirectory = file
                            loadFiles()
                        }
                    }
                    .onTapGesture {
                        // Handle single-click action
                        selectedIndex = index
                        appState.selectedFile = file
                    }
                }
            }
            .listStyle(PlainListStyle())
            .onAppear(perform: loadFiles)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
    }

    func loadFiles() {
        do {
            files = try FileManager.default.contentsOfDirectory(at: currentDirectory, includingPropertiesForKeys: nil)
            selectedIndex = nil
        } catch {
            print("Error loading files: \(error)")
        }
    }
}

