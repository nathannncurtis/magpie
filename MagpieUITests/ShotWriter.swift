import XCTest

/// Screenshots of the flow: one PNG per step under `MAGPIE_SHOTS_DIR`, and the same image
/// kept with the result bundle.
@MainActor
final class ShotWriter {
    private let test: XCTestCase
    private let prefix: String
    private let directory: URL?
    private var number = 0

    init(test: XCTestCase, prefix: String) {
        self.test = test
        self.prefix = prefix
        directory = ProcessInfo.processInfo.environment["MAGPIE_SHOTS_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let directory {
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }
    }

    /// Takes the app's picture, keeps it with the run's results, and files it on disk as
    /// `NN-<prefix>-<name>.png`.
    func snap(_ app: XCUIApplication, _ name: String) {
        keep(app.screenshot(), name)
    }

    /// The whole screen, not only the app, so a stuck launch or a crash shows too. Filed
    /// as `NN-<prefix>-fail-<name>.png`.
    func fail(_ name: String) {
        keep(XCUIScreen.main.screenshot(), "fail-\(name)")
    }

    private func keep(_ image: XCUIScreenshot, _ name: String) {
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
        guard let directory else { return }
        number += 1
        let file = String(format: "%02d-%@-%@.png", number, prefix, name)
        try? image.pngRepresentation.write(to: directory.appendingPathComponent(file))
    }
}

@MainActor
extension XCUIElement {

    /// Waits until the label reads `text`, exactly or contained in it.
    @discardableResult
    func waitForLabel(
        _ text: String, contains: Bool = false, timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let label = self.label
            if contains ? label.contains(text) : label == text { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }
}
