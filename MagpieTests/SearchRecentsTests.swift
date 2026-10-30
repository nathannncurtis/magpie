import Testing

@testable import Magpie

@Suite("RecentSearches")
struct SearchRecentsTests {

    @Test("queries come back freshest first")
    func order() async {
        let store = RecentSearches()
        await store.record("seasoning carbon steel")
        await store.record("quiet web")
        #expect(await store.recent(limit: 3) == ["quiet web", "seasoning carbon steel"])
    }

    @Test("seeded queries start oldest first, capped at capacity")
    func seeding() async {
        let store = RecentSearches(capacity: 2, seed: ["oldest", "middle", "newest"])
        #expect(await store.recent(limit: 10) == ["newest", "middle"])
    }

    @Test("re-recording moves a query to the front instead of duplicating it")
    func deduplicates() async {
        let store = RecentSearches()
        await store.record("one")
        await store.record("two")
        await store.record("one")
        #expect(await store.recent(limit: 10) == ["one", "two"])
    }

    @Test("only so many are kept")
    func capacity() async {
        let store = RecentSearches(capacity: 3)
        for index in 0..<6 {
            await store.record("query \(index)")
        }
        #expect(await store.recent(limit: 10) == ["query 5", "query 4", "query 3"])
    }

    @Test("blank input is not recorded")
    func blanksIgnored() async {
        let store = RecentSearches()
        await store.record("  ")
        await store.record("")
        #expect(await store.recent(limit: 3) == [])
    }

    @Test("recorded queries are trimmed")
    func trims() async {
        let store = RecentSearches()
        await store.record("  padded  ")
        #expect(await store.recent(limit: 3) == ["padded"])
    }

    @Test("everything can be forgotten")
    func removeAll() async {
        let store = RecentSearches()
        await store.record("one")
        await store.removeAll()
        #expect(await store.recent(limit: 3) == [])
    }
}
