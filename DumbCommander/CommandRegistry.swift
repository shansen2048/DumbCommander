import AppKit
import SwiftUI

enum CommanderCommand: String, CaseIterable, Identifiable, Sendable {
    case activateLeftPanel
    case activateRightPanel
    case showLeftFavorites
    case showRightFavorites
    case view
    case edit
    case copy
    case move
    case rename
    case createDirectory
    case trash
    case quit
    case goToDirectory
    case goBack
    case goForward
    case goHome
    case goRoot
    case focusFilter
    case reload

    var id: String { rawValue }
}

struct CommanderCommandDescriptor: Identifiable {
    let command: CommanderCommand
    let title: String
    let compactTitle: String
    let systemImage: String
    let keyCode: UInt16?
    let modifiers: NSEvent.ModifierFlags
    let functionKeyNumber: Int?
    let appearsInFunctionBar: Bool

    var id: CommanderCommand { command }
}

struct CommandRegistry {
    static let shared = CommandRegistry()

    let descriptors: [CommanderCommandDescriptor] = [
        .init(command: .activateLeftPanel, title: "Linkes Panel aktivieren", compactTitle: "Links", systemImage: "rectangle.leftthird.inset.filled", keyCode: 122, modifiers: [], functionKeyNumber: 1, appearsInFunctionBar: true),
        .init(command: .activateRightPanel, title: "Rechtes Panel aktivieren", compactTitle: "Rechts", systemImage: "rectangle.rightthird.inset.filled", keyCode: 120, modifiers: [], functionKeyNumber: 2, appearsInFunctionBar: true),
        .init(command: .showLeftFavorites, title: "Linke Favoriten", compactTitle: "Favoriten links", systemImage: "star", keyCode: 122, modifiers: [.option], functionKeyNumber: 1, appearsInFunctionBar: false),
        .init(command: .showRightFavorites, title: "Rechte Favoriten", compactTitle: "Favoriten rechts", systemImage: "star", keyCode: 120, modifiers: [.option], functionKeyNumber: 2, appearsInFunctionBar: false),
        .init(command: .view, title: "Anzeigen", compactTitle: "Anzeigen", systemImage: "eye", keyCode: 99, modifiers: [], functionKeyNumber: 3, appearsInFunctionBar: true),
        .init(command: .edit, title: "Bearbeiten", compactTitle: "Bearbeiten", systemImage: "pencil", keyCode: 118, modifiers: [], functionKeyNumber: 4, appearsInFunctionBar: true),
        .init(command: .copy, title: "Kopieren", compactTitle: "Kopieren", systemImage: "doc.on.doc", keyCode: 96, modifiers: [], functionKeyNumber: 5, appearsInFunctionBar: true),
        .init(command: .move, title: "Verschieben", compactTitle: "Verschieben", systemImage: "arrowshape.turn.up.right", keyCode: 97, modifiers: [], functionKeyNumber: 6, appearsInFunctionBar: true),
        .init(command: .rename, title: "Umbenennen", compactTitle: "Umbenennen", systemImage: "character.cursor.ibeam", keyCode: 97, modifiers: [.shift], functionKeyNumber: 6, appearsInFunctionBar: false),
        .init(command: .createDirectory, title: "Neuer Ordner", compactTitle: "Ordner", systemImage: "folder.badge.plus", keyCode: 98, modifiers: [], functionKeyNumber: 7, appearsInFunctionBar: true),
        .init(command: .trash, title: "In den Papierkorb", compactTitle: "Löschen", systemImage: "trash", keyCode: 100, modifiers: [], functionKeyNumber: 8, appearsInFunctionBar: true),
        .init(command: .quit, title: "Beenden", compactTitle: "Beenden", systemImage: "xmark.circle", keyCode: 109, modifiers: [], functionKeyNumber: 10, appearsInFunctionBar: true),
        .init(command: .goToDirectory, title: "Pfad öffnen …", compactTitle: "Pfad", systemImage: "location", keyCode: 5, modifiers: [.command], functionKeyNumber: nil, appearsInFunctionBar: false),
        .init(command: .goBack, title: "Zurück", compactTitle: "Zurück", systemImage: "chevron.left", keyCode: 33, modifiers: [.command], functionKeyNumber: nil, appearsInFunctionBar: false),
        .init(command: .goForward, title: "Vorwärts", compactTitle: "Vor", systemImage: "chevron.right", keyCode: 30, modifiers: [.command], functionKeyNumber: nil, appearsInFunctionBar: false),
        .init(command: .goHome, title: "Benutzerordner", compactTitle: "Home", systemImage: "house", keyCode: 4, modifiers: [.command, .shift], functionKeyNumber: nil, appearsInFunctionBar: false),
        .init(command: .goRoot, title: "Wurzelverzeichnis", compactTitle: "Wurzel", systemImage: "internaldrive", keyCode: 4, modifiers: [.command, .option], functionKeyNumber: nil, appearsInFunctionBar: false),
        .init(command: .focusFilter, title: "Schnellfilter", compactTitle: "Filter", systemImage: "line.3.horizontal.decrease.circle", keyCode: 3, modifiers: [.command], functionKeyNumber: nil, appearsInFunctionBar: false),
        .init(command: .reload, title: "Neu laden", compactTitle: "Neu laden", systemImage: "arrow.clockwise", keyCode: 15, modifiers: [.command], functionKeyNumber: nil, appearsInFunctionBar: false)
    ]

    var functionBarDescriptors: [CommanderCommandDescriptor] {
        descriptors.filter(\.appearsInFunctionBar)
    }

    func descriptor(for command: CommanderCommand) -> CommanderCommandDescriptor {
        descriptors.first { $0.command == command }!
    }

    func command(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        textInputActive: Bool
    ) -> CommanderCommand? {
        if textInputActive { return nil }
        let normalized = modifiers
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad])
        return descriptors.first {
            $0.keyCode == keyCode && $0.modifiers == normalized
        }?.command
    }

    func functionKeyEquivalent(_ number: Int) -> KeyEquivalent {
        KeyEquivalent(Character(UnicodeScalar(0xF704 + (number - 1))!))
    }

    func keyEquivalent(for descriptor: CommanderCommandDescriptor) -> KeyEquivalent? {
        if let functionKeyNumber = descriptor.functionKeyNumber {
            return functionKeyEquivalent(functionKeyNumber)
        }
        switch descriptor.command {
        case .goToDirectory: return "g"
        case .goBack: return "["
        case .goForward: return "]"
        case .goHome, .goRoot: return "h"
        case .focusFilter: return "f"
        case .reload: return "r"
        default: return nil
        }
    }

    func swiftUIModifiers(for descriptor: CommanderCommandDescriptor) -> EventModifiers {
        var result: EventModifiers = []
        if descriptor.modifiers.contains(.command) { result.insert(.command) }
        if descriptor.modifiers.contains(.option) { result.insert(.option) }
        if descriptor.modifiers.contains(.control) { result.insert(.control) }
        if descriptor.modifiers.contains(.shift) { result.insert(.shift) }
        return result
    }
}
