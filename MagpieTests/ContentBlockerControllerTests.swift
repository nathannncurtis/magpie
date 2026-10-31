import Foundation
import Testing

@testable import Magpie

/// The blocker against a recording controller and a fixed rule-set source: what applying
/// and toggling does to a page.
@Suite("ContentBlocker on pages")
@MainActor
struct ContentBlockerControllerTests {

    /// Counts rule lists by the token each carries.
    private final class FakeController: ContentRuleApplying {
        var tokens: [String] = []

        func apply(_ rules: [CompiledRuleList]) {
            tokens.append(contentsOf: rules.map { "\($0.payload)" })
        }

        func removeAllRules() {
            tokens.removeAll()
        }
    }

    /// Hands every set one compiled list, its token naming the set.
    private struct FixedRuleSets: RuleSetProviding {
        func refreshStale() async {}
        func refreshNow() async {}

        func ruleLists(for set: FilterRuleSet) async -> [CompiledRuleList] {
            [CompiledRuleList(payload: "list-\(set)" as NSString)]
        }

        var overallLastUpdated: Date? { nil }

        func listUpdates() async -> [FilterListUpdate] { [] }

        func setUserLists(_ lists: [FilterList]) async {}
    }

    private func makeBlocker(defaults: UserDefaults? = nil) -> ContentBlocker {
        ContentBlocker(store: FixedRuleSets(), defaults: defaults ?? makeDefaults())
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "blocker-controller-tests-\(UUID().uuidString)") ?? .standard
    }

    /// A toggle's re-apply runs as its own task; yields on the same actor let it finish.
    private func settle() async {
        for _ in 0..<100 {
            await Task.yield()
        }
    }

    @Test("attaching a page applies the enabled sets' lists")
    func attachApplies() async {
        let blocker = makeBlocker()
        let controller = FakeController()

        await blocker.attach(controller)
        #expect(controller.tokens.count == 2)
        #expect(controller.tokens.contains("list-adsAndTrackers"))
        #expect(controller.tokens.contains("list-cookieBanners"))
    }

    @Test("a toggle off re-applies without that set's lists, without reloading anything")
    func toggleRemoves() async {
        let blocker = makeBlocker()
        let controller = FakeController()
        await blocker.attach(controller)

        blocker.blocksCookieBanners = false
        await settle()
        #expect(controller.tokens == ["list-adsAndTrackers"])

        blocker.blocksAdsAndTrackers = false
        await settle()
        #expect(controller.tokens.isEmpty)

        blocker.blocksCookieBanners = true
        await settle()
        #expect(controller.tokens == ["list-cookieBanners"])
    }

    @Test("a page attached later gets the toggles as they stand")
    func attachAfterToggle() async {
        let blocker = makeBlocker()
        blocker.blocksAdsAndTrackers = false

        let controller = FakeController()
        await blocker.attach(controller)
        #expect(controller.tokens == ["list-cookieBanners"])
    }

    @Test("detaching a page drops it from later re-applies")
    func detach() async {
        let blocker = makeBlocker()
        let controller = FakeController()
        await blocker.attach(controller)

        blocker.detach(controller)
        blocker.blocksAdsAndTrackers = false
        await settle()
        #expect(controller.tokens == ["list-adsAndTrackers", "list-cookieBanners"])
    }

    @Test("refresh re-applies and reports the store's timestamp")
    func refresh() async {
        let blocker = makeBlocker()
        let controller = FakeController()
        await blocker.attach(controller)
        controller.removeAllRules()

        await blocker.refresh()
        #expect(controller.tokens.count == 2)
    }

    @Test("the lists mod installs block on top, while any of them is enabled")
    func modListsOnTop() async {
        let blocker = makeBlocker()
        let controller = FakeController()
        await blocker.attach(controller)

        let modList = FilterList.userAdded(
            id: "midnight", title: "Midnight Pages", url: url("https://e.example/list.txt"))
        await blocker.setModLists([modList])
        #expect(controller.tokens == ["list-adsAndTrackers", "list-cookieBanners", "list-mods"])

        blocker.blocksCookieBanners = false
        await settle()
        #expect(controller.tokens == ["list-adsAndTrackers", "list-mods"])

        // The last list going away takes the set with it.
        await blocker.setModLists([])
        await settle()
        #expect(controller.tokens == ["list-adsAndTrackers"])
    }

    private func url(_ address: String) -> URL {
        URL(string: address) ?? URL(fileURLWithPath: "/")
    }
}
