import XCTest

/// The quick parts of the address field: a copied link opens in one tap, a typed host
/// finishes itself, the page's address arrives selected, and a closed card can be undone.
@MainActor
final class AddressFieldTests: XCTestCase {

    private static let page = "http://127.0.0.1:53117/page"

    private var app: XCUIApplication!
    private var shots: ShotWriter!

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Paste and go

    func testCopiedLinkOpensInOneTap() {
        start(extra: ["-uiTestingPasteboard=\(Self.page)"], prefix: "paste")

        let row = element("search.paste")
        land("paste-row") { row.waitForExistence(timeout: 20) }
        shots.snap(app, "paste-row")
        row.tap()

        land("page-open") { self.element("bar.url").waitForExistence(timeout: 20) }
        land("page-painted") {
            self.app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "/page")).firstMatch
                .waitForExistence(timeout: 30)
        }
        shots.snap(app, "paste-opened")
    }

    func testNoPasteRowWithoutALink() {
        start(extra: [], prefix: "nopaste")
        let field = element("search.field")
        land("field") { field.waitForExistence(timeout: 20) }
        // Whatever the phone's pasteboard holds, typing takes the row away.
        field.tapWhenSettled()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeTextLogged("zz")
        XCTAssertFalse(element("search.paste").exists, "the row is gone once the user types")
    }

    // MARK: Inline completion

    func testTypedHostCompletesInline() {
        start(extra: [], prefix: "complete")
        let field = element("search.field")
        land("field") { field.waitForExistence(timeout: 20) }
        field.tapWhenSettled()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)

        field.typeText("wikip")
        land("completed") { self.fieldValue(field) == "wikipedia.org" }
        shots.snap(app, "completed")

        // Typing on replaces the selected rest, and completes again.
        field.typeText("e")
        land("completed-again") { self.fieldValue(field) == "wikipedia.org" }

        // Delete takes the completion away and keeps what was typed.
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        land("deleted") { self.fieldValue(field) == "wikipe" }

        // A letter that no host continues with just types.
        field.typeText("z")
        land("no-match") { self.fieldValue(field) == "wikipez" }
    }

    // MARK: Select all

    func testAddressArrivesSelectedOverAPage() {
        start(extra: [], prefix: "select")
        open(Self.page)
        let address = app.buttons["bar.url"]
        land("page") { address.waitForExistence(timeout: 20) }

        address.tap()
        let field = element("search.field")
        land("sheet") { field.waitForExistence(timeout: 10) }
        land("holds-address") { self.fieldValue(field).contains("127.0.0.1") }
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        shots.snap(app, "address-selected")

        // Typing replaces the whole address because it arrived selected.
        field.typeText("zz")
        land("replaced") { self.fieldValue(field) == "zz" }
    }

    // MARK: Undo close

    func testUndoBringsBackAClosedTab() {
        start(extra: [], prefix: "undo")
        open(Self.page)
        land("first-page") { self.app.buttons["bar.url"].waitForExistence(timeout: 20) }
        app.buttons["bar.tabs"].firstMatch.tap()
        app.buttons["tabs.plus"].tap()
        open(Self.page)
        land("second-page") { self.app.buttons["bar.url"].waitForExistence(timeout: 20) }
        app.buttons["bar.tabs"].firstMatch.tap()

        let count = element("tabs.openCount")
        land("two-open") { count.waitForLabel("2 open", timeout: 10) }
        flingCurrentCardUp()
        land("one-open") { count.waitForLabel("1 open", timeout: 10) }

        let undo = element("tabs.undo")
        land("undo-capsule") { undo.waitForExistence(timeout: 5) }
        shots.snap(app, "undo-capsule")
        undo.tap()
        land("two-again") { count.waitForLabel("2 open", timeout: 10) }
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5), "the capsule goes with the undo")
        shots.snap(app, "undone")
    }

    func testUndoCapsuleLeavesOnItsOwn() {
        start(extra: [], prefix: "undo-expire")
        open(Self.page)
        land("first-page") { self.app.buttons["bar.url"].waitForExistence(timeout: 20) }
        app.buttons["bar.tabs"].firstMatch.tap()
        app.buttons["tabs.plus"].tap()
        open(Self.page)
        land("second-page") { self.app.buttons["bar.url"].waitForExistence(timeout: 20) }
        app.buttons["bar.tabs"].firstMatch.tap()

        let count = element("tabs.openCount")
        land("two-open") { count.waitForLabel("2 open", timeout: 10) }
        flingCurrentCardUp()
        land("one-open") { count.waitForLabel("1 open", timeout: 10) }

        let undo = element("tabs.undo")
        land("undo-capsule") { undo.waitForExistence(timeout: 5) }
        land("capsule-gone") { undo.waitForNonExistence(timeout: 10) }
        XCTAssertTrue(count.waitForLabel("1 open", timeout: 5), "the close stands")
    }

    func testUndoBringsBackAPrivateTab() {
        start(extra: [], prefix: "undo-private")
        open(Self.page)
        land("page") { self.app.buttons["bar.url"].waitForExistence(timeout: 20) }

        app.buttons["bar.menu"].tap()
        let tile = element("menu.tile.private")
        land("private-tile") { tile.waitForExistence(timeout: 10) }
        tile.tap()
        land("private-launch") { self.element("launch.private").waitForExistence(timeout: 10) }
        open(Self.page)
        land("private-page") { self.element("bar.private").waitForExistence(timeout: 20) }

        app.buttons["bar.tabs"].firstMatch.tap()
        let count = element("tabs.openCount")
        land("two-open") { count.waitForLabel("2 open", timeout: 10) }
        flingCurrentCardUp()
        land("one-open") { count.waitForLabel("1 open", timeout: 10) }

        let undo = element("tabs.undo")
        land("undo-capsule") { undo.waitForExistence(timeout: 5) }
        undo.tap()
        land("two-again") { count.waitForLabel("2 open", timeout: 10) }
        shots.snap(app, "private-undone")
    }

    // MARK: Helpers

    private func start(extra: [String], prefix: String) {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding"] + extra
        shots = ShotWriter(test: self, prefix: prefix)
        self.app = app
        app.logsBesideShots()
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func fieldValue(_ field: XCUIElement) -> String {
        field.exists ? (field.value as? String ?? "") : ""
    }

    /// Types an address into whichever search sheet is up, and submits it.
    private func open(_ address: String) {
        let field = element("search.field")
        land("field") { field.waitForExistence(timeout: 20) }
        field.tapWhenSettled()
        // Keys up first: text typed before the keyboard is ready loses its first characters.
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeTextLogged(address + "\n")
    }

    private func flingCurrentCardUp() {
        let card = element("tabs.card.current")
        land("card") { card.waitForExistence(timeout: 10) }
        let press = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let release = press.withOffset(CGVector(dx: 0, dy: -360))
        press.press(forDuration: 0.05, thenDragTo: release)
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
