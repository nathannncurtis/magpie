import Foundation

/// A search engine from the first-launch picker, with its query and suggest endpoints.
struct SearchEngine: Equatable, Identifiable, Sendable {

    /// The layout of a suggest endpoint's response.
    enum SuggestFormat: Equatable, Sendable {
        /// `[query, [suggestion, ...]]`, the OpenSearch convention.
        case openSearchList
        /// `[{"phrase": "suggestion"}, ...]`.
        case phrases
        /// `[{"t": "suggestion", ...}, ...]`.
        case titled
    }

    /// Stable identity, also the picker's tile key.
    let id: String
    /// The name shown in the picker and in the field's engine tag.
    let displayName: String
    /// The search URL template, with `%s` where the encoded query goes.
    let searchTemplate: String
    /// The suggest endpoint with `%s`, when the engine has a public one.
    let suggestTemplate: String?
    /// The layout of the suggest endpoint's response.
    let suggestFormat: SuggestFormat?

    /// The built-in engines, in the picker's fixed order: DuckDuckGo, Google, Brave Search,
    /// Kagi, Ecosia, Startpage, Bing. "Other" is built from a user-supplied URL.
    static let builtins: [SearchEngine] = [
        SearchEngine(
            id: "duckduckgo", displayName: "DuckDuckGo",
            searchTemplate: "https://duckduckgo.com/?q=%s",
            suggestTemplate: "https://duckduckgo.com/ac/?q=%s&type=list",
            suggestFormat: .openSearchList),
        SearchEngine(
            id: "google", displayName: "Google",
            searchTemplate: "https://www.google.com/search?q=%s",
            suggestTemplate: "https://suggestqueries.google.com/complete/search?client=firefox&q=%s",
            suggestFormat: .openSearchList),
        SearchEngine(
            id: "brave", displayName: "Brave Search",
            searchTemplate: "https://search.brave.com/search?q=%s",
            suggestTemplate: "https://search.brave.com/api/suggest?q=%s",
            suggestFormat: .openSearchList),
        SearchEngine(
            id: "kagi", displayName: "Kagi",
            searchTemplate: "https://kagi.com/search?q=%s",
            suggestTemplate: "https://kagi.com/autosuggest?q=%s",
            suggestFormat: .titled),
        SearchEngine(
            id: "ecosia", displayName: "Ecosia",
            searchTemplate: "https://www.ecosia.org/search?q=%s",
            suggestTemplate: nil,
            suggestFormat: nil),
        SearchEngine(
            id: "startpage", displayName: "Startpage",
            searchTemplate: "https://www.startpage.com/sp/search?query=%s",
            suggestTemplate: nil,
            suggestFormat: nil),
        SearchEngine(
            id: "bing", displayName: "Bing",
            searchTemplate: "https://www.bing.com/search?q=%s",
            suggestTemplate: nil,
            suggestFormat: nil),
    ]

    /// The engine a fresh install searches on.
    static let `default` = builtins[0]

    /// The "Other" engine, from a search URL containing `%s`. Nil unless the URL is a valid
    /// http or https address with the placeholder in it.
    static func other(template: String) -> SearchEngine? {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("%s") else { return nil }
        guard let url = url(fromTemplate: trimmed, inserting: "probe") else { return nil }
        guard url.scheme == "https" || url.scheme == "http", url.host != nil else { return nil }
        return SearchEngine(
            id: "other", displayName: "Other",
            searchTemplate: trimmed,
            suggestTemplate: nil,
            suggestFormat: nil)
    }

    /// The URL of a search for `query`, with the query percent-encoded into the template.
    func searchURL(for query: String) -> URL? {
        Self.url(fromTemplate: searchTemplate, inserting: query)
    }

    /// The URL of the suggest endpoint for `query`.
    func suggestURL(for query: String) -> URL? {
        guard let suggestTemplate else { return nil }
        return Self.url(fromTemplate: suggestTemplate, inserting: query)
    }

    /// The query a results URL holds, when the URL is this engine's results page: the
    /// text between the template's parts around `%s`, decoded. The encoded query can
    /// never hold the URL's own separators, so the split point is fixed.
    func resultsQuery(for url: URL) -> String? {
        guard let placeholder = searchTemplate.range(of: "%s") else { return nil }
        let address = url.absoluteString
        let prefix = String(searchTemplate[..<placeholder.lowerBound])
        let suffix = String(searchTemplate[placeholder.upperBound...])
        guard
            address.hasPrefix(prefix),
            address.hasSuffix(suffix),
            address.count >= prefix.count + suffix.count
        else { return nil }
        let encoded = String(address.dropFirst(prefix.count).dropLast(suffix.count))
        guard let query = encoded.removingPercentEncoding else { return nil }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Substitutes the encoded query for `%s` in a URL template.
    private static func url(fromTemplate template: String, inserting query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: queryAllowed) else {
            return nil
        }
        return URL(string: template.replacingOccurrences(of: "%s", with: encoded))
    }

    /// Unreserved characters only, so `&`, `#`, `+`, spaces and non-ASCII all encode.
    private static let queryAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
}
