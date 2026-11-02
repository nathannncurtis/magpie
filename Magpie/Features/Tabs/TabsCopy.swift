import Foundation

/// The tabs screen strings, gathered in one place.
enum TabsCopy {
    /// "1 open", "3 open".
    static func openCount(_ count: Int) -> String {
        String(localized: "\(count) open")
    }

    /// The undo capsule's two words.
    static let closed = String(localized: "Closed")
    static let undo = String(localized: "Undo")

    /// What VoiceOver reads for the whole capsule.
    static let undoClose = String(localized: "Tab closed. Undo")

    /// "Archived · 12".
    static func archived(_ count: Int) -> String {
        String(localized: "Archived · \(count)")
    }
}
