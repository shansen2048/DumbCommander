import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum FileViewerMode: String, CaseIterable, Identifiable {
    case text = "Text"
    case hexadecimal = "Hex"
    case image = "Bild"
    case metadata = "Informationen"

    var id: String { rawValue }
}

struct FileViewerPayload: Sendable {
    let url: URL
    let data: Data
    let fileSize: Int64
    let modificationDate: Date?
    let creationDate: Date?
    let permissions: String
    let isTruncated: Bool
    let isImage: Bool
    let imagePreview: CGImage?
    let text: String
    let hexadecimalText: String
}

private extension FileViewerPayload {
    static func hexadecimalText(for data: Data) -> String {
        let bytes = data.prefix(524_288)
        var lines: [String] = []
        lines.reserveCapacity((bytes.count + 15) / 16)
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + 16, bytes.count)
            let slice = bytes[offset..<end]
            let hex = slice.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = slice.map { byte -> Character in
                (32...126).contains(byte) ? Character(UnicodeScalar(byte)) : "."
            }
            lines.append(
                String(format: "%08X  %-47@  %@", offset, hex as NSString, String(ascii))
            )
            offset = end
        }
        return lines.joined(separator: "\n")
    }
}

actor FileViewerLoader {
    static let previewLimit = 4 * 1_024 * 1_024
    static let imageLimit = 64 * 1_024 * 1_024

    func load(_ url: URL) throws -> FileViewerPayload {
        try Task.checkCancellation()
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let isImage = Self.isImage(url)
        let limit = isImage ? Self.imageLimit : Self.previewLimit
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit) ?? Data()
        try Task.checkCancellation()
        let imagePreview: CGImage?
        if isImage,
           let source = CGImageSourceCreateWithData(data as CFData, nil) {
            imagePreview = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2_048,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary
            )
        } else {
            imagePreview = nil
        }

        return FileViewerPayload(
            url: url,
            data: data,
            fileSize: fileSize,
            modificationDate: attributes[.modificationDate] as? Date,
            creationDate: attributes[.creationDate] as? Date,
            permissions: Self.permissions(from: attributes[.posixPermissions] as? NSNumber),
            isTruncated: fileSize > Int64(data.count),
            isImage: isImage,
            imagePreview: imagePreview,
            text: String(decoding: data.prefix(Self.previewLimit), as: UTF8.self),
            hexadecimalText: FileViewerPayload.hexadecimalText(
                for: Data(data.prefix(Self.previewLimit))
            )
        )
    }

    private static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    private static func permissions(from number: NSNumber?) -> String {
        guard let value = number?.uint16Value else { return "Unbekannt" }
        return String(format: "%03o", value & 0o777)
    }
}

@MainActor
final class FileViewerModel: ObservableObject {
    @Published private(set) var payload: FileViewerPayload?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    private let loader: FileViewerLoader
    private var task: Task<Void, Never>?

    init(loader: FileViewerLoader = FileViewerLoader()) {
        self.loader = loader
    }

    func load(_ url: URL) {
        task?.cancel()
        payload = nil
        errorMessage = nil
        isLoading = true
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await loader.load(url)
                try Task.checkCancellation()
                self.payload = payload
            } catch is CancellationError {
                return
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

struct FileViewerView: View {
    let url: URL
    let onClose: () -> Void
    @StateObject private var model = FileViewerModel()
    @State private var mode: FileViewerMode = .text

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(url.lastPathComponent)
                    .font(.title2.bold())
                Spacer()
                Picker("Darstellung", selection: $mode) {
                    ForEach(FileViewerMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
            }

            Group {
                if model.isLoading {
                    ProgressView("Datei wird geladen …")
                } else if let errorMessage = model.errorMessage {
                    ContentUnavailableView(
                        "Datei kann nicht angezeigt werden",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if let payload = model.payload {
                    viewerContent(payload)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                if model.payload?.isTruncated == true {
                    Label(
                        "Vorschau ist auf \(ByteCountFormatter.string(fromByteCount: Int64(model.payload?.data.count ?? 0), countStyle: .file)) begrenzt.",
                        systemImage: "scissors"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Schließen", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 820, minHeight: 600)
        .task(id: url) {
            model.load(url)
        }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder
    private func viewerContent(_ payload: FileViewerPayload) -> some View {
        switch mode {
        case .text:
            ScrollView([.horizontal, .vertical]) {
                Text(payload.text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .hexadecimal:
            ScrollView([.horizontal, .vertical]) {
                Text(payload.hexadecimalText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .image:
            if payload.isImage, let image = payload.imagePreview {
                ScrollView([.horizontal, .vertical]) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                ContentUnavailableView(
                    "Keine Bildvorschau",
                    systemImage: "photo",
                    description: Text("Das ausgewählte Element ist kein unterstütztes Bild.")
                )
            }
        case .metadata:
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                metadataRow("Pfad", payload.url.path)
                metadataRow("Größe", ByteCountFormatter.string(fromByteCount: payload.fileSize, countStyle: .file))
                metadataRow("POSIX-Rechte", payload.permissions)
                metadataRow("Geändert", payload.modificationDate?.formatted() ?? "Unbekannt")
                metadataRow("Erstellt", payload.creationDate?.formatted() ?? "Unbekannt")
                metadataRow("Vorschau", payload.isTruncated ? "Gekürzt" : "Vollständig")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func metadataRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).fontWeight(.semibold)
            Text(value).textSelection(.enabled)
        }
    }
}
