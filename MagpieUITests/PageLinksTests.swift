import XCTest

/// Pages behaving as in a browser: a `target=_blank` link opens a tab, and a page's
/// alert and confirm are answered on screen.
@MainActor
final class PageLinksTests: XCTestCase {

    private var app: XCUIApplication!
    private var shots: ShotWriter!

    override func setUp() {
        continueAfterFailure = false
    }

    func testBlankLinkOpensATabAndAlertShows() {
        launchOnLinksPage()

        let link = app.webViews.links["open blank"].firstMatch
        land("link") { link.waitForExistence(timeout: 20) }

        // An alert on a tap shows over the page and is answered.
        app.webViews.buttons["say hello"].firstMatch.tap()
        let alert = app.alerts.firstMatch
        land("alert") { alert.waitForExistence(timeout: 10) }
        XCTAssertTrue(alert.staticTexts["hello from the page"].exists, "the alert says the page's words")
        shots.snap(app, "alert")
        app.buttons["page.dialog.ok"].firstMatch.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 10), "the alert closed")

        // The blank link opens a second tab, which is current. The page's load-time
        // window.open, with no tap behind it, was dropped: two tabs, not three.
        link.tap()
        land("second-tab") { openTabCount() == 2 }
        shots.snap(app, "new-tab")
    }

    func testConfirmReachesThePage() {
        launchOnLinksPage()
        let ask = app.webViews.buttons["ask"].firstMatch
        land("ask") { ask.waitForExistence(timeout: 20) }
        ask.tap()
        let alert = app.alerts.firstMatch
        land("confirm") { alert.waitForExistence(timeout: 10) }
        shots.snap(app, "confirm")
        app.buttons["page.dialog.ok"].firstMatch.tap()
        land("answered") { alert.waitForNonExistence(timeout: 10) }
    }

    // MARK: Helpers

    private func launchOnLinksPage() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding"]
        shots = ShotWriter(test: self, prefix: "links")
        self.app = app
        app.logsBesideShots()
        app.launch()
        let field = app.descendants(matching: .any).matching(identifier: "search.field").firstMatch
        land("field") { field.waitForExistence(timeout: 20) }
        field.tapWhenSettled()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeTextLogged("http://127.0.0.1:53117/links\n")
        land("reading") { app.buttons["bar.url"].waitForExistence(timeout: 20) }
    }

    /// Opens the stack and reads the open count, then comes back to the page.
    private func openTabCount() -> Int {
        let tabs = app.buttons["bar.tabs"].firstMatch
        guard tabs.waitForExistence(timeout: 10) else { return -1 }
        tabs.tap()
        let count = app.descendants(matching: .any)["tabs.openCount"].firstMatch
        guard count.waitForExistence(timeout: 10) else { return -1 }
        let digits = Int(count.label.filter(\.isNumber)) ?? -1
        swipeBack()
        _ = app.buttons["bar.tabs"].firstMatch.waitForExistence(timeout: 10)
        return digits
    }

    /// An edge swipe from the stack to the page it came from.
    private func swipeBack() {
        Thread.sleep(forTimeInterval: 0.6)
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0)
    }

    private func land(
        _ step: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ check: () -> Bool
    ) {
        if check() { return }
        shots.fail(step)
        print("=== element tree at the failed step '\(step)' ===")
        print(app.debugDescription)
        XCTFail("the flow did not land '\(step)'", file: file, line: line)
    }
}
