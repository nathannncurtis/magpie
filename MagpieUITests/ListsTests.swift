import XCTest

/// The archive and the bookmarks, seeded and empty, under both appearances: the lists,
/// their search pills, the bookmarks' edit mode, and a folder's own list.
@MainActor
final class ListsTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testArchiveInLight() throws {
        try archive(appearance: "Light")
    }

    func testArchiveInDark() throws {
        try archive(appearance: "Dark")
    }

    func testBookmarksInLight() throws {
        try bookmarks(appearance: "Light")
    }

    func testBookmarksInDark() throws {
        try bookmarks(appearance: "Dark")
    }

    // MARK: Archive

    private func archive(appearance: String) throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSurface=archive",
            "-AppleInterfaceStyle", appearance,
        ]
        let shots = ShotWriter(test: self, prefix: appearance.lowercased())
        app.launch()

        // 01 · the seeded archive: yesterday, the week, and a month band.
        let seasoned = app.descendants(matching: .any)["archive.row.How to season a carbon steel pan"]
        XCTAssertTrue(
            seasoned.waitForExistence(timeout: 20), "the seeded archive, grouped by day")
        XCTAssertTrue(
            app.descendants(matching: .any)["archive.row.Knife steel, explained"].waitForExistence(
                timeout: 10),
            "a month band")
        shots.snap(app, "archive-list")

        // 02 · Done goes back to the stack.
        app.buttons["archive.done"].tap()
        XCTAssertTrue(
            app.staticTexts["tabs.openCount"].waitForExistence(timeout: 10), "back on the tabs")

        // 03 · the pill searches titles, live.
        app.buttons["tabs.archive"].tap()
        XCTAssertTrue(seasoned.waitForExistence(timeout: 10), "the archive, again")
        let field = app.textFields["list.search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the search pill")
        field.tap()
        field.typeText("season")
        XCTAssertFalse(
            app.descendants(matching: .any)["archive.row.rebase vs merge · git docs"].exists,
            "an unmatched row, filtered out")
        XCTAssertTrue(seasoned.exists, "the matched row, still there")
        field.typeText("\n")
        shots.snap(app, "archive-search")

        // 04 · nothing archived: the quiet line, and no pill to search with.
        app.terminate()
        app.launchArguments = [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSurface=archive",
            "-uiTestingListState=empty", "-AppleInterfaceStyle", appearance,
        ]
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["archive.empty"].waitForExistence(timeout: 20),
            "the empty archive")
        XCTAssertFalse(app.textFields["list.search.field"].exists, "no search pill")
        shots.snap(app, "archive-empty")
    }

    // MARK: Bookmarks

    private func bookmarks(appearance: String) throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSurface=bookmarks",
            "-AppleInterfaceStyle", appearance,
        ]
        let shots = ShotWriter(test: self, prefix: appearance.lowercased())
        app.launch()

        // 01 · the seeded list: the folders, then a mix of saved pages.
        let kitchen = app.buttons["bookmarks.folder.Kitchen"]
        XCTAssertTrue(kitchen.waitForExistence(timeout: 20), "the seeded folders")
        XCTAssertTrue(
            app.descendants(matching: .any)["bookmarks.row.Seasoning carbon steel"]
                .waitForExistence(timeout: 10),
            "the seeded Skim page")
        shots.snap(app, "bookmarks-list")

        // 02 · edit mode: new folder, reorder, rename, delete.
        app.buttons["bookmarks.edit"].tap()
        XCTAssertTrue(
            app.buttons["bookmarks.newFolder"].waitForExistence(timeout: 10), "edit mode")
        shots.snap(app, "bookmarks-edit")
        app.buttons["bookmarks.edit"].tap()
        XCTAssertFalse(app.buttons["bookmarks.newFolder"].exists, "out of edit mode")

        // 03 · a folder's own list.
        kitchen.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["bookmarks.folder.list"].waitForExistence(
                timeout: 10),
            "the folder's list")
        shots.snap(app, "bookmarks-folder")
        app.buttons["bookmarks.folder.back"].tap()
        XCTAssertTrue(kitchen.waitForExistence(timeout: 10), "back on the bookmarks")

        // 04 · nothing saved: the quiet line, and no pill to search with.
        app.terminate()
        app.launchArguments = [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSurface=bookmarks",
            "-uiTestingListState=empty", "-AppleInterfaceStyle", appearance,
        ]
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["bookmarks.empty"].waitForExistence(timeout: 20),
            "the empty bookmarks")
        XCTAssertFalse(app.textFields["list.search.field"].exists, "no search pill")
        shots.snap(app, "bookmarks-empty")
    }
}
