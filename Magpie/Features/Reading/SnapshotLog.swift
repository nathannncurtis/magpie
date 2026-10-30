import Foundation
import os

/// The snapshot pipeline's own record: a line per capture attempt, per path, while the
/// captures are being diagnosed on the simulator. Under the UI tests the lines also land
/// beside the run's shots, through the directory the test hands the app — the process's
/// own stderr never reaches the run's log. The two flows keep separate files, so one
/// run's lines survive the other's.
enum SnapshotLog {

    private static let logger = Logger(
        subsystem: "com.magpiebrowser.Magpie", category: "snapshot")

    private static let scheme = UITestEnvironment.colorScheme == .dark ? "dark" : "light"

    /// Where the test run asked for the log; nil outside a run that asked.
    private static let logURL = ProcessInfo.processInfo.environment["MAGPIE_SHOTS_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
            .appendingPathComponent("snapshot-\(scheme).log")
    }

    static func event(_ text: String) {
        logger.notice("\(text, privacy: .public)")
        guard let url = logURL else { return }
        append((scheme + " " + text + "\n").data(using: .utf8), to: url)
    }

    /// Appends to the log, making it first if it is not there yet.
    private static func append(_ line: Data?, to url: URL) {
        guard let line else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }
}
