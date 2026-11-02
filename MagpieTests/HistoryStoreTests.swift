import Foundation
import Testing

@testable import Magpie

@Suite("HistoryStore")
@MainActor
struct HistoryStoreTests {

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func url(_ address: String) -> URL {
        URL(string: address) ?? URL(fileURLWithPath: "/")
    }

    @Test("a visit is held, newest first")
    func recordHoldsVisits() {
        let store = HistoryStore()
        store.record(url: url("https://a.example/one"), title: "One", isPrivate: false, now: date(1))
        store.record(url: url("https://b.example/two"), title: "Two", isPrivate: false, now: date(2))

        #expect(store.entries.map(\.title) == ["Two", "One"])
        #expect(store.entries.first?.visitedAt == date(2))
        #expect(store.entries.first?.host == "b.example")
    }

    @Test("the same address twice in a row is one entry, and a later title lands on it")
    func consecutiveRevisitsDedupe() {
        let store = HistoryStore()
        let page = url("https://a.example/one")
        store.record(url: page, isPrivate: false, now: date(1))
        store.record(url: page, title: "One", isPrivate: false, now: date(2))
        store.record(url: page, isPrivate: false, now: date(3))

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.title == "One")
        #expect(store.entries.first?.visitedAt == date(1))
    }

    @Test("an address revisited after another page is a new entry")
    func nonConsecutiveRevisitCounts() {
        let store = HistoryStore()
        store.record(url: url("https://a.example"), isPrivate: false, now: date(1))
        store.record(url: url("https://b.example"), isPrivate: false, now: date(2))
        store.record(url: url("https://a.example"), isPrivate: false, now: date(3))

        #expect(store.entries.count == 3)
    }

    @Test("a private tab leaves nothing")
    func privateIsExcluded() {
        let store = HistoryStore()
        store.record(url: url("https://a.example"), title: "A", isPrivate: true, now: date(1))

        #expect(store.entries.isEmpty)
    }

    @Test("only web pages are kept")
    func nonWebAddressesAreSkipped() {
        let store = HistoryStore()
        store.record(url: url("about:blank"), isPrivate: false, now: date(1))
        store.record(url: url("magpie://skim/abc"), isPrivate: false, now: date(2))
        store.record(url: url("data:text/html,hi"), isPrivate: false, now: date(3))

        #expect(store.entries.isEmpty)
    }

    @Test("a title that arrives after the commit lands on its page's entry")
    func titleArrivesLate() {
        let store = HistoryStore()
        store.record(url: url("https://a.example"), isPrivate: false, now: date(1))
        store.updateTitle("Late title", for: url("https://a.example"))
        store.updateTitle("Nobody's", for: url("https://elsewhere.example"))

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.title == "Late title")
    }

    @Test("an entry with no title reads as its site")
    func untitledEntryUsesHost() {
        let entry = HistoryEntry(url: url("https://www.quietweb.org/slow"), title: " ", visitedAt: date(0))

        #expect(entry.displayTitle == "quietweb.org")
    }

    @Test("the list keeps the newest visits past its cap")
    func capDropsOldest() {
        let store = HistoryStore(capacity: 3)
        for i in 0..<5 {
            store.record(
                url: url("https://a.example/\(i)"), title: "\(i)", isPrivate: false,
                now: date(TimeInterval(i)))
        }

        #expect(store.entries.map(\.title) == ["4", "3", "2"])
    }

    @Test("the cap is about five thousand")
    func defaultCap() {
        #expect(HistoryStore.capacity == 5000)
    }

    @Test("search matches titles and sites, ignoring case")
    func searchMatchesTitleAndHost() {
        let store = HistoryStore()
        store.record(
            url: url("https://seriouseats.com/pan"), title: "Season a carbon steel pan",
            isPrivate: false, now: date(1))
        store.record(
            url: url("https://git-scm.com/rebase"), title: "rebase vs merge", isPrivate: false,
            now: date(2))

        #expect(store.search("CARBON").map(\.title) == ["Season a carbon steel pan"])
        #expect(store.search("git-scm").map(\.title) == ["rebase vs merge"])
        #expect(store.search("  ").count == 2)
        #expect(store.search("nothing like it").isEmpty)
    }

    @Test("removing entries leaves the rest")
    func removeKeepsTheRest() {
        let store = HistoryStore()
        store.record(url: url("https://a.example"), title: "A", isPrivate: false, now: date(1))
        store.record(url: url("https://b.example"), title: "B", isPrivate: false, now: date(2))
        store.remove(store.entries.filter { $0.title == "B" }.map(\.id))

        #expect(store.entries.map(\.title) == ["A"])
    }

    @Test("clearing forgets every visit")
    func clearEmpties() {
        let store = HistoryStore()
        store.record(url: url("https://a.example"), isPrivate: false, now: date(1))
        store.record(url: url("https://b.example"), isPrivate: false, now: date(2))
        store.clear()

        #expect(store.entries.isEmpty)
    }

    @Test("the entries persist, and a clear persists too")
    func persists() async {
        let persistence = InMemoryHistoryPersistence()
        let store = HistoryStore(persistence: persistence)
        store.record(url: url("https://a.example"), title: "A", isPrivate: false, now: date(1))
        store.record(url: url("https://b.example"), title: "B", isPrivate: false, now: date(2))
        await store.flushWrites()

        let reloaded = HistoryStore(persistence: persistence)
        await reloaded.loadIndex()
        #expect(reloaded.entries == store.entries)
        #expect(reloaded.entries.map(\.title) == ["B", "A"])

        reloaded.clear()
        await reloaded.flushWrites()
        let again = HistoryStore(persistence: persistence)
        await again.loadIndex()
        #expect(again.entries.isEmpty)
    }

    @Test("the file on disk round-trips")
    func fileRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(persistence: FileSystemHistoryPersistence(directory: directory))
        store.record(url: url("https://a.example"), title: "A", isPrivate: false, now: date(1_700_000_000))
        await store.flushWrites()

        let reloaded = HistoryStore(persistence: FileSystemHistoryPersistence(directory: directory))
        await reloaded.loadIndex()
        #expect(reloaded.entries == store.entries)
    }

    @Test("history rows fall into the archive's day bands")
    func groupsByDay() {
        let calendar = Calendar(identifier: .gregorian)
        let now = date(1_700_000_000)
        let entries = [
            HistoryEntry(url: url("https://a.example"), title: "A", visitedAt: now - 60),
            HistoryEntry(url: url("https://b.example"), title: "B", visitedAt: now - 86_400 - 60),
        ]
        let bands = ArchiveGrouping.bands(of: entries, date: \.visitedAt, now: now, calendar: calendar)

        #expect(bands.map(\.title).first == "Today")
        #expect(bands.flatMap(\.items).count == 2)
    }

    @Test("removed entries come back where their dates place them")
    func reinstateEntries() {
        let store = HistoryStore()
        store.record(url: url("https://a.example/one"), title: "One", isPrivate: false, now: date(1))
        store.record(url: url("https://b.example/two"), title: "Two", isPrivate: false, now: date(2))
        store.record(url: url("https://c.example/three"), title: "Three", isPrivate: false, now: date(3))

        let removed = store.remove(store.entries.filter { $0.title == "Two" }.map(\.id))
        #expect(store.entries.map(\.title) == ["Three", "One"])

        store.reinstate(removed)
        store.reinstate(removed)
        #expect(store.entries.map(\.title) == ["Three", "Two", "One"])
    }
}
