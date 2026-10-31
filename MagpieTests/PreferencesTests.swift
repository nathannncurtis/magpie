import Foundation
import Testing

@testable import Magpie

@Suite("Preferences")
@MainActor
struct PreferencesTests {

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "preferences-tests-\(UUID().uuidString)")
        return defaults ?? .standard
    }

    @Test("a fresh install's choices")
    func defaults() {
        let preferences = Preferences(defaults: makeDefaults())

        #expect(preferences.searchEngine == .default)
        #expect(preferences.suggestionsEnabled)
        #expect(preferences.skimEnabled)
        #expect(preferences.archiveInterval == Preferences.defaultArchiveInterval)
        #expect(!preferences.hasCompletedOnboarding)
    }

    @Test("changes write through, and a fresh Preferences reads them back")
    func persistence() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.searchEngine = SearchEngine.builtins[2]
        preferences.suggestionsEnabled = false
        preferences.skimEnabled = false
        preferences.archiveInterval = 7 * 24 * 3600
        preferences.hasCompletedOnboarding = true

        let reread = Preferences(defaults: defaults)
        #expect(reread.searchEngine == SearchEngine.builtins[2])
        #expect(!reread.suggestionsEnabled)
        #expect(!reread.skimEnabled)
        #expect(reread.archiveInterval == 7 * 24 * 3600)
        #expect(reread.hasCompletedOnboarding)
    }

    @Test("an Other engine persists by its id, name and template")
    func otherEnginePersists() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        let other = SearchEngine.other(template: "https://example.org/search?q=%s")
        preferences.searchEngine = other!

        let reread = Preferences(defaults: defaults)
        #expect(reread.searchEngine.id == "other")
        #expect(reread.searchEngine.searchTemplate == "https://example.org/search?q=%s")
        #expect(reread.searchEngine.searchURL(for: "magpie") != nil)
    }

    @Test("a stored engine that no longer parses falls back to the default")
    func corruptEngineFallsBack() {
        let defaults = makeDefaults()
        defaults.set("no-such-engine", forKey: "searchEngineID")
        defaults.set("not a url", forKey: "searchEngineTemplate")

        #expect(Preferences(defaults: defaults).searchEngine == .default)
    }

    @Test("the archive steps are the six offered, and they snap")
    func archiveSteps() {
        let day = 24 * 3600.0
        #expect(
            Preferences.archiveIntervalSteps == [0.5 * day, day, 3 * day, 7 * day, 14 * day, 30 * day])
        #expect(Preferences.defaultArchiveInterval == day)

        #expect(Preferences.nearestStep(to: 0) == 12 * 3600)
        #expect(Preferences.nearestStep(to: 20 * 3600) == 24 * 3600)
        #expect(Preferences.nearestStep(to: 40 * 24 * 3600) == 30 * 24 * 3600)

        // A value from outside the steps still reads as one of them.
        let preferences = Preferences(defaults: makeDefaults())
        preferences.archiveInterval = 5 * 24 * 3600
        #expect(preferences.archiveInterval == 3 * 24 * 3600)
    }

    @Test("the archive labels read like the Settings row")
    func archiveLabels() throws {
        #expect(Preferences.archiveIntervalLabel(12 * 3600) == "12 hours")
        #expect(Preferences.archiveIntervalLabel(24 * 3600) == "1 day")
        #expect(Preferences.archiveIntervalLabel(3 * 24 * 3600) == "3 days")
        #expect(Preferences.archiveIntervalLabel(7 * 24 * 3600) == "1 week")
        #expect(Preferences.archiveIntervalLabel(14 * 24 * 3600) == "2 weeks")
        #expect(Preferences.archiveIntervalLabel(30 * 24 * 3600) == "30 days")
    }

    @Test("onboarding gates on the flag alone")
    func onboardingGate() {
        let preferences = Preferences(defaults: makeDefaults())
        #expect(!preferences.hasCompletedOnboarding)

        preferences.hasCompletedOnboarding = true
        #expect(preferences.hasCompletedOnboarding)

        let reread = Preferences(defaults: makeDefaults())
        #expect(!reread.hasCompletedOnboarding)
    }
}

@Suite("AppModel reads its choices from Preferences")
@MainActor
struct AppModelPreferencesTests {

    private func makeModel(preferences: Preferences) -> AppModel {
        AppModel(
            store: TabStore(),
            preferences: preferences,
            suggestions: StubSuggestionProvider(rowsByPrefix: []),
            recents: RecentSearches())
    }

    /// A store of its own per test: a fixed suite name outlives the run on a device and
    /// hands the next run the last one's choices.
    private func freshPreferences() -> Preferences {
        Preferences(defaults: UserDefaults(suiteName: "appmodel-prefs-tests-\(UUID().uuidString)") ?? .standard)
    }

    @Test("the engine, the two rows and the archive interval come from Preferences")
    func readsFromPreferences() {
        let preferences = freshPreferences()
        preferences.searchEngine = SearchEngine.builtins[1]
        preferences.suggestionsEnabled = false
        preferences.skimEnabled = false
        preferences.archiveInterval = 7 * 24 * 3600

        let model = makeModel(preferences: preferences)
        #expect(model.engine == SearchEngine.builtins[1])
        #expect(!model.suggestionsEnabled)
        #expect(!model.skimEnabled)

        // A week's interval: a tab last read eight days ago archives; the current one stays.
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let url = URL(string: "https://example.org")!
        _ = model.store.newTab(url: url, now: now.addingTimeInterval(-8 * 24 * 3600))
        _ = model.store.newTab(url: url, now: now)
        model.refreshArchive(now: now)
        #expect(model.store.tabs.count == 1)
        #expect(model.store.archivedTabs.count == 1)

        // At thirty days, an eight-day-old tab stays where it is.
        preferences.archiveInterval = 30 * 24 * 3600
        let longModel = makeModel(preferences: preferences)
        _ = longModel.store.newTab(url: url, now: now.addingTimeInterval(-8 * 24 * 3600))
        _ = longModel.store.newTab(url: url, now: now)
        longModel.refreshArchive(now: now)
        #expect(longModel.store.tabs.count == 2)
        #expect(longModel.store.archivedTabs.isEmpty)
    }

    @Test("onboarding runs once, and completing it opens the app")
    func onboardingGate() {
        let preferences = freshPreferences()
        let model = makeModel(preferences: preferences)
        #expect(model.needsOnboarding)

        model.completeOnboarding()
        #expect(!model.needsOnboarding)
        #expect(preferences.hasCompletedOnboarding)
    }

    @Test("Settings shows and hides")
    func settingsPresentation() {
        let model = makeModel(
            preferences: freshPreferences())
        #expect(!model.showsSettings)

        model.showSettings()
        #expect(model.showsSettings)

        model.showsSettings = false
        #expect(!model.showsSettings)
    }
}
