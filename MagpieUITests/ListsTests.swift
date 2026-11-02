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

    // MARK: Waits

    /// Waits for an element to exist. A miss fails the test with a screenshot of what
    /// did render and the whole accessibility hierarchy in the log.
    @discardableResult
    private func wait(
        _ element: XCUIElement,
        timeout: TimeInterval,
        _ what: String,
        app: XCUIApplication,
        shots: ShotWriter,
        shot: String
    ) -> XCUIElement {
        guard element.waitForExistence(timeout: timeout) else {
            shots.snap(app, shot)
            print("=== \(what): \(element.identifier.isEmpty ? "element" : element.identifier) not found ===")
            print(app.debugDescription)
            XCTFail(what)
            return element
        }
        return element
    }

    /// Anything on the screen by identifier; SwiftUI does not promise an element's kind.
    private func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    // MARK: Archive

    private func archive(appearance: String) throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding", "-uiTestingSurface=archive",
            "-AppleInterfaceStyle", appearance,
        ]
        let shots = ShotWriter(test: self, prefix: appearance.lowercased())
        app.logsBesideShots()
        app.launch()

        // 01 · the seeded archive: yesterday, the week, and a month band.
        let seasoned = any(app, "archive.row.How to season a carbon steel pan")
        wait(
            seasoned, timeout: 20, "the seeded archive, grouped by day",
            app: app, shots: shots, shot: "archive-fail-seeded"
        )
        wait(
            any(app, "archive.row.Knife steel, explained"), timeout: 10, "a month band",
            app: app, shots: shots, shot: "archive-fail-month"
        )
        shots.snap(app, "archive-list")

        // 02 · Done goes back to the stack.
        wait(
            any(app, "archive.done"), timeout: 10, "the Done button",
            app: app, shots: shots, shot: "archive-fail-done"
        )
        .tap()
        wait(
            any(app, "tabs.openCount"), timeout: 10, "back on the tabs",
            app: app, shots: shots, shot: "archive-fail-back"
        )

        // 03 · the pill searches titles, live.
        wait(
            any(app, "tabs.archive"), timeout: 10, "the archived chip",
            app: app, shots: shots, shot: "archive-fail-chip"
        )
        .tap()
        wait(
            seasoned, timeout: 10, "the archive, again",
            app: app, shots: shots, shot: "archive-fail-return"
        )
        let field = app.textFields["list.search.field"]
        wait(
            field, timeout: 10, "the search pill",
            app: app, shots: shots, shot: "archive-fail-pill"
        )
        field.tapWhenSettled()
        // Keys up first: text typed before the keyboard is ready loses its first characters.
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeTextLogged("season")
        XCTAssertFalse(
            any(app, "archive.row.rebase vs merge · git docs").exists,
            "an unmatched row, filtered out")
        XCTAssertTrue(seasoned.exists, "the matched row, still there")
        field.typeText("\n")
        shots.snap(app, "archive-search")

        // 04 · nothing archived: the quiet line, and no pill to search with.
        app.terminate()
        app.launchArguments = [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding", "-uiTestingSurface=archive",
            "-uiTestingListState=empty", "-AppleInterfaceStyle", appearance,
        ]
        app.logsBesideShots()
        app.launch()
        wait(
            any(app, "archive.empty"), timeout: 20, "the empty archive",
            app: app, shots: shots, shot: "archive-fail-empty"
        )
        XCTAssertFalse(app.textFields["list.search.field"].exists, "no search pill")
        shots.snap(app, "archive-empty")
    }

    // MARK: Bookmarks

    private func bookmarks(appearance: String) throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding", "-uiTestingSurface=bookmarks",
            "-AppleInterfaceStyle", appearance,
        ]
        let shots = ShotWriter(test: self, prefix: appearance.lowercased())
        app.logsBesideShots()
        app.launch()

        // 01 · the seeded list: the folders, then a mix of saved pages.
        let kitchen = any(app, "bookmarks.folder.Kitchen")
        wait(
            kitchen, timeout: 20, "the seeded folders",
            app: app, shots: shots, shot: "bookmarks-fail-folders"
        )
        wait(
            any(app, "bookmarks.row.Seasoning carbon steel"), timeout: 10, "the seeded Skim page",
            app: app, shots: shots, shot: "bookmarks-fail-skim"
        )
        shots.snap(app, "bookmarks-list")

        // 02 · edit mode: new folder, reorder, rename, delete.
        wait(
            any(app, "bookmarks.edit"), timeout: 10, "the Edit button",
            app: app, shots: shots, shot: "bookmarks-fail-edit-button"
        )
        .tap()
        wait(
            any(app, "bookmarks.newFolder"), timeout: 10, "edit mode",
            app: app, shots: shots, shot: "bookmarks-fail-edit"
        )
        shots.snap(app, "bookmarks-edit")
        let save = wait(
            any(app, "bookmarks.edit"), timeout: 10, "the Save button",
            app: app, shots: shots, shot: "bookmarks-fail-edit-done"
        )
        XCTAssertEqual(save.label, "Save", "editing reads Save, never Done")
        wait(
            any(app, "bookmarks.done"), timeout: 10, "the Done button, still there in edit mode",
            app: app, shots: shots, shot: "bookmarks-fail-done-button"
        )
        save.tap()
        XCTAssertFalse(any(app, "bookmarks.newFolder").exists, "out of edit mode")

        // 03 · a folder's own list.
        wait(
            kitchen, timeout: 10, "the Kitchen folder",
            app: app, shots: shots, shot: "bookmarks-fail-kitchen"
        )
        .tap()
        wait(
            any(app, "bookmarks.folder.list"), timeout: 10, "the folder's list",
            app: app, shots: shots, shot: "bookmarks-fail-folder"
        )
        shots.snap(app, "bookmarks-folder")
        wait(
            any(app, "bookmarks.folder.back"), timeout: 10, "the folder's back button",
            app: app, shots: shots, shot: "bookmarks-fail-back-button"
        )
        .tap()
        wait(
            kitchen, timeout: 10, "back on the bookmarks",
            app: app, shots: shots, shot: "bookmarks-fail-back"
        )

        // 04 · nothing saved: the quiet line, and no pill to search with.
        app.terminate()
        app.launchArguments = [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding", "-uiTestingSurface=bookmarks",
            "-uiTestingListState=empty", "-AppleInterfaceStyle", appearance,
        ]
        app.logsBesideShots()
        app.launch()
        wait(
            any(app, "bookmarks.empty"), timeout: 20, "the empty bookmarks",
            app: app, shots: shots, shot: "bookmarks-fail-empty"
        )
        XCTAssertFalse(app.textFields["list.search.field"].exists, "no search pill")
        shots.snap(app, "bookmarks-empty")
    }
}
