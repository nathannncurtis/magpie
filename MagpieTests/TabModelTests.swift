import Foundation
import Testing

@testable import Magpie

@Suite("Tab")
struct TabModelTests {

    @Test("the host drops its www prefix")
    func hostDropsWww() {
        let tab = Tab(
            url: URL(string: "https://www.en.wikipedia.org/wiki/Carbon_steel"),
            lastActive: Date(timeIntervalSince1970: 0))
        #expect(tab.host == "en.wikipedia.org")
    }

    @Test("a tab with no url has no host")
    func noUrlNoHost() {
        let tab = Tab(lastActive: Date(timeIntervalSince1970: 0))
        #expect(tab.host == nil)
        #expect(tab.displayTitle == "")
    }

    @Test("the card title falls back to the host")
    func titleFallsBackToHost() {
        let tab = Tab(url: URL(string: "https://quietweb.org"), lastActive: Date(timeIntervalSince1970: 0))
        #expect(tab.displayTitle == "quietweb.org")

        let titled = Tab(
            url: URL(string: "https://quietweb.org"), title: "The web, read slowly",
            lastActive: Date(timeIntervalSince1970: 0))
        #expect(titled.displayTitle == "The web, read slowly")
    }
}

@Suite("Tabs copy")
struct TabsCopyTests {

    @Test("the open count reads n open")
    func openCount() {
        #expect(TabsCopy.openCount(3) == "3 open")
        #expect(TabsCopy.openCount(1) == "1 open")
        #expect(TabsCopy.openCount(0) == "0 open")
    }

    @Test("the archive chip reads Archived · n")
    func archivedChip() {
        #expect(TabsCopy.archived(12) == "Archived · 12")
        #expect(TabsCopy.archived(0) == "Archived · 0")
    }
}
