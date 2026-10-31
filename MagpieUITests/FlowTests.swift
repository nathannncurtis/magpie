import XCTest

/// The one flow, end to end, under both appearances: the launch search, reading, the sheet
/// over the page, the stack, a fling that closes a card, and a relaunch that restores the
/// last tab. A step that does not land stops the run with a shot of what was on screen and
/// the element tree in the log.
@MainActor
final class FlowTests: XCTestCase {

    private var app: XCUIApplication!
    private var shots: ShotWriter!

    override func setUp() {
        continueAfterFailure = false
    }

    func testFlowInLight() {
        flow(appearance: "Light")
    }

    func testFlowInDark() {
        flow(appearance: "Dark")
    }

    private func flow(appearance: String) {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding",
            "-AppleInterfaceStyle", appearance,
        ]
        // The app's capture log lands beside the shots; it cannot see the runner's own
        // environment, so the directory is handed over. The file is never cleared: one
        // run is one record, its lines named by appearance, launches and all.
        if let shotsDir = ProcessInfo.processInfo.environment["MAGPIE_SHOTS_DIR"] {
            app.launchEnvironment["MAGPIE_SHOTS_DIR"] = shotsDir
        }
        shots = ShotWriter(test: self, prefix: appearance.lowercased())
        self.app = app
        app.launch()

        // 01 · the launch search, its field focused with the keyboard up.
        land("launch-app") { app.state == .runningForeground }
        land("launch-field") { field.waitForExistence(timeout: 20) }
        land("launch-keyboard") { app.keyboards.element.waitForExistence(timeout: 10) }
        shots.snap(app, "launch")

        // 02 · a query, with the stub rows beneath it.
        field.tap()
        // Keys up first: text typed before the keyboard is ready loses its first characters.
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeTextLogged("magpie test")
        land("launch-row") {
            app.staticTexts["magpie test"].firstMatch.waitForExistence(timeout: 5)
        }
        shots.snap(app, "query")

        // 03 · submit: a new tab, on reading, the bar naming the stub host.
        field.typeText("\n")
        let address = app.buttons["bar.url"]
        land("reading-bar") { address.waitForExistence(timeout: 20) }
        land("reading-host") { address.waitForLabel("127.0.0.1", contains: true, timeout: 10) }
        shots.snap(app, "reading")

        // 04 · the URL pill: the sheet over the page, carrying the page's address.
        address.tap()
        land("sheet-field") { field.waitForExistence(timeout: 10) }
        shots.snap(app, "search-over-page")

        // 05 · a tap away folds the sheet back into the bar.
        let scrim = app.descendants(matching: .any)["search.scrim"].firstMatch
        if scrim.exists {
            scrim.tap()
        } else {
            app.descendants(matching: .any)["search.sheet"].firstMatch.swipeDown()
        }
        land("bar-back") { address.waitForExistence(timeout: 10) }
        shots.snap(app, "reading-again")

        // 06 · the tab count: the stack, with one open.
        app.buttons["bar.tabs"].tap()
        let openCount = app.descendants(matching: .any)
            .matching(identifier: "tabs.openCount").firstMatch
        land("tabs-one") { openCount.waitForLabel("1 open", timeout: 10) }
        waitForCurrentCardPicture()
        shots.snap(app, "tabs-one")

        // 07 · the +: the launch search again, this time for an address.
        app.buttons["tabs.plus"].tap()
        land("launch-again") { field.waitForExistence(timeout: 10) }
        field.tap()
        // Keys up first: text typed before the keyboard is ready loses its first characters.
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeTextLogged("http://127.0.0.1:53117/page")

        // 08 · a second tab: the count now reads two.
        field.typeText("\n")
        land("reading-two") { address.waitForExistence(timeout: 20) }
        app.buttons["bar.tabs"].tap()
        land("tabs-two") { openCount.waitForLabel("2 open", timeout: 10) }
        waitForCurrentCardPicture()
        shots.snap(app, "tabs-two")

        // 09 · a fling up on the current card closes it.
        let card = app.descendants(matching: .any)["tabs.card.current"].firstMatch
        land("card") { card.waitForExistence(timeout: 10) }
        let anchor = card.exists ? card : app.descendants(matching: .any)["tabs.stack"].firstMatch
        let press = anchor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let release = press.withOffset(CGVector(dx: 0, dy: -360))
        press.press(forDuration: 0.05, thenDragTo: release)
        land("fling-closed") { openCount.waitForLabel("1 open", timeout: 10) }
        waitForCurrentCardPicture()
        shots.snap(app, "tabs-one-again")

        // 10 · a relaunch restores the last tab.
        app.terminate()
        app.launchArguments = ["-uiTesting", "-uiTestingSkipOnboarding", "-AppleInterfaceStyle", appearance]
        app.launch()
        land("relaunch-restore") { address.waitForExistence(timeout: 20) }
        // The restored page itself, drawn: its heading carries the route.
        let restored = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "/search")).firstMatch
        land("relaunch-painted") { restored.waitForExistence(timeout: 45) }
        shots.snap(app, "relaunch-restore")
    }

    /// The search field, however the hierarchy exposes it.
    private var field: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "search.field").firstMatch
    }

    /// Gives the current card's settle the seconds it may still need to land its picture,
    /// then shoots whether or not it did — a pictureless card is a finding, not a stop.
    /// The wait is scoped inside the current card, so a neighbour's picture cannot
    /// satisfy it.
    private func waitForCurrentCardPicture() {
        let card = app.descendants(matching: .any)["tabs.card.current"].firstMatch
        let picture = card.descendants(matching: .any)
            .matching(identifier: "tabs.card.snapshot").firstMatch
        // A cold simulator's first pages can take many seconds to answer; a card that
        // never gets its picture is a failure, not a shot taken anyway.
        land("card-picture") { picture.waitForExistence(timeout: 45) }
    }

    /// A step of the flow: when it does not land, the run stops with a shot of what was on
    /// screen, the element tree in the log, and the failure named after the step.
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
