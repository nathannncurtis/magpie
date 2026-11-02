import XCTest

/// History and the data tools through real navigation: a page visited lands in History,
/// the pill finds it, a tap opens it; Clear browsing data empties History; and a site's
/// Desktop site choice reaches the page it loads. A step that does not land stops the run
/// with a shot of what was on screen and the element tree in the log.
@MainActor
final class HistoryTests: XCTestCase {

    private var app: XCUIApplication!
    private var shots: ShotWriter!

    override func setUp() {
        continueAfterFailure = false
    }

    func testVisitedPageIsInHistoryAndSearchable() {
        launchAndVisit("/page")
        openHistory()

        let row = anyElement("history.row.magpie test page")
        land("history-row") { row.waitForExistence(timeout: 20) }
        shots.snap(app, "history-list")

        // The pill: a search with no match, then one that finds the page.
        let field = app.textFields["list.search.field"]
        land("history-pill") { field.waitForExistence(timeout: 10) }
        field.tapWhenSettled()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeTextLogged("zzzz")
        land("no-results") { self.anyElement("history.results.empty").waitForExistence(timeout: 10) }
        shots.snap(app, "history-no-results")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        field.typeTextLogged("test page")
        land("search-finds-row") { row.waitForExistence(timeout: 10) }
        shots.snap(app, "history-search")
        field.typeText("\n")

        // A tap opens the page in a new tab, and History folds away.
        row.tap()
        land("opened") { self.app.buttons["bar.url"].waitForExistence(timeout: 20) }
        XCTAssertFalse(anyElement("history.screen").exists, "History is gone once a page opens")
        let tabs = app.buttons["bar.tabs"]
        land("two-tabs") { tabs.waitForExistence(timeout: 10) }
        XCTAssertTrue(tabs.label.contains("2") || (tabs.value as? String) == "2", "a second tab: \(tabs.label)")
    }

    func testClearBrowsingDataEmptiesHistory() {
        launchAndVisit("/page")
        openHistory()
        land("history-row") { self.anyElement("history.row.magpie test page").waitForExistence(timeout: 20) }
        anyElement("history.done").tap()
        land("back-on-page") { self.app.buttons["bar.menu"].waitForExistence(timeout: 20) }

        // Settings, Privacy, Clear browsing data.
        app.buttons["bar.menu"].tap()
        let settingsRow = anyElement("menu.settings")
        land("menu-settings") { settingsRow.waitForExistence(timeout: 10) }
        settingsRow.tap()
        let clearRow = anyElement("settings.clearData")
        land("settings-clear-row") { clearRow.waitForExistence(timeout: 20) }
        clearRow.tap()
        let clear = anyElement("settings.clearData.clear")
        land("clear-page") { clear.waitForExistence(timeout: 10) }
        shots.snap(app, "clear-page")
        clear.tap()
        let confirm = app.buttons["settings.clearData.confirm"]
        land("confirm") { confirm.waitForExistence(timeout: 10) }
        shots.snap(app, "clear-confirm")
        confirm.tap()
        land("cleared") { self.anyElement("settings.clearData.done").waitForExistence(timeout: 20) }
        shots.snap(app, "cleared")

        // Back out of Settings: History is empty.
        anyElement("settings.back").tap()
        anyElement("settings.done").tap()
        land("page-again") { self.app.buttons["bar.menu"].waitForExistence(timeout: 20) }
        openHistory()
        land("history-empty") { self.anyElement("history.empty").waitForExistence(timeout: 20) }
        shots.snap(app, "history-empty")
        XCTAssertFalse(anyElement("history.row.magpie test page").exists, "the visit is gone")
    }

    func testDesktopSiteReloadsThePageAsDesktop() {
        launchAndVisit("/mode")
        let mobile = modeLabel("mode: mobile")
        land("mobile-first") { mobile.waitForExistence(timeout: 20) }

        app.buttons["bar.menu"].tap()
        let toggle = anyElement("menu.toggle.desktop")
        land("desktop-row") { toggle.waitForExistence(timeout: 10) }
        shots.snap(app, "desktop-row")
        XCTAssertEqual(toggle.value as? String, "0", "mobile to begin with")
        toggle.tap()
        // The menu folds; the page has reloaded as the desktop version.
        app.buttons["bar.menu"].tap()
        let desktop = modeLabel("mode: desktop")
        land("desktop-after") { desktop.waitForExistence(timeout: 20) }
        shots.snap(app, "desktop-page")

        // And back.
        app.buttons["bar.menu"].tap()
        land("desktop-row-again") { toggle.waitForExistence(timeout: 10) }
        XCTAssertEqual(toggle.value as? String, "1", "remembered for the site")
        toggle.tap()
        app.buttons["bar.menu"].tap()
        land("mobile-after") { self.modeLabel("mode: mobile").waitForExistence(timeout: 20) }
    }

    // MARK: Steps

    /// A fresh run on a stub page: reading, painted.
    private func launchAndVisit(_ path: String) {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding",
            "-AppleInterfaceStyle", "Light",
        ]
        shots = ShotWriter(test: self, prefix: "history")
        self.app = app
        app.logsBesideShots()
        app.launch()

        let field = anyElement("search.field")
        land("field") { field.waitForExistence(timeout: 20) }
        field.tapWhenSettled()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeTextLogged("http://127.0.0.1:53117\(path)\n")
        land("reading") { self.app.buttons["bar.url"].waitForExistence(timeout: 20) }
        let heading = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", path == "/mode" ? "mode:" : path))
            .firstMatch
        land("page-painted") { heading.waitForExistence(timeout: 20) }
    }

    /// The menu's History row.
    private func openHistory() {
        app.buttons["bar.menu"].tap()
        let row = anyElement("menu.history")
        land("menu-history") { row.waitForExistence(timeout: 10) }
        row.tap()
        land("history-screen") { self.anyElement("history.screen").waitForExistence(timeout: 20) }
    }

    private func modeLabel(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", text)).firstMatch
    }

    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
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
