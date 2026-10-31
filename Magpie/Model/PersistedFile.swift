import Foundation
import os

/// Shared handling for the JSON files Magpie keeps on disk.
enum PersistedFile {

    private static let logger = Logger(subsystem: "Magpie", category: "Persistence")

    /// Decodes the file, or moves it aside as `<name>.corrupt` when it will not decode,
    /// so the store starts empty without its next save overwriting what was there.
    /// A missing or unreadable file returns nil and is left alone.
    static func decode<T: Decodable>(
        _ type: T.Type, from url: URL, decoder: JSONDecoder = JSONDecoder()
    ) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            quarantine(url, error: error)
            return nil
        }
    }

    /// Moves a file that would not decode to `<name>.corrupt`, replacing an older one.
    static func quarantine(_ url: URL, error: any Error) {
        logger.error("\(url.lastPathComponent, privacy: .public) would not decode: \(error, privacy: .public)")
        let backup = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
    }

    /// Logs a write that failed (disk full, for one); the in-memory state stays as it is.
    static func logWriteFailure(_ url: URL, error: any Error) {
        logger.error("\(url.lastPathComponent, privacy: .public) write failed: \(error, privacy: .public)")
    }

    /// Marks a cache directory so it is left out of iCloud and device backups.
    static func excludeFromBackup(_ directory: URL) {
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
