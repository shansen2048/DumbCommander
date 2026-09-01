//
//  DumbCommanderUITests.swift
//  DumbCommanderUITests
//
//  Created by Sascha Hansen on 25.07.24.
//

import XCTest

final class DumbCommanderUITests: XCTestCase {

    private func makeApp(directory: URL? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DUMBCOMMANDER_UI_TESTING"] = "1"
        if let directory {
            app.launchEnvironment["DUMBCOMMANDER_UI_TEST_DIRECTORY"] = directory.path
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
        let app = makeApp()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    // F1/F2 must switch the active panel (visible in the status bar)
    func testFunctionKeyPanelSwitching() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Links aktiv"].waitForExistence(timeout: 5))

        app.typeKey(XCUIKeyboardKey.F2, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Rechts aktiv"].waitForExistence(timeout: 5), "F2 sollte das rechte Panel aktivieren")

        app.typeKey(XCUIKeyboardKey.F1, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Links aktiv"].waitForExistence(timeout: 5), "F1 sollte das linke Panel aktivieren")
    }

    // The command prompt must accept commands with parameters (spaces) and run them on Enter
    func testShellCommandWithParameters() throws {
        let app = makeApp()
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
        let app = makeApp()
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

        let app = makeApp(directory: directory)
        app.launch()
        let row = app.staticTexts["rename-me.txt"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()

        app.typeKey(XCUIKeyboardKey.F6, modifierFlags: [.shift])

        XCTAssertTrue(
            app.descendants(matching: .any)["renameField"].waitForExistence(timeout: 5)
        )
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                    makeApp().launch()
            }
        }
    }
}
