import XCTest

/// The Skim screens, seeded through the UI-test environment with Skim forced
/// available: the working page, the finished page in each photo tier, and the
/// failure — under both appearances.
@MainActor
final class SkimTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testWorking() throws {
        try working(appearance: "Light")
        try working(appearance: "Dark")
    }

    func testPageMosaic() throws {
        try page(skimState: "photos3", shot: "skim-page-mosaic", appearance: "Light")
        try page(skimState: "photos3", shot: "skim-page-mosaic", appearance: "Dark")
    }

    func testPageHero() throws {
        try page(skimState: "photo1", shot: "skim-page-hero", appearance: "Light")
        try page(skimState: "photo1", shot: "skim-page-hero", appearance: "Dark")
    }

    func testPageWithoutPhotos() throws {
        try page(skimState: "none", shot: "skim-page-none", appearance: "Light")
        try page(skimState: "none", shot: "skim-page-none", appearance: "Dark")
    }

    func testFailed() throws {
        try failed(appearance: "Light")
        try failed(appearance: "Dark")
    }

    // MARK: Working

    private func working(appearance: String) throws {
        let (app, shots) = launch(surface: "skimWorking", appearance: appearance)

        XCTAssertTrue(
            app.descendants(matching: .any)["skim.working"].waitForExistence(timeout: 20),
            "the working screen")
        XCTAssertTrue(
            app.staticTexts["Reading 3 pages"].waitForExistence(timeout: 10),
            "the reading line")
        XCTAssertTrue(app.buttons["skim.cancel"].exists, "Cancel")

        // The query fades in under the mark; let it land before the shot.
        Thread.sleep(forTimeInterval: 1.2)
        shots.snap(app, "skim-working")
    }

    // MARK: The finished page

    private func page(skimState: String, shot: String, appearance: String) throws {
        let (app, shots) = launch(
            surface: "skimPage", skimState: skimState, appearance: appearance)

        XCTAssertTrue(
            app.buttons["skim.source.1"].waitForExistence(timeout: 20), "the sources")
        XCTAssertTrue(app.buttons["skim.digDeeper"].exists, "the dig-deeper control")
        XCTAssertTrue(
            app.descendants(matching: .any)["skim.queryBar"].exists, "the query bar")

        // The page rises over about 1.4 s; let it settle before the shot.
        Thread.sleep(forTimeInterval: 2)
        shots.snap(app, shot)

        // A citation chip scrolls to its source card.
        let third = app.buttons["skim.source.3"].firstMatch
        app.buttons["Source 3"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(third.isHittable, "the third source, scrolled to")
    }

    // MARK: Failed

    private func failed(appearance: String) throws {
        let (app, shots) = launch(surface: "skimFailed", appearance: appearance)

        XCTAssertTrue(
            app.descendants(matching: .any)["skim.failed"].waitForExistence(timeout: 20),
            "the failed screen")
        XCTAssertTrue(
            app.staticTexts[
                "Only 1 of 3 pages could be read. That's not enough to Skim."
            ].waitForExistence(timeout: 10),
            "the board's failure line")
        XCTAssertTrue(app.buttons["skim.showResults"].exists, "the results CTA")
        XCTAssertTrue(app.buttons["skim.retry"].exists, "Try again")

        Thread.sleep(forTimeInterval: 0.5)
        shots.snap(app, "skim-failed")
    }

    // MARK: Launch

    private func launch(
        surface: String, skimState: String? = nil, appearance: String
    ) -> (XCUIApplication, ShotWriter) {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding",
            "-uiTestingSurface=\(surface)", "-uiTestingSkim", "-AppleInterfaceStyle", appearance,
        ]
        if let skimState {
            app.launchArguments += ["-uiTestingSkimState=\(skimState)"]
        }
        let shots = ShotWriter(test: self, prefix: appearance.lowercased())
        app.launch()
        return (app, shots)
    }
}
