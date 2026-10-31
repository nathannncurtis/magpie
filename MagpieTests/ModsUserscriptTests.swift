import Foundation
import Testing
import WebKit

@testable import Magpie

/// Parsing a userscript's metadata block, and the rules inside it (04 · 06).
@Suite("Userscript")
struct ModsUserscriptTests {

    private static let script = """
        // ==UserScript==
        // @name         Wider Wikipedia
        // @namespace    magpie
        // @version      1.2
        // @author       l.marsh
        // @description  Lets articles use the full width.
        // @match        *://*.wikipedia.org/*
        // @match        https://example.com/*
        // @match        not a pattern
        // @include      *facebook*
        // @exclude      *.facebook.com/login*
        // @run-at       document-start
        // @grant        GM_addStyle
        // @grant        GM_xmlhttpRequest
        // @grant        GM_addStyle
        // @icon         https://example.com/icon.png
        // @noframes
        // ==/UserScript==
        let wide = document.body.style.maxWidth;
        """

    @Test("the metadata block reads out")
    func parsesMetadata() throws {
        let script = try #require(Userscript.parse(Self.script))
        let meta = script.metadata

        #expect(meta.name == "Wider Wikipedia")
        #expect(meta.namespace == "magpie")
        #expect(meta.version == "1.2")
        #expect(meta.author == "l.marsh")
        #expect(meta.summary == "Lets articles use the full width.")
        #expect(meta.icon == "https://example.com/icon.png")
        #expect(meta.noFrames)
        #expect(meta.runAt == .documentStart)
        #expect(meta.grants == ["GM_addStyle", "GM_xmlhttpRequest", "GM_addStyle"])
        #expect(script.body.contains("let wide"))
        // The malformed @match drops out; the two good ones stay, in order.
        #expect(meta.matches.map(\.host) == ["*.wikipedia.org", "example.com"])
    }

    @Test("the run-at values map, and anything else is the default")
    func runAtValues() {
        #expect(UserscriptMetadata.RunAt(raw: "document-start") == .documentStart)
        #expect(UserscriptMetadata.RunAt(raw: "document-end") == .documentEnd)
        #expect(UserscriptMetadata.RunAt(raw: "document-idle") == .documentIdle)
        #expect(UserscriptMetadata.RunAt(raw: "whenever") == .documentIdle)
    }

    @Test("a userscript without a metadata block is not a userscript")
    func rejectsNonScripts() {
        #expect(Userscript.parse("console.log(1);") == nil)
        #expect(Userscript.parse("<!DOCTYPE html><html><body></body></html>") == nil)
        // A block that never closes, or one with no keys at all.
        #expect(Userscript.parse("// ==UserScript==\n// @name X\n") == nil)
        #expect(Userscript.parse("// ==UserScript==\n// ==/UserScript==\n") == nil)
    }

    @Test("the grants the shim honours, and the ones it lists as unsupported")
    func grants() throws {
        let meta = try #require(Userscript.parse(Self.script)).metadata
        #expect(meta.unsupportedGrants == ["GM_xmlhttpRequest"])

        var plain = UserscriptMetadata()
        plain.grants = ["none", "GM_setValue"]
        #expect(plain.unsupportedGrants.isEmpty)
    }

    @Test("the hosts the @match rules name, deduplicated in writing order")
    func matchDomains() throws {
        let meta = try #require(Userscript.parse(Self.script)).metadata
        #expect(meta.matchDomains == ["wikipedia.org", "example.com"])

        var any = UserscriptMetadata()
        any.matches = [try #require(MatchPattern(raw: "*://*/*"))]
        #expect(any.matchDomains.isEmpty)
    }
}

/// A @match rule, with Chrome match-pattern semantics.
@Suite("MatchPattern")
struct ModsMatchPatternTests {

    private func matches(_ raw: String, _ url: String) throws -> Bool {
        let pattern = try #require(MatchPattern(raw: raw))
        let address = try #require(URL(string: url))
        return UserscriptMetadata.runsCheck(pattern, on: address)
    }

    @Test("valid and invalid patterns")
    func validity() {
        #expect(MatchPattern(raw: "*://*/*") != nil)
        #expect(MatchPattern(raw: "https://example.com/*") != nil)
        #expect(MatchPattern(raw: "http://*.example.com/path/*") != nil)
        #expect(MatchPattern(raw: "file:///*") != nil)
        #expect(MatchPattern(raw: "ftp://example.com/*") != nil)
        // No scheme, no path, a port, a scheme that isn't one, a star off the host's edge.
        #expect(MatchPattern(raw: "example.com/*") == nil)
        #expect(MatchPattern(raw: "https://example.com") == nil)
        #expect(MatchPattern(raw: "https://example.com:8080/*") == nil)
        #expect(MatchPattern(raw: "gopher://example.com/*") == nil)
        #expect(MatchPattern(raw: "https://*example.com/*") == nil)
        #expect(MatchPattern(raw: "https://www.*.com/*") == nil)
    }

    @Test("a *.domain pattern covers the domain and every subdomain, on http or https")
    func subdomainPattern() throws {
        #expect(try matches("*://*.wikipedia.org/*", "https://en.wikipedia.org/wiki/Tea"))
        #expect(try matches("*://*.wikipedia.org/*", "http://wikipedia.org/"))
        #expect(try matches("*://*.wikipedia.org/*", "https://DEEP.m.wikipedia.org/x"))
        #expect(try !matches("*://*.wikipedia.org/*", "https://notwikipedia.org/"))
        #expect(try !matches("*://*.wikipedia.org/*", "ftp://wikipedia.org/"))
    }

    @Test("an exact host matches only itself")
    func exactHost() throws {
        #expect(try matches("https://example.com/*", "https://example.com/any/path"))
        #expect(try !matches("https://example.com/*", "https://sub.example.com/"))
        #expect(try !matches("https://example.com/*", "http://example.com/"))
    }

    @Test("a literal scheme bars the others; a * covers http and https")
    func schemes() throws {
        #expect(try matches("http://*/*", "http://a.org/x"))
        #expect(try !matches("http://*/*", "https://a.org/x"))
        #expect(try matches("*://*/*", "https://a.org/x"))
        #expect(try matches("*://*/*", "http://a.org/x"))
    }

    @Test("the path is a glob whose star crosses slashes")
    func pathGlob() throws {
        #expect(try matches("https://example.com/foo*bar", "https://example.com/foobar"))
        #expect(try matches("https://example.com/foo*bar", "https://example.com/foo/a/bar"))
        #expect(try !matches("https://example.com/foo*bar", "https://example.com/bar"))
        #expect(try !matches("https://example.com/exact", "https://example.com/exact/x"))
    }

    @Test("a host rule is not fooled by look-alike hosts, userinfo, queries or fragments")
    func strictHosts() throws {
        // Exact host.
        #expect(try !matches("*://example.com/*", "https://example.com.evil.net/"))
        #expect(try !matches("*://example.com/*", "https://evilexample.com/"))
        #expect(try !matches("*://example.com/*", "https://example.com@evil.net/"))
        #expect(try !matches("*://example.com/*", "https://example.com:443@evil.net/"))
        #expect(try !matches("*://example.com/*", "https://evil.net/?example.com/"))
        #expect(try matches("*://example.com/*", "https://example.com:8443/x"))
        // Subdomain rule.
        #expect(try !matches("*://*.example.com/*", "https://example.com.evil.net/"))
        #expect(try !matches("*://*.example.com/*", "https://evilexample.com/"))
        #expect(try !matches("*://*.example.com/*", "https://evil.net?.example.com/"))
        #expect(try !matches("*://*.example.com/*", "https://evil.net#.example.com/"))
        #expect(try !matches("*://*.example.com/*", "https://evil.net/x.example.com/"))
        #expect(try !matches("*://*.example.com/*", "https://x.example.com@evil.net/"))
        #expect(try !matches("*://*.example.com/*", "https://u:p@evil.net:1/.example.com/"))
        #expect(try matches("*://*.example.com/*", "https://a.b.example.com:8080/x"))
        // A match rule never reaches an app-internal or script scheme.
        #expect(try !matches("*://*/*", "about:blank"))
        #expect(try !matches("*://*/*", "javascript:alert(1)//x/"))
        #expect(try !matches("*://*/*", "magpie://settings/"))
        #expect(try !matches("*://*/*", "file:///etc/hosts"))
    }

    @Test("the JavaScript guard agrees with Swift on the strict-host cases")
    func guardSourcesAreLiteralSafe() throws {
        let pattern = try #require(MatchPattern(raw: "*://*.example.com/*"))
        let literal = RuleRegexJS.literalSafe(pattern.regexSource)
        #expect(!literal.contains("[^/"))
        #expect(literal.contains("[^\\/?#@:"))
    }

    @Test("the pattern compiles to the anchored source the guard uses")
    func regexSource() throws {
        let pattern = try #require(MatchPattern(raw: "*://*.wikipedia.org/wiki/*"))
        #expect(pattern.regexSource == "^https?://(?:[^/?#@:\\\\.]+\\.)*wikipedia\\.org(?::[0-9]+)?/wiki/.*$")
        let any = try #require(MatchPattern(raw: "*://*/*"))
        #expect(any.regexSource == "^https?://[^/]*/.*$")
    }
}

/// @include and @exclude rules: globs over the whole address, or regexes between slashes.
@Suite("IncludeExclude")
struct ModsIncludeExcludeTests {

    @Test("glob includes")
    func globIncludes() throws {
        let rule = try #require(URLRule(raw: "*://*.facebook.com/*"))
        #expect(rule.regexSource == "^.*://.*\\.facebook\\.com/.*$")
    }

    @Test("a regex rule keeps its source and tests unanchored")
    func regexRules() throws {
        let rule = try #require(URLRule(raw: "/quiet[0-9]+/"))
        #expect(rule.kind == .regex(source: "quiet[0-9]+"))
        // "//" is too short to be a regex; it stays a glob.
        #expect(URLRule(raw: "//")?.kind == .glob(pattern: "//"))
    }

    @Test("runs(on:) follows matches, includes and excludes together")
    func runsOn() throws {
        var meta = UserscriptMetadata()
        meta.matches = [try #require(MatchPattern(raw: "*://*.example.com/*"))]
        meta.includes = [try #require(URLRule(raw: "*special*"))]
        meta.excludes = [try #require(URLRule(raw: "*.example.com/login*"))]

        let wiki = try #require(URL(string: "https://en.wikipedia.org/x"))
        let site = try #require(URL(string: "https://api.example.com/v1"))
        let login = try #require(URL(string: "https://api.example.com/login?next=1"))
        let special = try #require(URL(string: "https://special.example.org/"))

        #expect(!meta.runs(on: wiki))
        #expect(meta.runs(on: site))
        #expect(!meta.runs(on: login))
        #expect(meta.runs(on: special))
    }

    @Test("a script with no run rules runs nowhere")
    func noRunRules() throws {
        var meta = UserscriptMetadata()
        #expect(!meta.hasRunRules)
        let url = try #require(URL(string: "https://example.com/"))
        #expect(!meta.runs(on: url))

        meta.includes = [try #require(URLRule(raw: "*"))]
        #expect(meta.hasRunRules)
        #expect(meta.runs(on: url))
    }
}

/// The guard the injector wraps every script in, as JavaScript (04 · 06).
@Suite("Injection guard")
struct ModsGuardTests {

    @Test("run rules alone bar everything they don't let through")
    func runOnly() {
        let expression = ModInjector.guardExpression(
            run: ["^https?://example\\.com/.*$"], barring: [])
        #expect(expression == "!(/^https?:\\/\\/example\\.com\\/.*$/i.test(__href))")
    }

    @Test("two run rules join with ||")
    func runPair() {
        let expression = ModInjector.guardExpression(run: ["^a$", "^b$"], barring: [])
        #expect(expression == "!(/^a$/i.test(__href) || /^b$/i.test(__href))")
    }

    @Test("exclude rules are an exception, not a gate")
    func withBarring() {
        let expression = ModInjector.guardExpression(run: ["^a$"], barring: ["login"])
        #expect(expression == "!(/^a$/i.test(__href)) || (/login/i.test(__href))")
    }

    @Test("no run rules at all bars the whole web")
    func noRules() {
        #expect(ModInjector.guardExpression(run: [], barring: ["x"]) == "true")
    }

    @Test("slashes in a rule's source are escaped for the JavaScript literal")
    func literalSafe() {
        #expect(RuleRegexJS.literalSafe("^https?://a\\.com/") == "^https?:\\/\\/a\\.com\\/")
        // An escape pair survives; a lone trailing backslash is closed.
        #expect(RuleRegexJS.literalSafe("a\\/b\\") == "a\\/b\\\\")
    }

    @Test("run-at maps onto the two injection times WKUserScript offers")
    func injectionTimes() {
        #expect(ModInjector.injectionTime(for: .documentStart) == .atDocumentStart)
        #expect(ModInjector.injectionTime(for: .documentEnd) == .atDocumentEnd)
        #expect(ModInjector.injectionTime(for: .documentIdle) == .atDocumentEnd)
    }

    @Test("the wrapped script carries the guard, the shim and the code")
    func wrappedScript() throws {
        var meta = UserscriptMetadata()
        meta.name = "X"
        meta.matches = [try #require(MatchPattern(raw: "*://example.com/*"))]
        let guardExpression = ModInjector.guardExpression(
            run: meta.runRegexSources, barring: [])
        let wrapped = ModInjector.wrappedScript(
            metadata: meta, modID: "mod-1", modName: "X", body: "done();",
            values: [
                "count": "3"
            ])
        #expect(wrapped.contains("if (\(guardExpression)) { return; }"))
        #expect(wrapped.contains("var __href = location.href;"))
        #expect(wrapped.contains("function GM_addStyle(css)"))
        #expect(wrapped.contains("function GM_getValue(key, fallback)"))
        #expect(wrapped.contains("function GM_setValue(key, value)"))
        // The relay knows its mod from the world; the post doesn't name one.
        #expect(!wrapped.contains("\"mod\":"))
        #expect(!wrapped.contains("mod-1"))
        #expect(wrapped.contains("\"count\":\"3\""))
        #expect(wrapped.contains("done();"))
        #expect(wrapped.contains("GM_info.script"))
        #expect(!wrapped.contains("use strict"))
    }
}

extension UserscriptMetadata {
    /// Whether one pattern alone lets an address through, for the rule tests.
    static func runsCheck(_ pattern: MatchPattern, on url: URL) -> Bool {
        var meta = UserscriptMetadata()
        meta.matches = [pattern]
        return meta.runs(on: url)
    }
}

/// The GM bridge: what a post must look like before a value is stored.
@Suite("ModValueRelay")
struct ModValueRelayTests {

    @Test("only a key and a string value, within limits, are taken")
    func entryShape() {
        #expect(ModValueRelay.entry(from: ["key": "a", "value": "1"])?.key == "a")
        #expect(ModValueRelay.entry(from: ["key": "a", "value": "1", "mod": "other"])?.value == "1")
        #expect(ModValueRelay.entry(from: "a") == nil)
        #expect(ModValueRelay.entry(from: ["key": "a"]) == nil)
        #expect(ModValueRelay.entry(from: ["key": "", "value": "1"]) == nil)
        #expect(ModValueRelay.entry(from: ["key": 1, "value": "1"]) == nil)
        let longKey = String(repeating: "k", count: ModValueRelay.maxKeyLength + 1)
        #expect(ModValueRelay.entry(from: ["key": longKey, "value": "1"]) == nil)
        let bigValue = String(repeating: "v", count: ModValueRelay.maxValueLength + 1)
        #expect(ModValueRelay.entry(from: ["key": "a", "value": bigValue]) == nil)
    }
}
