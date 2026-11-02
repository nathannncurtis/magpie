import UIKit

/// Where the search sheet learns that the pasteboard holds a link.
///
/// Asking whether a link is there never raises the system's paste prompt; reading it does,
/// so the sheet only reads once the user taps the row.
@MainActor
protocol PasteboardLinkSource {
    /// Whether the pasteboard probably holds a web address. Reads nothing.
    func hasLink() async -> Bool
    /// The pasteboard's text. Raises the paste prompt, so only a tap calls it.
    func readLink() -> String?
}

/// The system pasteboard.
struct SystemPasteboardLink: PasteboardLinkSource {
    func hasLink() async -> Bool {
        let probe: Set<PartialKeyPath<UIPasteboard.DetectedValues>> = [\.probableWebURL]
        let found = try? await UIPasteboard.general.detectedPatterns(for: probe)
        return found?.contains(\UIPasteboard.DetectedValues.probableWebURL) ?? false
    }

    func readLink() -> String? {
        UIPasteboard.general.string
    }
}

/// A pasteboard with fixed contents, for previews and the UI tests.
struct FixedPasteboardLink: PasteboardLinkSource {
    var value: String?

    func hasLink() async -> Bool { value != nil }
    func readLink() -> String? { value }
}

/// What the address field draws on besides the engine: the user's own hosts for inline
/// completion, and the pasteboard.
struct AddressAssist {
    var userHosts: [String] = []
    var pasteboard: any PasteboardLinkSource = SystemPasteboardLink()
}
