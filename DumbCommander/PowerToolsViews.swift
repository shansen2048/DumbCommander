import SwiftUI

struct FileSearchView: View {
    let root: URL
    let fileSystem: any FileSystemServing
    let onShowResults: ([FileItem], String, URL) -> Void
    let onClose: () -> Void

    @State private var namePattern = "*"
    @State private var contentText = ""
    @State private var includesHidden = false
    @State private var isSearching = false
    @State private var visitedCount = 0
    @State private var currentDirectory = ""
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var savedName = ""
    @AppStorage("storedSearchPatterns") private var storedPatternsJSON = "[]"

    private var patterns: [StoredSearchPattern] {
        guard let data = storedPatternsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([StoredSearchPattern].self, from: data)) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dateisuche").font(.title2.bold())
            Text(root.path).font(.caption.monospaced()).foregroundStyle(.secondary)
            Form {
                TextField("Namensmuster, z. B. *.pdf", text: $namePattern)
                TextField("Enthaltener Text (optional, bis 4 MiB)", text: $contentText)
                Toggle("Versteckte Dateien einbeziehen", isOn: $includesHidden)
                if !patterns.isEmpty {
                    Picker("Gespeichertes Muster", selection: Binding(
                        get: { UUID?.none },
                        set: { id in
                            guard let pattern = patterns.first(where: { $0.id == id }) else { return }
                            namePattern = pattern.filePattern
                            contentText = pattern.contentText
                        }
                    )) {
                        Text("Auswählen …").tag(UUID?.none)
                        ForEach(patterns) { pattern in
                            Text(pattern.name).tag(UUID?.some(pattern.id))
                        }
                    }
                }
                HStack {
                    TextField("Name für dieses Muster", text: $savedName)
                    Button("Speichern") { savePattern() }
                        .disabled(savedName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .formStyle(.grouped)

            if isSearching {
                ProgressView()
                Text("\(visitedCount) Elemente geprüft – \(currentDirectory)")
                    .font(.caption.monospaced())
                    .lineLimit(2)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }

            HStack {
                Button("Schließen", role: .cancel) {
                    searchTask?.cancel()
                    onClose()
                }
                Spacer()
                if isSearching {
                    Button("Abbrechen", role: .cancel) { searchTask?.cancel() }
                } else {
                    Button("Suchen") { startSearch() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(minWidth: 620, minHeight: 390)
        .onDisappear { searchTask?.cancel() }
    }

    private func startSearch() {
        isSearching = true
        errorMessage = nil
        visitedCount = 0
        let request = FileSearchRequest(
            root: root,
            namePattern: namePattern,
            contentText: contentText,
            includesHidden: includesHidden
        )
        let service = FileSearchService(fileSystem: fileSystem)
        searchTask = Task {
            do {
                let results = try await service.search(request) { progress in
                    await MainActor.run {
                        visitedCount = progress.visitedCount
                        currentDirectory = progress.currentDirectory.path
                    }
                }
                guard !Task.isCancelled else { return }
                let title = "Suche: \(namePattern) (\(results.count))"
                onShowResults(results, title, root)
                onClose()
            } catch is CancellationError {
                isSearching = false
            } catch {
                errorMessage = error.localizedDescription
                isSearching = false
            }
        }
    }

    private func savePattern() {
        var values = patterns
        values.append(
            StoredSearchPattern(
                name: savedName.trimmingCharacters(in: .whitespacesAndNewlines),
                filePattern: namePattern,
                contentText: contentText
            )
        )
        guard let data = try? JSONEncoder().encode(values),
              let json = String(data: data, encoding: .utf8) else { return }
        storedPatternsJSON = json
        savedName = ""
    }
}

struct DirectoryComparisonView: View {
    let leftDirectory: URL
    let rightDirectory: URL
    let fileSystem: any FileSystemServing
    let showHiddenFiles: Bool
    let onMark: (Set<URL>, Set<URL>) -> Void
    let onSynchronize: ([URL], URL) -> Void
    let onClose: () -> Void

    @State private var entries: [DirectoryComparisonEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verzeichnisse vergleichen und synchronisieren").font(.title2.bold())
            HStack {
                Text("Links: \(leftDirectory.path)")
                Spacer()
                Text("Rechts: \(rightDirectory.path)")
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)

            if isLoading {
                ProgressView("Verzeichnisse werden verglichen …")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else {
                Table(entries) {
                    TableColumn("Name", value: \.name)
                    TableColumn("Ergebnis") { Text($0.difference.title) }
                    TableColumn("Links") { Text($0.left?.formattedSize ?? "—") }
                    TableColumn("Rechts") { Text($0.right?.formattedSize ?? "—") }
                }
                .frame(minHeight: 320)
            }

            Text("Die Synchronisation zeigt hier zuerst alle Unterschiede. Existierende Ziele werden weiterhin ausschließlich über den normalen Konfliktdialog behandelt.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Schließen", role: .cancel, action: onClose)
                Button("Unterschiede markieren") {
                    onMark(
                        Set(entries.filter { $0.difference != .identical }.compactMap { $0.left?.url }),
                        Set(entries.filter { $0.difference != .identical }.compactMap { $0.right?.url })
                    )
                }
                Spacer()
                Button("Rechts → Links") {
                    let sources = entries.filter { $0.difference != .identical }.compactMap { $0.right?.url }
                    onSynchronize(sources, leftDirectory)
                }
                .disabled(entries.allSatisfy { $0.difference == .identical || $0.right == nil })
                Button("Links → Rechts") {
                    let sources = entries.filter { $0.difference != .identical }.compactMap { $0.left?.url }
                    onSynchronize(sources, rightDirectory)
                }
                .disabled(entries.allSatisfy { $0.difference == .identical || $0.left == nil })
            }
        }
        .padding(22)
        .frame(minWidth: 840, minHeight: 520)
        .task { await load() }
    }

    private func load() async {
        do {
            entries = try await DirectoryComparisonService(fileSystem: fileSystem).compare(
                left: leftDirectory,
                right: rightDirectory,
                showHiddenFiles: showHiddenFiles
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct BatchRenameView: View {
    let sources: [URL]
    let fileSystem: any FileSystemServing
    let onChanged: () async -> Void
    let onClose: () -> Void

    @State private var rule = BatchRenameRule()
    @State private var isRunning = false
    @State private var resultMessage: String?
    @State private var undoMappings: [BatchRenameMapping] = []

    private var previews: [BatchRenamePreview] {
        BatchRenamePlanner.previews(for: sources, rule: rule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mehrfachumbenennung").font(.title2.bold())
            Form {
                TextField("Vorlage ([N] Name, [E] Endung, [C] Zähler)", text: $rule.template)
                HStack {
                    TextField("Suchen", text: $rule.find)
                    TextField("Ersetzen", text: $rule.replacement)
                }
                Stepper("Startzähler: \(rule.startIndex)", value: $rule.startIndex, in: 0...999_999)
                Picker("Schreibweise", selection: $rule.caseMode) {
                    ForEach(RenameCaseMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            .formStyle(.grouped)

            Table(previews) {
                TableColumn("Alt") { Text($0.source.lastPathComponent) }
                TableColumn("Neu", value: \.proposedName)
                TableColumn("Prüfung") { Text($0.validationError ?? "✓") }
            }
            .frame(minHeight: 280)

            if let resultMessage { Text(resultMessage).foregroundStyle(.secondary) }
            HStack {
                Button("Schließen", role: .cancel, action: onClose)
                if !undoMappings.isEmpty {
                    Button("Letzte Mehrfachumbenennung rückgängig") { undo() }
                }
                Spacer()
                if isRunning { ProgressView() }
                Button("Umbenennen") { execute() }
                    .disabled(isRunning || previews.isEmpty || previews.contains { $0.validationError != nil })
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(minWidth: 780, minHeight: 590)
    }

    private func execute() {
        isRunning = true
        Task {
            let result = await BatchRenameService(fileSystem: fileSystem).execute(previews)
            if result.errors.isEmpty {
                undoMappings = result.mappings
                resultMessage = "\(result.mappings.count) Elemente wurden umbenannt."
                await onChanged()
            } else {
                resultMessage = result.errors.joined(separator: "\n")
            }
            isRunning = false
        }
    }

    private func undo() {
        isRunning = true
        let mappings = undoMappings
        Task {
            let result = await BatchRenameService(fileSystem: fileSystem).undo(mappings)
            if result.errors.isEmpty {
                undoMappings = []
                resultMessage = "Die Mehrfachumbenennung wurde rückgängig gemacht."
                await onChanged()
            } else {
                resultMessage = result.errors.joined(separator: "\n")
            }
            isRunning = false
        }
    }
}

struct ChecksumView: View {
    let urls: [URL]
    let onClose: () -> Void
    @State private var checksums: [FileChecksum] = []
    @State private var errorMessage: String?
    @State private var expectedChecksum = ""
    @State private var verificationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SHA-256-Prüfsummen").font(.title2.bold())
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else if checksums.isEmpty {
                ProgressView("Prüfsummen werden berechnet …")
            } else {
                List(checksums) { checksum in
                    VStack(alignment: .leading) {
                        Text(checksum.url.lastPathComponent).fontWeight(.semibold)
                        Text(checksum.value).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                GroupBox("Prüfsumme der ersten Datei prüfen") {
                    HStack {
                        TextField("Erwartete SHA-256-Prüfsumme", text: $expectedChecksum)
                            .font(.system(.body, design: .monospaced))
                        Button("Prüfen") {
                            let expected = expectedChecksum
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .lowercased()
                            verificationMessage = expected == checksums.first?.value
                                ? "Prüfsumme stimmt überein."
                                : "Prüfsumme stimmt nicht überein."
                        }
                        .disabled(expectedChecksum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let verificationMessage {
                        Text(verificationMessage)
                            .foregroundStyle(verificationMessage.contains("nicht") ? .red : .green)
                    }
                }
            }
            HStack { Spacer(); Button("Schließen", action: onClose) }
        }
        .padding(22)
        .frame(minWidth: 700, minHeight: 420)
        .task {
            do { checksums = try await ChecksumService().sha256(for: urls) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

struct ContentComparisonView: View {
    let left: URL
    let right: URL
    let onClose: () -> Void
    @State private var message = "Dateien werden verglichen …"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dateiinhalte vergleichen").font(.title2.bold())
            Text(left.path).font(.caption.monospaced())
            Text(right.path).font(.caption.monospaced())
            Divider()
            Text(message)
            HStack { Spacer(); Button("Schließen", action: onClose) }
        }
        .padding(22)
        .frame(minWidth: 650)
        .task {
            do {
                let result = try await ContentComparisonService().compare(left, right)
                message = result.identical
                    ? "Die Dateien sind bytegenau identisch."
                    : "Erster Unterschied bei Byte \(result.firstDifferenceOffset ?? 0)."
            } catch { message = "Vergleich fehlgeschlagen: \(error.localizedDescription)" }
        }
    }
}

struct ArchiveToolView: View {
    let sources: [URL]
    let targetDirectory: URL
    let onChanged: () async -> Void
    let onClose: () -> Void

    @State private var entries: [ArchiveEntry] = []
    @State private var archiveName = "Archiv"
    @State private var format: ArchiveFormat = .zip
    @State private var message: String?
    @State private var isRunning = false

    private var selectedArchive: URL? {
        guard sources.count == 1,
              ["zip", "tar"].contains(sources[0].pathExtension.lowercased()) else { return nil }
        return sources[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Archive").font(.title2.bold())
            if let archive = selectedArchive {
                Text(archive.path).font(.caption.monospaced())
                List(entries) { entry in
                    Label(entry.path, systemImage: entry.isDirectory ? "folder" : "doc")
                }
                .frame(minHeight: 300)
                Button("Nach \(targetDirectory.path) entpacken") { extract(archive) }
            } else {
                Text("\(sources.count) ausgewählte Elemente packen")
                HStack {
                    TextField("Archivname", text: $archiveName)
                    Picker("Format", selection: $format) {
                        ForEach(ArchiveFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .frame(width: 120)
                }
                Button("Archiv im Zielpanel anlegen") { createArchive() }
                    .disabled(sources.isEmpty || archiveName.isEmpty)
            }
            if isRunning { ProgressView() }
            if let message { Text(message).foregroundStyle(.secondary) }
            HStack { Spacer(); Button("Schließen", action: onClose) }
        }
        .padding(22)
        .frame(minWidth: 700, minHeight: 470)
        .task {
            guard let selectedArchive else { return }
            do { entries = try await ArchiveService().list(selectedArchive) }
            catch { message = error.localizedDescription }
        }
    }

    private func extract(_ archive: URL) {
        isRunning = true
        Task {
            do {
                try await ArchiveService().extract(archive, to: targetDirectory)
                message = "Archiv wurde entpackt."
                await onChanged()
            } catch { message = error.localizedDescription }
            isRunning = false
        }
    }

    private func createArchive() {
        isRunning = true
        let destination = targetDirectory.appendingPathComponent("\(archiveName).\(format.rawValue)")
        Task {
            do {
                guard !FileManager.default.fileExists(atPath: destination.path) else {
                    message = "Das Zielarchiv existiert bereits."
                    isRunning = false
                    return
                }
                try await ArchiveService().create(format: format, sources: sources, destination: destination)
                message = "Archiv wurde angelegt."
                await onChanged()
            } catch { message = error.localizedDescription }
            isRunning = false
        }
    }
}
