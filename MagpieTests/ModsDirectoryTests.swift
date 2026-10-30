import Foundation
import Testing

@testable import Magpie

/// The directory: its index decoded, its downloads verified, and its once-a-day fetch
/// policy (04 · 06).
@Suite("ModDirectory")
@MainActor
struct ModsDirectoryTests {

    private func makeDirectory(
        cache: ModDirectoryCache = InMemoryModDirectoryCache(),
        clock: TestClock = TestClock(),
        replies: [String: StubReply] = [:]
    ) -> (ModDirectory, TestClock, StubModFetch) {
        let stub = StubModFetch(replies: replies)
        let directory = ModDirectory(
            cache: cache, clock: { clock.now() }, fetch: { url in try await stub.call(url) })
        return (directory, clock, stub)
    }

    private func entry(id: String, sha256: String) -> DirectoryMod {
        DirectoryMod(
            id: id, name: id, descriptionText: "", author: "someone",
            kind: .userscript, version: "1.0",
            url: URL(fileURLWithPath: "/\(id).user.js"),
            sha256: sha256, icon: .linkInstall())
    }

    private func encoded(_ index: DirectoryIndex) throws -> String {
        String(decoding: try JSONEncoder().encode(index), as: UTF8.self)
    }

    @Test("the bundled index decodes: five mods, one featured, three popular")
    func fixtureDecodes() throws {
        let index = try #require(UITestModFixtures.directoryIndex())

        #expect(index.version == 1)
        #expect(index.mods.count == 5)
        #expect(index.featured?.id == "google-answer-box")
        #expect(index.featured?.preview == .googleAnswerBox)
        #expect(index.popular.map(\.id) == ["midnight-pages", "youtube-quiet", "just-the-recipe"])
        #expect(index.entry(id: "wider-wikipedia")?.author == "l.marsh")
        #expect(index.entry(id: "wider-wikipedia")?.popularRank == nil)
        // The unranked and the featured are left out of "Popular this week".
        #expect(!index.popular.contains { $0.id == "google-answer-box" })

        let midnight = try #require(index.entry(id: "midnight-pages"))
        #expect(midnight.kind == .filterList)
        #expect(midnight.icon.glyph == "moon.fill")
        #expect(midnight.icon.gradient == ["#2B3358", "#0F1226"])
    }

    @Test("the fixture's digests match the files it points the UI tests at")
    func fixtureDigests() throws {
        let index = try #require(UITestModFixtures.directoryIndex())

        let script = try #require(index.entry(id: "wider-wikipedia"))
        #expect(script.sha256 == ModFetcher.sha256Hex(of: Data(UITestModFixtures.userscript.utf8)))

        let list = try #require(index.entry(id: "midnight-pages"))
        #expect(list.sha256 == ModFetcher.sha256Hex(of: Data(UITestModFixtures.filterList.utf8)))
    }

    @Test("the digest of some known bytes")
    func sha256() {
        let digest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        #expect(ModFetcher.sha256Hex(of: Data("abc".utf8)) == digest)
    }

    @Test("a download that verifies hands over the file")
    func downloadVerifies() async throws {
        let body = """
            // ==UserScript==
            // @name         X
            // @match        *://example.com/*
            // ==/UserScript==
            code();
            """
        let (directory, _, stub) = makeDirectory(
            cache: InMemoryModDirectoryCache.warm(nil),
            replies: ["x.user.js": .ok(body)])
        let index = DirectoryIndex(
            version: 1,
            mods: [entry(id: "x", sha256: ModFetcher.sha256Hex(of: Data(body.utf8)))])

        let text = try await directory.download(index.mods[0])
        #expect(text == body)
        #expect(stub.callCount == 1)
    }

    @Test("a changed file is refused")
    func downloadRefusesChangedFile() async {
        let (directory, _, _) = makeDirectory(
            cache: InMemoryModDirectoryCache.warm(nil),
            replies: ["x.user.js": .ok("other bytes")])
        let index = DirectoryIndex(version: 1, mods: [entry(id: "x", sha256: String(repeating: "0", count: 64))])

        await #expect(throws: DirectoryMod.DirectoryError.changedFile) {
            _ = try await directory.download(index.mods[0])
        }
    }

    @Test("anything but a 200 is unreachable")
    func downloadRefusesNon200() async {
        let (directory, _, _) = makeDirectory(
            cache: InMemoryModDirectoryCache.warm(nil),
            replies: ["x.user.js": .status(404)])
        let index = DirectoryIndex(version: 1, mods: [entry(id: "x", sha256: String(repeating: "0", count: 64))])

        await #expect(throws: DirectoryMod.DirectoryError.unreachable) {
            _ = try await directory.download(index.mods[0])
        }
    }

    @Test("a fresh cache is not fetched again")
    func freshCacheSkipsFetch() async {
        let cached = DirectoryIndex(version: 1, mods: [entry(id: "x", sha256: "0")])
        let (directory, _, stub) = makeDirectory(cache: InMemoryModDirectoryCache.warm(cached))
        #expect(directory.mods.map(\.id) == ["x"])

        await directory.refresh()
        #expect(directory.mods.map(\.id) == ["x"])
        #expect(stub.callCount == 0)
    }

    @Test("a day-old cache fetches, and the fresh one it leaves does not")
    func staleCacheFetches() async throws {
        let cached = DirectoryIndex(version: 1, mods: [entry(id: "old", sha256: "0")])
        let fetched = DirectoryIndex(version: 1, mods: [entry(id: "new", sha256: "0")])
        let (directory, clock, stub) = makeDirectory(
            cache: InMemoryModDirectoryCache.warm(cached),
            replies: ["index.json": .ok(try encoded(fetched))])
        #expect(directory.mods.map(\.id) == ["old"])

        clock.advance(by: ModDirectory.refreshInterval + 1)
        await directory.refresh()
        #expect(directory.mods.map(\.id) == ["new"])
        #expect(directory.entry(id: "new") != nil)
        #expect(stub.callCount == 1)

        // The fetch just refreshed the cache, so a day hasn't passed.
        await directory.refresh()
        #expect(stub.callCount == 1)
    }

    @Test("a fetch that fails keeps what the cache had")
    func failedFetchKeepsCache() async throws {
        let cached = DirectoryIndex(version: 1, mods: [entry(id: "old", sha256: "0")])
        let (directory, clock, _) = makeDirectory(
            cache: InMemoryModDirectoryCache.warm(cached),
            replies: ["index.json": .offline])

        clock.advance(by: ModDirectory.refreshInterval + 1)
        await directory.refresh()
        #expect(directory.mods.map(\.id) == ["old"])
    }

    @Test("an error status keeps the cache too, and an empty cache stays empty")
    func failedStatusKeepsCache() async throws {
        let cached = DirectoryIndex(version: 1, mods: [entry(id: "old", sha256: "0")])
        let (directory, clock, _) = makeDirectory(
            cache: InMemoryModDirectoryCache.warm(cached),
            replies: ["index.json": .status(503)])

        clock.advance(by: ModDirectory.refreshInterval + 1)
        await directory.refresh()
        #expect(directory.mods.map(\.id) == ["old"])

        let (empty, emptyClock, _) = makeDirectory(
            cache: InMemoryModDirectoryCache.warm(nil),
            replies: ["index.json": .offline])
        emptyClock.advance(by: ModDirectory.refreshInterval + 1)
        await empty.refresh()
        #expect(empty.mods.isEmpty)
        #expect(empty.featured == nil)
    }

    @Test("the cache's freshness follows the fetch date")
    func cacheFreshness() {
        let now = Date()
        var state = ModDirectoryCacheState()
        #expect(!state.isFresh(asOf: now))

        state.fetchedAt = now
        #expect(state.isFresh(asOf: now))
        #expect(state.isFresh(asOf: now.addingTimeInterval(23 * 60 * 60)))
        #expect(!state.isFresh(asOf: now.addingTimeInterval(ModDirectory.refreshInterval + 1)))
    }
}
