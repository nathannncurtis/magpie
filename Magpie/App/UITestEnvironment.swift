import Foundation

/// What the UI tests ask of the app through launch arguments: the same app, pointed at
/// its own local page server and a scratch tab store.
enum UITestEnvironment {

    /// The page server's port, shared by the engine's search template.
    static let pageServerPort: UInt16 = 53117

    /// Whether the app runs under the UI tests.
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    /// Whether this run starts from a clean slate; only the first launch of a flow passes it.
    static var resetsStore: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestingResetStore")
    }

    /// Whether the run skips the first-launch flow (Welcome and the engine picker).
    static var skipsOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestingSkipOnboarding")
    }

    /// Whether the app opens on Settings instead of the browser.
    static var startsAtSettings: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestingSurface=settings")
    }

    /// The model the app runs with: the live one, or the UI tests' own.
    @MainActor
    static func makeModel() -> AppModel {
        isUITesting ? AppModel.forUITesting(resetting: resetsStore) : AppModel.live()
    }
}

extension AppModel {

    /// The app as the UI tests drive it: a scratch store, a search engine pointed at the
    /// app's own local page server, fixed suggestion rows, and blocking over one tiny
    /// compiled rule list. The engine and the onboarding flag persist across a flow's
    /// launches, so `-uiTestingResetStore` clears them too.
    static func forUITesting(resetting: Bool) -> AppModel {
        let scratch = URL(
            fileURLWithPath: NSTemporaryDirectory(), isDirectory: true
        ).appendingPathComponent("uitest-store", isDirectory: true)
        if resetting {
            try? FileManager.default.removeItem(at: scratch)
        }
        let suite = "uitest-preferences"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        if resetting {
            defaults.removePersistentDomain(forName: suite)
        }
        let preferences = Preferences(defaults: defaults)
        preferences.searchEngine = SearchEngine(
            id: "uitest", displayName: "DuckDuckGo",
            searchTemplate: "http://127.0.0.1:\(UITestEnvironment.pageServerPort)/search?q=%s",
            suggestTemplate: nil, suggestFormat: nil)
        if UITestEnvironment.skipsOnboarding {
            preferences.hasCompletedOnboarding = true
        }
        return AppModel(
            store: TabStore(persistence: FileSystemTabPersistence(directory: scratch)),
            preferences: preferences,
            blocker: ContentBlocker(store: UITestRuleSets(), defaults: defaults),
            suggestions: StubSuggestionProvider(
                rowsByPrefix: ["magpie test", "magpie test page", "magpie test search"]),
            recents: RecentSearches())
    }
}

/// Blocking under the UI tests: one real, tiny rule list compiled into a private store,
/// with fixed timestamps so the Settings rows read the same every run. No network.
actor UITestRuleSets: RuleSetProviding {

    /// Blocks a URL substring nothing in the test pages contains.
    private static let json = #"[{"trigger":{"url-filter":"uitest-block"},"action":{"type":"block"}}]"#

    private let compiler = WebKitRuleListCompiler(
        url: URL(
            fileURLWithPath: NSTemporaryDirectory(), isDirectory: true
        ).appendingPathComponent("uitest-rules", isDirectory: true))

    /// Fixed at two hours ago, so every run reads "Updated 2 h ago".
    private let updated = Date(timeIntervalSinceNow: -(2 * 3600 + 60))
    private var compiled: CompiledRuleList?

    func refreshStale() async {}
    func refreshNow() async {}

    func ruleLists(for set: FilterRuleSet) async -> [CompiledRuleList] {
        if compiled == nil {
            compiled = try? await compiler.compile(identifier: "uitest-block", json: Self.json)
        }
        return compiled.map { [$0] } ?? []
    }

    var overallLastUpdated: Date? { updated }

    func listUpdates() async -> [FilterListUpdate] {
        FilterList.builtin.map { FilterListUpdate(list: $0, updated: updated) }
    }
}
