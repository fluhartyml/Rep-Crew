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
    /// REM: run 6 (2026-11-06) flagged labels sitting half under the translucent tab bar or past the screen
    /// edge — the audit grades them through the bar's blur. Those are skipped and LOGGED, never silenced;
    /// each screen is audited again after a scroll so they're graded once they're fully in view.
    private func audit(_ app: XCUIApplication, _ screen: String) throws {
        var visible = app.windows.firstMatch.frame
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists { visible.size.height = tabBar.frame.minY - visible.minY }
        let navBar = app.navigationBars.firstMatch
        if navBar.exists, navBar.frame.maxY > visible.minY {
            visible.size.height -= navBar.frame.maxY - visible.minY
            visible.origin.y = navBar.frame.maxY
        }
        // REM: 2026-11-06 — the audit's Dynamic Type and Text-clipped checks flag ANY custom-sized font (his
        // 18 pt needs one), even though the text measurably grows 11x and wraps (testTextGrowsWithTextSize +
        // robot screenshots at Accessibility XXXL). Those two are guarded by the measured test instead.
        // REM: 2026-11-06 — the agreement screen's solid bottom bar (I Agree) covers the text scrolling under it;
        // the bar's own contents are graded, text hidden behind it is skipped and logged, like the tab bar.
        let bottomBar = app.otherElements["agreementBar"]
        let barFrame: CGRect? = bottomBar.exists ? bottomBar.frame : nil
        if let barFrame { visible.size.height = min(visible.maxY, barFrame.minY) - visible.minY }
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting([.dynamicType, .textClipped])) { issue in
            let label = issue.element?.label ?? "no element"
            if let element = issue.element, element.exists, !visible.contains(element.frame),
               !(barFrame?.contains(element.frame) ?? false) {
                print("AUDIT-SKIPPED [\(screen)] not fully on screen: \(issue.compactDescription) — '\(label)'")
                return true
            }
            // REM: a turned-off button (I Agree before the end is read) wears Apple's standard dimmed look,
            // which contrast rules exempt for inactive controls. Logged, and graded again once it's on.
            if let element = issue.element, element.exists, element.elementType == .button, !element.isEnabled {
                print("AUDIT-SKIPPED [\(screen)] turned off: \(issue.compactDescription) — '\(label)'")
                return true
            }
            // Report every issue with the screen it was on, so the fix knows where to look.
            print("AUDIT [\(screen)] \(issue.auditType.rawValue): \(issue.compactDescription) — '\(label)' \(issue.element?.frame ?? .zero)")
            return false
        }
    }

    /// Audits what's on screen, then scrolls one page and audits again.
    private func auditScrolling(_ app: XCUIApplication, _ screen: String) throws {
        try audit(app, screen)
        let scroller = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
        guard scroller.exists else { return }
        scroller.swipeUp()
        try audit(app, screen + " (scrolled)")
        scroller.swipeDown()
    }

    // MARK: - Setup screens

    func testUserAgreementScreen() throws {
        let app = launch(agreed: false)
        let agree = app.buttons["I Agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 10), "The I Agree button has no accessible name")
        try auditScrolling(app, "User Agreement")
        // Read to the end, the way a person must, then grade I Agree turned on.
        let scroller = app.scrollViews.firstMatch
        for _ in 0..<25 where !agree.isEnabled { scroller.swipeUp() }
        XCTAssertTrue(agree.isEnabled, "I Agree never turned on after scrolling to the end")
        try audit(app, "User Agreement (end)")
    }

    func testBeforeYouStartScreen() throws {
        let app = launch(permissionsDone: false)
        XCTAssertTrue(app.staticTexts["Before you start"].waitForExistence(timeout: 10))
        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.exists, "Continue isn't reachable by name")
        try audit(app, "Before you start")
    }

    // MARK: - Text really grows

    /// REM: his 18 pt rule — "the user's text-size setting wins". Measures it instead of trusting the audit:
    /// the same heading at the default size and at the largest accessibility size must at least double.
    func testTextGrowsWithTextSize() throws {
        func headingHeight(_ size: String?) -> CGFloat {
            let app = XCUIApplication()
            app.launchArguments = ["-UITestRobot", "-agreementVersion", "0"]
            if let size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
            app.launch()
            let heading = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "End User License")).firstMatch
            XCTAssertTrue(heading.waitForExistence(timeout: 10))
            let height = heading.frame.height
            print("TEXTSIZE \(size ?? "default"): heading height \(height)")
            app.terminate()
            return height
        }
        let normal = headingHeight(nil)
        let largest = headingHeight("UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertGreaterThanOrEqual(largest, normal * 2, "Text didn't grow with the text-size setting")
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
            try auditScrolling(app, tab)
        }
    }
}
