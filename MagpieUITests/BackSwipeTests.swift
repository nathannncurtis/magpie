import XCTest

/// Every screen with somewhere to go back to leaves on a swipe in from the left edge:
/// the archive to the stack, the stack to its page, the bookmarks out of a folder and
/// off, a pushed Settings page to Settings, and Settings itself away.
@MainActor
final class BackSwipeTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testArchiveThenTabsSwipeBack() {
        let app = launch(surface: "archive")
        let shots = ShotWriter(test: self, prefix: "back")

        XCTAssertTrue(element(app, "archive.screen").waitForExistence(timeout: 20), "the archive")
        swipeBack(app)
        XCTAssertTrue(element(app, "tabs.screen").waitForExistence(timeout: 10), "the stack, off the archive")
        shots.snap(app, "archive-to-tabs")

        swipeBack(app)
        XCTAssertTrue(element(app, "reading.screen").waitForExistence(timeout: 10), "the page, off the stack")
        shots.snap(app, "tabs-to-reading")
    }

    func testBookmarksSwipeBack() {
        let app = launch(surface: "bookmarks")

        XCTAssertTrue(element(app, "bookmarks.screen").waitForExistence(timeout: 20), "the bookmarks")
        swipeBack(app)
        XCTAssertTrue(
            element(app, "bookmarks.screen").waitForNonExistence(timeout: 10), "off the bookmarks")
    }

    func testSettingsSwipeBack() {
        let app = launch(surface: "settings")

        let done = element(app, "settings.done")
        XCTAssertTrue(done.waitForExistence(timeout: 20), "Settings")
        element(app, "settings.about").tap()
        XCTAssertTrue(element(app, "settings.about.source").waitForExistence(timeout: 10), "About")

        swipeBack(app)
        XCTAssertTrue(
            element(app, "settings.about.source").waitForNonExistence(timeout: 10), "off About")
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Settings, after About")

        swipeBack(app)
        XCTAssertTrue(done.waitForNonExistence(timeout: 10), "off Settings")
    }

    func launch(surface: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding"]
        if let surface { app.launchArguments.append("-uiTestingSurface=\(surface)") }
        app.logsBesideShots()
        app.launch()
        return app
    }

    func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// A thumb's swipe: in from the very edge, most of the way across, mid-screen.
    /// The same from the right edge.
    func swipeForward(_ app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 0.6)
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.5))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0)
    }

    func swipeBack(_ app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 0.6)
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0)
    }
}

extension BackSwipeTests {

    /// On a page, the edge swipes walk back and forward through the page's own history.
    func testPageSwipeBackThroughHistory() {
        let app = launch(surface: nil)
        let field = element(app, "search.field")
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the launch field")
        field.tapWhenSettled()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeTextLogged("magpie test\n")
        XCTAssertTrue(
            app.webViews.staticTexts["/search"].firstMatch.waitForExistence(timeout: 20), "the first page")

        // A second page in the same tab, from the sheet over the page.
        app.buttons["bar.url"].tap()
        field.tapWhenSettled()
        let held = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: held.count + 4))
        field.typeTextLogged("http://127.0.0.1:53117/page\n")
        XCTAssertTrue(
            app.webViews.staticTexts["/page"].firstMatch.waitForExistence(timeout: 20), "the second page")

        swipeBack(app)
        XCTAssertTrue(
            app.webViews.staticTexts["/search"].firstMatch.waitForExistence(timeout: 10),
            "the first page again, off the edge swipe")

        swipeForward(app)
        XCTAssertTrue(
            app.webViews.staticTexts["/page"].firstMatch.waitForExistence(timeout: 10),
            "the second page again, off the trailing edge")
        ShotWriter(test: self, prefix: "back").snap(app, "page-history")
    }
}
