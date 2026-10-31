import Foundation
import Testing

@testable import Magpie

@Suite("FilterListConverter")
struct BlockingConverterTests {

    private func blocks(_ text: String) -> [ContentBlockerRule] {
        FilterListConverter.convert(text).blockRules
    }

    private func firstBlock(_ text: String) -> ContentBlockerRule? {
        blocks(text).first
    }

    private func skipped(_ text: String) -> FilterListSkipReason? {
        let stats = FilterListConverter.convert(text).stats
        return stats.skipped.first?.key
    }

    // MARK: Structure

    @Test("comments, headers and blank lines are counted, not converted")
    func commentsAndHeaders() {
        let conversion = FilterListConverter.convert(
            """
            [Adblock Plus 2.0]
            ! a comment

            ! another
            ||ads.example.com^
            """
        )
        #expect(conversion.stats.lines == 5)
        #expect(conversion.stats.comments == 3)
        #expect(conversion.stats.blanks == 1)
        #expect(conversion.stats.rules == 1)
        #expect(conversion.stats.emitted == 1)
        #expect(conversion.blockRules.count == 1)
    }

    // MARK: Network patterns

    @Test("|| anchors to the start of the host and ^ to a separator")
    func domainAnchor() {
        #expect(
            firstBlock("||example.com^")?.trigger.urlFilter
                == "^[a-z][a-z0-9+.-]*://([^/]+\\.)?example\\.com[^a-zA-Z0-9._%-]"
        )
        #expect(firstBlock("||example.com^")?.action.type == "block")
    }

    @Test("| anchors to the URL start and end")
    func urlAnchors() {
        #expect(
            firstBlock("|http://ads.example.com/|")?.trigger.urlFilter
                == "^http://ads\\.example\\.com/$"
        )
    }

    @Test("* is a wildcard and the rest is literal")
    func wildcardsAndLiterals() {
        #expect(firstBlock("tracker*.gif^")?.trigger.urlFilter == "tracker.*\\.gif[^a-zA-Z0-9._%-]")
        #expect(
            firstBlock("a+b(c)d[e]f{g}h$i")?.trigger.urlFilter == "a\\+b\\(c\\)d\\[e\\]f\\{g\\}h\\$i"
        )
    }

    @Test("a literal $ that isn't an option list stays in the pattern")
    func literalDollar() {
        #expect(firstBlock("/banner$value")?.trigger.urlFilter == "/banner\\$value")
        #expect(firstBlock("banner$image")?.trigger.resourceType == ["image"])
    }

    @Test("patterns with spaces or nothing are dropped")
    func invalidPatterns() {
        #expect(skipped("has space$script") == .invalidPattern)
        #expect(skipped("|") == .invalidPattern)
    }

    @Test("regex rules pass through inside WebKit's regex subset")
    func regexRules() {
        #expect(firstBlock("/^ad-server\\.[a-z]+/")?.trigger.urlFilter == "^ad-server\\.[a-z]+")
        #expect(skipped("/^track\\d+/") == .unsupportedRegex)
        #expect(skipped("/^a{2,}/") == .unsupportedRegex)
        #expect(skipped("/cat|dog/") == .unsupportedRegex)
    }

    @Test("regex WebKit rejects is dropped before compile, the rest of the list kept")
    func rejectedRegex() {
        for rule in [
            "/ad(?=s)/",  // lookahead
            "/ad(?!s)/",  // negative lookahead
            "/(a)b\\1/",  // backreference
            "/ad{1,3}/",  // quantifier range
            "/ad\\bx/",  // word boundary
            "/реклама/",  // non-ASCII
            "/a^b/",  // misplaced start anchor
            "/a$b/",  // misplaced end anchor
            "/ad+*/",  // stacked quantifiers
            "/ad()x/",  // empty group
            "/ad[]x/",  // empty class
        ] {
            let conversion = FilterListConverter.convert(rule + "\n||kept.com^")
            #expect(conversion.stats.skipped[.unsupportedRegex] == 1, "\(rule)")
            #expect(conversion.blockRules.count == 1, "\(rule)")
        }
    }

    @Test("anchors and quantifiers inside a class or in place are kept")
    func acceptedRegex() {
        #expect(firstBlock("/^ad[^/]*\\.js$/")?.trigger.urlFilter == "^ad[^/]*\\.js$")
        #expect(firstBlock("/ads[*+?$]/")?.trigger.urlFilter == "ads[*+?$]")
        #expect(firstBlock("/^(ad)+x/")?.trigger.urlFilter == "^(ad)+x")
    }

    @Test("non-ASCII literal patterns match their percent-encoded form")
    func nonASCIILiteral() {
        let filter = firstBlock("/реклама/banner^")?.trigger.urlFilter
        #expect(filter == "/%D1%80%D0%B5%D0%BA%D0%BB%D0%B0%D0%BC%D0%B0/banner[^a-zA-Z0-9._%-]")
        #expect(filter?.allSatisfy(\.isASCII) == true)
    }

    @Test("unsupported syntax on one line doesn't stop the lines after it")
    func unsupportedSyntaxContinues() {
        let conversion = FilterListConverter.convert(
            """
            example.com##+js(set-constant, x, 1)
            ||a.com^$removeparam=utm
            ||b.com^$redirect=noop.js
            example.com##div:has-text(Ad)
            example.com#$#body { color: red }
            ||kept.com^
            ##.kept
            """
        )
        #expect(conversion.blockRules.count == 2)
        #expect(conversion.stats.skipped.values.reduce(0, +) == 5)
    }

    // MARK: Options

    @Test("third-party and first-party map to load-type")
    func partyOptions() {
        #expect(firstBlock("||t.net^$third-party")?.trigger.loadType == ["third-party"])
        #expect(firstBlock("||t.net^$~third-party")?.trigger.loadType == ["first-party"])
        #expect(firstBlock("||t.net^")?.trigger.loadType == nil)
    }

    @Test("domain= maps to if-domain and unless-domain, lowercase with * prefix")
    func domainOption() {
        #expect(
            firstBlock("||t.net^$domain=Example.com|foo.de")?.trigger.ifDomain
                == ["*example.com", "*foo.de"]
        )
        #expect(
            firstBlock("||t.net^$domain=~bar.com")?.trigger.unlessDomain == ["*bar.com"]
        )
        #expect(skipped("||t.net^$domain=a.com|~b.com") == .mixedDomains)
    }

    @Test("resource types map to WebKit's, sorted")
    func resourceTypes() {
        #expect(firstBlock("||cdn.com/ad.js$script,image")?.trigger.resourceType == ["image", "script"])
        #expect(firstBlock("||cdn.com^$popup")?.trigger.resourceType == ["popup"])
        #expect(firstBlock("||cdn.com^$document")?.trigger.resourceType == ["document"])
        #expect(firstBlock("||cdn.com^$stylesheet")?.trigger.resourceType == ["style-sheet"])
        #expect(firstBlock("||cdn.com^$subdocument")?.trigger.resourceType == ["child-document"])
        #expect(firstBlock("||cdn.com^$xhr")?.trigger.resourceType == ["fetch"])
        #expect(firstBlock("||cdn.com^$websocket")?.trigger.resourceType == ["websocket"])
        #expect(firstBlock("||cdn.com^$ping")?.trigger.resourceType == ["ping"])
        #expect(
            firstBlock("||cdn.com^$match-case")?.trigger.urlFilterIsCaseSensitive == true
        )
        #expect(firstBlock("||cdn.com^")?.trigger.urlFilterIsCaseSensitive == nil)
    }

    @Test("a negated type expands to every safe type except it")
    func negatedType() {
        #expect(
            firstBlock("||cdn.com^$~xmlhttprequest")?.trigger.resourceType
                == ["child-document", "font", "image", "media", "other", "ping", "script", "style-sheet", "websocket"]
        )
    }

    @Test("the legacy vocabulary keeps the old resource-type names")
    func legacyVocabulary() {
        let conversion = FilterListConverter.convert(
            """
            ||cdn.com^$stylesheet
            ||cdn.com^$subdocument
            ||cdn.com^$xhr
            ||cdn.com^$websocket
            ||cdn.com^$ping
            """,
            vocabulary: .legacy
        )
        let names = conversion.blockRules.compactMap(\.trigger.resourceType)
        #expect(
            names == [["stylesheet"], ["subdocument"], ["xmlhttprequest"]]
        )
        #expect(conversion.stats.skipped[.unsupportedResourceType] == 2)
        #expect(
            FilterListConverter.convert("||cdn.com^$~xmlhttprequest", vocabulary: .legacy)
                .blockRules.first?.trigger.resourceType
                == ["font", "image", "media", "other", "script", "stylesheet", "subdocument"]
        )
    }

    @Test("options WebKit can't express are counted by reason")
    func unsupportedOptions() {
        #expect(skipped("||x.com^$removeparam=utm") == .removeparam)
        #expect(skipped("||x.com^$redirect=noop.js") == .redirect)
        #expect(skipped("||x.com^$csp=script-src 'none'") == .csp)
        #expect(skipped("||x.com^$rewrite=abp-resource:x") == .unsupportedOption)
        #expect(skipped("||x.com^$method=get") == .unsupportedOption)
        #expect(skipped("||x.com^$header=x-h:1") == .unsupportedOption)
        #expect(skipped("||x.com^$badfilter") == .unsupportedOption)
        #expect(skipped("||x.com^$beacon") == .unsupportedResourceType)
        #expect(skipped("||x.com^$webrtc") == .unsupportedResourceType)
    }

    @Test("important rules stay, as plain blocks")
    func importantKept() {
        #expect(firstBlock("||ads.com^$important")?.action.type == "block")
    }

    // MARK: Exceptions

    @Test("@@ rules become ignore-previous-rules in the exception tail")
    func exceptions() {
        let conversion = FilterListConverter.convert(
            """
            ||ads.example.com^
            @@||fine.example.com^
            """
        )
        #expect(conversion.blockRules.count == 1)
        #expect(conversion.exceptionRules.count == 1)
        #expect(conversion.exceptionRules.first?.action.type == "ignore-previous-rules")
        #expect(
            conversion.exceptionRules.first?.trigger.urlFilter
                == "^[a-z][a-z0-9+.-]*://([^/]+\\.)?fine\\.example\\.com[^a-zA-Z0-9._%-]"
        )
    }

    @Test("@@ with $document whitelists the whole page by host")
    func documentException() {
        let conversion = FilterListConverter.convert("@@||reader.example.com^$document")
        #expect(conversion.exceptionRules.count == 1)
        #expect(conversion.exceptionRules.first?.trigger.urlFilter == ".*")
        #expect(conversion.exceptionRules.first?.trigger.ifDomain == ["*reader.example.com"])
    }

    @Test("cosmetic-only whitelists are dropped")
    func cosmeticWhitelist() {
        #expect(skipped("@@||x.com^$generichide") == .cosmeticWhitelist)
        #expect(skipped("@@||x.com^$elemhide") == .cosmeticWhitelist)
        let conversion = FilterListConverter.convert("@@||x.com^$generichide,document")
        #expect(conversion.exceptionRules.count == 1)
    }

    // MARK: Element hiding

    @Test("generic selectors batch into one css-display-none rule over .*")
    func genericHiding() {
        let rules = blocks(
            """
            ##.ad-banner
            ##.promo
            """
        )
        #expect(rules.count == 1)
        #expect(rules.first?.trigger.urlFilter == ".*")
        #expect(rules.first?.trigger.ifDomain == nil)
        #expect(rules.first?.action.type == "css-display-none")
        #expect(rules.first?.action.selector == ".ad-banner,.promo")
    }

    @Test("domain-scoped selectors get if-domain, exceptions get unless-domain")
    func scopedHiding() {
        #expect(blocks("example.com###promo").first?.trigger.ifDomain == ["*example.com"])
        #expect(
            blocks("example.com,foo.de##.x").first?.trigger.ifDomain == ["*example.com", "*foo.de"]
        )
        #expect(blocks("~excluded.com##.y").first?.trigger.unlessDomain == ["*excluded.com"])
    }

    @Test("IDN domains encode to punycode for if-domain and unless-domain")
    func idnDomains() {
        #expect(blocks("münchen.de##.banner").first?.trigger.ifDomain == ["*xn--mnchen-3ya.de"])
        #expect(firstBlock("||x.com^$domain=中文.cn")?.trigger.ifDomain == ["*xn--fiq665c.cn"])
        #expect(
            firstBlock("||x.com^$domain=~bücher.example")?.trigger.unlessDomain
                == ["*xn--bcher-kva.example"]
        )
        // Mixed labels encode only the non-ASCII one.
        #expect(
            blocks("shop.münchen.de##.x").first?.trigger.ifDomain == ["*shop.xn--mnchen-3ya.de"]
        )
        #expect(
            blocks("graubünden.ch##.y").first?.trigger.ifDomain == ["*xn--graubnden-u9a.ch"]
        )
    }

    @Test("selectors batch per domain group, capped per rule")
    func selectorBatching() {
        let text = (0...500).map { "##.s\($0)" }.joined(separator: "\n")
        let rules = blocks(text)
        #expect(rules.count == 2)
        #expect(rules[0].action.selector?.split(separator: ",").count == 500)
        #expect(rules[1].action.selector?.split(separator: ",").count == 1)
    }

    @Test("snippets, injected styles and hiding exceptions are counted as dropped")
    func cosmeticSkips() {
        #expect(skipped("##+js(set-constant, ads, false)") == .scriptInjection)
        #expect(skipped("example.com#%#window.x = 1") == .scriptInjection)
        #expect(skipped("example.com#$#h1 { color: red }") == .cssInjection)
        #expect(skipped("example.com#@#.ad") == .elementHidingException)
        #expect(skipped("example.com#@?#.ad") == .elementHidingException)
    }

    @Test("procedural and invalid selectors are rejected")
    func selectorValidation() {
        #expect(skipped("##a:has-text(Ad)") == .proceduralSelector)
        #expect(skipped("##div:has(.ad)") == .proceduralSelector)
        #expect(skipped("##div:-abp-properties(width: 1px)") == .proceduralSelector)
        #expect(skipped("##a{color:red}") == .invalidSelector)
        #expect(skipped("##a[href=\"open]") == .invalidSelector)
        #expect(blocks("##a[href^=\"https\"]:not(.keep)").count == 1)
        #expect(blocks("##ul > li:nth-child(2n+1)").count == 1)
    }

    // MARK: JSON shape

    @Test("rules encode to WebKit's key names")
    func jsonKeys() throws {
        let rules = blocks("||ads.example.com^$script")
        let json = try FilterListConverter.encodedJSON(rules)
        let array = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        let first = try #require(array.first)
        let trigger = try #require(first["trigger"] as? [String: Any])
        #expect(trigger["url-filter"] as? String != nil)
        #expect(trigger["resource-type"] as? [String] == ["script"])
        let action = try #require(first["action"] as? [String: Any])
        #expect(action["type"] as? String == "block")
    }
}

@Suite("Rule chunking")
struct BlockingChunkingTests {

    private func conversion(blocks: [String], exceptions: [String] = []) -> FilterListConversion {
        var text = blocks.joined(separator: "\n")
        if !exceptions.isEmpty {
            text += "\n" + exceptions.joined(separator: "\n")
        }
        return FilterListConverter.convert(text)
    }

    @Test("chunks stay under the cap and each carries the exception tail at its end")
    func chunkingUnderTinyCap() {
        let conversion = self.conversion(
            blocks: ["||a.com^", "||b.com^", "||c.com^"],
            exceptions: ["@@||ok.com^"]
        )
        let chunks = FilterListConverter.ruleChunks(from: [conversion], cap: 2)
        #expect(chunks.count == 3)
        for chunk in chunks {
            #expect(chunk.count <= 2)
            #expect(chunk.last?.action.type == "ignore-previous-rules")
            #expect(chunk.first?.action.type == "block")
        }
    }

    @Test("duplicate rules across lists convert once")
    func dedupe() {
        let a = conversion(blocks: ["||a.com^", "||b.com^"])
        let b = conversion(blocks: ["||a.com^"])
        let chunks = FilterListConverter.ruleChunks(from: [a, b])
        #expect(chunks.count == 1)
        #expect(chunks[0].count == 2)
    }

    @Test("a small real-shaped set stays in one chunk with exceptions last")
    func singleChunk() {
        let conversion = self.conversion(
            blocks: ["||a.com^", "##.ad"],
            exceptions: ["@@||ok.com^"]
        )
        let chunks = FilterListConverter.ruleChunks(from: [conversion])
        #expect(chunks.count == 1)
        #expect(chunks[0].first?.action.type == "block")
        #expect(chunks[0].last?.action.type == "ignore-previous-rules")
    }

    @Test("a set over WebKit's per-list cap splits into lists that each fit")
    func overTheRealCap() {
        let cap = FilterListConverter.webKitRuleListLimit
        let text = (0..<(cap + 10)).map { "||host\($0).example^" }.joined(separator: "\n")
            + "\n@@||ok.example^"
        let chunks = FilterListConverter.ruleChunks(from: [FilterListConverter.convert(text)])
        #expect(chunks.count == 2)
        #expect(chunks.allSatisfy { $0.count <= cap })
        #expect(chunks.map { $0.count - 1 }.reduce(0, +) == cap + 10)
        #expect(chunks.allSatisfy { $0.last?.action.type == "ignore-previous-rules" })
    }
}
