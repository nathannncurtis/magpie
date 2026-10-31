import Foundation
import Testing

@testable import Magpie

/// The menu's wiring: the Bookmark tile's state, and Settings opening on the page the
/// menu sent it to.
@Suite("Menu wiring")
@MainActor
struct MenuModelTests {

    private func makeModel(persistence: TabPersistence? = InMemoryTabPersistence()) -> AppModel {
        AppModel(
            store: TabStore(persistence: persistence),
            suggestions: StubSuggestionProvider(rowsByPrefix: []),
            recents: RecentSearches())
    }

    private func url(_ address: String) -> URL {
        URL(string: address) ?? URL(fileURLWithPath: "/")
    }

    @Test("the Bookmark tile saves the page the tab shows, then takes it back out")
    func bookmarkTileRoundTrip() {
        let model = makeModel()
        model.openFromLaunch(url("https://quietweb.org/reading"))

        #expect(!model.currentPageIsBookmarked)
        #expect(model.toggleCurrentPageBookmark())
        #expect(model.currentPageIsBookmarked)
        #expect(model.bookmarks.bookmarks.count == 1)
        #expect(model.bookmarks.bookmarks.first?.url == url("https://quietweb.org/reading"))
        #expect(!model.toggleCurrentPageBookmark())
        #expect(!model.currentPageIsBookmarked)
        #expect(model.bookmarks.bookmarks.isEmpty)
    }

    @Test("saving a second page leaves the first bookmarked")
    func bookmarkTileTracksTheCurrentTab() {
        let model = makeModel()
        model.openFromLaunch(url("https://quietweb.org/one"))
        model.openFromLaunch(url("https://quietweb.org/two"))

        #expect(model.toggleCurrentPageBookmark())
        #expect(model.currentPageIsBookmarked)

        model.openFromLaunch(url("https://quietweb.org/three"))
        #expect(!model.currentPageIsBookmarked)
        #expect(model.bookmarks.bookmarks.count == 1)
    }

    @Test("the engine row opens Settings on its engine list, and Done clears the page")
    func engineRowOpensTheEngineList() {
        let model = makeModel()

        model.showEngineList()
        #expect(model.showsSettings)
        #expect(model.settingsPage == .engineList)

        model.closeSettings()
        #expect(!model.showsSettings)
        #expect(model.settingsPage == nil)

        model.showSettings()
        #expect(model.showsSettings)
        #expect(model.settingsPage == nil)
    }

    @Test("the archive stepper writes the preferences Settings reads")
    func archiveStepperSharesPreferences() {
        let defaults = UserDefaults(suiteName: "menu-archive-tests-\(UUID().uuidString)") ?? .standard
        let preferences = Preferences(defaults: defaults)
        let model = AppModel(
            store: TabStore(persistence: InMemoryTabPersistence()),
            preferences: preferences,
            suggestions: StubSuggestionProvider(rowsByPrefix: []),
            recents: RecentSearches())

        // The stepper's choice callback, as the menu passes it in.
        let choose: (TimeInterval) -> Void = { model.preferences.archiveInterval = $0 }
        choose(3 * 24 * 60 * 60)

        #expect(preferences.archiveInterval == 3 * 24 * 60 * 60)
        #expect(Preferences.archiveIntervalLabel(preferences.archiveInterval) == "3 days")
    }

    @Test("the Skim tile reads the search behind the engine's results page")
    func skimTileReadsTheCurrentEngine() {
        let model = makeModel()
        guard let results = model.engine.searchURL(for: "magpie test") else {
            Issue.record("no results url")
            return
        }
        model.openFromLaunch(results)

        #expect(model.skimTileQuery == "magpie test")
    }

    @Test("the Skim tile reads another engine's results page the same way")
    func skimTileReadsAForeignEngine() {
        let model = makeModel()
        guard let results = SearchEngine.builtins[1].searchURL(for: "quiet web") else {
            Issue.record("no results url")
            return
        }
        model.openFromLaunch(results)

        #expect(model.skimTileQuery == "quiet web")
    }

    @Test("off a results page, the Skim tile reads the title, then the host")
    func skimTileFallsBackToTitleThenHost() {
        let model = makeModel()

        // A page with its own title.
        model.openFromLaunch(url("https://quietweb.org/reading"))
        guard let titled = model.store.currentTab else {
            Issue.record("no tab")
            return
        }
        model.store.update(
            id: titled.id,
            url: url("https://quietweb.org/reading"),
            title: "The web, read slowly",
            faviconURL: nil,
            now: .now)
        #expect(model.skimTileQuery == "The web, read slowly")

        // A page whose title has not landed yet.
        model.openFromLaunch(url("https://www.debuyer.com/care"))
        guard let bare = model.store.currentTab else {
            Issue.record("no tab")
            return
        }
        model.store.update(
            id: bare.id,
            url: url("https://www.debuyer.com/care"),
            title: "  ",
            faviconURL: nil,
            now: .now)
        #expect(model.skimTileQuery == "debuyer.com")
    }
}
