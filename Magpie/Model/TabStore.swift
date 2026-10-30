import Foundation
import Observation

/// The open tabs in stack order, the tab the stack centres on, and the archive.
///
/// Every change schedules a write of the JSON index; snapshots are written as their own
/// files. All work with the index happens on the main actor and all file work inside the
/// persistence actor. Every method that needs the time takes `now`, so tests drive the clock.
@MainActor
@Observable
final class TabStore {
    /// The open tabs, in stack order.
    private(set) var tabs: [Tab] = []
    /// The centred tab; the one auto-archive never takes.
    private(set) var currentTabID: Tab.ID?
    /// The archived tabs, oldest first.
    private(set) var archivedTabs: [Tab] = []

    /// Auto-archive runs after one day by default.
    static let autoArchiveDefault: TimeInterval = 24 * 60 * 60
    /// The adjustable range: 12 hours to 30 days.
    static let autoArchiveRange: ClosedRange<TimeInterval> = 12 * 60 * 60...30 * 24 * 60 * 60
    /// The archive keeps tabs for 30 days, then deletes them.
    static let archiveRetention: TimeInterval = 30 * 24 * 60 * 60

    private let persistence: TabPersistence?
    private var indexWrite: Task<Void, Never>?
    private var snapshotWrites: [Tab.ID: Task<Void, Never>] = [:]

    /// The current tab, if any.
    var currentTab: Tab? { tabs.first { $0.id == currentTabID } }

    /// An empty store with nothing behind it.
    init(persistence: TabPersistence? = nil) {
        self.persistence = persistence
    }

    /// Loads the saved index into a fresh store.
    static func open(persistence: TabPersistence) async -> TabStore {
        let store = TabStore(persistence: persistence)
        if let index = try? await persistence.loadIndex() {
            store.tabs = index.openTabs
            store.archivedTabs = index.archivedTabs
            store.currentTabID =
                index.currentTabID.flatMap { id in
                    store.tabs.contains { $0.id == id } ? id : nil
                } ?? store.tabs.first?.id
        }
        return store
    }

    // MARK: Open tabs

    /// Opens a new tab and makes it current.
    @discardableResult
    func newTab(
        url: URL? = nil,
        title: String = "",
        faviconURL: URL? = nil,
        faviconData: Data? = nil,
        now: Date
    ) -> Tab {
        let tab = Tab(
            url: url, title: title, faviconURL: faviconURL, faviconData: faviconData, lastActive: now)
        tabs.append(tab)
        currentTabID = tab.id
        saveIndex()
        return tab
    }

    /// Centres a tab in the stack. Browsing the stack is not use: only opening a
    /// tab or navigating in it marks it active.
    func select(_ id: Tab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        currentTabID = id
        saveIndex()
    }

    /// Makes the tab current and marks it active — opening it, or navigating in it.
    func activate(_ id: Tab.ID, now: Date) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        currentTabID = id
        tabs[i].lastActive = now
        saveIndex()
    }

    /// Marks the tab active without changing which tab is current.
    func touch(_ id: Tab.ID, now: Date) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[i].lastActive = now
        saveIndex()
    }

    /// Closes the tab. Closing the current tab hands currency to the neighbour on its
    /// right, or the one on its left when there is no right neighbour.
    func close(_ id: Tab.ID) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasCurrent = currentTabID == id
        tabs.remove(at: i)
        if wasCurrent {
            currentTabID = tabs.indices.contains(i) ? tabs[i].id : tabs.last?.id
        }
        forgetSnapshot(for: id)
        saveIndex()
    }

    /// Moves the tab to a new place in the stack.
    func move(_ id: Tab.ID, to index: Int) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: i)
        let target = min(max(index, 0), tabs.count)
        tabs.insert(tab, at: target)
        saveIndex()
    }

    // MARK: Snapshots

    /// Stores the tab's page snapshot, in memory and as its own file. A nil clears it.
    func setSnapshot(_ data: Data?, for id: Tab.ID) {
        guard tabIndex(id) != nil else { return }
        applySnapshot(data, for: id)
        scheduleSnapshotWrite(data, for: id)
    }

    /// The tab's snapshot, from memory when it is there and otherwise from its file.
    func loadSnapshot(for id: Tab.ID) async -> Data? {
        if let data = self[id]?.snapshot { return data }
        guard let data = await persistence?.loadSnapshot(for: id) else { return nil }
        applySnapshot(data, for: id)
        return data
    }

    // MARK: Archive

    /// Moves every tab untouched for longer than `after` into the archive. The current
    /// tab is never taken. A nil `after` turns auto-archive off.
    @discardableResult
    func archiveStale(now: Date, after: TimeInterval?) -> [Tab.ID] {
        guard let after else { return [] }
        let stale = tabs.filter {
            $0.id != currentTabID && now.timeIntervalSince($0.lastActive) >= after
        }
        guard !stale.isEmpty else { return [] }
        let ids = stale.map(\.id)
        for tab in stale {
            var archived = tab
            archived.archivedAt = now
            archivedTabs.append(archived)
        }
        tabs.removeAll { ids.contains($0.id) }
        saveIndex()
        return ids
    }

    /// Keeps a chosen auto-archive interval inside the 12 hour to 30 day range.
    static func clampedAutoArchiveInterval(_ interval: TimeInterval) -> TimeInterval {
        min(max(interval, autoArchiveRange.lowerBound), autoArchiveRange.upperBound)
    }

    /// Deletes archived tabs that have been archived for `retention` or longer.
    @discardableResult
    func purgeArchived(now: Date, retention: TimeInterval = archiveRetention) -> [Tab.ID] {
        let expired = archivedTabs.filter {
            now.timeIntervalSince($0.archivedAt ?? now) >= retention
        }
        guard !expired.isEmpty else { return [] }
        let ids = expired.map(\.id)
        archivedTabs.removeAll { ids.contains($0.id) }
        for id in ids { forgetSnapshot(for: id) }
        saveIndex()
        return ids
    }

    /// Brings an archived tab back as the current open tab.
    @discardableResult
    func restore(_ id: Tab.ID, now: Date) -> Bool {
        guard let i = archivedTabs.firstIndex(where: { $0.id == id }) else { return false }
        var tab = archivedTabs.remove(at: i)
        tab.archivedAt = nil
        tab.lastActive = now
        tabs.append(tab)
        currentTabID = id
        saveIndex()
        return true
    }

    // MARK: Writes

    /// Awaits every write scheduled so far, so tests can look at what was stored.
    func flushWrites() async {
        await indexWrite?.value
        for write in snapshotWrites.values { await write.value }
    }

    /// The index as written: the snapshots stay out of it.
    private func strippedIndex() -> TabIndex {
        func strip(_ tab: Tab) -> Tab {
            var stripped = tab
            stripped.snapshot = nil
            return stripped
        }
        return TabIndex(
            openTabs: tabs.map(strip),
            currentTabID: currentTabID,
            archivedTabs: archivedTabs.map(strip))
    }

    /// Writes chain, so a later index never lands before an earlier one.
    private func saveIndex() {
        guard let persistence else { return }
        let index = strippedIndex()
        let previous = indexWrite
        indexWrite = Task { [persistence] in
            await previous?.value
            try? await persistence.saveIndex(index)
        }
    }

    private func scheduleSnapshotWrite(_ data: Data?, for id: Tab.ID) {
        guard let persistence else { return }
        let previous = snapshotWrites[id]
        snapshotWrites[id] = Task { [persistence] in
            await previous?.value
            if let data {
                try? await persistence.saveSnapshot(data, for: id)
            } else {
                try? await persistence.deleteSnapshot(for: id)
            }
        }
    }

    /// Drops the tab's snapshot everywhere, including its file.
    private func forgetSnapshot(for id: Tab.ID) {
        if let i = tabs.firstIndex(where: { $0.id == id }) { tabs[i].snapshot = nil }
        if let i = archivedTabs.firstIndex(where: { $0.id == id }) { archivedTabs[i].snapshot = nil }
        scheduleSnapshotWrite(nil, for: id)
    }

    private func applySnapshot(_ data: Data?, for id: Tab.ID) {
        if let i = tabs.firstIndex(where: { $0.id == id }) {
            tabs[i].snapshot = data
        } else if let i = archivedTabs.firstIndex(where: { $0.id == id }) {
            archivedTabs[i].snapshot = data
        }
    }

    private func tabIndex(_ id: Tab.ID) -> Int? {
        tabs.firstIndex { $0.id == id }
    }

    private subscript(id: Tab.ID) -> Tab? {
        tabs.first { $0.id == id }
    }
}
