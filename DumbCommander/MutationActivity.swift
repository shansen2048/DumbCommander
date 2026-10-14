import SwiftUI
import AppKit

struct MutationJobRecord: Identifiable {
    let id: UUID
    let title: String
    let summary: String
    let details: [String]
}

@MainActor
final class MutationActivity: ObservableObject {
    static let shared = MutationActivity()
    @Published private(set) var running: [UUID: String] = [:]
    @Published private(set) var reports: [MutationJobRecord] = []
    private var cancellation: [UUID: () -> Void] = [:]
    private var idleActions: [() -> Void] = []
    var isRunning: Bool { !running.isEmpty }

    func begin(_ title: String, cancel: @escaping () -> Void) -> UUID {
        let id = UUID()
        running[id] = title
        cancellation[id] = cancel
        return id
    }

    func finish(_ id: UUID, summary: String, details: [String]) {
        guard let title = running.removeValue(forKey: id) else { return }
        cancellation.removeValue(forKey: id)
        reports.insert(MutationJobRecord(id: id, title: title, summary: summary, details: details), at: 0)
        if !isRunning {
            let actions = idleActions
            idleActions.removeAll()
            actions.forEach { $0() }
        }
    }

    func cancelAll() { Array(cancellation.values).forEach { $0() } }

    func whenIdle(_ action: @escaping () -> Void) {
        if isRunning { idleActions.append(action) } else { action() }
    }

    enum CloseChoice { case keepWorking, cancelAndWait, wait }

    func closeChoice() -> CloseChoice {
        let alert = NSAlert()
        alert.messageText = "Dateioperationen laufen noch"
        alert.informativeText = "Beim Abbrechen wird zuerst die laufende Wiederherstellung abgeschlossen. Temporäre Daten dürfen nicht durch sofortiges Beenden verloren gehen."
        alert.addButton(withTitle: "Weiterarbeiten")
        alert.addButton(withTitle: "Abbrechen und warten")
        alert.addButton(withTitle: "Nach Abschluss schließen")
        switch alert.runModal() {
        case .alertSecondButtonReturn: return .cancelAndWait
        case .alertThirdButtonReturn: return .wait
        default: return .keepWorking
        }
    }
}

@MainActor
final class CommanderApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let activity = MutationActivity.shared
        guard activity.isRunning else { return .terminateNow }
        switch activity.closeChoice() {
        case .keepWorking: return .terminateCancel
        case .cancelAndWait: activity.cancelAll()
        case .wait: break
        }
        guard activity.isRunning else { return .terminateNow }
        activity.whenIdle { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

struct MutationWindowGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> GuardView { GuardView() }
    func updateNSView(_ view: GuardView, context: Context) {}

    final class GuardView: NSView, NSWindowDelegate {
        private weak var originalDelegate: NSWindowDelegate?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window, window.delegate !== self {
                originalDelegate = window.delegate
                window.delegate = self
            }
        }
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            originalDelegate?.responds(to: selector) == true ? originalDelegate : super.forwardingTarget(for: selector)
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            let activity = MutationActivity.shared
            guard activity.isRunning else { return originalDelegate?.windowShouldClose?(sender) ?? true }
            switch activity.closeChoice() {
            case .keepWorking: return false
            case .cancelAndWait: activity.cancelAll()
            case .wait: break
            }
            guard activity.isRunning else { return originalDelegate?.windowShouldClose?(sender) ?? true }
            activity.whenIdle { [weak sender] in sender?.performClose(nil) }
            return false
        }
        static func dismantle(_ view: GuardView) {
            if let window = view.window, window.delegate === view { window.delegate = view.originalDelegate }
        }
    }

    static func dismantleNSView(_ view: GuardView, coordinator: ()) { GuardView.dismantle(view) }
}

struct MutationHistoryView: View {
    @ObservedObject var activity = MutationActivity.shared
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Operationsberichte dieser Sitzung").font(.title2.bold())
            List(activity.reports) { report in
                DisclosureGroup {
                    ForEach(Array(report.details.enumerated()), id: \.offset) { _, detail in
                        Text(detail).font(.caption).textSelection(.enabled)
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text(report.title).fontWeight(.semibold)
                        Text(report.summary).foregroundStyle(.secondary)
                    }
                }
            }
            HStack { Spacer(); Button("Schließen", action: onClose).keyboardShortcut(.cancelAction) }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 400)
    }
}
