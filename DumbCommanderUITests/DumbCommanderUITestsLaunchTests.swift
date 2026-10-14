//
//  DumbCommanderUITestsLaunchTests.swift
//  DumbCommanderUITests
//
//  Created by Sascha Hansen on 25.07.24.
//

import XCTest

final class DumbCommanderUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DumbCommander-Launch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let suite = "DumbCommander-Tests-\(UUID().uuidString)"
        let app = XCUIApplication()
        app.launchEnvironment["DUMBCOMMANDER_UI_TESTING"] = "1"
        app.launchEnvironment["DUMBCOMMANDER_UI_TEST_DIRECTORY"] = root.path
        app.launchEnvironment["DUMBCOMMANDER_TEST_DEFAULTS"] = suite
        defer {
            app.terminate()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
