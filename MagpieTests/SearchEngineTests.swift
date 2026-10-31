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

    @Test("suggest URLs substitute the same way")
    func suggestURLs() {
        let duckduckgo = SearchEngine.builtins[0]
        #expect(
            duckduckgo.suggestURL(for: "car & bike")?.absoluteString
                == "https://duckduckgo.com/ac/?q=car%20%26%20bike&type=list")
        #expect(SearchEngine.builtins[4].suggestURL(for: "anything") == nil)
    }
}
