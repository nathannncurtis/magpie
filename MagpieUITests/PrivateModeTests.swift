import XCTest

/// The tabs screen's two modes through real navigation: the switch, the empty private
/// card, the private stack on its own, and the ordinary stack untouched. Run under both
/// appearances, since the private look is night whichever is set.
@MainActor
final class PrivateModeTests: XCTestCase {

    private var app: XCUIApplication!
    private var shots: ShotWriter!

    override func setUp() {
        continueAfterFailure = false
    }

    func testModesLight() {
        flow(appearance: "Light")
    }

    func testModesDark() {
        flow(appearance: "Dark")
    }

    private func flow(appearance: String) {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding",
            "-AppleInterfaceStyle", appearance,
        ]
        shots = ShotWriter(test: self, prefix: appearance.lowercased())
        self.app = app
        app.logsBesideShots()
        app.launch()

        // An ordinary tab, then the tabs screen.
        open("http://127.0.0.1:53117/page")
        land("reading") { self.element("bar.url").waitForExistence(timeout: 20) }
        app.buttons["bar.tabs"].firstMatch.tap()
        land("tabs") { self.element("tabs.mode.normal").waitForExistence(timeout: 10) }
        land("tabs-one-open") { self.element("tabs.openCount").waitForLabel("1 open", contains: true, timeout: 10) }
        land("tabs-ordinary-label") { !self.element("tabs.label.private").exists }
        shots.snap(app, "tabs-ordinary")

        // Private: nothing there yet, so the card says what it is.
        element("tabs.mode.private").tap()
        land("empty-card") { self.element("tabs.private.empty").waitForExistence(timeout: 10) }
        land("empty-card-button") { self.element("tabs.private.new").exists }
        land("ordinary-card-gone") { !self.element("tabs.card.current").exists }
        shots.snap(app, "tabs-private-empty")

        // New private tab: the private look on the launch search, then a private page.
        element("tabs.private.new").tap()
        land("launch-private") { self.element("launch.private").waitForExistence(timeout: 10) }
        shots.snap(app, "launch-private")
        open("http://127.0.0.1:53117/page")
        land("bar-private") { self.element("bar.private").waitForExistence(timeout: 20) }
        shots.snap(app, "reading-private")

        // The private stack holds that tab alone.
        app.buttons["bar.tabs"].firstMatch.tap()
        land("tabs-private") { self.element("tabs.mode.private").waitForExistence(timeout: 10) }
        land("private-one-open") { self.element("tabs.openCount").waitForLabel("1 open", contains: true, timeout: 10) }
        land("private-label") { self.element("tabs.label.private").waitForExistence(timeout: 10) }
        land("private-single-card") { self.cards == 1 }
        shots.snap(app, "tabs-private")

        // Back to Tabs: the ordinary tab alone, the private one kept for later.
        element("tabs.mode.normal").tap()
        land("ordinary-again") { self.element("tabs.card.current").waitForExistence(timeout: 10) }
        land("ordinary-one-open") { self.element("tabs.openCount").waitForLabel("1 open", contains: true, timeout: 10) }
        land("ordinary-no-private-label") { !self.element("tabs.label.private").exists }
        land("ordinary-single-card") { self.cards == 1 }
        shots.snap(app, "tabs-ordinary-again")

        element("tabs.mode.private").tap()
        land("private-kept") { self.element("tabs.label.private").waitForExistence(timeout: 10) }
    }

    /// Every card on screen, the centered one and its neighbors.
    private var cards: Int {
        element("tabs.card.current").exists
            ? 1 + app.descendants(matching: .any).matching(identifier: "tabs.card.neighbour").count : 0
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func open(_ address: String) {
        let field = element("search.field")
        land("field") { field.waitForExistence(timeout: 20) }
        field.tapWhenSettled()
        // Keys up first: text typed before the keyboard is ready loses its first characters.
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeTextLogged(address + "\n")
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
