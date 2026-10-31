import Foundation
import Observation

/// Which surface is up (04 · the navigation map).
enum Surface: Equatable {
    /// The mist with the search sheet: a cold start with no tabs, the + on the tabs screen,
    /// or the last tab closing.
    case launchSearch
    /// Reading, with the search sheet over the page while it is open.
    case reading(searchOpen: Bool)
    /// The tab stack.
    case tabs
    /// The archive, over whatever screen opened it.
    case archive
    /// The bookmarks, over whatever screen opened it.
    case bookmarks
}

/// The app's own state: the tabs, the engine, the recents, and which surface is up.
///
/// Each open tab owns its own page session. A bounded number stay live — the current tab
/// plus the most recently read others — and the rest load again from their address when
/// they are opened.
@MainActor
@Observable
final class AppModel {

    /// How many page sessions stay live at once: the current tab plus the most recent others.
    static let liveSessionCount = 4

    /// The open tabs, the current one, and the archive.
    let store: TabStore
    /// The saved bookmarks and their folders.
    let bookmarks: BookmarkStore
    /// The engine searches run on. The picker lands later, so it stays the default.
    private(set) var engine: SearchEngine
    /// Where the search sheet's suggestion rows come from.
    let suggestions: any SuggestionProviding
    /// Recent searches.
    let recents: any RecentSearchStoring

    /// Nil until `start` has loaded the saved tabs: the app shows the mist while that
    /// happens, and the restored surface lands with nothing animating.
    private(set) var surface: Surface?

    /// The live page sessions, by tab.
    private(set) var sessions: [Tab.ID: ReadingSession] = [:]
    private var sessionTasks: [Tab.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var captureGates: [Tab.ID: CaptureGate] = [:]
    @ObservationIgnored private var captureDrains: [Tab.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var captureRetries: [Tab.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var retryAttempts: [Tab.ID: Int] = [:]

    init(
        store: TabStore = TabStore(),
        bookmarks: BookmarkStore = BookmarkStore(),
        engine: SearchEngine = .default,
        suggestions: any SuggestionProviding = SuggestionService(),
        recents: any RecentSearchStoring = RecentSearches()
    ) {
        self.store = store
        self.bookmarks = bookmarks
        self.engine = engine
        self.suggestions = suggestions
        self.recents = recents
    }

    /// The app as it runs on a device: the JSON indexes in Application Support.
    static func live() -> AppModel {
        AppModel(
            store: TabStore(persistence: FileSystemTabPersistence()),
            bookmarks: BookmarkStore(persistence: FileSystemBookmarkPersistence()))
    }

    // MARK: Lifecycle

    /// Loads the saved tabs and bookmarks, archives what went stale, and lands on the
    /// surface to open on.
    func start(now: Date = .now) async {
        await store.loadIndex()
        await bookmarks.loadIndex()
        refreshArchive(now: now)
        coldStart()
    }

    /// A cold start: restore the last tab, with nothing animating, or open on the launch
    /// search when there is no tab to restore.
    func coldStart() {
        guard let tab = store.currentTab else {
            surface = .launchSearch
            return
        }
        _ = ensureSession(for: tab)
        surface = .reading(searchOpen: false)
    }

    /// Auto-archive, on every launch and every return to the foreground.
    func refreshArchive(now: Date = .now) {
        _ = store.archiveStale(now: now, after: TabStore.autoArchiveDefault)
        _ = store.purgeArchived(now: now)
        dropSessions(notIn: Set(store.tabs.map(\.id)))
    }

    // MARK: Sessions

    /// The current tab's live session, when it has one.
    var currentSession: ReadingSession? {
        store.currentTab.flatMap { sessions[$0.id] }
    }

    /// Pages that still owe their tab a picture while no reading screen shows them. WebKit
    /// stops drawing a page that is out of the window, so a tab left before its page drew
    /// would never get one; the root keeps these in the window, unseen, until it lands.
    /// A page can be in only one web view at a time, so the tab a reading screen shows —
    /// up, or on its way in or out — is never kept here.
    var pagesStillDrawing: [ReadingSession] {
        let readingUp: Bool = {
            if case .reading = surface { return true }
            return readingScreenMounted
        }()
        let shown = readingUp ? store.currentTabID : nil
        return store.tabs.compactMap { tab in
            guard tab.id != shown, tab.snapshot == nil, let session = sessions[tab.id],
                session.failure == nil
            else { return nil }
            return session
        }
    }

    /// Whether a reading screen is in the hierarchy, set by the screen itself: it stays
    /// through its leaving transition, after the surface has already moved on.
    var readingScreenMounted = false

    /// The tab's page session, made on demand and kept in step with the tab. A reused
    /// session whose page is already loaded settles again, so it still gets its picture.
    func ensureSession(for tab: Tab) -> ReadingSession {
        if let session = sessions[tab.id] {
            refireSettleIfPictureless(tab, session: session)
            return session
        }
        let session = ReadingSession(url: tab.url ?? Self.blankPage)
        session.logTag = "tab=\(tab.id.uuidString.prefix(4))"
        session.viewportSize = restingPageSize
        sessions[tab.id] = session
        sessionTasks[tab.id] = Task { await session.run() }
        session.onPageSettled = { [weak self] in self?.pageSettled(for: tab.id) }
        session.onPageTitled = { [weak self] in self?.syncTab(for: tab.id) }
        pruneSessions()
        return session
    }

    private static let blankPage = URL(string: "about:blank") ?? URL(fileURLWithPath: "/")

    /// The page area's size while the reading screen was last at rest. A session made
    /// with no reading screen up — an address submitted and left at once — still needs a
    /// region to capture at, and no screen will measure one for it.
    @ObservationIgnored private var restingPageSize: CGSize?

    /// The reading screen's word for the page area's size. The fact is remembered for
    /// sessions made with no screen up, and handed to any session off screen — its own
    /// screen may have left before its size held, or squeezed on the way out.
    func notePageSize(_ size: CGSize) {
        restingPageSize = size
        for (_, session) in sessions {
            session.noteViewport(size)
        }
    }

    /// Keeps only the current tab's session and the most recently read others.
    private func pruneSessions() {
        dropSessions(notIn: liveTabIDs())
    }

    /// The tabs whose sessions stay live.
    private func liveTabIDs() -> Set<Tab.ID> {
        guard let current = store.currentTabID else { return [] }
        let recent = store.tabs
            .filter { $0.id != current }
            .sorted { $0.lastActive > $1.lastActive }
            .prefix(Self.liveSessionCount - 1)
        return Set(recent.map(\.id)).union([current])
    }

    private func dropSessions(notIn keep: Set<Tab.ID>) {
        for (id, task) in sessionTasks where !keep.contains(id) {
            task.cancel()
            sessionTasks[id] = nil
            sessions[id] = nil
        }
    }

    /// Brings the tab in step with its page: where it is, what it's called, its site's icon.
    private func syncTab(for id: Tab.ID) {
        guard let session = sessions[id] else { return }
        store.update(
            id: id,
            url: session.page.url,
            title: session.page.title,
            faviconURL: session.pageIconURL,
            now: .now)
    }

    /// A page settled: the tab takes what the page now shows. The capture is debounced — a
    /// settle that lands while one is still in flight replaces it.
    private func pageSettled(for id: Tab.ID) {
        SnapshotLog.event("settle fired tab=\(id.uuidString.prefix(4))")
        syncTab(for: id)
        captureSnapshot(for: id, trigger: "settle")
    }

    /// A reused session whose page has settled with no picture — a tab switched back to,
    /// or one restored — settles again, with its viewport already known. Only a page that
    /// truly settled: one still in flight would write its half-state onto the tab.
    private func refireSettleIfPictureless(_ tab: Tab, session: ReadingSession) {
        guard
            session.hasSettled,
            session.failure == nil,
            store.tabs.first(where: { $0.id == tab.id })?.snapshot == nil
        else { return }
        pageSettled(for: tab.id)
    }

    /// How long capture triggers wait for their neighbours: geometry, session and URL
    /// landing in the same frame are one moment, one capture.
    private static let captureDebounce: Duration = .milliseconds(150)

    /// One tab's place in the capture pipeline. `pendingTrigger` is the debounced capture
    /// to run; `rerunTrigger` is the one trigger that may land while a capture runs.
    private struct CaptureGate {
        var isRunning = false
        var pendingTrigger: String?
        var rerunTrigger: String?
    }

    /// The nil-capture backoff ladder: a pictureless tab that is still current tries
    /// again at these delays, then waits for the next real opportunity.
    private static let captureRetryDelays: [Duration] = [
        .milliseconds(400), .milliseconds(800), .milliseconds(1_600), .milliseconds(3_200),
    ]

    /// The page's picture onto its tab. Triggers coalesce: they wait out the debounce,
    /// one capture runs at a time, and a trigger that lands while one runs asks for
    /// exactly one rerun after it — the page and its view answer one caller at a time,
    /// and captures left to overlap have been seen to starve each other into nil.
    /// Nothing is cancelled mid-flight. A real trigger resets the retry ladder.
    private func captureSnapshot(for id: Tab.ID, trigger: String) {
        captureRetries[id]?.cancel()
        captureRetries[id] = nil
        retryAttempts[id] = 0
        enqueueCapture(for: id, trigger: trigger)
    }

    private func enqueueCapture(for id: Tab.ID, trigger: String) {
        var gate = captureGates[id] ?? CaptureGate()
        if gate.isRunning {
            gate.rerunTrigger = trigger
        } else {
            gate.pendingTrigger = trigger
        }
        captureGates[id] = gate
        guard captureDrains[id] == nil else { return }
        captureDrains[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.captureDebounce)
            await self?.drainCaptures(for: id)
            self?.captureDrains[id] = nil
        }
    }

    /// The pending captures, one at a time.
    private func drainCaptures(for id: Tab.ID) async {
        while true {
            var gate = captureGates[id] ?? CaptureGate()
            guard !gate.isRunning, let trigger = gate.pendingTrigger else { return }
            gate.isRunning = true
            gate.pendingTrigger = nil
            captureGates[id] = gate
            guard let session = sessions[id] else {
                captureGates[id] = nil
                return
            }
            // A page with no reading screen is drawn unseen only while its tab has no
            // picture; once one lands it leaves the window, and a capture of it then
            // is laid out wrong. It may fill a missing picture, never replace one.
            let pictureless = store.tabs.first(where: { $0.id == id })?.snapshot == nil
            let outcome = await session.snapshot(trigger: trigger, offScreenAllowed: pictureless)
            gate = captureGates[id] ?? CaptureGate()
            gate.isRunning = false
            if let rerun = gate.rerunTrigger {
                gate.pendingTrigger = rerun
                gate.rerunTrigger = nil
            }
            captureGates[id] = gate
            switch outcome {
            case .notReady:
                // The page has not laid out; the session's layout watch re-fires the
                // opportunity when it does. A held capture owes no retry rung.
                continue
            case .miss:
                // Nothing else is waiting: climb the ladder, if the tab still holds the
                // screen's attention.
                if captureGates[id]?.pendingTrigger == nil {
                    scheduleRetry(for: id)
                }
                continue
            case .stored(let data):
                retryAttempts[id] = 0
                store.setSnapshot(data, for: id)
                SnapshotLog.event("\(trigger) stored \(data.count)B tab=\(id.uuidString.prefix(4))")
                // The page's own colour is sampled only now that a picture exists: at
                // commit time the page has not painted yet, and script there has been
                // seen to stall the load.
                if session.pageBackground == nil {
                    await session.refreshPageBackground()
                }
            }
        }
    }

    /// A capture that came back nil on the tab that is still current tries again up the
    /// ladder; past the top it stops until a real opportunity resets the ladder.
    private func scheduleRetry(for id: Tab.ID) {
        guard store.currentTabID == id else { return }
        let attempt = retryAttempts[id] ?? 0
        guard attempt < Self.captureRetryDelays.count else { return }
        retryAttempts[id] = attempt + 1
        let delay = Self.captureRetryDelays[attempt]
        captureRetries[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.captureRetries[id] = nil
            self.enqueueCapture(for: id, trigger: "retry")
        }
    }

    // MARK: Actions

    /// A submitted search or address from the launch sheet: a new tab, opened on the spot.
    func openFromLaunch(_ url: URL, now: Date = .now) {
        let tab = store.newTab(url: url, now: now)
        _ = ensureSession(for: tab)
        surface = .reading(searchOpen: false)
    }

    /// A submitted search or address over the page: the current tab navigates.
    func navigateCurrent(_ url: URL) {
        guard let session = currentSession else {
            openFromLaunch(url)
            return
        }
        surface = .reading(searchOpen: false)
        session.open(url)
    }

    /// The URL pill: the sheet opens over the page.
    func openSearchOverPage() {
        surface = .reading(searchOpen: true)
    }

    /// A swipe down or a tap away: the sheet folds back into the bar.
    func closeSearchOverPage() {
        surface = .reading(searchOpen: false)
    }

    /// The tabs screen. The page folds into its card carrying the picture its settle
    /// captured; capturing on the way out is worthless — by the time it runs, the page is
    /// off-window and its renderer never answers.
    func showTabs() {
        surface = .tabs
    }

    /// A tapped card: its tab becomes current and opens.
    func openTab(_ id: Tab.ID, now: Date = .now) {
        guard let tab = store.tabs.first(where: { $0.id == id }) else { return }
        store.activate(id, now: now)
        _ = ensureSession(for: tab)
        surface = .reading(searchOpen: false)
    }

    /// The + on the tabs screen: the launch search, which submits into a new tab.
    func newTabFromTabs() {
        surface = .launchSearch
    }

    /// A swipe down on the launch sheet: back to the stack, when there are tabs to show.
    func dismissLaunchSearch() {
        guard !store.tabs.isEmpty else { return }
        surface = .tabs
    }

    /// A flung card. Closing the last tab leaves the launch search.
    func closeTab(_ id: Tab.ID) {
        sessionTasks[id]?.cancel()
        sessionTasks[id] = nil
        sessions[id] = nil
        store.close(id)
        if store.tabs.isEmpty {
            surface = .launchSearch
        }
    }

    // MARK: Archive and bookmarks

    /// The Archived chip on the tabs screen.
    func showArchive() {
        surface = .archive
    }

    /// The archive's Done: back to the stack, or the launch search with no tabs to show.
    func doneWithArchive() {
        surface = store.tabs.isEmpty ? .launchSearch : .tabs
    }

    /// A tapped archive row: the tab comes back and opens.
    func restoreArchivedTab(_ id: Tab.ID, now: Date = .now) {
        guard store.restore(id, now: now), let tab = store.currentTab else { return }
        _ = ensureSession(for: tab)
        surface = .reading(searchOpen: false)
    }

    /// The Bookmark tile's long press, and the UI tests' way in.
    func showBookmarks() {
        surface = .bookmarks
    }

    /// A tapped bookmark: a new tab, opened on the spot.
    func openBookmark(_ url: URL, now: Date = .now) {
        openFromLaunch(url, now: now)
    }

    /// The Bookmark tile's tap: the page the current tab shows, saved.
    @discardableResult
    func bookmarkCurrentPage(now: Date = .now) -> Bookmark? {
        guard let tab = store.currentTab, let url = tab.url else { return nil }
        return bookmarks.add(
            url: url,
            title: tab.displayTitle,
            faviconURL: tab.faviconURL,
            folder: nil,
            now: now)
    }
}
