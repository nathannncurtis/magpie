import Foundation
import Observation

/// The open tabs in stack order, the tab the stack centers on, and the archive.
///
/// Every change schedules a write of the JSON index; snapshots are written as their own
/// files. All work with the index happens on the main actor and all file work inside the
/// persistence actor. Every method that needs the time takes `now`, so tests drive the clock.
@MainActor
@Observable
final class TabStore {
    /// The open tabs, in stack order.
    private(set) var tabs: [Tab] = []
    /// The centered tab; the one auto-archive never takes.
    private(set) var currentTabID: Tab.ID?
    /// The archived tabs, oldest first.
    private(set) var archivedTabs: [Tab] = []

    /// Auto-archive runs after one day by default.
    static let autoArchiveDefault: TimeInterval = 24 * 60 * 60
    /// The adjustable range: 12 hours to 30 days.
    static let autoArchiveRange: ClosedRange<TimeInterval> = 12 * 60 * 60...30 * 24 * 60 * 60
    /// The archive keeps tabs for 30 days, then deletes them.
    static let archiveRetention: TimeInterval = 30 * 24 * 60 * 60

    /// Each mode's own current tab, so flipping between ordinary and private tabs lands
    /// back where each left off. Keyed by `isPrivate`.
    private var rememberedCurrent: [Bool: Tab.ID] = [:]

    private let persistence: TabPersistence?
    private var indexWrite: Task<Void, Never>?
    private var snapshotWrites: [Tab.ID: Task<Void, Never>] = [:]

    /// The current tab, if any.
    var currentTab: Tab? { tabs.first { $0.id == currentTabID } }

    /// The open tabs of one mode, in stack order: private tabs, or the ordinary ones.
    func tabs(inPrivate isPrivate: Bool) -> [Tab] {
        tabs.filter { $0.isPrivate == isPrivate }
    }

    /// The tab a mode centers on: the one it last had current, else its last tab.
    func currentTabID(inPrivate isPrivate: Bool) -> Tab.ID? {
        if let id = rememberedCurrent[isPrivate],
            tabs.contains(where: { $0.id == id && $0.isPrivate == isPrivate })
        {
            return id
        }
        return tabs.last { $0.isPrivate == isPrivate }?.id
    }

    /// Makes a tab current, and the one its mode comes back to.
    private func setCurrent(_ id: Tab.ID?) {
        currentTabID = id
        if let id, let tab = tabs.first(where: { $0.id == id }) {
            rememberedCurrent[tab.isPrivate] = id
        }
    }

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
        setCurrent(
            index.currentTabID.flatMap { id in
                tabs.contains { $0.id == id } ? id : nil
            } ?? tabs.first?.id)
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
        setCurrent(tab.id)
        saveIndex()
        return tab
    }

    /// Centres a tab in the stack. Browsing the stack is not use: only opening a
    /// tab or navigating in it marks it active.
    func select(_ id: Tab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        setCurrent(id)
        saveIndex()
    }

    /// Makes the tab current and marks it active — opening it, or navigating in it.
    func activate(_ id: Tab.ID, now: Date) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        setCurrent(id)
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
            // The place belonged to the page left behind.
            tabs[i].scrollOffset = nil
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

    /// Keeps how far down its page the open tab was read, so a rebuilt page can scroll back.
    /// A private tab keeps it in memory only: the index never carries a private tab.
    func setScrollOffset(_ offset: Double?, for id: Tab.ID) {
        guard let i = tabIndex(id) else { return }
        let kept = offset.flatMap { $0 > 0 ? $0 : nil }
        guard tabs[i].scrollOffset != kept else { return }
        tabs[i].scrollOffset = kept
        if !tabs[i].isPrivate { saveIndex() }
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

    /// A tab just closed, with what it takes to put it back where it was.
    struct ClosedTab: Equatable, Sendable {
        let tab: Tab
        /// Its place in the stack.
        let index: Int
        /// Whether it was the centered tab.
        let wasCurrent: Bool
    }

    /// Closes the tab. Closing the current tab hands currency to the neighbor of its own
    /// mode on its right, or the one on its left when there is no right neighbor. Returns
    /// the tab as it was, in memory only, for an undo.
    @discardableResult
    func close(_ id: Tab.ID) -> ClosedTab? {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        let wasCurrent = currentTabID == id
        let wasPrivate = tabs[i].isPrivate
        let closed = ClosedTab(tab: tabs[i], index: i, wasCurrent: wasCurrent)
        tabs.remove(at: i)
        if wasCurrent {
            let sameMode = tabs.indices.filter { tabs[$0].isPrivate == wasPrivate }
            let next = sameMode.first { $0 >= i } ?? sameMode.last
            setCurrent(next.map { tabs[$0].id } ?? tabs.last?.id)
        }
        if wasPrivate {
            // Nothing of it was ever on disk.
            saveIndex()
            return closed
        }
        forgetSnapshot(for: id)
        saveIndex()
        return closed
    }

    /// Puts a closed tab back in its place, and back at the center when it was there. The
    /// snapshot file closing deleted is written again.
    func reinstate(_ closed: ClosedTab) {
        guard !tabs.contains(where: { $0.id == closed.tab.id }) else { return }
        tabs.insert(closed.tab, at: min(closed.index, tabs.count))
        if closed.wasCurrent { setCurrent(closed.tab.id) }
        if !closed.tab.isPrivate, let snapshot = closed.tab.snapshot {
            scheduleSnapshotWrite(snapshot, for: closed.tab.id)
        }
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
            !$0.isPrivate && $0.id != currentTabID(inPrivate: false) && now.timeIntervalSince($0.lastActive) >= after
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
        setCurrent(id)
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
        // Private tabs never reach the disk; the ordinary mode's current tab is the one
        // written, whichever mode is up.
        let saved = tabs.filter { !$0.isPrivate }
        let current = currentTabID(inPrivate: false)
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
