//
//  DumbCommanderUITests.swift
//  DumbCommanderUITests
//
//  Created by Sascha Hansen on 25.07.24.
//

import XCTest

final class DumbCommanderUITests: XCTestCase {

    private func makeApp(directory: URL? = nil) throws -> XCUIApplication {
        let root = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("DumbCommander-UI-\(UUID().uuidString)", isDirectory: true)
        if directory == nil {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        }
        let suite = "DumbCommander-Tests-\(UUID().uuidString)"
        let app = XCUIApplication()
        app.launchEnvironment["DUMBCOMMANDER_UI_TESTING"] = "1"
        app.launchEnvironment["DUMBCOMMANDER_CAPTURE_EXTERNAL_OPEN"] = "1"
        app.launchEnvironment["DUMBCOMMANDER_UI_TEST_DIRECTORY"] = root.path
        app.launchEnvironment["DUMBCOMMANDER_TEST_DEFAULTS"] = suite
        addTeardownBlock {
            app.terminate()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            if directory == nil { try FileManager.default.removeItem(at: root) }
        }
        return app
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = try makeApp()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    // F1/F2 must switch the active panel (visible in the status bar)
    func testFunctionKeyPanelSwitching() throws {
        let app = try makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Links aktiv"].waitForExistence(timeout: 5))

        app.typeKey(XCUIKeyboardKey.F2, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Rechts aktiv"].waitForExistence(timeout: 5), "F2 sollte das rechte Panel aktivieren")

        app.typeKey(XCUIKeyboardKey.F1, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Links aktiv"].waitForExistence(timeout: 5), "F1 sollte das linke Panel aktivieren")
    }

    // The command prompt must accept commands with parameters (spaces) and run them on Enter
    func testShellCommandWithParameters() throws {
        let app = try makeApp()
        app.launch()

        app.buttons["experimentalCommandPromptButton"].click()

        let commandField = app.descendants(matching: .any)["commandField"]
        XCTAssertTrue(commandField.waitForExistence(timeout: 5))
        commandField.click()
        commandField.typeText("echo hello world")

        let typedValue = commandField.value as? String
        XCTAssertEqual(typedValue, "echo hello world", "Leerzeichen müssen im Kommandofeld ankommen")

        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        let output = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "hello world", "hello world")
        ).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 5), "Die Ausgabe des Kommandos muss erscheinen")
    }

    func testTextInputDoesNotTriggerCommanderShortcuts() throws {
        let app = try makeApp()
        app.launch()

        let filter = app.descendants(matching: .any)["leftFilterField"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.click()
        filter.typeText("abc def")
        XCTAssertEqual(filter.value as? String, "abc def")

        app.typeKey(XCUIKeyboardKey.F7, modifierFlags: [])
        XCTAssertFalse(app.descendants(matching: .any)["newFolderNameField"].exists)
        app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Links aktiv"].exists)
    }

    func testShiftF6OpensRenameForSelectedItem() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DumbCommander-UI-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let file = directory.appendingPathComponent("rename-me.txt")
        try Data("test".utf8).write(to: file)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let app = try makeApp(directory: directory)
        app.launch()
        let row = app.staticTexts["rename-me.txt"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()

        app.typeKey(XCUIKeyboardKey.F6, modifierFlags: [.shift])

        XCTAssertTrue(
            app.descendants(matching: .any)["renameField"].waitForExistence(timeout: 5)
        )
    }

    func testEnterFollowsDirectorySymbolicLink() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DumbCommander-UI-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let target = directory.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("inside".utf8).write(to: target.appendingPathComponent("inside.txt"))
        let link = directory.appendingPathComponent("linked-folder")
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: target.lastPathComponent
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let app = try makeApp(directory: directory)
        app.launch()
        let row = app.staticTexts["linked-folder"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()

        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        XCTAssertTrue(
            app.staticTexts["inside.txt"].firstMatch.waitForExistence(timeout: 5),
            "Enter sollte in das Ziel eines Verzeichnis-Links wechseln."
        )
    }

    func testEnterOpensSymbolicLinkFileTargetWithAssociatedApplication() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DumbCommander-UI-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let targetDirectory = directory.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(
            at: targetDirectory,
            withIntermediateDirectories: false
        )
        try Data("linked content".utf8).write(
            to: targetDirectory.appendingPathComponent("actual.txt")
        )
        let link = directory.appendingPathComponent("linked-file.txt")
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: "target/actual.txt"
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let app = try makeApp(directory: directory)
        app.launch()
        let row = app.staticTexts["linked-file.txt"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()

        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        XCTAssertTrue(app.buttons["OK"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.sheets.staticTexts.containing(
                NSPredicate(format: "value CONTAINS %@", "actual.txt")
            ).firstMatch.waitForExistence(timeout: 5),
            "Enter sollte das Ziel eines Datei-Links mit der Standard-App öffnen."
        )
    }

    func testDoubleClickOpensDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DumbCommander-UI-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let child = directory.appendingPathComponent("double-click-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        try Data("inside".utf8).write(to: child.appendingPathComponent("inside.txt"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let app = try makeApp(directory: directory)
        app.launch()
        let row = app.staticTexts["double-click-folder"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        row.doubleClick()

        XCTAssertTrue(
            app.staticTexts["inside.txt"].firstMatch.waitForExistence(timeout: 5),
            "Ein Doppelklick sollte das Verzeichnis öffnen."
        )
    }

    func testDoubleClickOpensFileWithAssociatedApplication() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DumbCommander-UI-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let file = directory.appendingPathComponent("double-click-file.txt")
        try Data("viewer content".utf8).write(to: file)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let app = try makeApp(directory: directory)
        app.launch()
        let row = app.staticTexts["double-click-file.txt"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        row.doubleClick()

        XCTAssertTrue(app.buttons["OK"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.sheets.staticTexts.containing(
                NSPredicate(format: "value CONTAINS %@", "double-click-file.txt")
            ).firstMatch.waitForExistence(timeout: 5),
            "Ein Doppelklick sollte die Datei mit der Standard-App öffnen."
        )
    }

    func testEnterOpensMultipleMarkedFilesWithAssociatedApplications() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DumbCommander-UI-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data("alpha".utf8).write(to: directory.appendingPathComponent("alpha.txt"))
        try Data("beta".utf8).write(to: directory.appendingPathComponent("beta.txt"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let app = try makeApp(directory: directory)
        app.launch()
        let alpha = app.staticTexts["alpha.txt"].firstMatch
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        alpha.click()
        app.typeKey(XCUIKeyboardKey.space, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.space, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.upArrow, modifierFlags: [])

        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        XCTAssertTrue(app.buttons["OK"].waitForExistence(timeout: 5))
        let message = app.sheets.staticTexts.containing(
            NSPredicate(format: "value CONTAINS %@ AND value CONTAINS %@", "alpha.txt", "beta.txt")
        ).firstMatch
        XCTAssertTrue(
            message.waitForExistence(timeout: 5),
            "Enter sollte alle markierten Dateien an ihre Standard-Apps übergeben."
        )
    }

    func testF3KeepsUsingInternalViewer() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DumbCommander-UI-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data("viewer".utf8).write(to: directory.appendingPathComponent("viewer-file.txt"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let app = try makeApp(directory: directory)
        app.launch()
        let row = app.staticTexts["viewer-file.txt"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()

        app.typeKey(XCUIKeyboardKey.F3, modifierFlags: [])

        XCTAssertTrue(
            app.buttons["Schließen"].waitForExistence(timeout: 5),
            "F3 muss weiterhin den internen Viewer öffnen."
        )
    }

    func testPanelTabAndSearchShortcuts() throws {
        let app = try makeApp()
        app.launch()

        app.typeKey("t", modifierFlags: [.command])
        XCTAssertTrue(
            app.buttons["Tab schließen"].firstMatch.waitForExistence(timeout: 5),
            "Cmd-T sollte im aktiven Panel einen zweiten Tab anlegen."
        )

        app.typeKey("f", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            app.staticTexts["Dateisuche"].waitForExistence(timeout: 5),
            "Cmd-Shift-F sollte die rekursive Dateisuche öffnen."
        )
    }

    func testNewTabAtSamePathLoadsFilesAndUsesCurrentKeyboardTarget() throws {
        let app = try makeApp()
        let root = URL(fileURLWithPath: try XCTUnwrap(app.launchEnvironment["DUMBCOMMANDER_UI_TEST_DIRECTORY"]))
        try Data("alpha".utf8).write(to: root.appendingPathComponent("alpha.txt"))
        try Data("beta".utf8).write(to: root.appendingPathComponent("beta.txt"))
        app.launch()
        let left = app.descendants(matching: .any)["leftPanel"]
        XCTAssertTrue(left.staticTexts["alpha.txt"].firstMatch.waitForExistence(timeout: 5))
        app.typeKey("t", modifierFlags: [.command])
        XCTAssertTrue(app.buttons["leftTab1"].waitForExistence(timeout: 5))
        XCTAssertTrue(left.staticTexts["alpha.txt"].firstMatch.waitForExistence(timeout: 5))
        left.staticTexts["alpha.txt"].firstMatch.click()
        app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.F6, modifierFlags: [.shift])
        let rename = app.descendants(matching: .any)["renameField"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        XCTAssertEqual(rename.value as? String, "beta.txt")
    }

    func testShiftArrowRangeSelectionStaysInActivePanel() throws {
        let app = try makeApp()
        let root = URL(fileURLWithPath: try XCTUnwrap(app.launchEnvironment["DUMBCOMMANDER_UI_TEST_DIRECTORY"]))
        for name in ["alpha.txt", "beta.txt", "gamma.txt"] {
            try Data(name.utf8).write(to: root.appendingPathComponent(name))
        }
        app.launch()
        let left = app.descendants(matching: .any)["leftPanel"]
        XCTAssertTrue(left.staticTexts["alpha.txt"].firstMatch.waitForExistence(timeout: 5))
        left.staticTexts["alpha.txt"].firstMatch.click()
        app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [.shift])
        XCTAssertTrue(left.staticTexts["2 markiert"].firstMatch.waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Rechts aktiv"].exists)
        XCTAssertTrue(left.staticTexts["2 markiert"].firstMatch.exists)
        let right = app.descendants(matching: .any)["rightPanel"]
        XCTAssertFalse(right.staticTexts["2 markiert"].firstMatch.exists)
    }

    func testViewerFindBarAcceptsTextWithoutPanelShortcuts() throws {
        let app = try makeApp()
        let root = URL(fileURLWithPath: try XCTUnwrap(app.launchEnvironment["DUMBCOMMANDER_UI_TEST_DIRECTORY"]))
        try Data("first needle\nsecond needle".utf8).write(to: root.appendingPathComponent("find.txt"))
        app.launch()
        let row = app.descendants(matching: .any)["leftPanel"].staticTexts["find.txt"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        app.typeKey(XCUIKeyboardKey.F3, modifierFlags: [])
        XCTAssertTrue(app.buttons["viewerFindButton"].waitForExistence(timeout: 5))
        app.buttons["viewerFindButton"].click()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeText("needle")
        XCTAssertEqual(search.value as? String, "needle")
        app.typeKey(XCUIKeyboardKey.F7, modifierFlags: [])
        XCTAssertFalse(app.descendants(matching: .any)["newFolderNameField"].exists)
    }

    func testTabsAndFiltersSurviveRelaunchInIsolatedSession() throws {
        let app = try makeApp()
        let root = URL(fileURLWithPath: try XCTUnwrap(app.launchEnvironment["DUMBCOMMANDER_UI_TEST_DIRECTORY"]))
        try Data("test".utf8).write(to: root.appendingPathComponent("keep.txt"))
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["leftPanel"].staticTexts["keep.txt"].firstMatch.waitForExistence(timeout: 5))
        app.typeKey("t", modifierFlags: [.command])
        XCTAssertTrue(app.buttons["leftTab1"].waitForExistence(timeout: 5))
        let filter = app.descendants(matching: .any)["leftFilterField"]
        filter.click()
        filter.typeText("keep")
        XCTAssertEqual(filter.value as? String, "keep")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["leftTab1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["leftTab1"].value as? String, "Aktiv")
        XCTAssertEqual(app.descendants(matching: .any)["leftFilterField"].value as? String, "keep")
    }

    func testQuitWaitsForCancelledCopyAndKeepsSource() throws {
        let app = try makeApp()
        let root = URL(fileURLWithPath: app.launchEnvironment["DUMBCOMMANDER_UI_TEST_DIRECTORY"]!)
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let source = root.appendingPathComponent("large.bin")
        try Data(repeating: 42, count: 32 * 1_024 * 1_024).write(to: source)
        app.launchEnvironment["DUMBCOMMANDER_TEST_SLOW_COPY"] = "1"
        app.launch()
        let rightPath = app.textFields["rightPathField"]
        XCTAssertTrue(rightPath.waitForExistence(timeout: 5))
        rightPath.click()
        rightPath.typeKey("a", modifierFlags: .command)
        rightPath.typeText(target.path)
        rightPath.typeKey(.return, modifierFlags: [])
        let left = app.descendants(matching: .any)["leftPanel"]
        let file = left.staticTexts["large.bin"].firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        file.click()
        app.typeKey(XCUIKeyboardKey(rawValue: "\u{F708}"), modifierFlags: []) // F5
        let cancel = app.buttons["Abbrechen"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey(rawValue: "\u{F70D}"), modifierFlags: []) // F10
        let keepWorking = app.buttons["Weiterarbeiten"].firstMatch
        XCTAssertTrue(keepWorking.waitForExistence(timeout: 5))
        keepWorking.click()
        XCTAssertTrue(app.windows.firstMatch.exists)
        app.windows.firstMatch.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(keepWorking.waitForExistence(timeout: 5))
        keepWorking.click()
        app.typeKey("q", modifierFlags: .command)
        app.buttons["Abbrechen und warten"].firstMatch.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        XCTAssertEqual(try Data(contentsOf: source).count, 32 * 1_024 * 1_024)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            let app = try makeApp()
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                app.launch()
            }
        }
    }
}
