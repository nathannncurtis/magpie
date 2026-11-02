import Foundation
import Testing

@testable import Magpie

@Suite("Page recovery")
@MainActor
struct PageRecoveryTests {

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func url(_ host: String) -> URL {
        URL(string: "https://\(host)") ?? URL(fileURLWithPath: "/")
    }

    private func makeModel() -> AppModel {
        AppModel(
            store: TabStore(persistence: InMemoryTabPersistence()),
            suggestions: StubSuggestionProvider(rowsByPrefix: []),
            recents: RecentSearches())
    }

    // MARK: Renderer death

    @Test("the first death reloads, a second soon after fails")
    func deathThenDeath() {
        var recovery = RendererRecovery()
        #expect(recovery.died(at: date(100)) == .reload)
        #expect(recovery.died(at: date(105)) == .fail)
    }

    @Test("a death long after the last reload reloads again")
    func laterDeathReloads() {
        var recovery = RendererRecovery()
        #expect(recovery.died(at: date(100)) == .reload)
        #expect(recovery.died(at: date(100 + RendererRecovery.window + 1)) == .reload)
    }

    @Test("one death reported twice is one death")
    func sameDeathIgnored() {
        var recovery = RendererRecovery()
        #expect(recovery.died(at: date(100)) == .reload)
        #expect(recovery.died(at: date(100.1)) == .ignore)
        #expect(recovery.died(at: date(105)) == .fail)
    }

    @Test("a session that dies twice shows the failure page")
    func sessionFails() {
        let session = ReadingSession(url: url("a.example"))
        session.rendererTerminated(at: date(100))
        #expect(session.failure == nil)

        session.rendererTerminated(at: date(110))

        #expect(session.failure?.reason == .crashed)
        #expect(session.failure?.host == "a.example")
        #expect(session.failure?.title == "This page stopped working")
    }

    @Test("a death away from the screen waits to reload until the tab is shown")
    func backgroundDeathWaits() {
        let session = ReadingSession(url: url("a.example"))
        session.rendererTerminated(at: date(100))
        #expect(session.reloadWhenShown)

        session.readingViewAppeared()

        #expect(!session.reloadWhenShown)
    }

    // MARK: Stalled loads

    @Test("a load that never committed has stalled; a committed one has not")
    func stallCondition() {
        #expect(ReadingSession.loadStalled(failed: false, committed: false))
        #expect(!ReadingSession.loadStalled(failed: false, committed: true))
        #expect(!ReadingSession.loadStalled(failed: true, committed: false))
    }

    @Test("the stalled copy")
    func stalledCopy() {
        let failure = PageLoadFailure(host: "a.example", isOffline: false, reason: .stalled)
        #expect(failure.title == "This page stopped loading")
        #expect(!failure.line.isEmpty)
    }

    // MARK: Place in the page

    @Test("an index written before scroll offsets existed still decodes")
    func oldIndexDecodes() throws {
        let json = """
            {"openTabs":[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","url":"https://a.example",
            "title":"A","lastActive":"2026-01-01T00:00:00Z"}],"archivedTabs":[]}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let index = try decoder.decode(TabIndex.self, from: Data(json.utf8))
        #expect(index.openTabs.first?.title == "A")
        #expect(index.openTabs.first?.scrollOffset == nil)
    }

    @Test("a scroll offset survives a relaunch")
    func offsetPersists() async {
        let persistence = InMemoryTabPersistence()
        let store = TabStore(persistence: persistence)
        let tab = store.newTab(url: url("a.example"), now: date(1))
        store.setScrollOffset(1_234.5, for: tab.id)
        await store.flushWrites()

        let reopened = await TabStore.open(persistence: persistence)

        #expect(reopened.tabs.first?.scrollOffset == 1_234.5)
    }

    @Test("a private tab's offset never reaches the index")
    func privateOffsetStaysOut() async {
        let persistence = InMemoryTabPersistence()
        let store = TabStore(persistence: persistence)
        let open = store.newTab(url: url("a.example"), now: date(1))
        let secret = store.newTab(url: url("b.example"), isPrivate: true, now: date(2))
        store.setScrollOffset(40, for: open.id)
        store.setScrollOffset(900, for: secret.id)
        await store.flushWrites()

        let index = try? await persistence.loadIndex()

        #expect(index?.openTabs.map(\.id) == [open.id])
        #expect(index?.openTabs.first?.scrollOffset == 40)
    }

    @Test("moving to another page forgets the place on the old one")
    func newAddressForgetsOffset() {
        let store = TabStore(persistence: nil)
        let tab = store.newTab(url: url("a.example"), now: date(1))
        store.setScrollOffset(500, for: tab.id)

        store.update(id: tab.id, url: url("b.example"), title: "B", faviconURL: nil, now: date(2))

        #expect(store.tabs.first?.scrollOffset == nil)
    }

    @Test("a rebuilt session is handed the tab's offset")
    func rebuiltSessionRestores() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        let first = model.store.currentTabID!
        model.store.setScrollOffset(777, for: first)
        model.openFromLaunch(url("b.example"), now: date(10))
        model.memoryWarning()
        #expect(model.sessions[first] == nil)

        model.openTab(first, now: date(20))

        #expect(model.sessions[first]?.scrollToRestore == 777)
    }

    @Test("a navigation by the reader spends the offset")
    func openClearsRestore() {
        let session = ReadingSession(url: url("a.example"))
        session.scrollToRestore = 300
        session.open(url("b.example"))
        #expect(session.scrollToRestore == nil)
    }

    // MARK: Links from other apps

    @Test("a link from another app closes Settings and opens in a new tab")
    func linkClosesSettings() {
        let model = makeModel()
        model.preferences.hasCompletedOnboarding = true
        model.showSettings()

        model.openExternalLink(url("a.example"), now: date(0))

        #expect(!model.showsSettings)
        #expect(model.surface == .reading(searchOpen: false))
        #expect(model.store.currentTab?.url == url("a.example"))
    }

    @Test("a link that arrives under onboarding opens when onboarding is done")
    func linkWaitsForOnboarding() {
        let model = makeModel()
        model.preferences.hasCompletedOnboarding = false

        model.openExternalLink(url("a.example"), now: date(0))
        #expect(model.store.tabs.isEmpty)

        model.completeOnboarding()
        #expect(model.store.currentTab?.url == url("a.example"))
        #expect(model.surface == .reading(searchOpen: false))
    }
}
