import XCTest

/// The bar is a handle: a sideways swipe on it steps through the tabs, and a swipe up
/// opens the tab stack.
@MainActor
final class BarSwipeFlowTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testBarSwipesStepTabsAndOpenStack() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding"]
        app.logsBesideShots()
        app.launch()
        let shots = ShotWriter(test: self, prefix: "barswipe")

        // The first tab, on /search.
        let field = app.descendants(matching: .any)["search.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the launch field")
        field.tapWhenSettled()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeTextLogged("magpie test\n")
        XCTAssertTrue(text(app, "/search").waitForExistence(timeout: 20), "the first tab")

        // The second, on /page, opened from the stack's +.
        app.buttons["bar.tabs"].tap()
        let plus = app.buttons["tabs.plus"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10), "the stack")
        plus.tap()
        field.tapWhenSettled()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeTextLogged("http://127.0.0.1:53117/page\n")
        XCTAssertTrue(text(app, "/page").waitForExistence(timeout: 20), "the second tab")

        // Right drags back to the first; left again to the second.
        swipeBar(app, from: 0.25, to: 0.8)
        XCTAssertTrue(text(app, "/search").waitForExistence(timeout: 10), "the first tab, off a swipe right")
        shots.snap(app, "stepped-back")

        swipeBar(app, from: 0.8, to: 0.25)
        XCTAssertTrue(text(app, "/page").waitForExistence(timeout: 10), "the second tab, off a swipe left")

        // At the end of the stack, a further swipe leaves the tab where it is.
        swipeBar(app, from: 0.8, to: 0.25)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(text(app, "/page").exists, "still the second tab at the end")

        // A tap on a bar button still taps: the swipes did not eat it.
        XCTAssertTrue(app.buttons["bar.tabs"].isHittable, "the tabs button")

        // Up opens the stack.
        let bar = app.buttons["bar.url"]
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(
            forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -220)),
            withVelocity: .default, thenHoldForDuration: 0)
        XCTAssertTrue(
            app.descendants(matching: .any)["tabs.screen"].firstMatch.waitForExistence(timeout: 10),
            "the stack, off a swipe up")
        shots.snap(app, "swiped-up")
    }

    private func text(_ app: XCUIApplication, _ route: String) -> XCUIElement {
        app.webViews.staticTexts[route].firstMatch
    }

    /// A drag along the bar's own height, between two fractions of the screen's width.
    private func swipeBar(_ app: XCUIApplication, from: CGFloat, to: CGFloat) {
        Thread.sleep(forTimeInterval: 0.6)
        let window = app.windows.firstMatch
        let y = app.buttons["bar.url"].frame.midY / window.frame.height
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: from, dy: y))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: to, dy: y))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0)
    }
}
