import XCTest

/// Bookmarks from the menu's own row, and a swipe-away that can be taken back.
@MainActor
final class BookmarksFlowTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func testMenuRowOpensBookmarks() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding",
        ]
        let shots = ShotWriter(test: self, prefix: "menu-bookmarks")
        app.logsBesideShots()
        app.launch()

        let field = any(app, "search.field")
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the launch search")
        field.tapWhenSettled()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeTextLogged("http://127.0.0.1:53117/page\n")

        let menuButton = app.buttons["bar.menu"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 20), "reading")
        menuButton.tap()

        let row = any(app, "menu.bookmarks")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the Bookmarks row in the menu")
        shots.snap(app, "menu-with-bookmarks-row")
        row.tap()

        XCTAssertTrue(any(app, "bookmarks.title").waitForExistence(timeout: 10), "Bookmarks opened")
    }

    func testDeletedBookmarkComesBackOnUndo() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding",
            "-uiTestingSurface=bookmarks",
        ]
        let shots = ShotWriter(test: self, prefix: "bookmarks-undo")
        app.logsBesideShots()
        app.launch()

        let row = any(app, "bookmarks.row.Pro Git, chapter 3")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the seeded bookmarks")

        row.swipeLeft()
        let delete = app.buttons["Delete"]
        if delete.waitForExistence(timeout: 2) { delete.tap() }

        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "the swipe deleted at once")
        let undo = any(app, "undo.capsule")
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "the Undo capsule")
        shots.snap(app, "undo-capsule")

        undo.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the bookmark is back")
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5), "the capsule goes with the undo")
    }
}
