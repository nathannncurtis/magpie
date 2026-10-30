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
    /// The mods screen.
    case mods
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
    /// The engine searches run on. The picker lands later, so it stays the default.
    private(set) var engine: SearchEngine
    /// Where the search sheet's suggestion rows come from.
    let suggestions: any SuggestionProviding
    /// Recent searches.
    let recents: any RecentSearchStoring
    /// The mod directory (04 · 06).
    let modDirectory: ModDirectory
    /// The installed mods.
    let modStore: ModStore
    /// Adds the enabled userscript mods to every page.
    let modInjector: ModInjector
    /// Content blocking, including the lists filter-list mods install.
    let blocker: ContentBlocker

    /// Nil until `start` has loaded the saved tabs: the app shows the mist while that
    /// happens, and the restored surface lands with nothing animating.
    private(set) var surface: Surface?

    /// The surface to open on instead, once `start` has run: how a UI test enters the app
    /// somewhere other than a cold start.
    var launchSurfaceOverride: Surface?

    /// The live page sessions, by tab.
    private(set) var sessions: [Tab.ID: ReadingSession] = [:]
    private var sessionTasks: [Tab.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var snapshotTasks: [Tab.ID: Task<Void, Never>] = [:]

    init(
        store: TabStore = TabStore(),
        engine: SearchEngine = .default,
        suggestions: any SuggestionProviding = SuggestionService(),
        recents: any RecentSearchStoring = RecentSearches(),
        blocker: ContentBlocker? = nil,
        modStore: ModStore? = nil,
        modDirectory: ModDirectory? = nil
    ) {
        self.store = store
        self.engine = engine
        self.suggestions = suggestions
        self.recents = recents
        let blocker = blocker ?? ContentBlocker(store: FilterListStore())
        self.blocker = blocker
        let mods = modStore ?? ModStore(listSink: blocker)
        self.modStore = mods
        self.modDirectory = modDirectory ?? ModDirectory()
        let injector = ModInjector(values: mods)
        self.modInjector = injector
        mods.onUserscriptsChanged = { [weak injector] userscripts in
            injector?.apply(userscripts)
        }
    }

    /// The app as it runs on a device: the JSON index in Application Support.
    static func live() -> AppModel {
        AppModel(store: TabStore(persistence: FileSystemTabPersistence()))
    }

    // MARK: Lifecycle

    /// Loads the saved tabs, archives what went stale, arms the mods and the blocking on
    /// the pages' shared configuration, and lands on the surface to open on.
    func start(now: Date = .now) async {
        await store.loadIndex()
        refreshArchive(now: now)
        await blocker.apply(to: modInjector.contentController)
        modInjector.apply(modStore.enabledUserscripts)
        await blocker.refresh()
        await modDirectory.refresh()
        coldStart()
        if let launchSurfaceOverride {
            surface = launchSurfaceOverride
        }
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

    /// The tab's page session, made on demand and kept in step with the tab. A reused
    /// session whose page is already loaded settles again, so it still gets its picture.
    func ensureSession(for tab: Tab) -> ReadingSession {
        if let session = sessions[tab.id] {
            refireSettleIfPictureless(tab, session: session)
            return session
        }
        let session = ReadingSession(
            url: tab.url ?? Self.blankPage,
            pageConfiguration: modInjector.pageConfiguration())
        sessions[tab.id] = session
        sessionTasks[tab.id] = Task { await session.run() }
        session.onPageSettled = { [weak self] in self?.pageSettled(for: tab.id) }
        pruneSessions()
        return session
    }

    private static let blankPage = URL(string: "about:blank") ?? URL(fileURLWithPath: "/")

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

    /// A reused session whose page is already loaded but has no picture — a tab switched
    /// back to, or one restored — settles again, with its viewport already known.
    private func refireSettleIfPictureless(_ tab: Tab, session: ReadingSession) {
        guard
            session.page.url != nil,
            session.failure == nil,
            store.tabs.first(where: { $0.id == tab.id })?.snapshot == nil
        else { return }
        pageSettled(for: tab.id)
    }

    /// The page's picture onto its tab, whenever it answers.
    private func captureSnapshot(for id: Tab.ID, trigger: String) {
        guard let session = sessions[id] else { return }
        snapshotTasks[id]?.cancel()
        snapshotTasks[id] = Task { @MainActor in
            let data = await session.snapshot(trigger: trigger)
            guard !Task.isCancelled, let data else { return }
            store.setSnapshot(data, for: id)
            SnapshotLog.event("\(trigger) stored \(data.count)B tab=\(id.uuidString.prefix(4))")
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

    // MARK: Mods

    /// Where Done on the mods screen returns to.
    private var surfaceBeforeMods: Surface?

    /// The mods screen (04 · 06). No menu yet; the app model's callers open it.
    func showMods() {
        guard surface != .mods else { return }
        surfaceBeforeMods = surface
        surface = .mods
    }

    /// Done: back to whatever was up before the mods screen.
    func closeMods() {
        surface = surfaceBeforeMods ?? .launchSearch
        surfaceBeforeMods = nil
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
}
