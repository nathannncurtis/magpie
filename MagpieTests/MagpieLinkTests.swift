import Foundation
import Testing

@testable import Magpie

@Suite("MagpieLink")
struct MagpieLinkTests {

    private func link(_ text: String) -> MagpieLink? {
        URL(string: text).flatMap(MagpieLink.init(url:))
    }

    @Test("open reads the encoded address")
    func openReadsAddress() {
        #expect(
            link("magpie://open?url=https%3A%2F%2Fquietweb.org%2Fa%3Fx%3D1%26y%3D2")
                == .open(URL(string: "https://quietweb.org/a?x=1&y=2")!))
    }

    @Test("open takes only web addresses")
    func openRefusesOtherSchemes() {
        #expect(link("magpie://open?url=javascript%3Aalert(1)") == nil)
        #expect(link("magpie://open?url=file%3A%2F%2F%2Fetc%2Fpasswd") == nil)
        #expect(link("magpie://open?url=magpie%3A%2F%2Fsearch") == nil)
        #expect(link("magpie://open?url=https%3A%2F%2F") == nil)
        #expect(link("magpie://open") == nil)
    }

    @Test("search reads the query, and none opens the empty sheet")
    func searchReadsQuery() {
        #expect(link("magpie://search?q=carbon%20steel%20pan") == .search("carbon steel pan"))
        #expect(link("magpie://search?q=a%2Bb") == .search("a+b"))
        #expect(link("magpie://search") == .search(nil))
        #expect(link("magpie://search?q=%20%20") == .search(nil))
    }

    @Test("anything else is not a link")
    func otherLinksAreIgnored() {
        #expect(link("magpie://settings") == nil)
        #expect(link("https://example.com/open?url=https%3A%2F%2Fa.com") == nil)
        #expect(link("MAGPIE://SEARCH?q=x") == .search("x"))
    }

    @Test("built links read back as what they were built from")
    func roundTrip() throws {
        let page = try #require(URL(string: "https://example.com/a b?x=1&y=2+3#frag"))
        let built = try #require(MagpieLink.openURL(for: page))
        #expect(MagpieLink(url: built) == .open(page))

        let query = "cats & dogs = 100% + more"
        let search = try #require(MagpieLink.searchURL(for: query))
        #expect(MagpieLink(url: search) == .search(query))
    }

    @Test("quick action types map to actions")
    func shortcutTypes() {
        #expect(ShortcutAction(rawValue: "com.magpiebrowser.Magpie.newPrivateTab") == .newPrivateTab)
        #expect(ShortcutAction(rawValue: "com.magpiebrowser.Magpie.search") == .search)
        #expect(ShortcutAction(rawValue: "nope") == nil)
    }
}

@Suite("AppModel links and quick actions")
@MainActor
struct AppModelLinkTests {

    private func makeModel() -> AppModel {
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "links-\(UUID().uuidString)", directoryHint: .isDirectory)
        return AppModel(
            store: TabStore(persistence: InMemoryTabPersistence()),
            suggestions: StubSuggestionProvider(rowsByPrefix: []),
            recents: RecentSearches(),
            downloads: DownloadStore(directory: scratch))
    }

    @Test("an open link makes a tab and reads it")
    func openLink() {
        let model = makeModel()
        model.newPrivateTab()
        model.handle(.open(URL(string: "https://quietweb.org")!))
        #expect(model.store.tabs.count == 1)
        #expect(model.store.currentTab?.isPrivate == false)
        #expect(model.surface == .reading(searchOpen: false))
    }

    @Test("a search link runs the query on the engine")
    func searchLink() {
        let model = makeModel()
        model.handle(.search("carbon steel"))
        let url = model.store.currentTab?.url?.absoluteString ?? ""
        #expect(url.contains("carbon"))
        #expect(model.surface == .reading(searchOpen: false))
    }

    @Test("a search link with no query opens the search sheet")
    func emptySearchLink() {
        let model = makeModel()
        model.handle(.search(nil))
        #expect(model.surface == .launchSearch)
        #expect(model.searchIsPrivate == false)
        #expect(model.store.tabs.isEmpty)
    }

    @Test("the quick actions open the launch search")
    func quickActions() {
        let model = makeModel()
        model.handle(.newTab)
        #expect(model.surface == .launchSearch)
        #expect(model.launchIsPrivate == false)

        model.handle(.newPrivateTab)
        #expect(model.surface == .launchSearch)
        #expect(model.launchIsPrivate)

        model.handle(.search)
        #expect(model.surface == .launchSearch)
        #expect(model.launchIsPrivate == false)
    }

    @Test("downloads return to the screen that opened them")
    func downloadsSurface() {
        let model = makeModel()
        model.openFromLaunch(URL(string: "https://a.example")!)
        model.showDownloads()
        #expect(model.surface == .downloads)
        model.closeDownloads()
        #expect(model.surface == .reading(searchOpen: false))
    }
}
