import XCTest

/// Runs against mocked services (`-UITestMode` / `-DemoMode`), so no Google account,
/// camera or Health data is needed.
final class PuffyMeterUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testOnboardingToFirstScan() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode"]
        app.launch()

        app.buttons["Skip"].tap()
        app.buttons["Continue with Google"].tap()
        XCTAssertTrue(app.buttons["Choose Drive folder"].waitForExistence(timeout: 5))
        app.buttons["Choose Drive folder"].tap()
        XCTAssertTrue(app.buttons["Use this folder"].waitForExistence(timeout: 5))
        app.buttons["Use this folder"].tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()
        app.buttons["Allow camera"].tap()
        app.buttons["Start my first scan"].tap()
        // Simulated camera passes all checks and auto-captures.
        let baseline = app.descendants(matching: .any)["Baseline set"]
        if !baseline.waitForExistence(timeout: 20) {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.lifetime = .keepAlways
            add(shot)
            XCTFail("Baseline result didn't appear")
            return
        }
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Summary"].waitForExistence(timeout: 5))
    }

    func testUseWithoutAccount() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode"]
        app.launch()
        app.buttons["Skip"].tap()
        app.buttons["Use without an account"].tap()
        XCTAssertTrue(app.buttons["Allow camera"].waitForExistence(timeout: 5))
        app.buttons["Allow camera"].tap()
        app.buttons["Start my first scan"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Baseline set"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Saved on this iPhone"].exists)
    }

    func testDemoSummaryShowsMockupData() {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoMode"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Summary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Face zones"].exists)
        XCTAssertTrue(app.staticTexts["7-day scan streak"].exists)
    }

    func testQuickLogClosesHabitsRing() {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoMode"]
        app.launch()
        let alcohol = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Alcohol'")).firstMatch
        alcohol.swipeUpUntilVisible()
        alcohol.tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Back to Summary"].waitForExistence(timeout: 5), "All rings closed celebration")
    }
}

private extension XCUIElement {
    func swipeUpUntilVisible(maxSwipes: Int = 6) {
        var swipes = 0
        while !isHittable && swipes < maxSwipes {
            XCUIApplication().swipeUp()
            swipes += 1
        }
    }
}
