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
    var onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            self.onKeyDown(event)
            return event
        }
        context.coordinator.keyDownMonitor = keyDownMonitor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let keyDownMonitor = coordinator.keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var keyDownMonitor: Any?
    }
}
