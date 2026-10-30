import Foundation
import Observation
import WebKit

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
    /// The mods screen.
    case mods
    /// A Skim run: working, its finished page, or the failure that stopped it.
    case skim
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
    /// The user's choices: the engine, the search rows, the archive interval.
    let preferences: Preferences
    /// Content blocking: the two toggles and the rule lists they apply to every page.
    let blocker: ContentBlocker
    /// The saved bookmarks and their folders.
    let bookmarks: BookmarkStore
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
    /// Whether Skim can run on this device; every Skim entry point is hidden
    /// wherever this is false.
    let skimAvailable: Bool
    /// The pieces a Skim run is made of; fakes for the UI tests.
    let skimDependencies: SkimDependencies
    /// Saved Skim pages, brought back by their bookmarks.
    let skimPageStore: SkimPageStore

    /// The Skim run on screen, when one is going.
    private(set) var skimRun: SkimRun?
    /// Where to go back to when a Skim run leaves the screen.
    private var surfaceBeforeSkim: Surface?
    /// Text the search sheet opens with: the Skim query bar's edit.
    var searchPrefill: String?

    /// Nil until `start` has loaded the saved tabs: the app shows the mist while that
    /// happens, and the restored surface lands with nothing animating.
    private(set) var surface: Surface?

    /// The first-launch flow, until it has run once (04 · 07a, 07b).
    var needsOnboarding: Bool { !preferences.hasCompletedOnboarding }

    /// Settings, once the menu exists; the UI tests open it directly meanwhile.
    var showsSettings = false
    /// The page Settings opens on: the engine list, when the menu's Search engine row
    /// sent it there.
    var settingsPage: SettingsScreen.Page?

    /// The live page sessions, by tab.
    private(set) var sessions: [Tab.ID: ReadingSession] = [:]
    private var sessionTasks: [Tab.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var snapshotTasks: [Tab.ID: Task<Void, Never>] = [:]

    init(
        store: TabStore = TabStore(),
        preferences: Preferences? = nil,
        blocker: ContentBlocker? = nil,
        bookmarks: BookmarkStore = BookmarkStore(),
        suggestions: any SuggestionProviding = SuggestionService(),
        recents: any RecentSearchStoring = RecentSearches(),
        modStore: ModStore? = nil,
        modDirectory: ModDirectory? = nil,
        skimPageStore: SkimPageStore = SkimPageStore(),
        skimDependencies: SkimDependencies = .live,
        skimAvailable: Bool = SkimAvailability.resolve().isAvailable
    ) {
        self.store = store
        self.preferences = preferences ?? Preferences(defaults: Self.freshDefaults())
        let blocker =
            blocker
            ?? ContentBlocker(
                store: NoRuleSets(), defaults: Self.freshDefaults())
        self.blocker = blocker
        self.bookmarks = bookmarks
        self.suggestions = suggestions
        self.recents = recents
        let mods = modStore ?? ModStore(listSink: blocker)
        self.modStore = mods
        self.modDirectory = modDirectory ?? ModDirectory()
        let injector = ModInjector(values: mods)
        self.modInjector = injector
        mods.onUserscriptsChanged = { [weak injector] userscripts in
            injector?.apply(userscripts)
        }
        self.skimPageStore = skimPageStore
        self.skimDependencies = skimDependencies
        self.skimAvailable = skimAvailable
    }

    /// The app as it runs on a device: the JSON indexes in Application Support.
    static func live() -> AppModel {
        AppModel(
            store: TabStore(persistence: FileSystemTabPersistence()),
            preferences: Preferences(),
            blocker: ContentBlocker(store: FilterListStore()),
            bookmarks: BookmarkStore(persistence: FileSystemBookmarkPersistence()),
            modDirectory: ModDirectory())
    }

    /// A defaults suite nothing else shares, so a default-built model changes nothing.
    private static func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "magpie-scratch-\(UUID().uuidString)") ?? .standard
    }

    // MARK: Lifecycle

    /// Loads the saved tabs and bookmarks, archives what went stale, arms the mods and
    /// the blocking on the pages' shared configuration, and lands on the surface to open on.
    func start(now: Date = .now) async {
        await store.loadIndex()
        await bookmarks.loadIndex()
        refreshArchive(now: now)
        await blocker.attach(modInjector.contentController)
        modInjector.apply(modStore.enabledUserscripts)
        await refreshBlocking()
        await modDirectory.refresh()
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
        _ = store.archiveStale(now: now, after: preferences.archiveInterval)
        _ = store.purgeArchived(now: now)
        dropSessions(notIn: Set(store.tabs.map(\.id)))
    }

    /// Refreshes the filter lists when stale and re-applies them to the live pages.
    func refreshBlocking() async {
        await blocker.refresh()
    }

    // MARK: Settings and onboarding

    /// Opens Settings; the menu lands later, so the UI tests reach it directly meanwhile.
    func showSettings() {
        settingsPage = nil
        showsSettings = true
    }

    /// The menu's Search engine row: Settings, straight onto its engine list.
    func showEngineList() {
        settingsPage = .engineList
        showsSettings = true
    }

    /// Settings' Done, or the cover going away: back to whatever lay beneath.
    func closeSettings() {
        showsSettings = false
        settingsPage = nil
    }

    /// The last step of the first-launch flow: the choices are saved and the app appears.
    func completeOnboarding() {
        preferences.hasCompletedOnboarding = true
    }

    /// The engine searches run on, from the user's choice.
    var engine: SearchEngine { preferences.searchEngine }

    /// Whether the search sheet asks the engine for suggestion rows.
    var suggestionsEnabled: Bool { preferences.suggestionsEnabled }

    /// Whether the Skim pill is offered in the search sheet.
    var skimEnabled: Bool { preferences.skimEnabled }

    /// Whether Skim entry points show at all: offered in Preferences and runnable here.
    var offersSkim: Bool { preferences.skimEnabled && skimAvailable }

    // MARK: Sessions

    /// The current tab's live session, when it has one.
    var currentSession: ReadingSession? {
        store.currentTab.flatMap { sessions[$0.id] }
    }

    /// The tab's page session, made on demand and kept in step with the tab. Every page
    /// carries the mods' configuration, so the installed scripts run on each; a reused
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
        sessionTasks[tab.id] = Task {
            await session.run()
        }
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
        searchPrefill = nil
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
        searchPrefill = nil
        surface = .launchSearch
    }

    /// A swipe down on the launch sheet: back to the stack, when there are tabs to show.
    func dismissLaunchSearch() {
        guard !store.tabs.isEmpty else { return }
        searchPrefill = nil
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

    // MARK: Skim

    /// The query the menu's Skim tile reads: the search behind the page when it is a
    /// results page on a known engine, otherwise the page's title, falling back to its
    /// host. Never the page's address itself.
    var skimTileQuery: String? {
        guard let tab = store.currentTab else { return nil }
        if let url = tab.url {
            let engines = [engine] + SearchEngine.builtins
            if let query = engines.lazy.compactMap({ $0.resultsQuery(for: url) }).first {
                return query
            }
        }
        let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let host = HostFormatter.host(for: tab.url)
        return host.isEmpty ? nil : host
    }

    /// A Skim pill, or a retry: read the top results for the query and build the
    /// page, on the Skim surface.
    func startSkim(query: String) {
        guard
            skimAvailable,
            !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        if case .reading(true) = surface {
            surfaceBeforeSkim = .reading(searchOpen: false)
        } else if surface != .skim {
            surfaceBeforeSkim = surface
        }
        let run = SkimRun(query: query, engine: engine, dependencies: skimDependencies)
        skimRun = run
        searchPrefill = nil
        surface = .skim
        run.start()
    }

    /// The working screen's Cancel: back to where the Skim began.
    func cancelSkim() {
        skimRun?.cancel()
        leaveSkim()
    }

    /// The query bar on a finished page: the search sheet with the query in the
    /// field, ready to run again.
    func editSkimQuery() {
        guard let run = skimRun else { return }
        let query = run.query
        run.cancel()
        skimRun = nil
        surfaceBeforeSkim = nil
        searchPrefill = query
        surface = .launchSearch
    }

    /// A failure's way forward: the query on the engine, in a tab.
    func showSkimSearchResults() {
        guard let run = skimRun else { return }
        let query = run.query
        skimRun = nil
        surfaceBeforeSkim = nil
        searchPrefill = nil
        guard let url = engine.searchURL(for: query) else { return }
        openFromLaunch(url)
    }

    /// A failure's other way forward: the same query, read again.
    func retrySkim() {
        skimRun?.start()
    }

    /// The control bar's "Dig deeper": read on up to ten sources, then compose
    /// again from all of them.
    func skimDigDeeper() {
        skimRun?.digDeeper()
    }

    /// A run made elsewhere: a saved page, or the UI tests' seeded run.
    func showSkimRun(_ run: SkimRun) {
        if case .reading(true) = surface {
            surfaceBeforeSkim = .reading(searchOpen: false)
        } else if surface != .skim {
            surfaceBeforeSkim = surface
        }
        skimRun = run
        searchPrefill = nil
        surface = .skim
    }

    private func leaveSkim() {
        let back = surfaceBeforeSkim
        surfaceBeforeSkim = nil
        skimRun = nil
        searchPrefill = nil
        if let back {
            surface = back
        } else {
            coldStart()
        }
    }

    /// The Bookmark tile's tap on a Skim page: the page saved, and its address
    /// kept in the bookmarks as a Skim page.
    @discardableResult
    func bookmarkSkimPage(now: Date = .now) -> Bookmark? {
        guard let page = skimRun?.page else { return nil }
        let id = UUID()
        guard
            let address = SkimPageStore.address(forID: id),
            skimPageStore.save(page, id: id)
        else { return nil }
        return bookmarks.add(
            url: address,
            title: page.title,
            faviconURL: nil,
            folder: nil,
            kind: .skim(sourceHosts: page.sources.map(\.host)),
            now: now)
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

    /// A tapped bookmark: a new tab, opened on the spot — or, for a Skim page,
    /// the saved page back on the Skim surface.
    func openBookmark(_ url: URL, now: Date = .now) {
        if let id = SkimPageStore.pageID(forBookmarkURL: url),
            let page = skimPageStore.load(id: id)
        {
            openSkimPage(page)
            return
        }
        openFromLaunch(url, now: now)
    }

    /// A saved Skim page, back on the screen without reading its sources again.
    private func openSkimPage(_ page: SkimPage) {
        let run = SkimRun(query: page.query, engine: engine, dependencies: skimDependencies)
        run.land(.finished(page))
        showSkimRun(run)
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

    /// Whether the page the current tab shows sits in Bookmarks already: the Bookmark
    /// tile's state.
    var currentPageIsBookmarked: Bool {
        guard let url = store.currentTab?.url else { return false }
        return bookmarks.bookmarks.contains { $0.url == url }
    }

    /// The Bookmark tile's tap: saved already, this tap takes the page back out.
    /// Returns whether the page is saved after the tap.
    @discardableResult
    func toggleCurrentPageBookmark(now: Date = .now) -> Bool {
        guard let tab = store.currentTab, let url = tab.url else { return false }
        if let saved = bookmarks.bookmarks.first(where: { $0.url == url }) {
            bookmarks.remove(saved.id)
            return false
        }
        _ = bookmarkCurrentPage(now: now)
        return true
    }
}

/// A blocking source with no lists in it: what a default-built AppModel holds, inert
/// until the app wires the real filter lists.
private struct NoRuleSets: RuleSetProviding {
    func refreshStale() async {}
    func refreshNow() async {}
    func ruleLists(for set: FilterRuleSet) async -> [CompiledRuleList] { [] }
    var overallLastUpdated: Date? { nil }
    func listUpdates() async -> [FilterListUpdate] { [] }
    func setUserLists(_ lists: [FilterList]) async {}
}
