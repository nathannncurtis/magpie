import Foundation
import Testing

@testable import Magpie

/// The app model's surface moves that the main suites leave out: the mods screen's way
/// back, and the moves that must do nothing when what they name is gone.
@Suite("AppModel surfaces")
@MainActor
struct AppModelSurfaceTests {

    /// Dates from a zero base, so ordering comparisons stay exact.
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

    // MARK: Mods

    @Test("the mods screen's Done goes back to the screen that opened it")
    func modsReturnToOpener() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        model.showTabs()

        model.showMods()
        #expect(model.surface == .mods)

        model.closeMods()
        #expect(model.surface == .tabs)
    }

    @Test("opening the mods screen twice still goes back to the screen before it")
    func modsOpenedTwice() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))

        model.showMods()
        model.showMods()
        model.closeMods()

        #expect(model.surface == .reading(searchOpen: false))
    }

    @Test("the mods screen with nothing beneath it falls back to the launch search")
    func modsWithNothingBeneath() async {
        let model = makeModel()
        await model.start(now: date(0))
        model.showMods()
        model.closeMods()
        #expect(model.surface == .launchSearch)

        // The remembered screen is spent: a later open starts fresh.
        model.openFromLaunch(url("a.example"), now: date(10))
        model.showMods()
        model.closeMods()
        #expect(model.surface == .reading(searchOpen: false))
    }

    // MARK: Gone tabs

    @Test("a card for a tab that is gone opens nothing")
    func openMissingTab() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        let current = model.store.currentTabID
        model.showTabs()

        model.openTab(UUID(), now: date(10))

        #expect(model.surface == .tabs)
        #expect(model.store.currentTabID == current)
    }

    @Test("an archive row for a tab that is gone restores nothing")
    func restoreMissingTab() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        model.showArchive()

        model.restoreArchivedTab(UUID(), now: date(10))

        #expect(model.surface == .archive)
        #expect(model.store.tabs.count == 1)
    }

    // MARK: Closing and the launch sheet

    @Test("closing one of several tabs drops its page session and keeps the others")
    func closeDropsOnlyItsSession() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        let first = model.store.currentTab!.id
        model.openFromLaunch(url("b.example"), now: date(10))
        let second = model.store.currentTab!.id
        model.showTabs()

        model.closeTab(first)

        #expect(model.sessions[first] == nil)
        #expect(model.sessions[second] != nil)
        #expect(model.store.currentTabID == second)
        #expect(model.surface == .tabs)
    }

    @Test("a swipe down on the launch sheet drops the text it opened with")
    func dismissClearsPrefill() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        model.newTabFromTabs()
        model.searchPrefill = "seasoning carbon steel"

        model.dismissLaunchSearch()

        #expect(model.surface == .tabs)
        #expect(model.searchPrefill == nil)
    }

    @Test("a bookmark opened from the bookmarks screen lands on reading, in a new tab")
    func bookmarkFromBookmarks() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        model.showBookmarks()

        model.openBookmark(url("b.example"), now: date(10))

        #expect(model.surface == .reading(searchOpen: false))
        #expect(model.store.tabs.count == 2)
        #expect(model.store.currentTab?.url == url("b.example"))
        #expect(model.currentSession != nil)
    }
}
