import SwiftUI

struct CommanderSelectionSummary: View {
    @ObservedObject var panel: PanelState

    var body: some View {
        Text(panel.selectedItem.map { "Ausgewählt: \($0.name)" } ?? "Keine Auswahl")
            .lineLimit(1)
            .truncationMode(.middle)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct PanelIdentityHeader: View {
    @ObservedObject var panel: PanelState
    let side: ActivePanel
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: panel.isVirtual ? "magnifyingglass" : "folder.fill")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            Text(side == .left ? "Links" : "Rechts")
                .font(.headline)
            Spacer()
            Label(
                isActive ? "Quelle" : (panel.isVirtual ? "Suchergebnis" : "Ziel"),
                systemImage: isActive ? "arrow.up.right" : (panel.isVirtual ? "magnifyingglass" : "arrow.down.left")
            )
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.08), in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

struct PanelStatusBar: View {
    @ObservedObject var panel: PanelState

    var body: some View {
        let visible = panel.visibleItems
        let marked = visible.filter { panel.markedURLs.contains($0.url) }
        HStack(spacing: 8) {
            if panel.isLoading {
                ProgressView().controlSize(.mini)
                Text("Wird geladen …")
            } else {
                Text("\(visible.count) Einträge")
                if !panel.filterText.isEmpty {
                    Text("von \(panel.items.count)").foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            if !marked.isEmpty {
                Label("\(marked.count) markiert", systemImage: "checkmark.square.fill")
                    .foregroundStyle(Color.accentColor)
                Text(ByteCountFormatter.string(
                    fromByteCount: marked.filter { !$0.isDirectory }.reduce(0) { $0 + $1.size },
                    countStyle: .file
                ))
            } else {
                Text("Shift: Bereich markieren")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityIdentifier("panelStatus")
    }
}

struct CommanderWorkspaceHeader: View {
    let onSearch: () -> Void
    let onCompare: () -> Void
    let onArchive: () -> Void
    let onHistory: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Dateien").font(.title2.weight(.semibold))
                Text("Zwei Panels. Ein Arbeitsbereich.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onSearch) { Label("Suchen", systemImage: "magnifyingglass") }
                .help("Rekursive Dateisuche · ⇧⌘F")
            Button(action: onCompare) { Label("Vergleichen", systemImage: "rectangle.split.2x1") }
            Button(action: onArchive) { Label("Archive", systemImage: "archivebox") }
            Button(action: onHistory) { Image(systemName: "list.bullet.clipboard") }
                .help("Operationsberichte dieser Sitzung")
                .accessibilityLabel("Operationsberichte")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}
