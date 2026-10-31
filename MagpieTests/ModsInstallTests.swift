import Foundation
import Testing

@testable import Magpie

/// Telling what a pasted link leads to, and the draft it becomes (04 · 06).
@Suite("Install from a link")
struct ModsInstallTests {

    private static let userscript = """
        // ==UserScript==
        // @name         Quiet Tabs
        // @version      3.1
        // @author       a.okafor
        // @description  Dims the noise around the page.
        // @match        *://*.example.org/*
        // @grant        GM_addStyle
        // ==/UserScript==
        code();
        """

    private static let noRunRules = """
        // ==UserScript==
        // @name         Rootless
        // @version      1.0
        // ==/UserScript==
        code();
        """

    private static let filterList = """
        ! A list
        ||ads.example.com^
        ||tracker.example.net^
        banner.example.com/banner.gif
        """

    private static let webPage = """
        <!DOCTYPE html>
        <html><head><title>Not a mod</title></head><body></body></html>
        """

    private func address(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    // MARK: Classifying the text

    @Test("a userscript that parses and says where it runs")
    func classifyUserscript() throws {
        let result = InstallClassifier.classify(Self.userscript)
        guard case .userscript(let script) = result else {
            Issue.record("Expected a userscript, got \(result)")
            return
        }
        #expect(script.metadata.name == "Quiet Tabs")
        #expect(result.isInstallable)
    }

    @Test("a userscript with no @match and no @include runs nowhere")
    func classifyNoRunRules() {
        #expect(InstallClassifier.classify(Self.noRunRules) == .noRunRules)
        #expect(!InstallClassifier.classify(Self.noRunRules).isInstallable)
    }

    @Test("filter-list syntax is told from prose")
    func classifyFilterList() {
        #expect(InstallClassifier.classify(Self.filterList) == .filterList)
        #expect(InstallClassifier.classify(Self.filterList).isInstallable)

        // Too few rules is prose.
        #expect(InstallClassifier.classify("||ads.example.com^\n! that's all") == .webPage)
        // A sentence is not a rule line.
        let mixed = "||ads.example.com^\n||tracker.example.net^\n||cdn.example.net^\nHello there."
        #expect(InstallClassifier.classify(mixed) == .webPage)
    }

    @Test("a web page, and plain prose, are not mods")
    func classifyWebPage() {
        #expect(InstallClassifier.classify(Self.webPage) == .webPage)
        #expect(InstallClassifier.classify("Just a line of writing.") == .webPage)
        #expect(InstallClassifier.classify("") == .webPage)
        #expect(!InstallClassifier.classify(Self.webPage).isInstallable)
    }

    // MARK: Inspecting a link

    @Test("a 200 userscript comes back as itself")
    func inspectUserscript() async throws {
        let url = try address("https://example.com/quiet.user.js")
        let stub = StubModFetch(replies: ["quiet.user.js": .ok(Self.userscript)])

        let result = await ModLinkInstaller.inspect(url, fetch: { try await stub.call($0) })
        guard case .userscript(let script) = result else {
            Issue.record("Expected a userscript, got \(result)")
            return
        }
        #expect(script.metadata.version == "3.1")
        #expect(stub.callCount == 1)
    }

    @Test("a missing link, an offline link, and a link that isn't one")
    func inspectFailures() async throws {
        let stub = StubModFetch(replies: [
            "gone.user.js": .status(404),
            "down.user.js": .offline,
        ])

        let gone = try address("https://example.com/gone.user.js")
        #expect(await ModLinkInstaller.inspect(gone, fetch: { try await stub.call($0) }) == .unreachable)

        let down = try address("https://example.com/down.user.js")
        #expect(await ModLinkInstaller.inspect(down, fetch: { try await stub.call($0) }) == .unreachable)

        // A link that is not http or https is never fetched.
        let local = try address("file:///Users/me/quiet.user.js")
        #expect(await ModLinkInstaller.inspect(local, fetch: { try await stub.call($0) }) == .webPage)
        #expect(stub.callCount == 2)

        // Plain http is never fetched either, except from this device's loopback.
        let plain = try address("http://example.com/quiet.user.js")
        #expect(await ModLinkInstaller.inspect(plain, fetch: { try await stub.call($0) }) == .webPage)
        #expect(stub.callCount == 2)
        #expect(ModFetcher.isSecure(try address("http://127.0.0.1:53117/mod.user.js")))
        #expect(!ModFetcher.isSecure(try address("http://127.0.0.1.evil.net/mod.user.js")))
    }

    @Test("an oversized download is refused")
    func oversizedRefused() async throws {
        let big = String(repeating: "a", count: ModFetcher.maxDownloadBytes + 1)
        let stub = StubModFetch(replies: ["big.user.js": .ok(big)])
        let url = try address("https://example.com/big.user.js")
        #expect(await ModLinkInstaller.inspect(url, fetch: { try await stub.call($0) }) == .unreachable)
    }

    @Test("a list link is classified too")
    func inspectFilterList() async throws {
        let url = try address("https://example.com/list.txt")
        let stub = StubModFetch(replies: ["list.txt": .ok(Self.filterList)])

        let result = await ModLinkInstaller.inspect(url, fetch: { try await stub.call($0) })
        #expect(result == .filterList)
    }

    // MARK: The draft

    @Test("a userscript draft carries the script and where it came from")
    func userscriptDraft() throws {
        let url = try address("https://example.com/quiet.user.js")
        let result = InstallClassifier.classify(Self.userscript)
        let draft = try #require(ModLinkInstaller.draft(from: result, url: url))

        #expect(draft.id == ModLinkInstaller.linkID(for: url))
        #expect(draft.name == "Quiet Tabs")
        #expect(draft.kind == .userscript)
        #expect(draft.author == "a.okafor")
        #expect(draft.version == "3.1")
        #expect(draft.summary == "Dims the noise around the page.")
        #expect(draft.icon == .linkInstall())
        #expect(draft.source == .link(url))
        #expect(draft.script?.name == "Quiet Tabs")
        #expect(draft.scriptBody == "code();")
        #expect(draft.listURL == nil)
    }

    @Test("a filter-list draft is named for its file")
    func filterListDraft() throws {
        let url = try address("https://example.com/a-quite-long-list-name.txt")
        let draft = try #require(ModLinkInstaller.draft(from: .filterList, url: url))

        #expect(draft.kind == .filterList)
        #expect(draft.name == "a-quite-long-list-name.txt")
        #expect(draft.listURL == url)
        #expect(draft.source == .link(url))
        #expect(draft.script == nil)

        // Nothing installs from the results that aren't mods.
        #expect(ModLinkInstaller.draft(from: .webPage, url: url) == nil)
        #expect(ModLinkInstaller.draft(from: .noRunRules, url: url) == nil)
        #expect(ModLinkInstaller.draft(from: .unreachable, url: url) == nil)
    }

    @Test("the same link always names the same mod")
    func linkID() throws {
        let first = try address("https://example.com/quiet.user.js")
        let again = try address("https://example.com/quiet.user.js")
        let other = try address("https://example.com/loud.user.js")

        let id = ModLinkInstaller.linkID(for: first)
        #expect(id == ModLinkInstaller.linkID(for: again))
        #expect(id != ModLinkInstaller.linkID(for: other))
        #expect(id.hasPrefix("link-"))
        let digits = id.dropFirst("link-".count)
        #expect(digits.count == 12)
        // The id's digits are the hex of a digest.
        #expect(digits.allSatisfy { $0.isHexDigit })
    }

    @Test("what a link is called when nothing better is known")
    func fallbackNames() throws {
        let file = try address("https://example.com/quiet.user.js")
        #expect(ModLinkInstaller.name(from: file) == "quiet.user.js")

        let hostOnly = try address("https://example.com/")
        #expect(ModLinkInstaller.name(from: hostOnly) == "example.com")

        // A very long file name is cut short.
        let long = try address("https://example.com/\(String(repeating: "a", count: 60)).user.js")
        #expect(ModLinkInstaller.name(from: long).count == 40)
    }

    @Test("a script with no run rules makes no draft at all")
    func noDraftForRunless() throws {
        let url = try address("https://example.com/rootless.user.js")
        let result = InstallClassifier.classify(Self.noRunRules)
        #expect(result == .noRunRules)
        #expect(ModLinkInstaller.draft(from: result, url: url) == nil)
    }
}
