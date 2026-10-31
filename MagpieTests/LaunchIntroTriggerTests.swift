import Foundation
import Testing

@testable import Magpie

@Suite("LaunchIntro trigger")
@MainActor
struct LaunchIntroTriggerTests {

    private func url(_ host: String) -> URL {
        URL(string: "https://\(host)") ?? URL(fileURLWithPath: "/")
    }

    private func makeModel(persistence: TabPersistence = InMemoryTabPersistence()) -> AppModel {
        AppModel(
            store: TabStore(persistence: persistence),
            suggestions: StubSuggestionProvider(rowsByPrefix: []),
            recents: RecentSearches())
    }

    // MARK: The decision

    @Test("no tabs and onboarding done: the intro plays")
    func coldEmptyLaunchPlaysTheIntro() {
        #expect(AppModel.shouldPlayLaunchIntro(hasTabsToRestore: false, onboardingDone: true))
    }

    @Test("a tab to restore: no intro")
    func restoredLaunchPlaysNoIntro() {
        #expect(!AppModel.shouldPlayLaunchIntro(hasTabsToRestore: true, onboardingDone: true))
    }

    @Test("onboarding pending: no intro, the flow has its own mark")
    func pendingOnboardingPlaysNoIntro() {
        #expect(!AppModel.shouldPlayLaunchIntro(hasTabsToRestore: false, onboardingDone: false))
    }

    // MARK: Start

    @Test("start with nothing to restore and onboarding done arms the intro")
    func startArmsTheIntro() async {
        let model = makeModel()
        model.preferences.hasCompletedOnboarding = true

        await model.start()

        #expect(model.playsLaunchIntro)
        #expect(model.surface == .launchSearch)
    }

    @Test("start with a tab to restore plays no intro")
    func startWithATabToRestorePlaysNoIntro() async {
        let persistence = InMemoryTabPersistence()
        let first = makeModel(persistence: persistence)
        first.openFromLaunch(url("a.example"))
        await first.store.flushWrites()

        let model = makeModel(persistence: persistence)
        model.preferences.hasCompletedOnboarding = true

        await model.start()

        #expect(!model.playsLaunchIntro)
        #expect(model.surface == .reading(searchOpen: false))
    }

    @Test("start with onboarding pending opens on the launch search with no intro")
    func startWithOnboardingPendingPlaysNoIntro() async {
        let model = makeModel()

        await model.start()

        #expect(!model.playsLaunchIntro)
        #expect(model.surface == .launchSearch)
    }

    @Test("the intro plays once: done clears it, and nothing re-arms it")
    func doneClearsTheIntro() async {
        let model = makeModel()
        model.preferences.hasCompletedOnboarding = true
        await model.start()
        #expect(model.playsLaunchIntro)

        model.launchIntroDone()
        model.newTabFromTabs()

        #expect(!model.playsLaunchIntro)
        #expect(model.surface == .launchSearch)
    }
}
