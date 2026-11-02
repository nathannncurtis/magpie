import Foundation

/// Magpie's own URL scheme: `magpie://open?url=<encoded>` opens an address in a new tab,
/// `magpie://search?q=<encoded>` runs a search, and `magpie://search` alone opens the search
/// sheet. The share extension and the widgets build these; the app reads them.
///
/// Foundation only, so the extension compiles this file too.
enum MagpieLink: Equatable {
    /// A web address to open in a new tab.
    case open(URL)
    /// A search to run, or the empty search sheet when there is no query.
    case search(String?)

    static let scheme = "magpie"

    /// Reads a link; nil for anything that is not one of Magpie's own, or is malformed.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let value = { (name: String) -> String? in
            components.queryItems?.first(where: { $0.name == name })?.value
        }
        switch components.host?.lowercased() {
        case "open":
            guard let raw = value("url"),
                let target = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
                ["http", "https"].contains(target.scheme?.lowercased()),
                !(target.host ?? "").isEmpty
            else { return nil }
            self = .open(target)
        case "search":
            let query = value("q")?.trimmingCharacters(in: .whitespacesAndNewlines)
            self = .search(query?.isEmpty == false ? query : nil)
        default:
            return nil
        }
    }

    /// The link that opens `page` in Magpie.
    static func openURL(for page: URL) -> URL? {
        URL(string: "\(scheme)://open?url=\(encoded(page.absoluteString))")
    }

    /// The link that searches for `query` in Magpie.
    static func searchURL(for query: String) -> URL? {
        URL(string: "\(scheme)://search?q=\(encoded(query))")
    }

    /// Everything but unreserved characters is escaped, so a `&`, `=` or `+` inside a
    /// value cannot be read as part of the query's own structure.
    private static func encoded(_ text: String) -> String {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

/// The home-screen quick actions, by the type string in Info.plist.
enum ShortcutAction: String, Equatable, Sendable {
    case newTab = "com.magpiebrowser.Magpie.newTab"
    case newPrivateTab = "com.magpiebrowser.Magpie.newPrivateTab"
    case search = "com.magpiebrowser.Magpie.search"
}
