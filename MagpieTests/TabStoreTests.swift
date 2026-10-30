import Foundation
import Testing

@testable import Magpie

@Suite("TabStore")
@MainActor
struct TabStoreTests {

    /// Dates from a zero base, so threshold comparisons stay exact.
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    @Test("a new tab is appended and becomes current")
    func newTabBecomesCurrent() {
        let store = TabStore()
        let first = store.newTab(url: URL(string: "https://a.example"), title: "A", now: date(0))
        let second = store.newTab(url: URL(string: "https://b.example"), title: "B", now: date(10))

        #expect(store.tabs.map(\.id) == [first.id, second.id])
        #expect(store.currentTabID == second.id)
        #expect(store.currentTab?.id == second.id)
        #expect(store.tabs.last?.lastActive == date(10))
        #expect(store.tabs.last?.url == URL(string: "https://b.example"))
    }

    @Test("select makes a tab current and marks it active")
    func selectTouches() {
        let store = TabStore()
        let first = store.newTab(title: "A", now: date(0))
        store.newTab(title: "B", now: date(10))

        store.select(first.id, now: date(20))

        #expect(store.currentTabID == first.id)
        #expect(store.tabs.first?.lastActive == date(20))
        #expect(store.tabs.last?.lastActive == date(10))
    }

    @Test("touch marks a tab active without changing currency")
    func touchKeepsCurrent() {
        let store = TabStore()
        let first = store.newTab(title: "A", now: date(0))
        store.newTab(title: "B", now: date(10))

        store.touch(first.id, now: date(30))

        #expect(store.currentTabID == store.tabs.last?.id)
        #expect(store.tabs.first?.lastActive == date(30))
    }

    @Test("closing the current tab picks the neighbour to the right")
    func closeCurrentPicksRight() {
        let store = TabStore()
        let a = store.newTab(title: "A", now: date(0))
        let b = store.newTab(title: "B", now: date(0))
        let c = store.newTab(title: "C", now: date(0))

        store.close(b.id)

        #expect(store.tabs.map(\.id) == [a.id, c.id])
        #expect(store.currentTabID == c.id)
    }

    @Test("closing the last tab picks the neighbour to the left")
    func closeLastPicksLeft() {
        let store = TabStore()
        let a = store.newTab(title: "A", now: date(0))
        let b = store.newTab(title: "B", now: date(0))

        store.close(b.id)

        #expect(store.tabs.map(\.id) == [a.id])
        #expect(store.currentTabID == a.id)
    }

    @Test("closing the only tab clears currency")
    func closeOnlyTab() {
        let store = TabStore()
        let a = store.newTab(title: "A", now: date(0))

        store.close(a.id)

        #expect(store.tabs.isEmpty)
        #expect(store.currentTabID == nil)
    }

    @Test("closing a tab that is not current keeps the current tab")
    func closeNonCurrent() {
        let store = TabStore()
        let a = store.newTab(title: "A", now: date(0))
        let b = store.newTab(title: "B", now: date(0))
        let c = store.newTab(title: "C", now: date(0))
        store.select(a.id, now: date(1))

        store.close(b.id)

        #expect(store.tabs.map(\.id) == [a.id, c.id])
        #expect(store.currentTabID == a.id)
    }

    @Test("move puts a tab where it is told, clamped to the stack")
    func moveReorders() {
        let store = TabStore()
        let a = store.newTab(title: "A", now: date(0))
        let b = store.newTab(title: "B", now: date(0))
        let c = store.newTab(title: "C", now: date(0))
        let d = store.newTab(title: "D", now: date(0))

        store.move(d.id, to: 0)
        #expect(store.tabs.map(\.id) == [d.id, a.id, b.id, c.id])

        store.move(a.id, to: 9)
        #expect(store.tabs.map(\.id) == [d.id, b.id, c.id, a.id])
    }

    @Test("closing a tab deletes its snapshot file")
    func closeDeletesSnapshot() async {
        let persistence = InMemoryTabPersistence()
        let store = TabStore(persistence: persistence)
        let tab = store.newTab(title: "A", now: date(0))
        store.setSnapshot(Data([1, 2, 3]), for: tab.id)
        await store.flushWrites()

        #expect(await persistence.loadSnapshot(for: tab.id) == Data([1, 2, 3]))

        store.close(tab.id)
        await store.flushWrites()

        #expect(await persistence.loadSnapshot(for: tab.id) == nil)
    }

    // MARK: Auto-archive

    @Test("a tab untouched past the set time is archived")
    func staleTabArchived() {
        let store = TabStore()
        let stale = store.newTab(url: URL(string: "https://stale.example"), title: "Stale", now: date(0))
        store.newTab(title: "Fresh", now: date(86_400))

        let archived = store.archiveStale(now: date(86_400 + 3_600), after: 86_400)

        #expect(archived == [stale.id])
        #expect(store.tabs.map(\.title) == ["Fresh"])
        #expect(store.archivedTabs.map(\.id) == [stale.id])
        #expect(store.archivedTabs.first?.archivedAt == date(86_400 + 3_600))
    }

    @Test("a tab at exactly the threshold is archived")
    func exactlyAtThresholdArchived() {
        let store = TabStore()
        let stale = store.newTab(title: "Stale", now: date(0))
        store.newTab(title: "Current", now: date(0))

        let archived = store.archiveStale(now: date(86_400), after: 86_400)

        #expect(archived == [stale.id])
    }

    @Test("a tab just short of the threshold stays open")
    func justShortStaysOpen() {
        let store = TabStore()
        let almost = store.newTab(title: "Almost", now: date(1))
        store.newTab(title: "Current", now: date(0))

        let archived = store.archiveStale(now: date(86_400), after: 86_400)

        #expect(archived.isEmpty)
        #expect(store.tabs.map(\.id).contains(almost.id))
    }

    @Test("the current tab is never auto-archived")
    func currentTabExempt() {
        let store = TabStore()
        store.newTab(title: "Stale one", now: date(0))
        let current = store.newTab(title: "Stale current", now: date(0))

        let archived = store.archiveStale(now: date(10 * 86_400), after: 86_400)

        #expect(!archived.contains(current.id))
        #expect(store.currentTabID == current.id)
        #expect(store.tabs.map(\.id) == [current.id])
    }

    @Test("a nil interval turns auto-archive off")
    func nilIntervalDisables() {
        let store = TabStore()
        store.newTab(title: "Stale", now: date(0))
        store.newTab(title: "Current", now: date(0))

        let archived = store.archiveStale(now: date(30 * 86_400), after: nil)

        #expect(archived.isEmpty)
        #expect(store.tabs.count == 2)
    }

    @Test("the interval clamps to 12 hours through 30 days")
    func intervalClamping() {
        #expect(TabStore.autoArchiveDefault == 86_400)
        #expect(TabStore.autoArchiveRange.lowerBound == 12 * 3_600)
        #expect(TabStore.autoArchiveRange.upperBound == 30 * 86_400)
        #expect(TabStore.clampedAutoArchiveInterval(60) == 12 * 3_600)
        #expect(TabStore.clampedAutoArchiveInterval(45 * 86_400) == 30 * 86_400)
        #expect(TabStore.clampedAutoArchiveInterval(86_400) == 86_400)
    }

    // MARK: Retention

    @Test("archived tabs are purged at 30 days")
    func purgeAtRetention() {
        let store = TabStore()
        let old = store.newTab(title: "Old", now: date(0))
        store.newTab(title: "Current", now: date(0))
        store.archiveStale(now: date(0), after: 0)

        let purged = store.purgeArchived(now: date(30 * 86_400))

        #expect(purged == [old.id])
        #expect(store.archivedTabs.isEmpty)
    }

    @Test("archived tabs younger than 30 days stay")
    func purgeKeepsYounger() {
        let store = TabStore()
        store.newTab(title: "Young", now: date(0))
        store.newTab(title: "Current", now: date(0))
        store.archiveStale(now: date(0), after: 0)

        let purged = store.purgeArchived(now: date(29 * 86_400))

        #expect(purged.isEmpty)
        #expect(store.archivedTabs.count == 1)
    }

    @Test("purging deletes the snapshot file")
    func purgeDeletesSnapshot() async {
        let persistence = InMemoryTabPersistence()
        let store = TabStore(persistence: persistence)
        let old = store.newTab(title: "Old", now: date(0))
        store.setSnapshot(Data([4, 5]), for: old.id)
        store.newTab(title: "Current", now: date(0))
        await store.flushWrites()

        store.archiveStale(now: date(0), after: 0)
        let purged = store.purgeArchived(now: date(30 * 86_400))
        await store.flushWrites()

        #expect(purged == [old.id])
        #expect(await persistence.loadSnapshot(for: old.id) == nil)
    }

    // MARK: Restore

    @Test("restoring brings an archived tab back as the current tab")
    func restoreMakesCurrent() {
        let store = TabStore()
        let a = store.newTab(title: "A", now: date(0))
        let current = store.newTab(title: "Current", now: date(100_000))
        store.archiveStale(now: date(100_000), after: 86_400)
        #expect(store.archivedTabs.map(\.id) == [a.id])

        let restored = store.restore(a.id, now: date(100_050))

        #expect(restored)
        #expect(store.archivedTabs.isEmpty)
        #expect(store.tabs.map(\.id) == [current.id, a.id])
        #expect(store.currentTabID == a.id)
        #expect(store.tabs.last?.archivedAt == nil)
        #expect(store.tabs.last?.lastActive == date(100_050))
        #expect(!store.restore(a.id, now: date(100_060)))
    }
}
