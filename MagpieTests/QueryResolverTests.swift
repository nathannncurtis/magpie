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

    private func urlString(_ resolution: QueryResolution?) -> String? {
        guard case .url(let url)? = resolution else { return nil }
        return url.absoluteString
    }
}
