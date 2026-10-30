import Foundation

/// One anchor found on a results page, before filtering.
struct RawAnchor: Equatable, Sendable {
    var href: String
    var className: String
}

/// Scans anchors out of results-page HTML. Kept in Swift so the whole result
/// filter is testable against saved fixtures.
enum AnchorScan {

    // Regex is deeply immutable but not marked Sendable in this toolchain.
    nonisolated(unsafe) private static let anchorPattern = #/<a\b([^>]*)>/#
    nonisolated(unsafe) private static let attributePattern =
        #/(?i)([a-z-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s]+))/#

    static func anchors(inHTML html: String) -> [RawAnchor] {
        anchorsWithRanges(inHTML: html).map(\.anchor)
    }

    /// Each anchor with where it sat in the page, for the filters that work by
    /// position.
    static func anchorsWithRanges(inHTML html: String) -> [(anchor: RawAnchor, range: Range<String.Index>)] {
        html.matches(of: anchorPattern).map { match in
            let tag = String(match.1)
            return (
                anchor: RawAnchor(
                    href: attribute("href", inTag: tag) ?? "",
                    className: attribute("class", inTag: tag) ?? ""),
                range: match.range
            )
        }
    }

    static func attribute(_ name: String, inTag tag: String) -> String? {
        for match in tag.matches(of: attributePattern) {
            guard match.1.lowercased() == name else { continue }
            for value in [match.2, match.3, match.4] {
                if let value { return String(value) }
            }
        }
        return nil
    }
}

/// The spans of a results page an ad block covers: a container the engine marks
/// as paid, whose anchors are ads even when the anchors carry no marker of
/// their own.
enum AdBlocks {

    // Regex is deeply immutable but not marked Sendable in this toolchain.
    nonisolated(unsafe) private static let tagPattern =
        #/<(\/?)(div|article|section|aside|li|ul)\b([^>]*)>/#

    static func ranges(inHTML html: String) -> [Range<String.Index>] {
        var stack: [(name: Substring, ad: Bool, start: String.Index)] = []
        var out: [Range<String.Index>] = []
        for match in html.matches(of: tagPattern) {
            guard match.1.isEmpty else {
                if let index = stack.lastIndex(where: { $0.name == match.2 }) {
                    let opened = stack.remove(at: index)
                    if opened.ad {
                        out.append(opened.start..<match.range.upperBound)
                    }
                }
                continue
            }
            let tag = String(match.3)
            let className = AnchorScan.attribute("class", inTag: tag) ?? ""
            stack.append(
                (
                    name: match.2,
                    ad: OrganicLinkFilter.isAdClassed(className),
                    start: match.range.lowerBound
                ))
        }
        for opened in stack where opened.ad {
            out.append(opened.start..<html.endIndex)
        }
        return out
    }
}

/// Keeps the organic results: unwraps the engine's redirects and drops ads, the
/// engine's own pages, its verticals, and PDFs.
enum OrganicLinkFilter {

    /// Classes that mark an ad, paid placement, or sponsored result.
    private static let adTokens: Set<String> = [
        "ad", "ads", "advert", "adverts", "advertisement", "advertisements",
        "sponsored", "paid", "promoted", "result--ad", "result--paid",
    ]

    /// The organic links straight off a results page: anchors outside every ad
    /// block, in page order.
    static func links(inHTML html: String, base: URL, engineHosts: Set<String>) -> [URL] {
        let ads = AdBlocks.ranges(inHTML: html)
        let anchors = AnchorScan.anchorsWithRanges(inHTML: html).compactMap { anchor, range in
            ads.contains(where: { $0.contains(range.lowerBound) }) ? nil : anchor
        }
        return links(from: anchors, base: base, engineHosts: engineHosts)
    }

    static func links(from anchors: [RawAnchor], base: URL, engineHosts: Set<String>) -> [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        for anchor in anchors {
            guard let link = organicLink(anchor, base: base, engineHosts: engineHosts) else { continue }
            let key = Self.key(link)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(link)
        }
        return out
    }

    static func isAdClassed(_ className: String) -> Bool {
        className.split(whereSeparator: \.isWhitespace).contains { token in
            let value = token.lowercased()
            return adTokens.contains(value)
                || value.hasPrefix("result--ad") || value.hasPrefix("result--paid")
                || value.contains("sponsored")
        }
    }

    static func hostIsEngine(_ host: String, engineHosts: Set<String>) -> Bool {
        engineHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func organicLink(
        _ anchor: RawAnchor, base: URL, engineHosts: Set<String>
    ) -> URL? {
        guard !anchor.href.isEmpty, !isAdClassed(anchor.className) else { return nil }
        guard let resolved = URL(string: anchor.href, relativeTo: base)?.absoluteURL else { return nil }
        guard var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        guard let host = components.host?.lowercased() else { return nil }

        // The engine's own host: a redirect to unwrap, otherwise its own page,
        // a vertical, or an ad tracker.
        if hostIsEngine(host, engineHosts: engineHosts) {
            guard let target = redirectTarget(components) else { return nil }
            var unwrapped = target
            if URL(string: unwrapped) == nil {
                unwrapped = unwrapped.replacingOccurrences(of: "+", with: "%20")
            }
            return organicLink(
                RawAnchor(href: unwrapped, className: ""), base: base, engineHosts: engineHosts)
        }

        guard !components.path.lowercased().hasSuffix(".pdf") else { return nil }
        components.host = host
        return components.url
    }

    /// The target inside the engine's redirect link, when the link is one.
    private static func redirectTarget(_ components: URLComponents) -> String? {
        guard components.path == "/l" || components.path == "/l/" else { return nil }
        return components.queryItems?.first { $0.name == "uddg" }?.value
    }

    private static func key(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        let scheme = components?.scheme?.lowercased() ?? ""
        let host = components?.host?.lowercased() ?? ""
        let query = components?.percentEncodedQuery.map { "?" + $0 } ?? ""
        return scheme + "://" + host + (components?.path ?? "") + query
    }
}

/// What a Skim run uses to find the top results for a query.
protocol ResultFinding: Sendable {
    /// The top organic result links, or nil when the results page itself could
    /// not be read.
    func topResultLinks(query: String, engine: SearchEngine) async -> [URL]?
}

/// Reads a results page offscreen and keeps its organic links. Only the HTML
/// results endpoint parses today; whatever the app's engine is set to, Skim
/// reads that endpoint.
struct ResultFinder: ResultFinding {

    /// The HTML results endpoint: one page, no scripts to wait for.
    static let searchURL =
        URL(string: "https://html.duckduckgo.com/html/") ?? URL(fileURLWithPath: "/")

    /// The engine's own host: redirects to unwrap, its pages and verticals to drop.
    static let engineHosts: Set<String> = ["duckduckgo.com"]

    var timeout: TimeInterval = 10

    func topResultLinks(query: String, engine: SearchEngine) async -> [URL]? {
        guard
            var components = URLComponents(
                url: Self.searchURL, resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return nil }

        guard
            let html = await OffscreenPage.load(
                url: url, timeout: timeout, script: Self.htmlScript)
        else { return nil }
        return OrganicLinkFilter.links(inHTML: html, base: url, engineHosts: Self.engineHosts)
    }

    static let htmlScript = "document.body ? document.body.innerHTML : \"\""
}
