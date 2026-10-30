import Foundation

/// The tabs screen strings, gathered in one place.
enum TabsCopy {
    /// "1 open", "3 open".
    static func openCount(_ count: Int) -> String {
        String(localized: "\(count) open")
    }

    /// "Archived · 12".
    static func archived(_ count: Int) -> String {
        String(localized: "Archived · \(count)")
    }
}
