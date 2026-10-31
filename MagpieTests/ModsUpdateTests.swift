import Foundation
import Testing

@testable import Magpie

/// A link update that widens where a mod runs waits for the user's word; one that
/// doesn't lands at once (04 · 06).
@Suite("Mod updates")
@MainActor
struct ModsUpdateTests {

    private static let link =
        URL(string: "https://mods.example.com/tweak.user.js")
        ?? URL(fileURLWithPath: "/tweak.user.js")

    private func script(
        version: String, matches: [String] = [], includes: [String] = [], grants: [String] = []
    ) -> String {
        var lines = ["// ==UserScript==", "// @name Tweak", "// @version \(version)"]
        lines += matches.map { "// @match \($0)" }
        lines += includes.map { "// @include \($0)" }
        lines += grants.map { "// @grant \($0)" }
        lines += ["// ==/UserScript==", "run();"]
        return lines.joined(separator: "\n")
    }

    private func metadata(
        matches: [String] = [], includes: [String] = [], grants: [String] = []
    ) throws -> UserscriptMetadata {
        try #require(
            Userscript.parse(script(version: "1", matches: matches, includes: includes, grants: grants))
        ).metadata
    }

    private var emptyDirectory: ModDirectory {
        ModDirectory(
            cache: InMemoryModDirectoryCache.warm(DirectoryIndex(version: 1, mods: [])),
            fetch: { _ in throw URLError(.badURL) })
    }

    /// A store with the link mod installed at 1.0, running where `matches` say.
    private func storeWithLinkMod(matches: [String], grants: [String] = []) throws -> (ModStore, String) {
        let parsed = try #require(Userscript.parse(script(version: "1.0", matches: matches, grants: grants)))
        let draft = try #require(ModLinkInstaller.draft(from: .userscript(parsed), url: Self.link))
        let store = ModStore(io: InMemoryModStoreIO())
        store.install(draft)
        return (store, draft.id)
    }

    // MARK: The comparison

    @Test("the same rules, in any order, widen nothing")
    func sameRules() throws {
        let old = try metadata(matches: ["*://a.com/*", "*://b.com/*"], grants: ["GM_addStyle"])
        let new = try metadata(matches: ["*://b.com/*", "*://a.com/*"], grants: ["GM_addStyle"])
        #expect(ModWidening(from: old, to: new).isEmpty)
    }

    @Test("dropping a rule or a grant widens nothing")
    func narrowing() throws {
        let old = try metadata(matches: ["*://a.com/*", "*://b.com/*"], grants: ["GM_addStyle"])
        let new = try metadata(matches: ["*://a.com/*"])
        #expect(ModWidening(from: old, to: new).isEmpty)
    }

    @Test("a new @match is a new site")
    func newMatch() throws {
        let old = try metadata(matches: ["*://a.com/*"])
        let new = try metadata(matches: ["*://a.com/*", "*://*.b.com/*"])
        let widening = ModWidening(from: old, to: new)
        #expect(widening.newSites == ["*://*.b.com/*"])
        #expect(widening.newGrants.isEmpty)
    }

    @Test("a new @include counts, even one an old rule covers")
    func newInclude() throws {
        let old = try metadata(matches: ["*://*/*"])
        let new = try metadata(matches: ["*://*/*"], includes: ["https://a.com/*", "/b\\.com/"])
        #expect(ModWidening(from: old, to: new).newSites == ["https://a.com/*", "/b\\.com/"])
    }

    @Test("a new grant widens; @grant none does not")
    func newGrants() throws {
        let old = try metadata(matches: ["*://a.com/*"], grants: ["GM_getValue"])
        let new = try metadata(
            matches: ["*://a.com/*"], grants: ["none", "GM_getValue", "GM_xmlhttpRequest", "GM_xmlhttpRequest"])
        let widening = ModWidening(from: old, to: new)
        #expect(widening.newSites.isEmpty)
        #expect(widening.newGrants == ["GM_xmlhttpRequest"])
    }

    @Test("a filter list carries no rules to widen")
    func filterList() {
        #expect(ModWidening(from: nil, to: nil).isEmpty)
    }

    // MARK: Held or silent

    @Test("an update on the same sites lands at once")
    func silentUpdate() async throws {
        let (store, id) = try storeWithLinkMod(matches: ["*://a.com/*"])
        let body = script(version: "2.0", matches: ["*://a.com/*"])
        let stub = StubModFetch(replies: ["tweak.user.js": .ok(body)])

        let result = await store.update(id: id, directory: emptyDirectory) { try await stub.call($0) }
        #expect(result == .updated)
        #expect(store.pendingUpdate == nil)
        #expect(store.mod(id: id)?.version == "2.0")
    }

    @Test("an update that runs on more sites is held until confirmed")
    func heldThenConfirmed() async throws {
        let (store, id) = try storeWithLinkMod(matches: ["*://a.com/*"])
        let body = script(version: "2.0", matches: ["*://a.com/*", "*://b.com/*"])
        let stub = StubModFetch(replies: ["tweak.user.js": .ok(body)])

        let result = await store.update(id: id, directory: emptyDirectory) { try await stub.call($0) }
        #expect(result == .held)
        #expect(store.mod(id: id)?.version == "1.0")
        #expect(store.pendingUpdate?.id == id)
        #expect(store.pendingUpdate?.widening.newSites == ["*://b.com/*"])

        store.confirmPendingUpdate()
        #expect(store.pendingUpdate == nil)
        #expect(store.mod(id: id)?.version == "2.0")
        #expect(store.mod(id: id)?.script?.matches.count == 2)
    }

    @Test("an update that asks for a new grant is held; cancel keeps the old version")
    func heldThenCancelled() async throws {
        let (store, id) = try storeWithLinkMod(matches: ["*://a.com/*"])
        let body = script(version: "2.0", matches: ["*://a.com/*"], grants: ["GM_setValue"])
        let stub = StubModFetch(replies: ["tweak.user.js": .ok(body)])

        let result = await store.update(id: id, directory: emptyDirectory) { try await stub.call($0) }
        #expect(result == .held)
        #expect(store.pendingUpdate?.widening.newGrants == ["GM_setValue"])

        store.cancelPendingUpdate()
        #expect(store.pendingUpdate == nil)
        #expect(store.mod(id: id)?.version == "1.0")
        #expect(store.mod(id: id)?.script?.grants.isEmpty == true)
    }
}
