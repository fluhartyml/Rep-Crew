//
//  RepCrewUITests.swift
//  Rep Crew — the shakedown robot
//
//  REM: his word 2026-11-06 19:2x: "after you edit the app each time can you have an xcode robot shake
//  each edit down to make sure the app works as newly designed and none of the assistive devices are
//  broken and you can freely navigate without human eyes or a track pad?"
//  And why: "because claude doesnt have human eyes or a trackpad without a skills lab screenshot."
//
//  So the robot never looks at pixels. It finds every control by its accessibility label (the same
//  names VoiceOver and Voice Control use), and runs Apple's accessibility audit on each screen
//  (labels, contrast, Dynamic Type, hit regions). Run after every edit, before commit.
//
//  -UITestRobot is a Debug-only switch in SignIn.swift that skips the Apple ID and iCloud checks,
//  since Sign in with Apple can't be driven in the Simulator. The other arguments set the same
//  UserDefaults the app writes after each setup step, so each test starts at the screen it checks.
//

import XCTest

final class RepCrewUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true   // report every audit issue on a screen, not just the first
    }

    // MARK: - Launch helpers

    /// Launches signed in as a generic test member, with setup finished up to the given step.
    /// REM: shipped-agnostic rule: a neutral test name, never his accounts or data.
    private func launch(agreed: Bool = true, applied: Bool = true, permissionsDone: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestRobot",
            "-agreementVersion", agreed ? "999" : "0",
            "-appleUserID", "ui-test-member",
            "-yourName", "Test Member",
            "-profileRestored", "YES",
            "-applicationDone", applied ? "YES" : "NO",
            "-permissionSetupDone", permissionsDone ? "YES" : "NO",
        ]
        app.launch()
        return app
    }

    /// Apple's accessibility audit for the current screen.
    /// REM: contrast is checked too; his 18 pt and contrast rules mean it should pass, not be excused.
    private func audit(_ app: XCUIApplication, _ screen: String) throws {
        try app.performAccessibilityAudit { issue in
            // Report every issue with the screen it was on, so the fix knows where to look.
            print("AUDIT [\(screen)] \(issue.auditType): \(issue.compactDescription) — \(issue.element?.debugDescription.prefix(200) ?? "no element")")
            return false
        }
    }

    // MARK: - Setup screens

    func testUserAgreementScreen() throws {
        let app = launch(agreed: false)
        XCTAssertTrue(app.buttons["I Agree"].waitForExistence(timeout: 10), "The I Agree button has no accessible name")
        try audit(app, "User Agreement")
    }

    func testBeforeYouStartScreen() throws {
        let app = launch(permissionsDone: false)
        XCTAssertTrue(app.staticTexts["Before you start"].waitForExistence(timeout: 10))
        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.exists, "Continue isn't reachable by name")
        try audit(app, "Before you start")
    }

    // MARK: - Every tab, by name only

    func testEveryTabReachableByNameAndPassesAudit() throws {
        let app = launch()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15), "Home never appeared")
        for tab in ["Home", "Leaderboard", "Feed", "Comms", "Profile"] {
            let button = tabBar.buttons[tab]
            XCTAssertTrue(button.exists, "Tab \(tab) can't be found by its name")
            button.tap()
            XCTAssertTrue(button.isSelected, "Tab \(tab) didn't open")
            try audit(app, tab)
        }
    }
}
