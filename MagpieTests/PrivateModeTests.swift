import Foundation
import Testing

@testable import Magpie

@Suite("Private mode")
@MainActor
struct PrivateModeTests {

    private func url(_ host: String) -> URL {
        URL(string: "https://\(host)") ?? URL(fileURLWithPath: "/")
    }

    private func makeModel() -> AppModel {
        AppModel(
            store: TabStore(persistence: InMemoryTabPersistence()),
            suggestions: StubSuggestionProvider(rowsByPrefix: []),
            recents: RecentSearches())
    }

    /// Two ordinary tabs and two private ones, on the tabs screen in ordinary mode.
    private func makeMixed() -> (model: AppModel, normal: [Tab.ID], priv: [Tab.ID]) {
        let model = makeModel()
        model.openFromLaunch(url("a.example"))
        model.openFromLaunch(url("b.example"))
        model.newPrivateTab()
        model.openFromLaunch(url("p1.example"))
        model.newPrivateTab()
        model.openFromLaunch(url("p2.example"))
        let tabs = model.store.tabs
        model.showTabs()
        model.setPrivateMode(false)
        return (model, tabs.filter { !$0.isPrivate }.map(\.id), tabs.filter(\.isPrivate).map(\.id))
    }

    // MARK: Filtering

    @Test("each mode shows only its own tabs")
    func modesFilter() {
        let (model, normal, priv) = makeMixed()

        #expect(model.isPrivateMode == false)
        #expect(model.modeTabs.map(\.id) == normal)

        model.setPrivateMode(true)
        #expect(model.modeTabs.map(\.id) == priv)

        model.setPrivateMode(false)
        #expect(model.modeTabs.map(\.id) == normal)
    }

    @Test("flipping back to ordinary keeps the private tabs for the session")
    func privateTabsSurviveAFlip() {
        let (model, _, priv) = makeMixed()

        model.setPrivateMode(true)
        model.setPrivateMode(false)
        model.setPrivateMode(true)

        #expect(model.modeTabs.map(\.id) == priv)
        #expect(model.store.hasPrivateTabs)
    }

    // MARK: Current tab

    @Test("each mode remembers its own current tab")
    func perModeCurrent() {
        let (model, normal, priv) = makeMixed()

        model.store.select(normal[0])
        model.setPrivateMode(true)
        #expect(model.modeCurrentTabID == priv[1])
        model.store.select(priv[0])

        model.setPrivateMode(false)
        #expect(model.modeCurrentTabID == normal[0])
        #expect(model.store.currentTabID == normal[0])

        model.setPrivateMode(true)
        #expect(model.modeCurrentTabID == priv[0])
        #expect(model.store.currentTabID == priv[0])
    }

    @Test("closing a tab hands currency to a neighbour of its own mode")
    func closeStaysInMode() {
        let (model, normal, priv) = makeMixed()
        model.setPrivateMode(true)
        model.store.select(priv[1])

        model.closeTab(priv[1])

        #expect(model.modeCurrentTabID == priv[0])
        #expect(model.store.currentTab?.isPrivate == true)
        #expect(model.store.currentTabID(inPrivate: false) == normal[1])
    }

    @Test("a stale ordinary tab is archived even while private is the current mode")
    func archiveSkipsOnlyOrdinaryCurrent() {
        let store = TabStore()
        let old = Date(timeIntervalSince1970: 0)
        let a = store.newTab(title: "A", now: old)
        let b = store.newTab(title: "B", now: old)
        store.newTab(title: "P", isPrivate: true, now: old)
        store.select(a.id)
        store.select(store.tabs.last?.id ?? a.id)

        let archived = store.archiveStale(now: Date(timeIntervalSince1970: 10 * 86_400), after: 86_400)

        // The ordinary mode's current tab, A, stays; B goes.
        #expect(archived == [b.id])
    }

    // MARK: The +

    @Test("the + opens a tab of the kind the mode shows")
    func plusFollowsMode() {
        let (model, _, _) = makeMixed()

        model.newTabFromTabs()
        #expect(model.launchIsPrivate == false)
        #expect(model.surface == .launchSearch)
        model.openFromLaunch(url("c.example"))
        #expect(model.store.currentTab?.isPrivate == false)

        model.showTabs()
        model.setPrivateMode(true)
        model.newTabFromTabs()
        #expect(model.launchIsPrivate == true)
        model.openFromLaunch(url("p3.example"))
        #expect(model.store.currentTab?.isPrivate == true)
        #expect(model.isPrivateMode)
    }

    @Test("the other kind is a long press away")
    func otherKind() {
        let (model, _, _) = makeMixed()
        model.setPrivateMode(true)

        model.newNormalTab()
        #expect(model.launchIsPrivate == false)
        #expect(model.isPrivateMode == false)

        model.showTabs()
        model.newPrivateTab()
        #expect(model.launchIsPrivate == true)
        #expect(model.isPrivateMode)
    }

    @Test("the menu's Private tile switches to private mode and opens a private search")
    func tileSwitchesMode() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"))

        model.newPrivateTab()

        #expect(model.isPrivateMode)
        #expect(model.surface == .launchSearch)
        #expect(model.searchIsPrivate)
    }

    // MARK: Leaving

    @Test("flipping to ordinary with no ordinary tab shows the ordinary launch search")
    func flipWithNoOrdinaryTabs() {
        let model = makeModel()
        model.newPrivateTab()
        model.openFromLaunch(url("p.example"))
        model.showTabs()
        #expect(model.isPrivateMode)

        model.setPrivateMode(false)

        #expect(model.surface == .launchSearch)
        #expect(model.launchIsPrivate == false)
        #expect(model.isPrivateMode == false)
    }

    @Test("swiping that search away lands on the private stack, the only one there is")
    func dismissLandsOnPrivate() {
        let model = makeModel()
        model.newPrivateTab()
        model.openFromLaunch(url("p.example"))
        model.showTabs()
        model.setPrivateMode(false)

        model.dismissLaunchSearch()

        #expect(model.surface == .tabs)
        #expect(model.isPrivateMode)
    }

    @Test("an empty private stack stays on the tabs screen")
    func emptyPrivateStays() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"))
        model.newPrivateTab()
        model.openFromLaunch(url("p.example"))
        let privateID = model.store.currentTabID
        model.showTabs()

        if let privateID { model.closeTab(privateID) }

        #expect(model.surface == .tabs)
        #expect(model.isPrivateMode)
        #expect(model.modeTabs.isEmpty)
        #expect(model.store.hasPrivateTabs == false)
    }

    @Test("closing the last ordinary tab leaves the ordinary launch search")
    func lastOrdinaryClosed() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"))
        let ordinary = model.store.currentTabID
        model.newPrivateTab()
        model.openFromLaunch(url("p.example"))
        model.showTabs()
        model.setPrivateMode(false)

        if let ordinary { model.closeTab(ordinary) }

        #expect(model.surface == .launchSearch)
        #expect(model.launchIsPrivate == false)
        #expect(model.store.hasPrivateTabs)
    }

    @Test("opening a tab sets the mode to its kind")
    func openingSetsMode() {
        let (model, normal, priv) = makeMixed()

        model.openTab(priv[0])
        #expect(model.isPrivateMode)

        model.openTab(normal[0])
        #expect(model.isPrivateMode == false)
    }

    @Test("private tabs never reach the saved index, and the ordinary current is what is saved")
    func neverPersisted() async throws {
        let persistence = InMemoryTabPersistence()
        let model = AppModel(
            store: TabStore(persistence: persistence),
            suggestions: StubSuggestionProvider(rowsByPrefix: []),
            recents: RecentSearches())
        model.openFromLaunch(url("a.example"))
        let ordinary = model.store.currentTabID
        model.newPrivateTab()
        model.openFromLaunch(url("p.example"))
        model.showTabs()
        model.setPrivateMode(true)
        await model.store.flushWrites()

        let index = try #require(await persistence.loadIndex())
        #expect(index.openTabs.count == 1)
        #expect(index.currentTabID == ordinary)
    }
}
