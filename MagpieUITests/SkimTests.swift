import XCTest

/// The Skim screens, seeded through the UI-test environment with Skim forced
/// available: the working page, the finished page in each photo tier, and the
/// failure — under both appearances. A step that does not land stops the run
/// with a shot of what was on screen and the element tree in the log.
@MainActor
final class SkimTests: XCTestCase {

    private var app: XCUIApplication!
    private var shots: ShotWriter!

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
        launch(surface: "skimWorking", appearance: appearance)

        land("working-screen") { self.element("skim.working").waitForExistence(timeout: 30) }
        land("working-reading") { self.label("Reading 3 pages").waitForExistence(timeout: 10) }
        land("working-cancel") { self.element("skim.cancel").waitForExistence(timeout: 10) }

        // The query fades in under the mark; let it land before the shot.
        Thread.sleep(forTimeInterval: 1.2)
        shots.snap(app, "skim-working")
    }

    // MARK: The finished page

    private func page(skimState: String, shot: String, appearance: String) throws {
        launch(surface: "skimPage", skimState: skimState, appearance: appearance)

        land("page-screen") { self.element("skim.page").waitForExistence(timeout: 30) }
        land("page-source") { self.element("skim.source.1").waitForExistence(timeout: 10) }
        land("page-dig") { self.element("skim.digDeeper").waitForExistence(timeout: 10) }
        land("page-query-bar") { self.element("skim.queryBar").waitForExistence(timeout: 10) }

        // The page rises over about 1.4 s; let it settle before the shot.
        Thread.sleep(forTimeInterval: 2)
        shots.snap(app, shot)

        // A citation chip scrolls to its source card.
        app.buttons["Source 3"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1)
        let third = element("skim.source.3")
        land("page-third-source") { third.exists && third.isHittable }
    }

    // MARK: Failed

    private func failed(appearance: String) throws {
        launch(surface: "skimFailed", appearance: appearance)

        land("failed-screen") { self.element("skim.failed").waitForExistence(timeout: 30) }
        land("failed-line") { self.label("Only 1 of 3 pages").waitForExistence(timeout: 10) }
        land("failed-results") { self.element("skim.showResults").waitForExistence(timeout: 10) }
        land("failed-retry") { self.element("skim.retry").waitForExistence(timeout: 10) }

        Thread.sleep(forTimeInterval: 0.5)
        shots.snap(app, "skim-failed")
    }

    // MARK: Launch

    private func launch(
        surface: String, skimState: String? = nil, appearance: String
    ) {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-uiTestingResetStore", "-uiTestingSurface=\(surface)",
            "-uiTestingSkim", "-AppleInterfaceStyle", appearance,
        ]
        if let skimState {
            app.launchArguments += ["-uiTestingSkimState=\(skimState)"]
        }
        shots = ShotWriter(test: self, prefix: appearance.lowercased())
        self.app = app
        app.launch()
    }

    /// An element by identifier, however the hierarchy exposes it.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// An element by the text it shows, however the hierarchy exposes it.
    private func label(_ text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// A step of the flow: when it does not land, the run stops with a shot of
    /// what was on screen, the element tree in the log, and the failure named
    /// after the step.
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
        XCTFail("the screen did not land '\(step)'", file: file, line: line)
    }
}
