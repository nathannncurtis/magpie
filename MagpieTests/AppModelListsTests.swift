import Foundation
import Testing

@testable import Magpie

/// The archive and bookmark surfaces of the app model.
@Suite("AppModel lists")
@MainActor
struct AppModelListsTests {

    /// Dates from a zero base, so threshold comparisons stay exact.
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func url(_ host: String) -> URL {
        URL(string: "https://\(host)") ?? URL(fileURLWithPath: "/")
    }

    private func makeModel(
        tabs: TabPersistence = InMemoryTabPersistence(),
        bookmarks: BookmarkPersistence = InMemoryBookmarkPersistence()
    ) -> AppModel {
        AppModel(
            store: TabStore(persistence: tabs),
            bookmarks: BookmarkStore(persistence: bookmarks),
            suggestions: StubSuggestionProvider(rowsByPrefix: []),
            recents: RecentSearches())
    }

    // MARK: Archive

    @Test("the archived chip opens the archive; Done goes back to the stack")
    func archiveInAndOut() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))

        model.showArchive()
        #expect(model.surface == .archive)

        model.doneWithArchive()
        #expect(model.surface == .tabs)
    }

    @Test("the archive's Done falls to the launch search with no tabs to show")
    func doneWithArchiveWithoutTabs() {
        let model = makeModel()

        model.showArchive()
        model.doneWithArchive()

        #expect(model.surface == .launchSearch)
    }

    @Test("a tapped archive row comes back and opens")
    func restoreOpensTheTab() {
        let model = makeModel()
        model.openFromLaunch(url("stale.example"), now: date(0))
        model.openFromLaunch(url("current.example"), now: date(100))
        let stale = model.store.tabs[0].id
        model.showTabs()
        _ = model.store.archiveStale(now: date(100), after: 10)
        #expect(model.store.archivedTabs.map(\.id) == [stale])

        model.restoreArchivedTab(stale, now: date(200))

        #expect(model.surface == .reading(searchOpen: false))
        #expect(model.store.archivedTabs.isEmpty)
        #expect(model.store.currentTab?.url == url("stale.example"))
        #expect(model.store.currentTab?.lastActive == date(200))
        #expect(model.currentSession != nil)
    }

    @Test("a deleted archived tab is gone for good")
    func deleteArchived() {
        let persistence = InMemoryTabPersistence()
        let model = makeModel(tabs: persistence)
        model.openFromLaunch(url("stale.example"), now: date(0))
        model.openFromLaunch(url("current.example"), now: date(100))
        model.showTabs()
        let stale = model.store.tabs[0].id
        _ = model.store.archiveStale(now: date(100), after: 10)

        #expect(model.store.archivedTabs.map(\.id) == [stale])

        model.store.deleteArchived([stale])
        #expect(model.store.archivedTabs.isEmpty)
    }

    // MARK: Bookmarks

    @Test("the bookmarks surface comes and goes")
    func bookmarksSurface() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))
        model.showTabs()

        model.showBookmarks()
        #expect(model.surface == .bookmarks)
    }

    @Test("the Bookmark tile saves the page the current tab shows")
    func bookmarkCurrentPage() {
        let model = makeModel()
        model.openFromLaunch(url("quietweb.org/slow"), now: date(0))
        model.store.update(
            id: model.store.currentTab!.id, url: url("quietweb.org/slow"),
            title: "The web, read slowly", faviconURL: url("quietweb.org/icon.png"), now: date(1))

        let saved = model.bookmarkCurrentPage(now: date(10))

        #expect(saved?.title == "The web, read slowly")
        #expect(saved?.url == url("quietweb.org/slow"))
        #expect(saved?.faviconURL == url("quietweb.org/icon.png"))
        #expect(model.bookmarks.bookmarks.map(\.addedAt) == [date(10)])
    }

    @Test("there is nothing to bookmark without a page")
    func bookmarkWithoutAPage() {
        let model = makeModel()

        let saved = model.bookmarkCurrentPage(now: date(0))

        #expect(saved == nil)
        #expect(model.bookmarks.bookmarks.isEmpty)
    }

    @Test("a tapped bookmark opens in a new tab")
    func openBookmarkOpensANewTab() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"), now: date(0))

        model.showBookmarks()
        model.openBookmark(url("b.example"), now: date(20))

        #expect(model.surface == .reading(searchOpen: false))
        #expect(model.store.tabs.count == 2)
        #expect(model.store.currentTab?.url == url("b.example"))
        #expect(model.currentSession != nil)
    }

    @Test("a start loads the saved bookmarks")
    func startLoadsBookmarks() async {
        let persistence = InMemoryBookmarkPersistence(
            index: BookmarkIndex(
                bookmarks: [
                    Bookmark(url: url("a.example"), title: "A", addedAt: date(0))
                ],
                folders: []))
        let model = makeModel(bookmarks: persistence)

        await model.start(now: date(10))

        #expect(model.bookmarks.bookmarks.map(\.title) == ["A"])
    }
}
