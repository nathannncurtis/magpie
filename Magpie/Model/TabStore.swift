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
        await store.loadIndex()
        return store
    }

    /// Reads the saved index into this store.
    func loadIndex() async {
        guard let persistence, let index = try? await persistence.loadIndex() else { return }
        tabs = index.openTabs
        archivedTabs = index.archivedTabs
        currentTabID =
            index.currentTabID.flatMap { id in
                tabs.contains { $0.id == id } ? id : nil
            } ?? tabs.first?.id
    }

    // MARK: Open tabs

    /// Opens a new tab and makes it current.
    @discardableResult
    func newTab(
        url: URL? = nil,
        title: String = "",
        faviconURL: URL? = nil,
        faviconData: Data? = nil,
        isPrivate: Bool = false,
        now: Date
    ) -> Tab {
        let tab = Tab(
            url: url, title: title, faviconURL: faviconURL, faviconData: faviconData, lastActive: now,
            isPrivate: isPrivate)
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

    /// Brings the tab in step with its page: where it is, what it's called, its site's own
    /// icon, and when it was last read. A new icon address drops the bytes the old one
    /// left behind. Nothing without a page behind it moves it.
    func update(id: Tab.ID, url: URL?, title: String, faviconURL: URL?, now: Date) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = false
        if let url, tabs[i].url != url {
            tabs[i].url = url
            changed = true
        }
        if !trimmed.isEmpty, tabs[i].title != trimmed {
            tabs[i].title = trimmed
            changed = true
        }
        if let faviconURL, tabs[i].faviconURL != faviconURL {
            tabs[i].faviconURL = faviconURL
            tabs[i].faviconData = nil
            changed = true
        }
        guard changed else { return }
        tabs[i].lastActive = now
        saveIndex()
    }

    /// The site's icon onto the tab, open or archived: the bytes the card's label and the
    /// archive rows show in place of the letter tile. They land in the index with the tab.
    func setFavicon(_ data: Data, for id: Tab.ID) {
        if let i = tabs.firstIndex(where: { $0.id == id }) {
            guard tabs[i].faviconData != data else { return }
            tabs[i].faviconData = data
        } else if let i = archivedTabs.firstIndex(where: { $0.id == id }) {
            guard archivedTabs[i].faviconData != data else { return }
            archivedTabs[i].faviconData = data
        } else {
            return
        }
        saveIndex()
    }

    /// Closes the tab. Closing the current tab hands currency to the neighbour on its
    /// right, or the one on its left when there is no right neighbour.
    func close(_ id: Tab.ID) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasCurrent = currentTabID == id
        let wasPrivate = tabs[i].isPrivate
        tabs.remove(at: i)
        if wasCurrent {
            currentTabID = tabs.indices.contains(i) ? tabs[i].id : tabs.last?.id
        }
        if wasPrivate {
            // Nothing of it was ever on disk.
            saveIndex()
            return
        }
        forgetSnapshot(for: id)
        saveIndex()
    }

    /// Whether any private tab is open.
    var hasPrivateTabs: Bool {
        tabs.contains(where: \.isPrivate)
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
        guard let i = tabIndex(id) else { return }
        applySnapshot(data, for: id)
        // A private tab's picture lives in memory only.
        guard !tabs[i].isPrivate else { return }
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
        // Private tabs never reach the archive: it is written to disk.
        let stale = tabs.filter {
            !$0.isPrivate && $0.id != currentTabID && now.timeIntervalSince($0.lastActive) >= after
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

    /// Deletes archived tabs for good, snapshot files included.
    func deleteArchived(_ ids: [Tab.ID]) {
        let doomed = Set(ids)
        guard archivedTabs.contains(where: { doomed.contains($0.id) }) else { return }
        archivedTabs.removeAll { doomed.contains($0.id) }
        for id in ids { forgetSnapshot(for: id) }
        saveIndex()
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
        // Private tabs never reach the disk; a private current tab is written as none.
        let saved = tabs.filter { !$0.isPrivate }
        let current = saved.contains { $0.id == currentTabID } ? currentTabID : nil
        return TabIndex(
            openTabs: saved.map(strip),
            currentTabID: current,
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
