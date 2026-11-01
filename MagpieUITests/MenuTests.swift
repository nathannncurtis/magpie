import XCTest

/// The menu (05) through real navigation, under both appearances: the bar growing into
/// the sheet, the toggles' one source of truth with Settings, the Bookmark tile's tap
/// and long press, and the Mods tile. A step that does not land stops the run with a
/// shot of what was on screen and the element tree in the log.
@MainActor
final class MenuTests: XCTestCase {

    private var app: XCUIApplication!
    private var shots: ShotWriter!

    override func setUp() {
        continueAfterFailure = false
    }

    func testMenuInLight() {
        menu(appearance: "Light")
    }

    func testMenuInDark() {
        menu(appearance: "Dark")
    }

    private func menu(appearance: String) {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding",
            "-AppleInterfaceStyle", appearance,
        ]
        shots = ShotWriter(test: self, prefix: appearance.lowercased())
        self.app = app
        app.logsBesideShots()
        app.launch()

        // Reading, on the stub page.
        let field = app.descendants(matching: .any).matching(identifier: "search.field")
            .firstMatch
        land("field") { field.waitForExistence(timeout: 20) }
        field.tapWhenSettled()
        // Keys up first: text typed before the keyboard is ready loses its first characters.
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeTextLogged("http://127.0.0.1:53117/page\n")
        let address = app.buttons["bar.url"]
        land("reading") { address.waitForExistence(timeout: 20) }

        // The page's own content, painted behind whatever opens over it.
        let heading = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "/page")).firstMatch
        land("page-painted") { heading.waitForExistence(timeout: 20) }

        // •••: the bar grows into the menu, the bar row pinned at its base.
        let menuButton = app.buttons["bar.menu"]
        land("menu-button") { menuButton.waitForExistence(timeout: 10) }
        menuButton.tap()
        land("menu-open") { menuSheet.waitForExistence(timeout: 10) }
        shots.snap(app, "menu-open")

        // The cookie toggle: off here, off in Settings too — one source of truth.
        let cookies = app.descendants(matching: .any)["menu.toggle.cookies"].firstMatch
        land("menu-toggle-cookies") { cookies.waitForExistence(timeout: 10) }
        XCTAssertEqual(cookies.value as? String, "1", "cookie banners blocked by default")
        cookies.tap()
        XCTAssertEqual(cookies.value as? String, "0", "the menu's toggle turned it off")

        let settingsRow = app.descendants(matching: .any)["menu.settings"].firstMatch
        land("menu-settings-row") { settingsRow.waitForExistence(timeout: 10) }
        settingsRow.tap()
        let settingsCookies = app.descendants(matching: .any)["settings.cookies"].firstMatch
        land("settings-from-menu") { settingsCookies.waitForExistence(timeout: 20) }
        shots.snap(app, "settings-from-menu")
        XCTAssertEqual(
            settingsCookies.value as? String, "0",
            "Settings reads the same choice the menu made")

        // Done: back on the page, the menu folded away.
        app.buttons["settings.done"].tap()
        land("menu-folded") { address.waitForExistence(timeout: 20) }

        // The Bookmark tile: the long press opens Bookmarks, the saved page in it.
        menuButton.tap()
        land("menu-reopen") { menuSheet.waitForExistence(timeout: 10) }
        let cookiesAgain = app.descendants(matching: .any)["menu.toggle.cookies"].firstMatch
        cookiesAgain.tap()
        XCTAssertEqual(cookiesAgain.value as? String, "1", "the choice holds across opens")

        let bookmark = app.descendants(matching: .any)["menu.tile.bookmark"].firstMatch
        land("menu-bookmark-tile") { bookmark.waitForExistence(timeout: 10) }
        bookmark.tap()
        bookmark.press(forDuration: 0.7)
        let savedRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "bookmarks.row."))
            .firstMatch
        land("bookmarks-from-menu") {
            app.descendants(matching: .any)["bookmarks.screen"].firstMatch.waitForExistence(
                timeout: 20)
        }
        land("saved-page") { savedRow.waitForExistence(timeout: 10) }
        shots.snap(app, "bookmarks-from-menu")

        // The saved page, opened: back on reading.
        savedRow.tap()
        land("reading-again") { address.waitForExistence(timeout: 20) }

        // The Mods tile: the mods screen over the page.
        menuButton.tap()
        land("menu-again") { menuSheet.waitForExistence(timeout: 10) }
        let mods = app.descendants(matching: .any)["menu.tile.mods"].firstMatch
        land("menu-mods-tile") { mods.waitForExistence(timeout: 10) }
        mods.tap()
        land("mods-from-menu") {
            app.descendants(matching: .any)["mods.screen"].firstMatch.waitForExistence(
                timeout: 20)
        }
        shots.snap(app, "mods-from-menu")
    }

    /// The menu's sheet, however the hierarchy exposes it.
    private var menuSheet: XCUIElement {
        app.descendants(matching: .any)["menu.sheet"].firstMatch
    }

    /// A step of the flow: when it does not land, the run stops with a shot of what was
    /// on screen, the element tree in the log, and the failure named after the step.
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
