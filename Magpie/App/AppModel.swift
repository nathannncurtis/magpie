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
    /// The sites' own icons: fetched off the main actor, shared by every row that points
    /// at the same address.
    let faviconFetcher: FaviconFetcher

    /// The Skim run on screen, when one is going.
    private(set) var skimRun: SkimRun?
    /// Where to go back to when a Skim run leaves the screen.
    private var surfaceBeforeSkim: Surface?
    /// Text the search sheet opens with: the Skim query bar's edit.
    var searchPrefill: String?

    // MARK: Private tabs

    /// Whether the launch search submits into a private tab.
    private(set) var launchIsPrivate = false

    /// The website data every private tab shares while any is open: cookies and storage
    /// in memory only, dropped with the last private tab so the next one starts clean.
    @ObservationIgnored private var privateDataStore: WKWebsiteDataStore?

    /// Whether the tab on screen is private.
    var currentIsPrivate: Bool {
        store.currentTab?.isPrivate ?? false
    }

    /// Whether the search up now belongs to a private tab: the launch search opened for
    /// one, or the sheet over a private page.
    var searchIsPrivate: Bool {
        surface == .launchSearch ? launchIsPrivate : currentIsPrivate
    }

    /// The recents the search reads and writes: a private search keeps nothing.
    var searchRecents: any RecentSearchStoring {
        searchIsPrivate ? PrivateRecents(base: recents) : recents
    }

    /// Whether the tabs screen shows the private stack instead of the ordinary one. The
    /// mode follows the page being read, and the + opens the kind of tab it names.
    private(set) var isPrivateMode = false

    /// The tabs the tabs screen shows: those of the current mode.
    var modeTabs: [Tab] {
        store.tabs(inPrivate: isPrivateMode)
    }

    /// The tab the current mode centres on.
    var modeCurrentTabID: Tab.ID? {
        store.currentTabID(inPrivate: isPrivateMode)
    }

    /// The tabs screen's switch. Flipping swaps the stack and each mode keeps its own
    /// current tab; private tabs stay open for the session while the other mode shows.
    /// With no ordinary tab to flip to, the ordinary launch search opens instead.
    func setPrivateMode(_ isPrivate: Bool) {
        guard isPrivate != isPrivateMode else { return }
        isPrivateMode = isPrivate
        if let id = store.currentTabID(inPrivate: isPrivate) {
            store.select(id)
        }
        if !isPrivate, store.tabs(inPrivate: false).isEmpty {
            newNormalTab()
        }
    }

    /// The menu's Private tile, or the +'s long press: the launch search, submitting into a
    /// private tab.
    func newPrivateTab() {
        searchPrefill = nil
        isPrivateMode = true
        launchIsPrivate = true
        surface = .launchSearch
    }

    /// The launch search for an ordinary tab, from any mode.
    func newNormalTab() {
        searchPrefill = nil
        isPrivateMode = false
        launchIsPrivate = false
        surface = .launchSearch
    }

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
    @ObservationIgnored private var captureGates: [Tab.ID: CaptureGate] = [:]
    @ObservationIgnored private var captureDrains: [Tab.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var captureRetries: [Tab.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var retryAttempts: [Tab.ID: Int] = [:]

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
        skimAvailable: Bool = SkimAvailability.resolve().isAvailable,
        faviconFetcher: FaviconFetcher = FaviconFetcher()
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
        self.faviconFetcher = faviconFetcher
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
        armLaunchIntro()
        await bookmarks.loadIndex()
        fillMissingFavicons()
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

    /// Whether this cold start plays the launch intro (05 · 07). Decided the moment the
    /// saved tabs are in — and the launch search lands early when it plays, so the intro
    /// runs while the rest of the start work still does. Cleared once the intro has had
    /// its moment, so no later return to the launch search draws the mark again.
    private(set) var playsLaunchIntro = false

    /// The intro's trigger, on its own: a cold start with no tab to restore and onboarding
    /// already done. A restored tab, the first-launch flow, the + on the tabs screen —
    /// none of them play it.
    static func shouldPlayLaunchIntro(hasTabsToRestore: Bool, onboardingDone: Bool) -> Bool {
        !hasTabsToRestore && onboardingDone
    }

    /// Decides the intro from the loaded tabs, landing the launch search early when it
    /// plays. A restored launch is never held for it.
    private func armLaunchIntro() {
        playsLaunchIntro = Self.shouldPlayLaunchIntro(
            hasTabsToRestore: store.currentTab != nil,
            onboardingDone: !needsOnboarding)
        if playsLaunchIntro {
            surface = .launchSearch
        }
    }

    /// The intro's own call once it has played, been skipped, or left the screen.
    func launchIntroDone() {
        playsLaunchIntro = false
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

    /// Pages that still owe their tab a picture while no reading screen shows them. WebKit
    /// stops drawing a page that is out of the window, so a tab left before its page drew
    /// would never get one; the root keeps these in the window, unseen, until it lands.
    /// A page can be in only one web view at a time, so the tab a reading screen shows —
    /// up, or on its way in or out — is never kept here, nor a page whose reading view
    /// has yet to let it go.
    var pagesStillDrawing: [ReadingSession] {
        let readingUp: Bool = {
            if case .reading = surface { return true }
            return readingScreenMounted
        }()
        let shown = readingUp ? store.currentTabID : nil
        return store.tabs.compactMap { tab in
            guard tab.id != shown, tab.snapshot == nil, let session = sessions[tab.id],
                session.failure == nil, !session.isOnReadingScreen
            else { return nil }
            return session
        }
    }

    /// Whether a reading screen is in the hierarchy, set by the screen itself: it stays
    /// through its leaving transition, after the surface has already moved on.
    var readingScreenMounted: Bool { readingScreenHolds > 0 }
    private var readingScreenHolds = 0

    /// How long a web view that has left the screen keeps its page from every other web
    /// view: longer than any transition it can leave with. A page in two web views at
    /// once is a WebKit trap.
    static let webViewReleaseDelay = Duration.seconds(1)

    func readingScreenAppeared() { readingScreenHolds += 1 }

    /// The screen's disappearance can come while it is still animating out, its web
    /// view still holding the page; the hold outlasts the transition.
    func readingScreenDisappeared() {
        Task { [weak self] in
            try? await Task.sleep(for: Self.webViewReleaseDelay)
            self?.readingScreenHolds -= 1
        }
    }

    /// The tab's page session, made on demand and kept in step with the tab. Every page
    /// carries the mods' configuration, so the installed scripts run on each; a reused
    /// session whose page is already loaded settles again, so it still gets its picture.
    func ensureSession(for tab: Tab) -> ReadingSession {
        if let session = sessions[tab.id] {
            refireSettleIfPictureless(tab, session: session)
            return session
        }
        var configuration = modInjector.pageConfiguration()
        if tab.isPrivate {
            let store = privateDataStore ?? .nonPersistent()
            privateDataStore = store
            configuration.websiteDataStore = store
        }
        let session = ReadingSession(
            url: tab.url ?? Self.blankPage,
            pageConfiguration: configuration)
        session.logTag = "tab=\(tab.id.uuidString.prefix(4))"
        session.isPrivate = tab.isPrivate
        session.viewportSize = restingPageSize
        sessions[tab.id] = session
        sessionTasks[tab.id] = Task {
            await session.run()
        }
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
        for id in Array(sessions.keys) where !keep.contains(id) {
            dropSession(id)
        }
    }

    /// Lets the tab's page go, and every piece of work kept for it. The tab keeps its
    /// picture and its address; its page loads again from there when it is opened.
    private func dropSession(_ id: Tab.ID) {
        sessionTasks[id]?.cancel()
        sessionTasks[id] = nil
        sessions[id]?.close()
        sessions[id] = nil
        captureDrains[id]?.cancel()
        captureDrains[id] = nil
        captureRetries[id]?.cancel()
        captureRetries[id] = nil
        captureGates[id] = nil
        retryAttempts[id] = nil
    }

    /// The system is short of memory: only the current tab keeps its page live. The
    /// others keep their pictures and load again when opened.
    func memoryWarning() {
        dropSessions(notIn: Set([store.currentTabID].compactMap { $0 }))
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
        fetchTabFavicon(for: id, at: session.pageIconURL)
    }

    // MARK: Favicons

    /// The icons the saved rows point at but do not hold. One pass as the indexes land;
    /// from then on each icon arrives as its page names it.
    private func fillMissingFavicons() {
        for tab in store.tabs + store.archivedTabs {
            fetchTabFavicon(for: tab.id, at: tab.faviconURL)
        }
        for bookmark in bookmarks.bookmarks {
            fetchBookmarkFavicon(for: bookmark.id, at: bookmark.faviconURL)
        }
    }

    /// The icon onto the tab whose page named it — fetched off the main actor, cached
    /// back onto the tab, and left to the letter tile when the site has none to give.
    private func fetchTabFavicon(for id: Tab.ID, at url: URL?) {
        let tab = store.tabs.first { $0.id == id } ?? store.archivedTabs.first { $0.id == id }
        // A private tab fetches nothing on the side: the shared session would cache it.
        guard tab?.faviconData == nil, tab?.isPrivate != true else { return }
        fetchFavicon(
            at: url,
            stillCurrent: { [store] in
                (store.tabs.first { $0.id == id } ?? store.archivedTabs.first { $0.id == id })?
                    .faviconURL == url
            },
            save: { [store] in store.setFavicon($0, for: id) }
        )
    }

    /// The icon onto its bookmark, the same way.
    private func fetchBookmarkFavicon(for id: Bookmark.ID, at url: URL?) {
        guard bookmarks.bookmarks.first(where: { $0.id == id })?.faviconData == nil else { return }
        fetchFavicon(
            at: url,
            stillCurrent: { [bookmarks] in
                bookmarks.bookmarks.first(where: { $0.id == id })?.faviconURL == url
            },
            save: { [bookmarks] in bookmarks.setFavicon($0, for: id) }
        )
    }

    /// One download per address, shared by every row that points at it. A slow download
    /// can outlast the navigation that began it, so the bytes are saved onto a row only
    /// while it still points at the address they came from.
    private func fetchFavicon(
        at url: URL?,
        stillCurrent: @MainActor @escaping () -> Bool,
        save: @MainActor @escaping (Data) -> Void
    ) {
        guard let url else { return }
        Task { [faviconFetcher] in
            guard let data = await faviconFetcher.favicon(at: url) else { return }
            guard stillCurrent() else { return }
            save(data)
        }
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
        let tab = store.newTab(url: url, isPrivate: launchIsPrivate, now: now)
        isPrivateMode = tab.isPrivate
        launchIsPrivate = false
        _ = ensureSession(for: tab)
        searchPrefill = nil
        surface = .reading(searchOpen: false)
    }

    /// A submitted search or address over the page: the current tab navigates.
    func navigateCurrent(_ url: URL) {
        guard let session = currentSession else {
            // A private page's search stays private in the tab it opens.
            if currentIsPrivate { launchIsPrivate = true }
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

    /// A swipe back off the tabs screen: the current tab's page, when there is one.
    var canLeaveTabs: Bool { modeCurrentTabID != nil }

    /// The swipe itself: the current card grows back into its page.
    func leaveTabs() {
        guard let id = modeCurrentTabID else { return }
        openTab(id)
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

    /// The tab whose card is growing back into its page: the reading screen holds the
    /// card's picture over the page until the page has drawn at its own width.
    private(set) var cardArrival: Tab.ID?

    /// A tapped card: its tab becomes current and opens.
    func openTab(_ id: Tab.ID, now: Date = .now) {
        guard let tab = store.tabs.first(where: { $0.id == id }) else { return }
        isPrivateMode = tab.isPrivate
        store.activate(id, now: now)
        _ = ensureSession(for: tab)
        cardArrival = tab.snapshot == nil ? nil : id
        surface = .reading(searchOpen: false)
    }

    /// The page has taken over from its card's picture.
    func cardArrivalDone() {
        cardArrival = nil
    }

    /// The picture a card growing back into its page carries over it, while it does.
    var cardArrivalPicture: Data? {
        guard let id = cardArrival, id == store.currentTabID else { return nil }
        return store.tabs.first(where: { $0.id == id })?.snapshot
    }

    /// The + on the tabs screen: the launch search, which submits into a new tab of the
    /// kind the current mode shows.
    func newTabFromTabs() {
        if isPrivateMode { newPrivateTab() } else { newNormalTab() }
    }

    /// A swipe down on the launch sheet: back to the stack of the kind it was opened for,
    /// when there are tabs to show. With no ordinary tab, the private stack is what is left.
    func dismissLaunchSearch() {
        guard !store.tabs.isEmpty else { return }
        searchPrefill = nil
        isPrivateMode = launchIsPrivate || store.tabs(inPrivate: false).isEmpty
        launchIsPrivate = false
        surface = .tabs
    }

    /// A flung card. Closing the last tab leaves the launch search.
    func closeTab(_ id: Tab.ID) {
        let wasPrivate = store.tabs.first { $0.id == id }?.isPrivate ?? false
        dropSession(id)
        store.close(id)
        if !store.hasPrivateTabs {
            // The last private tab gone: its cookies and storage go with it.
            privateDataStore = nil
        }
        // The last ordinary tab gone leaves the ordinary launch search; the last private
        // one leaves the private stack's empty card.
        if !wasPrivate, store.tabs(inPrivate: false).isEmpty {
            newNormalTab()
        }
    }

    // MARK: Keyboard

    /// Whether a page is up, with nothing over it: where the page's own shortcuts apply.
    var isReadingPage: Bool { surface == .reading(searchOpen: false) }

    /// The find bar over the page (⌘F).
    var isFindingInPage = false

    /// ⌘T: the launch search, which submits into a new tab.
    var canOpenNewTab: Bool { surface != .launchSearch && surface != nil }

    /// ⌘⇧\: the tab stack, from the page or the launch search.
    var canShowTabsFromKeyboard: Bool {
        switch surface {
        case .reading: true
        case .launchSearch: !store.tabs.isEmpty
        default: false
        }
    }

    /// ⌘W: the current tab closes and the next one opens in its place; the last one
    /// closing leaves the launch search.
    func closeCurrentTab() {
        guard isReadingPage, let id = store.currentTabID else { return }
        isFindingInPage = false
        let wasPrivate = currentIsPrivate
        closeTab(id)
        if let next = store.currentTabID(inPrivate: wasPrivate) {
            openTab(next)
        } else if wasPrivate {
            // The last private page closed: the private stack's empty card.
            showTabs()
        }
    }

    /// ⌘[ and ⌘]: whether the current page has somewhere to go.
    var canGoBack: Bool { isReadingPage && (currentSession?.canGoBack ?? false) }
    var canGoForward: Bool { isReadingPage && (currentSession?.canGoForward ?? false) }

    /// Esc: whether there is a search sheet to fold away or a find bar to close.
    var canDismissWithEscape: Bool {
        switch surface {
        case .reading(let searchOpen): searchOpen || isFindingInPage
        case .launchSearch: !store.tabs.isEmpty
        default: false
        }
    }

    /// Esc: the search sheet folds back, over the page or over the stack; else the find
    /// bar closes.
    func dismissWithEscape() {
        switch surface {
        case .reading(searchOpen: true): closeSearchOverPage()
        case .reading: isFindingInPage = false
        case .launchSearch: dismissLaunchSearch()
        default: break
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
            // A private page runs no Skim: its reads land in the shared, kept website data.
            !searchIsPrivate || surface == .skim,
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
        returnToStack()
    }

    /// The stack, or the launch search with no tabs to show. With only private tabs open,
    /// the private stack is the one to land on.
    private func returnToStack() {
        guard !store.tabs.isEmpty else {
            surface = .launchSearch
            return
        }
        if store.tabs(inPrivate: false).isEmpty { isPrivateMode = true }
        surface = .tabs
    }

    /// A tapped archive row: the tab comes back and opens.
    func restoreArchivedTab(_ id: Tab.ID, now: Date = .now) {
        guard store.restore(id, now: now), let tab = store.currentTab else { return }
        isPrivateMode = false
        _ = ensureSession(for: tab)
        surface = .reading(searchOpen: false)
    }

    /// Where a swipe back off the bookmarks returns to.
    private var surfaceBeforeBookmarks: Surface?

    /// The Bookmark tile's long press, and the UI tests' way in.
    func showBookmarks() {
        guard surface != .bookmarks else { return }
        if case .reading(true) = surface {
            surfaceBeforeBookmarks = .reading(searchOpen: false)
        } else {
            surfaceBeforeBookmarks = surface
        }
        surface = .bookmarks
    }

    /// A swipe back off the bookmarks: whatever was up before them.
    func closeBookmarks() {
        let back = surfaceBeforeBookmarks
        surfaceBeforeBookmarks = nil
        if let back, back != .bookmarks {
            surface = back
        } else {
            returnToStack()
        }
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
            faviconData: tab.faviconData,
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
