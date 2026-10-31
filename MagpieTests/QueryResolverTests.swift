import Foundation
import Testing

@testable import Magpie

@Suite("QueryResolver")
struct QueryResolverTests {

    @Test("full URLs with a scheme open as themselves")
    func explicitURLs() {
        let cases = [
            "https://quietweb.org",
            "http://example.com",
            "HTTPS://EXAMPLE.COM/PAGE",
            "https://example.com/a/b?x=1&y=2#frag",
            "ftp://files.example.com/pub",
        ]
        for input in cases {
            let resolution = QueryResolver.resolve(input, engine: .default)
            #expect(resolution == .url(URL(string: input)!), "failed for \(input)")
        }
    }

    @Test("bare hosts gain https")
    func bareHosts() {
        let cases = [
            "quietweb.org": "https://quietweb.org",
            "quietweb.org/notes/slow-web": "https://quietweb.org/notes/slow-web",
            "example.com?q=cars": "https://example.com?q=cars",
            "example.com#top": "https://example.com#top",
            "node.js": "https://node.js",
            "example.com.": "https://example.com.",
            "sub.domain.example.co.uk": "https://sub.domain.example.co.uk",
            "localhost": "https://localhost",
            "localhost:8080": "https://localhost:8080",
            "localhost:8080/admin": "https://localhost:8080/admin",
            "192.168.1.4": "https://192.168.1.4",
            "10.0.0.2:9000/x?y=1": "https://10.0.0.2:9000/x?y=1",
            "[::1]:8080": "https://[::1]:8080",
            "[2607:f8b0:4004:800::200e]": "https://[2607:f8b0:4004:800::200e]",
        ]
        for (input, expected) in cases {
            let resolution = QueryResolver.resolve(input, engine: .default)
            #expect(resolution.map(urlString) == expected, "failed for \(input)")
        }
    }

    @Test("host shapes that are really searches")
    func searchShaped() {
        let cases = [
            "node.js tutorial",
            "e.g.",
            "e.g. apples",
            "what is a host",
            "münchen",
            "example",
            "a..b",
            "-leadinghyphen.org",
            "trailinghyphen-.org",
            "example.c",
            "example.1a",
            "192.168.1.256",
            "192.168.01.1",
            "1.2.3",
            "http://",
            "https:///only/a/path",
            "::1",
            "localhost:notaport",
            "example.com:99999",
        ]
        for input in cases {
            let resolution = QueryResolver.resolve(input, engine: .default)
            #expect(resolution == .search(input), "failed for \(input)")
        }
    }

    @Test("javascript: and friends are never opened")
    func unsafeSchemes() {
        let cases = [
            "javascript:alert(1)",
            "JavaScript:alert(1)",
            "data:text/html,<h1>hi</h1>",
            "file:///etc/passwd",
            "tel:+15551234567",
            "fake-scheme://example.com",
            "about:config",
            "about:credits",
        ]
        for input in cases {
            #expect(QueryResolver.resolve(input, engine: .default) == .search(input), "failed for \(input)")
        }
    }

    @Test("about:blank opens")
    func aboutBlank() {
        #expect(QueryResolver.resolve("about:blank", engine: .default) == .url(URL(string: "about:blank")!))
        #expect(QueryResolver.resolve("ABOUT:BLANK", engine: .default) == .url(URL(string: "about:blank")!))
    }

    @Test("whitespace trims, and interior whitespace searches")
    func whitespace() {
        #expect(QueryResolver.resolve("   ", engine: .default) == nil)
        #expect(QueryResolver.resolve("\n\t", engine: .default) == nil)
        #expect(
            QueryResolver.resolve("  quietweb.org  ", engine: .default)
                == .url(URL(string: "https://quietweb.org")!))
        #expect(QueryResolver.resolve("quiet web.org", engine: .default) == .search("quiet web.org"))
    }

    @Test("non-ASCII hosts convert to punycode")
    func idn() {
        #expect(
            urlString(QueryResolver.resolve("bücher.de", engine: .default)) == "https://xn--bcher-kva.de")
        #expect(
            urlString(QueryResolver.resolve("münchen.de/pfad", engine: .default))
                == "https://xn--mnchen-3ya.de/pfad")
    }

    @Test("a search builds a URL on the chosen engine")
    func searchResolution() {
        let engine = SearchEngine.builtins[1]  // Google
        let resolution = QueryResolver.resolve("quiet web", engine: engine)
        #expect(resolution == .search("quiet web"))
        #expect(engine.searchURL(for: "quiet web")?.absoluteString == "https://www.google.com/search?q=quiet%20web")
    }

    // MARK: Edge cases

    @Test(
        "edge inputs that open as addresses",
        arguments: [
            ("example.com", "https://example.com"),
            ("sub.example.co.uk", "https://sub.example.co.uk"),
            ("www.example.com", "https://www.example.com"),
            ("Example.COM/Path", "https://example.com/Path"),
            ("example.com:8443/a/b?x=1&y=2#f", "https://example.com:8443/a/b?x=1&y=2#f"),
            ("github.com/foo", "https://github.com/foo"),
            ("example.com/🕊", "https://example.com/%F0%9F%95%8A"),
            ("localhost:3000", "https://localhost:3000"),
            ("LOCALHOST:3000", "https://localhost:3000"),
            ("Localhost", "https://localhost"),
            ("localhost/path", "https://localhost/path"),
            ("127.0.0.1:8080", "https://127.0.0.1:8080"),
            ("1.1.1.1", "https://1.1.1.1"),
            ("[::1]", "https://[::1]"),
            ("[::1]:8080/x", "https://[::1]:8080/x"),
            ("xn--bcher-kva.de", "https://xn--bcher-kva.de"),
            ("BÜCHER.DE", "https://xn--bcher-kva.de"),
            ("https://例え.jp", "https://xn--r8jz45g.jp"),
            ("HTTPS://example.com", "HTTPS://example.com"),
            ("http://localhost:3000", "http://localhost:3000"),
            ("  example.com\n", "https://example.com"),
            ("\n\nexample.com\r\n\t", "https://example.com"),
            // No TLD list: any alphabetic tail reads as one, as with node.js.
            ("file.txt", "https://file.txt"),
        ])
    func edgeAddresses(input: String, expected: String) {
        #expect(urlString(QueryResolver.resolve(input, engine: .default)) == expected)
    }

    @Test(
        "edge inputs that search",
        arguments: [
            "search",
            "example.com is down",
            "what is 3.5 in cm",
            "3.5",
            "2+2",
            "c#",
            "100%",
            "🕊",
            "🕊.com",
            "user@example.com",
            "example.com/a b",
            "https://example.com is down",
            "example.com:",
            "[::1]x",
            "mailto:me@example.com",
        ])
    func edgeSearches(input: String) {
        #expect(QueryResolver.resolve(input, engine: .default) == .search(input))
    }

    @Test("pasted multi-line text searches as one line")
    func multiLine() {
        #expect(
            QueryResolver.resolve("line one\nline two", engine: .default) == .search("line one line two"))
        #expect(
            QueryResolver.resolve("example.com\r\nexample.org", engine: .default)
                == .search("example.com example.org"))
        #expect(
            QueryResolver.resolve("  first \n\n  second\tthird\n", engine: .default)
                == .search("first second third"))
        // Plain interior spaces stay as typed.
        #expect(QueryResolver.resolve("two  spaces", engine: .default) == .search("two  spaces"))
    }

    @Test("names longer than DNS allows search")
    func dnsLengths() {
        let longLabel = String(repeating: "a", count: 64) + ".com"
        #expect(QueryResolver.resolve(longLabel, engine: .default) == .search(longLabel))
        let maxLabel = String(repeating: "a", count: 63) + ".com"
        #expect(urlString(QueryResolver.resolve(maxLabel, engine: .default)) == "https://" + maxLabel)
        let longHost = Array(repeating: String(repeating: "a", count: 60), count: 5).joined(separator: ".") + ".com"
        #expect(QueryResolver.resolve(longHost, engine: .default) == .search(longHost))
    }

    @Test("very long input searches and still builds a URL")
    func veryLongInput() {
        let words = Array(repeating: "magpie", count: 2_000).joined(separator: " ")
        #expect(QueryResolver.resolve(words, engine: .default) == .search(words))
        #expect(SearchEngine.default.searchURL(for: words) != nil)
        let token = String(repeating: "x", count: 10_000)
        #expect(QueryResolver.resolve(token, engine: .default) == .search(token))
    }

    private func urlString(_ resolution: QueryResolution?) -> String? {
        guard case .url(let url)? = resolution else { return nil }
        return url.absoluteString
    }
}
