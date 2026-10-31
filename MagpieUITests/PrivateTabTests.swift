import XCTest

/// Private tabs through real navigation: the menu's Private tile opens the search for
/// one, the bar marks it, the stack counts it, and a relaunch leaves nothing of it.
@MainActor
final class PrivateTabTests: XCTestCase {

    private var app: XCUIApplication!
    private var shots: ShotWriter!

    override func setUp() {
        continueAfterFailure = false
    }

    func testPrivateTabLeavesNothing() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding"]
        shots = ShotWriter(test: self, prefix: "private")
        self.app = app
        app.launch()

        // An ordinary tab first, on the stub page.
        open("http://127.0.0.1:53117/page")
        let address = app.buttons["bar.url"]
        land("reading") { address.waitForExistence(timeout: 20) }
        XCTAssertFalse(app.descendants(matching: .any)["bar.private"].exists)

        // •••, then Private: the search says what it opens.
        app.buttons["bar.menu"].tap()
        let tile = app.descendants(matching: .any)["menu.tile.private"].firstMatch
        land("menu-tile-private") { tile.waitForExistence(timeout: 10) }
        tile.tap()
        let banner = app.descendants(matching: .any)["launch.private"].firstMatch
        land("launch-private") { banner.waitForExistence(timeout: 10) }
        shots.snap(app, "launch-private")

        open("http://127.0.0.1:53117/page")
        let mark = app.descendants(matching: .any)["bar.private"].firstMatch
        land("bar-private") { mark.waitForExistence(timeout: 20) }
        shots.snap(app, "reading-private")

        // Two tabs open, the private one among them.
        app.buttons["bar.tabs"].firstMatch.tap()
        let count = app.descendants(matching: .any)["tabs.openCount"].firstMatch
        land("tabs-two") {
            count.waitForExistence(timeout: 10)
                && count.label.contains("2")
        }
        shots.snap(app, "tabs-private")

        // A relaunch keeps the ordinary tab and drops the private one.
        app.terminate()
        app.launchArguments.removeAll { $0 == "-uiTestingResetStore" }
        app.launch()
        land("relaunched") { address.waitForExistence(timeout: 20) }
        XCTAssertFalse(
            app.descendants(matching: .any)["bar.private"].exists,
            "the private tab did not come back")
        app.buttons["bar.tabs"].firstMatch.tap()
        land("tabs-one") {
            count.waitForExistence(timeout: 10)
                && count.label.contains("1")
        }
        shots.snap(app, "tabs-after-relaunch")
    }

    private func open(_ address: String) {
        let field = app.descendants(matching: .any).matching(identifier: "search.field")
            .firstMatch
        land("field") { field.waitForExistence(timeout: 20) }
        field.tap()
        // Keys up first: text typed before the keyboard is ready loses its first characters.
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeText(address + "\n")
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
