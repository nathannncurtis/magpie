import XCTest

/// The cold-start intro (05 · 07), under both appearances: the mark mid-draw, whole with
/// its bead seated, and the handed-off sheet with the keyboard up; the tap that skips it;
/// and the whole mark under Reduce Motion. The phase shots run with the phases held past
/// their beats, so each shot lands inside its phase whatever the runner's latency; the
/// skip runs on the real clock.
@MainActor
final class LaunchIntroTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testIntroPhasesInLight() {
        phases(appearance: "Light")
    }

    func testIntroPhasesInDark() {
        phases(appearance: "Dark")
    }

    private func phases(appearance: String) {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding",
            "-uiTestingHoldIntro",
            "-AppleInterfaceStyle", appearance,
        ]
        let shots = ShotWriter(test: self, prefix: appearance.lowercased())
        forwardShotsDir(to: app)
        app.launch()

        // Mid-draw: the stroke partway along its centreline, no bead yet.
        let intro = app.descendants(matching: .any)["launch.intro"].firstMatch
        XCTAssertTrue(intro.waitForExistence(timeout: 20), "the intro")
        Thread.sleep(forTimeInterval: 1.5)
        shots.snap(app, "launch-intro-drawing")

        // The hold: the mark whole, the bead seated in its dry gap.
        Thread.sleep(forTimeInterval: 4)
        shots.snap(app, "launch-intro-whole")

        // The hand-off: the sheet up, the field focused, the keyboard with it.
        let field = app.descendants(matching: .any)["search.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the handed-off sheet")
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 10), "the keyboard")
        shots.snap(app, "launch-intro-handoff")
    }

    func testTapSkipsToTheFocusedSheet() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding",
        ]
        app.launch()

        let intro = app.descendants(matching: .any)["launch.intro"].firstMatch
        XCTAssertTrue(intro.waitForExistence(timeout: 20), "the intro")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()

        // Focus reads through the keyboard: the field holds it exactly when the keyboard
        // is up (XCUIElement.hasFocus reads false on SwiftUI fields either way).
        let field = app.descendants(matching: .any)["search.field"].firstMatch
        let deadline = Date().addingTimeInterval(1)
        var focused = false
        while Date() < deadline {
            if field.exists && app.keyboards.element.exists {
                focused = true
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(focused, "the skip lands on the focused field within 1 s")
    }

    func testReducedMotionInLight() {
        reduced(appearance: "Light")
    }

    func testReducedMotionInDark() {
        reduced(appearance: "Dark")
    }

    private func reduced(appearance: String) {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding",
            "-uiTestingHoldIntro", "-uiTestingReduceMotion",
            "-AppleInterfaceStyle", appearance,
        ]
        let shots = ShotWriter(test: self, prefix: appearance.lowercased())
        app.launch()

        // The mark whole from the first moment: no draw, no bead drop.
        let intro = app.descendants(matching: .any)["launch.intro"].firstMatch
        XCTAssertTrue(intro.waitForExistence(timeout: 20), "the intro")
        Thread.sleep(forTimeInterval: 1)
        shots.snap(app, "launch-intro-reduced")

        // The sheet still arrives, crossfading in.
        let field = app.descendants(matching: .any)["search.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the sheet crossfades in")
    }

    /// The shots directory, handed to the app where its capture log lives.
    private func forwardShotsDir(to app: XCUIApplication) {
        if let shotsDir = ProcessInfo.processInfo.environment["MAGPIE_SHOTS_DIR"] {
            app.launchEnvironment["MAGPIE_SHOTS_DIR"] = shotsDir
        }
    }
}
