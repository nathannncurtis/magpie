import Foundation

/// Finds the open tab that already shows an address, so opening a saved page twice
/// brings the tab back instead of making another.
enum TabMatch {

    /// The tab showing `url`, in the given mode. Addresses compare by scheme, host, path
    /// and query; the fragment and a trailing slash don't count. The current tab wins a
    /// tie, then the first in stack order. Archived tabs never match.
    static func existingTab(
        for url: URL, in tabs: [Tab], isPrivate: Bool, current: Tab.ID? = nil
    ) -> Tab.ID? {
        guard let wanted = key(for: url) else { return nil }
        let matches = tabs.filter { tab in
            tab.isPrivate == isPrivate && tab.archivedAt == nil
                && tab.url.flatMap(key(for:)) == wanted
        }
        return matches.first { $0.id == current }?.id ?? matches.first?.id
    }

    /// The address with what doesn't tell pages apart left out; nil for one with no host.
    static func key(for url: URL) -> String? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let host = parts.host?.lowercased(), !host.isEmpty
        else { return nil }
        let scheme = parts.scheme?.lowercased() ?? ""
        var path = parts.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        parts.fragment = nil
        let query = parts.percentEncodedQuery.map { "?\($0)" } ?? ""
        let port = parts.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)\(path)\(query)"
    }
}
