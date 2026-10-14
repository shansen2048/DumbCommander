//
//  KeyEventHandlingView.swift
//  DumbCommander
//
//  Created by Sascha Hansen on 10.10.24.
//

import SwiftUI
import Foundation
import AppKit // Import AppKit for NSColor

struct KeyEventHandlingView: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        coordinator.onKeyDown = onKeyDown
        let keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak view, weak coordinator] event in
            guard let window = view?.window, window.isKeyWindow,
                  event.window == window else { return event }
            if coordinator?.onKeyDown?(event) == true {
                return nil
            } else {
                return event
            }
        }
        context.coordinator.keyDownMonitor = keyDownMonitor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // SwiftUI reuses this bridge when the selected panel tab changes.
        context.coordinator.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let keyDownMonitor = coordinator.keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        coordinator.keyDownMonitor = nil
        coordinator.onKeyDown = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var keyDownMonitor: Any?
        var onKeyDown: ((NSEvent) -> Bool)?
    }
}
