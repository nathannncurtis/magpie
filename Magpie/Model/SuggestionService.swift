import Foundation

/// Anything that can turn a partial query into suggestion rows.
/// Swap in a stub for tests and previews.
protocol SuggestionProviding: Sendable {
    /// Rows for the field's current text, at most a handful, newest keystrokes only.
    /// Returns an empty list quietly on every failure.
    func suggestions(for query: String, engine: SearchEngine, enabled: Bool) async -> [String]
}

/// Fetches suggestions from the engine's public endpoint: no cookies, a short timeout,
/// a debounce so only settled keystrokes are asked for, and a quiet fall to no rows.
struct SuggestionService: SuggestionProviding {

    /// How long keystrokes are given to settle before the endpoint is asked.
    var debounce: Duration = .milliseconds(150)
    /// The most rows the sheet ever shows.
    var maxRows: Int = 3
    /// The session carries no cookies and gives up quickly.
    let session: URLSession

    init(debounce: Duration = .milliseconds(150), maxRows: Int = 3, session: URLSession? = nil) {
        self.debounce = debounce
        self.maxRows = maxRows
        self.session = session ?? URLSession(configuration: Self.configuration)
    }

    /// Ephemeral by design: nothing is stored, no cookies are sent or kept.
    static let configuration: URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        return configuration
    }()

    func suggestions(for query: String, engine: SearchEngine, enabled: Bool = true) async -> [String] {
        guard enabled, engine.suggestTemplate != nil else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Debounce: a superseded call is canceled while it sleeps and leaves quietly.
        do {
            try await Task.sleep(for: debounce)
        } catch {
            return []
        }
        guard !Task.isCancelled, let url = engine.suggestURL(for: trimmed) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let format = engine.suggestFormat ?? .openSearchList
            return rows(from: Self.parse(data, format: format), for: trimmed)
        } catch {
            return []
        }
    }

    /// Drops echoes of the query itself, duplicates and blanks; caps the count.
    private func rows(from parsed: [String], for query: String) -> [String] {
        var seen: Set<String> = [query.lowercased()]
        var rows: [String] = []
        for suggestion in parsed where !suggestion.isEmpty {
            let key = suggestion.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            rows.append(suggestion)
            if rows.count == maxRows { break }
        }
        return rows
    }

    // MARK: Response shapes

    /// `[query, [suggestion, ...]]`.
    private struct OpenSearchResponse: Decodable {
        let suggestions: [String]

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            _ = try container.decode(String.self)
            suggestions = try container.decode([String].self)
        }
    }

    /// `[{"phrase": "suggestion"}, ...]`.
    private struct PhraseResponse: Decodable {
        let phrases: [String]

        init(from decoder: Decoder) throws {
            let items = try [Item](from: decoder)
            phrases = items.map(\.phrase)
        }

        private struct Item: Decodable {
            let phrase: String
        }
    }

    /// `[{"t": "suggestion", ...}, ...]`.
    private struct TitledResponse: Decodable {
        let titles: [String]

        init(from decoder: Decoder) throws {
            let items = try [Item](from: decoder)
            titles = items.map(\.t)
        }

        private struct Item: Decodable {
            let t: String
        }
    }

    /// Reads one response body in the engine's format. Pure; garbage reads as no rows.
    static func parse(_ data: Data, format: SearchEngine.SuggestFormat) -> [String] {
        let decoder = JSONDecoder()
        switch format {
        case .openSearchList:
            return (try? decoder.decode(OpenSearchResponse.self, from: data))?.suggestions ?? []
        case .phrases:
            return (try? decoder.decode(PhraseResponse.self, from: data))?.phrases ?? []
        case .titled:
            return (try? decoder.decode(TitledResponse.self, from: data))?.titles ?? []
        }
    }
}
