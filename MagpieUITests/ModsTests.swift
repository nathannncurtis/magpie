import XCTest

/// The mods screens, end to end under both appearances: the directory, the installed list
/// and its empty state, the install sheet's preview and its refusal, and the install
/// landing behind the sheet (04 · 06, 04 · 12, 04 · 17, 05 · 06). A step that does not
/// land stops the run with a shot of what was on screen and the element tree in the log.
@MainActor
final class ModsTests: XCTestCase {

    private var app: XCUIApplication!
    private var shots: ShotWriter!

    override func setUp() {
        continueAfterFailure = false
    }

    func testModsInLight() {
        run(appearance: "Light")
    }

    func testModsInDark() {
        run(appearance: "Dark")
    }

    private func run(appearance: String) {
        shots = ShotWriter(test: self, prefix: appearance.lowercased())

        // 01 · the directory: the featured card and the popular list, all from the fixture.
        launch(appearance: appearance, resetting: true)
        land("mods-screen") { screen.waitForExistence(timeout: 20) }
        land("directory-featured") { featured.waitForExistence(timeout: 10) }
        land("directory-rows") { getButton.waitForExistence(timeout: 10) }
        shots.snap(app, "mods-directory")

        // 02 · installed, with the three seeded mods and the link one tagged unreviewed.
        launch(appearance: appearance, seeding: true)
        land("installed-open") { screen.waitForExistence(timeout: 20) }
        app.buttons["segment.1"].tap()
        land("installed-not-reviewed") { notReviewed.waitForExistence(timeout: 10) }
        land("installed-rows") { installedCountLabel.waitForLabel("Installed · 3", timeout: 10) }
        shots.snap(app, "mods-installed")

        // 03 · installed, with nothing in it.
        launch(appearance: appearance)
        land("empty-open") { screen.waitForExistence(timeout: 20) }
        app.buttons["segment.1"].tap()
        land("installed-empty") { emptyState.waitForExistence(timeout: 10) }
        shots.snap(app, "mods-installed-empty")

        // 04 · the install sheet: a userscript link reads out as a preview and a warning.
        openSheet(appearance: appearance)
        typeLink("http://127.0.0.1:53117/mod.user.js")
        land("sheet-preview") { preview.waitForExistence(timeout: 15) }
        land("sheet-warning") { warning.waitForExistence(timeout: 5) }
        dropKeyboard()
        shots.snap(app, "install-sheet")

        // 05 · the install sheet's refusal: a web page is not a mod.
        openSheet(appearance: appearance)
        typeLink("http://127.0.0.1:53117/page")
        land("sheet-failure") { failure.waitForExistence(timeout: 15) }
        land("sheet-refused-copy") {
            app.staticTexts["That's a web page, not a mod."].firstMatch.waitForExistence(timeout: 5)
        }
        dropKeyboard()
        shots.snap(app, "install-failed")

        // 06 · the install: the sheet drops and the confirmation row lands behind it.
        // The check is read the moment it pops — and this launch holds it, so the shot
        // catches it whatever the runner's latency; the released app clears it on beat.
        openSheet(appearance: appearance, holdingInstallCheck: true)
        typeLink("http://127.0.0.1:53117/mod.user.js")
        land("sheet-preview-again") { preview.waitForExistence(timeout: 15) }
        dropKeyboard()
        app.buttons["mods.sheet.install"].tap()
        land("row-checked") { seen(installedCheck, timeout: 10) }
        land("sheet-dropped") { gone(sheetField, timeout: 10) }
        shots.snap(app, "mod-installed")
    }

    // MARK: Launching and typing

    private func launch(
        appearance: String, resetting: Bool = false, seeding: Bool = false,
        holdingInstallCheck: Bool = false
    ) {
        app?.terminate()
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingSurface=mods", "-AppleInterfaceStyle", appearance]
        if resetting {
            app.launchArguments.append("-uiTestingResetStore")
        }
        if seeding {
            app.launchArguments.append("-uiTestingModsInstalled")
        }
        if holdingInstallCheck {
            app.launchArguments.append("-uiTestingHoldInstallCheck")
        }
        self.app = app
        app.launch()
    }

    /// Opens a fresh install sheet over the mods screen.
    private func openSheet(appearance: String, holdingInstallCheck: Bool = false) {
        launch(appearance: appearance, holdingInstallCheck: holdingInstallCheck)
        land("sheet-footer") { installFooter.waitForExistence(timeout: 20) }
        installFooter.tap()
        land("sheet-open") { sheetField.waitForExistence(timeout: 10) }
    }

    /// Types a link and returns, which reads it at once.
    private func typeLink(_ link: String) {
        sheetField.tap()
        sheetField.typeText(link)
        sheetField.typeText("\n")
    }

    /// Puts the keyboard away so the shot carries the sheet, not the keys.
    private func dropKeyboard() {
        guard app.keyboards.element.exists else { return }
        app.staticTexts["Install from URL"].firstMatch.tap()
    }

    /// Whether an element has arrived, polled short.
    private func seen(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return element.exists
    }

    /// Whether an element has left the screen.
    private func gone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return !element.exists
    }

    // MARK: Elements

    private var screen: XCUIElement { app.descendants(matching: .any)["mods.screen"].firstMatch }
    private var featured: XCUIElement { app.descendants(matching: .any)["mods.featured"].firstMatch }
    private var getButton: XCUIElement { app.buttons["mods.get"].firstMatch }
    private var notReviewed: XCUIElement { app.descendants(matching: .any)["mods.notReviewed"].firstMatch }
    private var emptyState: XCUIElement { app.descendants(matching: .any)["mods.empty"].firstMatch }
    private var installFooter: XCUIElement { app.buttons["mods.installFooter"].firstMatch }
    private var sheetField: XCUIElement { app.descendants(matching: .any)["mods.sheet.field"].firstMatch }
    private var preview: XCUIElement { app.descendants(matching: .any)["mods.sheet.preview"].firstMatch }
    private var warning: XCUIElement { app.descendants(matching: .any)["mods.sheet.warning"].firstMatch }
    private var failure: XCUIElement { app.descendants(matching: .any)["mods.sheet.failure"].firstMatch }
    private var installedCheck: XCUIElement {
        app.descendants(matching: .any)["mods.installedCheck"].firstMatch
    }

    /// The segmented control's "Installed · N" segment, read from its label.
    private var installedCountLabel: XCUIElement { app.buttons["segment.1"] }

    /// A step of the flow: when it does not land, the run stops with a shot of what was on
    /// screen, the element tree in the log, and the failure named after the step.
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
        XCTFail("the mods flow did not land '\(step)'", file: file, line: line)
    }
}
