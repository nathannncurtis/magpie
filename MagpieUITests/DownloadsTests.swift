import XCTest

/// A page that answers with a Content-Disposition attachment is saved, not shown: the
/// toast says so, and the Downloads list from the menu holds the file.
@MainActor
final class DownloadsTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testAttachmentDownloadsAndListsInDownloads() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTestingResetStore", "-uiTestingSkipOnboarding"]
        app.logsBesideShots()
        app.launch()
        let shots = ShotWriter(test: self, prefix: "downloads")
        let any = { (id: String) in app.descendants(matching: .any)[id].firstMatch }

        let field = any("search.field")
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the launch field")
        field.tapWhenSettled()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        field.typeTextLogged("http://127.0.0.1:53117/download.txt\n")

        let toast = any("download.toast")
        XCTAssertTrue(toast.waitForExistence(timeout: 20), "the toast")
        shots.snap(app, "toast")
        XCTAssertTrue(
            toast.waitForLabel("Downloaded magpie-sample.txt", timeout: 20), "the toast says it is done")

        // The list, from the menu.
        let menu = app.buttons["bar.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "the bar")
        menu.tap()
        let row = any("menu.downloads")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the Downloads row")
        row.tap()
        XCTAssertTrue(any("downloads.screen").waitForExistence(timeout: 10), "the Downloads screen")
        XCTAssertTrue(any("downloads.row.magpie-sample.txt").waitForExistence(timeout: 10), "the file")
        shots.snap(app, "list")

        // Swipe back leaves the screen.
        Thread.sleep(forTimeInterval: 0.6)
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
            .press(
                forDuration: 0.05,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)),
                withVelocity: .default, thenHoldForDuration: 0)
        XCTAssertTrue(
            any("downloads.screen").waitForNonExistence(timeout: 10), "back off the Downloads screen")
    }
}
