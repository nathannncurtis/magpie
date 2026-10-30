import Foundation
import os

/// The snapshot pipeline's own record: a line per capture attempt, per path, while the
/// captures are being diagnosed on the simulator. Under the UI tests the line also goes
/// to stderr, which the test run collects verbatim.
enum SnapshotLog {

    private static let logger = Logger(
        subsystem: "com.magpiebrowser.Magpie", category: "snapshot")

    static func event(_ text: String) {
        logger.notice("\(text, privacy: .public)")
        if UITestEnvironment.isUITesting {
            FileHandle.standardError.write(Data("snapshot: \(text)\n".utf8))
        }
    }
}
