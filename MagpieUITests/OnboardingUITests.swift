import XCTest

/// The first launch (04 · 07a, 07b), under both appearances: Welcome, then the engine
/// picker empty, DuckDuckGo picked, and Other with its URL entry.
@MainActor
final class OnboardingUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testOnboardingInLight() throws {
        try onboarding(appearance: "Light")
    }

    func testOnboardingInDark() throws {
        try onboarding(appearance: "Dark")
    }

    private func onboarding(appearance: String) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingResetStore", "-AppleInterfaceStyle", appearance,
        ]
        app.launch()
        let mode = appearance.lowercased()

        // 07a · Welcome: the mark, the name, one button. Onboarding comes before the launch
        // sheet ever focuses, so no keyboard is up under it.
        let start = app.descendants(matching: .any)["welcome.start"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20), "Welcome")
        XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 2), "no keyboard under Welcome")
        ShotWriter(test: self, prefix: "onboarding-welcome").snap(app, mode)

        // 07b · the picker, nothing picked yet.
        start.tap()
        let duckduckgo = app.descendants(matching: .any)["picker.tile.duckduckgo"].firstMatch
        XCTAssertTrue(duckduckgo.waitForExistence(timeout: 10), "the engine picker")
        ShotWriter(test: self, prefix: "onboarding-picker-empty").snap(app, mode)

        // DuckDuckGo picked: the ring, the check badge, the CTA carrying the name.
        duckduckgo.tap()
        let continueButton = app.descendants(matching: .any)["picker.continue"].firstMatch
        XCTAssertTrue(
            continueButton.waitForLabel("Continue with DuckDuckGo", timeout: 10),
            "the CTA once an engine is picked")
        ShotWriter(test: self, prefix: "onboarding-picker-duckduckgo").snap(app, mode)

        // Other: the URL entry appears under the grid, and the CTA waits for a valid one.
        app.descendants(matching: .any)["picker.tile.other"].firstMatch.tap()
        let urlField = app.descendants(matching: .any)["picker.otherURL"].firstMatch
        XCTAssertTrue(urlField.waitForExistence(timeout: 10), "the Other URL entry")
        ShotWriter(test: self, prefix: "onboarding-picker-other").snap(app, mode)
    }
}
