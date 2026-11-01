import XCTest

/// The launch search with no tabs, folded away: the mist keeps the mark and a bottom row,
/// and + brings the sheet back with the keyboard up. A dismissal here must never leave a
/// screen with nothing to tap.
@MainActor
final class LaunchEmptyTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testFoldedLaunchKeepsItsControls() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding"]
        let shots = ShotWriter(test: self, prefix: "light")
        app.logsBesideShots()
        app.launch()

        let field = app.descendants(matching: .any)["search.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the launch field")

        // A tap above the sheet, with no tabs to go back to: the sheet folds into the mist.
        app.descendants(matching: .any)["search.scrim"].firstMatch.tap()
        let plus = app.descendants(matching: .any)["launch.plus"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 10), "the + after folding")
        XCTAssertTrue(app.descendants(matching: .any)["launch.archive"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["launch.settings"].firstMatch.exists)
        shots.snap(app, "launch-folded")

        // + brings the sheet back, its field focused with the keys up.
        plus.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the field after +")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "the keys after +")
        shots.snap(app, "launch-unfolded")

        // Settings opens from the folded row too.
        app.descendants(matching: .any)["search.scrim"].firstMatch.tap()
        let settings = app.descendants(matching: .any)["launch.settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "the gear after folding again")
        settings.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.cookies"].firstMatch.waitForExistence(timeout: 10),
            "Settings from the folded row")
    }
}
