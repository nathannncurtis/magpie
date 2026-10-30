import XCTest

/// The one flow, end to end, under both appearances: the launch search, reading, the sheet
/// over the page, the stack, a fling that closes a card, and a relaunch that restores the
/// last tab.
@MainActor
final class FlowTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testFlowInLight() throws {
        try flow(appearance: "Light")
    }

    func testFlowInDark() throws {
        try flow(appearance: "Dark")
    }

    private func flow(appearance: String) throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding",
            "-AppleInterfaceStyle", appearance,
        ]
        let shots = ShotWriter(test: self, prefix: appearance.lowercased())
        app.launch()

        // 01 · the launch search, its field focused with the keyboard up.
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the launch search's field")
        XCTAssertTrue(
            app.keyboards.element.waitForExistence(timeout: 10), "the keyboard, up on arrival")
        shots.snap(app, "launch")

        // 02 · a query, with the stub rows beneath it.
        field.tap()
        field.typeText("magpie test")
        XCTAssertTrue(
            app.staticTexts["magpie test"].firstMatch.waitForExistence(timeout: 5),
            "the stub suggestion row")
        shots.snap(app, "query")

        // 03 · submit: a new tab, on reading, the bar naming the stub host.
        field.typeText("\n")
        let address = app.buttons["bar.url"]
        XCTAssertTrue(address.waitForExistence(timeout: 20), "the reading bar")
        XCTAssertTrue(address.waitForLabel("127.0.0.1", contains: true, timeout: 10))
        shots.snap(app, "reading")

        // 04 · the URL pill: the sheet over the page, carrying the page's address.
        address.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the sheet over the page")
        shots.snap(app, "search-over-page")

        // 05 · a tap away folds the sheet back into the bar.
        let scrim = app.descendants(matching: .any)["search.scrim"].firstMatch
        if scrim.exists {
            scrim.tap()
        } else {
            app.descendants(matching: .any)["search.sheet"].firstMatch.swipeDown()
        }
        XCTAssertTrue(address.waitForExistence(timeout: 10), "the bar, back")
        shots.snap(app, "reading-again")

        // 06 · the tab count: the stack, with one open.
        app.buttons["bar.tabs"].tap()
        let openCount = app.staticTexts["tabs.openCount"]
        XCTAssertTrue(openCount.waitForLabel("1 open", timeout: 10))
        shots.snap(app, "tabs-one")

        // 07 · the +: the launch search again, this time for an address.
        app.buttons["tabs.plus"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the launch search, again")
        field.tap()
        field.typeText("http://127.0.0.1:53117/page")

        // 08 · a second tab: the count now reads two.
        field.typeText("\n")
        XCTAssertTrue(address.waitForExistence(timeout: 20), "the second tab, on reading")
        app.buttons["bar.tabs"].tap()
        XCTAssertTrue(openCount.waitForLabel("2 open", timeout: 10))
        shots.snap(app, "tabs-two")

        // 09 · a fling up on the current card closes it.
        let card = app.descendants(matching: .any)["tabs.card.current"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the current card")
        let anchor = card.exists ? card : app.descendants(matching: .any)["tabs.stack"].firstMatch
        let press = anchor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let release = press.withOffset(CGVector(dx: 0, dy: -360))
        press.press(forDuration: 0.05, thenDragTo: release)
        XCTAssertTrue(openCount.waitForLabel("1 open", timeout: 10), "the flung card, closed")
        shots.snap(app, "tabs-one-again")

        // 10 · a relaunch restores the last tab.
        app.terminate()
        app.launchArguments = ["-uiTesting", "-uiTestingSkipOnboarding", "-AppleInterfaceStyle", appearance]
        app.launch()
        XCTAssertTrue(address.waitForExistence(timeout: 20), "the restored tab, on reading")
        shots.snap(app, "relaunch-restore")
    }
}
