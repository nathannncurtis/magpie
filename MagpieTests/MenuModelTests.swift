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
}
