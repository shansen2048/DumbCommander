//
//  DumbCommanderUITests.swift
//  DumbCommanderUITests
//
//  Created by Sascha Hansen on 25.07.24.
//

import XCTest

final class DumbCommanderUITests: XCTestCase {

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
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    // F1/F2 must switch the active panel (visible in the status bar)
    func testFunctionKeyPanelSwitching() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Links aktiv"].waitForExistence(timeout: 5))

        app.typeKey(XCUIKeyboardKey.F2, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Rechts aktiv"].waitForExistence(timeout: 5), "F2 sollte das rechte Panel aktivieren")

        app.typeKey(XCUIKeyboardKey.F1, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Links aktiv"].waitForExistence(timeout: 5), "F1 sollte das linke Panel aktivieren")
    }

    // The command prompt must accept commands with parameters (spaces) and run them on Enter
    func testShellCommandWithParameters() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Kommandozeile"].click()

        let commandField = app.textFields.firstMatch
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

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
