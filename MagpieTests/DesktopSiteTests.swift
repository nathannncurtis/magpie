import Foundation
import Testing

@testable import Magpie

@Suite("Desktop site, per site")
@MainActor
struct DesktopSiteTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "desktop-site-tests-\(UUID().uuidString)") ?? .standard
    }

    private func url(_ address: String) -> URL {
        URL(string: address) ?? URL(fileURLWithPath: "/")
    }

    @Test("every site starts on its mobile version")
    func offByDefault() {
        let preferences = Preferences(defaults: makeDefaults())

        #expect(!preferences.usesDesktopSite(for: url("https://example.org/page")))
        #expect(preferences.desktopSiteHosts.isEmpty)
    }

    @Test("the choice is for one host and holds across its pages")
    func rememberedPerHost() {
        let preferences = Preferences(defaults: makeDefaults())
        preferences.setDesktopSite(true, for: url("https://example.org/a"))

        #expect(preferences.usesDesktopSite(for: url("https://example.org/b?q=1")))
        #expect(!preferences.usesDesktopSite(for: url("https://other.example/a")))
        #expect(!preferences.usesDesktopSite(for: url("https://sub.example.org/a")))
    }

    @Test("a site and its www twin share one choice, whatever the case")
    func wwwAndCaseFold() {
        let preferences = Preferences(defaults: makeDefaults())
        preferences.setDesktopSite(true, for: url("https://WWW.Example.org/a"))

        #expect(preferences.usesDesktopSite(for: url("https://example.org")))
        #expect(Preferences.siteKey(for: url("https://www.example.org")) == "example.org")
    }

    @Test("turning it off forgets the host")
    func turnsOff() {
        let preferences = Preferences(defaults: makeDefaults())
        preferences.setDesktopSite(true, for: url("https://example.org"))
        preferences.setDesktopSite(false, for: url("https://example.org/x"))

        #expect(!preferences.usesDesktopSite(for: url("https://example.org")))
        #expect(preferences.desktopSiteHosts.isEmpty)
    }

    @Test("the choice survives a relaunch")
    func persists() {
        let defaults = makeDefaults()
        Preferences(defaults: defaults).setDesktopSite(true, for: url("https://example.org"))

        let reread = Preferences(defaults: defaults)
        #expect(reread.usesDesktopSite(for: url("https://example.org/anything")))
    }

    @Test("an address with no host has no choice to make")
    func noHost() {
        let preferences = Preferences(defaults: makeDefaults())
        preferences.setDesktopSite(true, for: url("about:blank"))
        preferences.setDesktopSite(true, for: nil)

        #expect(preferences.desktopSiteHosts.isEmpty)
        #expect(!preferences.usesDesktopSite(for: nil))
        #expect(Preferences.siteKey(for: nil) == nil)
    }

    @Test("the menu row follows the current tab's site")
    func modelFollowsCurrentTab() {
        let model = AppModel(
            suggestions: StubSuggestionProvider(rowsByPrefix: []), recents: RecentSearches())
        #expect(!model.canChooseDesktopSite)

        model.store.newTab(url: url("https://example.org/a"), title: "A", now: .now)
        #expect(model.canChooseDesktopSite)
        #expect(!model.currentSiteIsDesktop)

        model.preferences.setDesktopSite(true, for: url("https://example.org/a"))
        #expect(model.currentSiteIsDesktop)
    }
}

@Suite("Clear browsing data")
@MainActor
struct BrowsingDataKindsTests {

    @Test("everything is ticked to begin with")
    func allOn() {
        let kinds = BrowsingDataKinds()

        #expect(kinds.history && kinds.cookiesAndSiteData && kinds.cache)
        #expect(!kinds.isEmpty)
    }

    @Test("cache and site data stand for different website data")
    func typesSplit() {
        var kinds = BrowsingDataKinds(history: false, cookiesAndSiteData: false, cache: true)
        let cache = kinds.websiteDataTypes
        kinds = BrowsingDataKinds(history: false, cookiesAndSiteData: true, cache: false)
        let site = kinds.websiteDataTypes

        #expect(!cache.isEmpty && !site.isEmpty)
        #expect(cache.isDisjoint(with: site))
        #expect(site.contains("WKWebsiteDataTypeCookies"))
        #expect(cache.contains("WKWebsiteDataTypeDiskCache"))
    }

    @Test("history alone touches no website data")
    func historyOnly() {
        let kinds = BrowsingDataKinds(history: true, cookiesAndSiteData: false, cache: false)

        #expect(kinds.websiteDataTypes.isEmpty)
    }

    @Test("clearing history through the model empties it")
    func modelClearsHistory() async {
        let model = AppModel(
            suggestions: StubSuggestionProvider(rowsByPrefix: []), recents: RecentSearches())
        model.history.record(
            url: URL(string: "https://example.org") ?? URL(fileURLWithPath: "/"), isPrivate: false, now: .now)
        await model.clearBrowsingData(
            BrowsingDataKinds(history: true, cookiesAndSiteData: false, cache: false))

        #expect(model.history.entries.isEmpty)
    }
}
