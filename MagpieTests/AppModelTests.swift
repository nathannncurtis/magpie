import Foundation
import Testing

@testable import Magpie

@Suite("AppModel")
@MainActor
struct AppModelTests {

    /// Dates from a zero base, so threshold comparisons stay exact.
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func url(_ host: String) -> URL {
        URL(string: "https://\(host)") ?? URL(fileURLWithPath: "/")
    }

    private func makeModel(persistence: TabPersistence? = InMemoryTabPersistence()) -> AppModel {
        AppModel(
            store: TabStore(persistence: persistence),
            suggestions: StubSuggestionProvider(rowsByPrefix: []),
            recents: RecentSearches())
    }

    // MARK: Start

    @Test("a cold start with no tabs opens on the launch search")
    func startEmptyOpensLaunchSearch() async {
        let model = makeModel()

        await model.start(now: date(0))

        #expect(model.surface == .launchSearch)
        #expect(model.currentSession == nil)
    }

    @Test("a later launch restores the last tab on reading")
    func startRestoresLastTab() async {
        let persistence = InMemoryTabPersistence()
        let first = makeModel(persistence: persistence)
        await first.start(now: date(0))
        first.openFromLaunch(url("a.example"), now: date(10))
        first.openFromLaunch(url("b.example"), now: date(20))
        await first.store.flushWrites()

        let model = makeModel(persistence: persistence)
        await model.start(now: date(100))

        #expect(model.surface == .reading(searchOpen: false))
        #expect(model.store.tabs.count == 2)
        #expect(model.store.currentTab?.url == url("b.example"))
        #expect(model.currentSession != nil)
    }

    @Test("a start with no store behind it opens on the launch search")
    func startWithoutPersistence() async {
        let model = makeModel(persistence: nil)

        await model.start(now: date(0))

        #expect(model.surface == .launchSearch)
    }

    // MARK: Surfaces

    @Test("a launch submission opens a new tab on reading")
    func openFromLaunchOpensTab() {
        let model = makeModel()

        model.openFromLaunch(url("a.example"), now: date(0))

        #expect(model.surface == .reading(searchOpen: false))
        #expect(model.store.tabs.count == 1)
        #expect(model.store.currentTab?.url == url("a.example"))
        #expect(model.currentSession != nil)
    }

    @Test("the search sheet opens over the page and folds back into the bar")
    func searchOverPage() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))

        model.openSearchOverPage()
        #expect(model.surface == .reading(searchOpen: true))

        model.closeSearchOverPage()
        #expect(model.surface == .reading(searchOpen: false))
    }

    @Test("the tab count shows the stack, a card opens its tab")
    func tabsAndCards() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        let first = model.store.currentTab!.id
        model.openFromLaunch(url("b.example"), now: date(10))

        model.showTabs()
        #expect(model.surface == .tabs)

        model.openTab(first, now: date(20))
        #expect(model.surface == .reading(searchOpen: false))
        #expect(model.store.currentTab?.id == first)
        #expect(model.store.currentTab?.lastActive == date(20))
    }

    @Test("the plus on the tabs screen opens the launch search; a swipe down goes back")
    func launchSearchFromTabs() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))

        model.newTabFromTabs()
        #expect(model.surface == .launchSearch)

        model.dismissLaunchSearch()
        #expect(model.surface == .tabs)
    }

    @Test("a swipe down on the launch sheet does nothing when there are no tabs")
    func launchSearchDismissNeedsTabs() async {
        let model = makeModel()
        await model.start(now: date(0))

        model.dismissLaunchSearch()

        #expect(model.surface == .launchSearch)
    }

    @Test("a card flung closed on the stack offers an undo that brings the tab back")
    func undoCloseOnTheStack() throws {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        let first = try #require(model.store.currentTab).id
        model.openFromLaunch(url("b.example"), now: date(10))
        model.showTabs()

        model.closeTab(first)
        #expect(model.closedTabNotice != nil)
        #expect(model.store.tabs.count == 1)

        model.undoCloseTab()
        #expect(model.closedTabNotice == nil)
        #expect(model.store.tabs.map(\.id).first == first)
        #expect(model.store.tabs.count == 2)
    }

    @Test("an undo that ran out, or a close that left the last tab, leaves the close standing")
    func undoExpires() throws {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        let first = try #require(model.store.currentTab).id
        model.openFromLaunch(url("b.example"), now: date(10))
        let second = try #require(model.store.currentTab).id
        model.showTabs()

        model.closeTab(first)
        let stale = try #require(model.closedTabNotice).id
        model.closeTab(second)
        #expect(model.closedTabNotice == nil)
        #expect(model.surface == .launchSearch)

        model.expireClosedTabNotice(stale)
        model.undoCloseTab()
        #expect(model.store.tabs.isEmpty)
    }

    @Test("an old timer does not clear a newer undo")
    func staleTimerKeepsNewerNotice() throws {
        let model = makeModel()
        for host in ["a.example", "b.example", "c.example"] {
            model.openFromLaunch(url(host), now: date(0))
        }
        let ids = model.store.tabs.map(\.id)
        model.showTabs()

        model.closeTab(ids[0])
        let old = try #require(model.closedTabNotice).id
        model.closeTab(ids[1])

        model.expireClosedTabNotice(old)
        #expect(model.closedTabNotice != nil)
    }

    @Test("closing a card from a page, not the stack, offers no undo")
    func noUndoOffPageClose() throws {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        model.openFromLaunch(url("b.example"), now: date(10))

        model.closeCurrentTab()

        #expect(model.closedTabNotice == nil)
    }

    @Test("closing the last tab leaves the launch search")
    func closingLastTab() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        let only = model.store.currentTab!.id

        model.closeTab(only)

        #expect(model.store.tabs.isEmpty)
        #expect(model.surface == .launchSearch)
        #expect(model.sessions.isEmpty)
    }

    @Test("closing a tab hands currency to its neighbor")
    func closingHandsCurrencyOver() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        let first = model.store.currentTab!.id
        model.openFromLaunch(url("b.example"), now: date(10))
        model.showTabs()

        model.closeTab(model.store.currentTab!.id)

        #expect(model.store.tabs.map(\.id) == [first])
        #expect(model.surface == .tabs)
    }

    // MARK: Live sessions

    @Test("only the current tab and the three most recent others stay live")
    func boundedLiveSessions() {
        let model = makeModel()
        for index in 0..<6 {
            model.openFromLaunch(url("t\(index).example"), now: date(Double(index)))
        }

        #expect(model.store.tabs.count == 6)
        #expect(model.sessions.count == AppModel.liveSessionCount)
        let live = Set(model.store.tabs.suffix(4).map(\.id))
        #expect(Set(model.sessions.keys) == live)
        #expect(model.sessions[model.store.currentTabID!] != nil)
    }

    @Test("opening a pruned tab brings its session back")
    func prunedSessionComesBack() {
        let model = makeModel()
        for index in 0..<6 {
            model.openFromLaunch(url("t\(index).example"), now: date(Double(index)))
        }
        let oldest = model.store.tabs.first!.id
        #expect(model.sessions[oldest] == nil)

        model.openTab(oldest, now: date(100))

        #expect(model.sessions[oldest] != nil)
        #expect(model.store.currentTabID == oldest)
    }

    @Test("a memory warning keeps only the current tab's page live")
    func memoryWarningDropsOtherSessions() {
        let model = makeModel()
        for index in 0..<3 {
            model.openFromLaunch(url("t\(index).example"), now: date(Double(index)))
        }
        let current = model.store.currentTabID!
        #expect(model.sessions.count == 3)

        model.memoryWarning()

        #expect(Set(model.sessions.keys) == [current])
        #expect(model.store.tabs.count == 3)
    }

    @Test("a page dropped under a memory warning comes back on open")
    func memoryWarningSessionComesBack() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        let first = model.store.currentTabID!
        model.openFromLaunch(url("b.example"), now: date(10))
        model.memoryWarning()
        #expect(model.sessions[first] == nil)

        model.openTab(first, now: date(20))

        #expect(model.sessions[first] != nil)
        #expect(model.sessions[first]?.requestedURL == url("a.example"))
    }

    // MARK: Auto-archive

    @Test("a start archives the stale and keeps the current")
    func startArchivesStaleTabs() async {
        let model = makeModel()
        model.openFromLaunch(url("old.example"), now: date(0))
        model.openFromLaunch(url("current.example"), now: date(10))
        await model.store.flushWrites()

        await model.start(now: date(10) + TabStore.autoArchiveDefault)

        #expect(model.store.tabs.count == 1)
        #expect(model.store.currentTab?.url == url("current.example"))
        #expect(model.store.archivedTabs.count == 1)
        #expect(Set(model.sessions.keys) == Set(model.store.tabs.map(\.id)))
    }

    @Test("a return to the foreground archives the stale")
    func foregroundArchivesStaleTabs() async {
        let model = makeModel()
        await model.start(now: date(0))
        model.openFromLaunch(url("a.example"), now: date(0))
        model.openFromLaunch(url("b.example"), now: date(60))

        model.refreshArchive(now: date(60) + TabStore.autoArchiveDefault)

        #expect(model.store.tabs.count == 1)
        #expect(model.store.currentTab?.url == url("b.example"))
        #expect(model.surface == .reading(searchOpen: false))
    }
}
