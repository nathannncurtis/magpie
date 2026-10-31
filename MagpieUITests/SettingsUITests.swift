import XCTest

/// Settings and its pages, under both appearances, from the `-uiTestingSurface=settings`
/// launch argument until the menu exists.
@MainActor
final class SettingsUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testSettingsInLight() throws {
        try settings(appearance: "Light")
    }

    func testSettingsInDark() throws {
        try settings(appearance: "Dark")
    }

    private func settings(appearance: String) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding",
            "-uiTestingSurface=settings", "-AppleInterfaceStyle", appearance,
        ]
        app.launch()
        let mode = appearance.lowercased()

        // 11 · Settings, with the default browser card on top.
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.done"].firstMatch.waitForExistence(timeout: 20),
            "Settings")
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.defaultBrowser"].firstMatch.exists,
            "the default browser card")
        waitForNoKeyboard(app)
        ShotWriter(test: self, prefix: "settings-home").snap(app, mode)

        // The engine list, pushed.
        app.descendants(matching: .any)["settings.engine"].firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.engineList.duckduckgo"].firstMatch
                .waitForExistence(timeout: 10),
            "the engine list")
        ShotWriter(test: self, prefix: "settings-engineList").snap(app, mode)
        goBack(app)

        // The filter lists page, with its fixed two-hour-old timestamp.
        app.descendants(matching: .any)["settings.filterLists"].firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.updateNow"].firstMatch.waitForExistence(timeout: 10),
            "the filter lists page")
        ShotWriter(test: self, prefix: "settings-filterLists").snap(app, mode)
        goBack(app)

        // The archive picker.
        app.descendants(matching: .any)["settings.archive"].firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.archiveStep.1"].firstMatch.waitForExistence(timeout: 10),
            "the archive picker")
        ShotWriter(test: self, prefix: "settings-archive").snap(app, mode)
        goBack(app)

        // About.
        app.descendants(matching: .any)["settings.about"].firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.about.source"].firstMatch.waitForExistence(timeout: 10),
            "About")
        ShotWriter(test: self, prefix: "settings-about").snap(app, mode)
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.descendants(matching: .any)["settings.back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the back button")
        back.tap()
    }

    /// The launch sheet's keyboard drops once Settings covers it; shots wait for it to go.
    private func waitForNoKeyboard(_ app: XCUIApplication) {
        let deadline = Date().addingTimeInterval(5)
        while app.keyboards.element.exists && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
}
