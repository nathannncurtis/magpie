import Foundation
import Testing

@testable import Magpie

@Suite("SearchEngine")
struct SearchEngineTests {

    @Test("the picker's engines, in order, with DuckDuckGo first")
    func pickerOrder() {
        #expect(
            SearchEngine.builtins.map(\.displayName) == [
                "DuckDuckGo", "Google", "Brave Search", "Kagi", "Ecosia", "Startpage", "Bing",
            ])
        #expect(SearchEngine.default == SearchEngine.builtins[0])
        #expect(SearchEngine.default.displayName == "DuckDuckGo")
    }

    @Test("only engines with a public suggest endpoint carry one")
    func suggestEndpoints() {
        let withEndpoint = Set(SearchEngine.builtins.filter { $0.suggestTemplate != nil }.map(\.id))
        #expect(withEndpoint == ["duckduckgo", "google", "brave", "kagi"])
        for engine in SearchEngine.builtins {
            #expect((engine.suggestTemplate != nil) == (engine.suggestFormat != nil))
            if let template = engine.suggestTemplate {
                #expect(template.contains("%s"))
            }
        }
    }

    @Test("every search URL template carries the placeholder and a host")
    func templates() {
        for engine in SearchEngine.builtins {
            #expect(engine.searchTemplate.contains("%s"))
            #expect(engine.searchURL(for: "x")?.host != nil, "no host for \(engine.id)")
        }
    }

    @Test("queries are encoded so they cannot break the URL apart")
    func escaping() {
        let raw = "a&b#c+d e🕊"
        for engine in SearchEngine.builtins {
            let url = engine.searchURL(for: raw)
            #expect(url != nil, "no url for \(engine.id)")
            guard let url,
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems
            else {
                Issue.record("no query items for \(engine.id)")
                continue
            }
            let value = items.first?.value
            #expect(value == raw, "query did not round-trip for \(engine.id): \(String(describing: value))")
            #expect(!url.absoluteString.contains("a&b#c+d"), "unencoded characters leaked for \(engine.id)")
        }
    }

    @Test("specific encodings")
    func specificEncodings() {
        let duckduckgo = SearchEngine.builtins[0]
        #expect(
            duckduckgo.searchURL(for: "a&b#c+d")?.absoluteString
                == "https://duckduckgo.com/?q=a%26b%23c%2Bd")
        #expect(
            duckduckgo.searchURL(for: "two words")?.absoluteString
                == "https://duckduckgo.com/?q=two%20words")
        #expect(
            duckduckgo.searchURL(for: "🕊")?.absoluteString
                == "https://duckduckgo.com/?q=%F0%9F%95%8A")
    }

    @Test("the Other engine comes from a validated search URL")
    func otherEngine() {
        let other = SearchEngine.other(template: "https://example.org/search?q=%s&safe=1")
        #expect(other != nil)
        #expect(other?.displayName == "Other")
        #expect(other?.suggestTemplate == nil)
        #expect(
            other?.searchURL(for: "quiet web")?.absoluteString
                == "https://example.org/search?q=quiet%20web&safe=1")

        #expect(SearchEngine.other(template: "https://example.org/search") == nil)
        #expect(SearchEngine.other(template: "javascript:alert(1)//%s") == nil)
        #expect(SearchEngine.other(template: "not a url %s") == nil)
        #expect(SearchEngine.other(template: "  ") == nil)
        #expect(SearchEngine.other(template: "  https://example.org/?q=%s  ") != nil)
    }

    @Test("an Other URL typed without a scheme is taken as https")
    func otherWithoutScheme() {
        #expect(
            SearchEngine.other(template: "search.example/?q=%s")?.searchTemplate
                == "https://search.example/?q=%s")
        #expect(
            SearchEngine.other(template: "example.org:8080/find?q=%s")?.searchTemplate
                == "https://example.org:8080/find?q=%s")
        #expect(
            SearchEngine.other(template: "http://example.org/?q=%s")?.searchTemplate
                == "http://example.org/?q=%s")
        #expect(SearchEngine.other(template: "search.example/") == nil)
        #expect(SearchEngine.other(template: "ftp://example.org/?q=%s") == nil)
    }

    @Test("suggest URLs substitute the same way")
    func suggestURLs() {
        let duckduckgo = SearchEngine.builtins[0]
        #expect(
            duckduckgo.suggestURL(for: "car & bike")?.absoluteString
                == "https://duckduckgo.com/ac/?q=car%20%26%20bike&type=list")
        #expect(SearchEngine.builtins[4].suggestURL(for: "anything") == nil)
    }

    @Test("every engine's results page gives the query back")
    func resultsQueries() {
        for engine in SearchEngine.builtins {
            guard let url = engine.searchURL(for: "magpie test") else {
                Issue.record("no url for \(engine.id)")
                continue
            }
            #expect(
                engine.resultsQuery(for: url) == "magpie test", "no query for \(engine.id)")
        }
    }

    @Test("a results query with the encoded characters round-trips")
    func resultsQueryEscaping() {
        let raw = "a&b#c+d e🕊"
        for engine in SearchEngine.builtins {
            guard let url = engine.searchURL(for: raw) else {
                Issue.record("no url for \(engine.id)")
                continue
            }
            #expect(engine.resultsQuery(for: url) == raw, "no query for \(engine.id)")
        }
    }

    @Test("the Other engine's results page gives the query back")
    func otherResultsQuery() {
        let other = SearchEngine.other(template: "https://example.org/search?q=%s&safe=1")
        guard let other, let url = other.searchURL(for: "quiet web") else {
            Issue.record("no other engine url")
            return
        }
        #expect(other.resultsQuery(for: url) == "quiet web")
        #expect(
            other.resultsQuery(
                for: URL(string: "https://example.org/search?q=&safe=1")!) == nil)
    }

    @Test("a page that is not the engine's results page holds no query")
    func nonResultsPages() {
        let duckduckgo = SearchEngine.builtins[0]
        let google = SearchEngine.builtins[1]

        // The engine's own site, off the results path.
        #expect(
            duckduckgo.resultsQuery(for: URL(string: "https://duckduckgo.com/about")!) == nil)
        // Another engine's results page.
        guard let foreign = google.searchURL(for: "magpie test") else {
            Issue.record("no google url")
            return
        }
        #expect(duckduckgo.resultsQuery(for: foreign) == nil)

        // A page carrying the template's own placeholder, raw or encoded.
        #expect(
            duckduckgo.resultsQuery(for: URL(string: "https://duckduckgo.com/?q=%s")!) == nil)
        #expect(
            duckduckgo.resultsQuery(for: URL(string: "https://duckduckgo.com/?q=%25s")!) == nil)
        // A query that trims away to nothing.
        guard let blank = duckduckgo.searchURL(for: " ") else {
            Issue.record("no blank url")
            return
        }
        #expect(duckduckgo.resultsQuery(for: blank) == nil)
    }

    @Test("an Other URL's scheme is read without regard to case")
    func otherSchemeCase() {
        let other = SearchEngine.other(template: "HTTPS://example.org/?q=%s")
        #expect(other != nil)
        #expect(other?.searchURL(for: "a b")?.host == "example.org")
        #expect(SearchEngine.other(template: "Http://example.org/?q=%s") != nil)
    }

    @Test("an Other URL with no host, or another scheme, is turned away")
    func otherRejects() {
        #expect(SearchEngine.other(template: "https:///?q=%s") == nil)
        #expect(SearchEngine.other(template: "mailto:%s") == nil)
        #expect(SearchEngine.other(template: "file:///search?q=%s") == nil)
        #expect(SearchEngine.other(template: "https://example.org/?q=\t%s") == nil)
    }

    @Test("an Other URL keeps every placeholder it has")
    func otherRepeatedPlaceholder() {
        let other = SearchEngine.other(template: "https://example.org/?q=%s&again=%s")
        #expect(
            other?.searchURL(for: "x y")?.absoluteString
                == "https://example.org/?q=x%20y&again=x%20y")
    }

    @Test(
        "each engine encodes +, &, #, %, spaces, line breaks and unicode",
        arguments: SearchEngine.builtins)
    func encodingPerEngine(engine: SearchEngine) {
        let encoded = "a%2Bb%20%26%20c%23d%20100%25%20%C3%A9%0Ax%20%F0%9F%95%8A"
        let expected = engine.searchTemplate.replacingOccurrences(of: "%s", with: encoded)
        #expect(engine.searchURL(for: "a+b & c#d 100% é\nx 🕊")?.absoluteString == expected)
        if let suggest = engine.suggestTemplate {
            #expect(
                engine.suggestURL(for: "a+b & c#d 100% é\nx 🕊")?.absoluteString
                    == suggest.replacingOccurrences(of: "%s", with: encoded))
        }
    }

    @Test("a query holding the placeholder itself is encoded, not re-substituted")
    func placeholderInQuery() {
        #expect(
            SearchEngine.default.searchURL(for: "%s and %s")?.absoluteString
                == "https://duckduckgo.com/?q=%25s%20and%20%25s")
        #expect(SearchEngine.default.resultsQuery(for: SearchEngine.default.searchURL(for: "100% %s")!) == "100% %s")
    }

    @Test("an Other template encodes the same way, wherever the placeholder sits")
    func otherEncoding() {
        let path = SearchEngine.other(template: "https://example.org/find/%s")
        #expect(path?.searchURL(for: "a/b c?")?.absoluteString == "https://example.org/find/a%2Fb%20c%3F")
        let query = SearchEngine.other(template: "https://example.org/?q=%s&lang=en")
        #expect(
            query?.searchURL(for: "bücher & co")?.absoluteString
                == "https://example.org/?q=b%C3%BCcher%20%26%20co&lang=en")
    }
}
