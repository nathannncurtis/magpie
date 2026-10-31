import Foundation
import Testing

@testable import Magpie

@Suite("AppModel · keyboard")
@MainActor
struct AppModelKeyboardTests {

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

    @Test("the page's shortcuts apply only while a page is up with nothing over it")
    func readingPageGatesShortcuts() async {
        let model = makeModel()
        await model.start(now: date(0))
        #expect(!model.isReadingPage)
        #expect(!model.canOpenNewTab)
        #expect(!model.canShowTabsFromKeyboard)

        model.openFromLaunch(url("a.example"), now: date(10))
        #expect(model.isReadingPage)
        #expect(model.canOpenNewTab)
        #expect(model.canShowTabsFromKeyboard)
        #expect(!model.canGoBack)
        #expect(!model.canGoForward)

        model.openSearchOverPage()
        #expect(!model.isReadingPage)

        model.closeSearchOverPage()
        model.showTabs()
        #expect(!model.isReadingPage)
        #expect(!model.canShowTabsFromKeyboard)
    }

    @Test("closing the current tab opens its neighbour in its place")
    func closeCurrentTabOpensNeighbour() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        let first = model.store.currentTab!.id
        model.openFromLaunch(url("b.example"), now: date(10))

        model.closeCurrentTab()

        #expect(model.store.tabs.map(\.id) == [first])
        #expect(model.store.currentTabID == first)
        #expect(model.surface == .reading(searchOpen: false))
        #expect(model.currentSession != nil)
    }

    @Test("closing the current last tab leaves the launch search")
    func closeCurrentLastTab() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        model.isFindingInPage = true

        model.closeCurrentTab()

        #expect(model.store.tabs.isEmpty)
        #expect(model.surface == .launchSearch)
        #expect(!model.isFindingInPage)
    }

    @Test("closing the current tab does nothing off the page")
    func closeCurrentTabNeedsReading() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        model.showTabs()

        model.closeCurrentTab()

        #expect(model.store.tabs.count == 1)
        #expect(model.surface == .tabs)
    }

    @Test("escape folds the search sheet over the page back into the bar")
    func escapeClosesSearchOverPage() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        #expect(!model.canDismissWithEscape)

        model.openSearchOverPage()
        #expect(model.canDismissWithEscape)
        model.dismissWithEscape()

        #expect(model.surface == .reading(searchOpen: false))
    }

    @Test("escape closes the find bar")
    func escapeClosesFind() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        model.isFindingInPage = true
        #expect(model.canDismissWithEscape)

        model.dismissWithEscape()

        #expect(!model.isFindingInPage)
        #expect(model.surface == .reading(searchOpen: false))
    }

    @Test("escape on the launch sheet goes back to the stack, only when there are tabs")
    func escapeOnLaunchSearch() async {
        let model = makeModel()
        await model.start(now: date(0))
        #expect(!model.canDismissWithEscape)

        model.openFromLaunch(url("a.example"), now: date(10))
        model.newTabFromTabs()
        #expect(model.canDismissWithEscape)
        model.dismissWithEscape()

        #expect(model.surface == .tabs)
    }
}
