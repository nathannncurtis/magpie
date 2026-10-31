import Foundation
import Testing

@testable import Magpie

@Suite("The archive and bookmarks search")
struct ListSearchTests {

    private func tab(title: String, address: String) -> Tab {
        Tab(url: URL(string: address), title: title, lastActive: Date(timeIntervalSince1970: 0))
    }

    // MARK: Archive

    @Test("an empty query matches everything")
    func emptyQueryMatchesAll() {
        let tab = tab(title: "How to season a carbon steel pan", address: "https://seriouseats.com/pan")
        #expect(ArchiveSearch.matches(tab, query: ""))
        #expect(ArchiveSearch.matches(tab, query: "   "))
    }

    @Test("titles match, without minding case")
    func matchesTitleCaseInsensitively() {
        let tab = tab(title: "How to season a carbon steel pan", address: "https://seriouseats.com/pan")
        #expect(ArchiveSearch.matches(tab, query: "carbon steel"))
        #expect(ArchiveSearch.matches(tab, query: "CARBON STEEL"))
        #expect(!ArchiveSearch.matches(tab, query: "cast iron"))
    }

    @Test("addresses match, whole or in part")
    func matchesAddresses() {
        let tab = tab(title: "Pan care", address: "https://debuyer.com/en/care")
        #expect(ArchiveSearch.matches(tab, query: "debuyer"))
        #expect(ArchiveSearch.matches(tab, query: "https://debuyer.com/en/care"))
        #expect(!ArchiveSearch.matches(tab, query: "seriouseats"))
    }

    @Test("the host matches without its www prefix")
    func matchesBareHost() {
        let tab = tab(title: "A page", address: "https://www.wikipedia.org/wiki/Magpie")
        #expect(ArchiveSearch.matches(tab, query: "wikipedia"))
        #expect(ArchiveSearch.matches(tab, query: "wiki/Magpie"))
    }

    // MARK: Bookmarks

    @Test("bookmarks match on title and address, not folder")
    func bookmarksMatchOnTitleAndAddress() {
        let bookmark = Bookmark(
            url: URL(string: "https://quietweb.org/slow")!,
            title: "The web, read slowly",
            folderID: BookmarkFolder.ID(),
            addedAt: Date(timeIntervalSince1970: 0))
        #expect(BookmarkSearch.matches(bookmark, query: "read slowly"))
        #expect(BookmarkSearch.matches(bookmark, query: "quietweb"))
        #expect(BookmarkSearch.matches(bookmark, query: ""))
        #expect(!BookmarkSearch.matches(bookmark, query: "reading"))
    }
}
