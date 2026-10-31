import Foundation
import Testing

@testable import Magpie

@Suite("Private tabs keep nothing")
@MainActor
struct PrivateTabLeakTests {

    private func url(_ host: String) -> URL {
        URL(string: "https://\(host)") ?? URL(fileURLWithPath: "/")
    }

    private func makeModel(skimAvailable: Bool = false) -> AppModel {
        AppModel(
            store: TabStore(persistence: InMemoryTabPersistence()),
            suggestions: StubSuggestionProvider(rowsByPrefix: []),
            recents: RecentSearches(),
            skimAvailable: skimAvailable)
    }

    @Test("a private tab's session keeps its addresses out of the log")
    func sessionLogsNoAddress() {
        let model = makeModel()
        model.newPrivateTab()
        model.openFromLaunch(url("a.example"))

        #expect(model.currentSession?.isPrivate == true)
        #expect(model.currentSession?.loggable(url("a.example")) == "private")
    }

    @Test("an ordinary tab's session logs its address")
    func ordinarySessionLogsAddress() {
        let model = makeModel()
        model.openFromLaunch(url("a.example"))

        #expect(model.currentSession?.isPrivate == false)
        #expect(model.currentSession?.loggable(url("a.example")) == "https://a.example")
    }

    @Test("a search over a private page with no session opens a private tab")
    func navigateWithoutSessionStaysPrivate() {
        let model = makeModel()
        model.store.newTab(url: url("a.example"), isPrivate: true, now: .now)
        #expect(model.currentSession == nil)

        model.navigateCurrent(url("b.example"))

        #expect(model.store.currentTab?.url == url("b.example"))
        #expect(model.store.currentTab?.isPrivate == true)
    }

    @Test("a private page runs no Skim")
    func privatePageRunsNoSkim() {
        let model = makeModel(skimAvailable: true)
        model.newPrivateTab()
        model.openFromLaunch(url("a.example"))

        model.startSkim(query: "anything")

        #expect(model.skimRun == nil)
        #expect(model.surface == .reading(searchOpen: false))
    }

    @Test("a mod's value set on a private page is not saved")
    func modValueFromPrivatePageDropped() {
        let values = RecordingModValues()
        let relay = ModValueRelay()
        relay.values = values

        relay.store("1", forKey: "k", modID: "m", fromPrivatePage: true)
        #expect(values.stored.isEmpty)

        relay.store("2", forKey: "k", modID: "m", fromPrivatePage: false)
        #expect(values.stored == ["m.k=2"])
    }
}

@MainActor
private final class RecordingModValues: ModValuesReading {
    var stored: [String] = []

    func scriptBody(for mod: InstalledMod) -> String? { nil }
    func storedValues(modID: String) -> [String: String] { [:] }
    func storeValue(_ json: String, forKey key: String, modID: String) {
        stored.append("\(modID).\(key)=\(json)")
    }
}
