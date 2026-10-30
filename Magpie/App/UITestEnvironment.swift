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

    /// The surface to open on, when a flow names one: "-uiTestingSurface=mods".
    static var launchSurface: Surface? {
        guard
            let argument = ProcessInfo.processInfo.arguments.first(where: {
                $0.hasPrefix("-uiTestingSurface=")
            })
        else { return nil }
        switch argument.dropFirst("-uiTestingSurface=".count) {
        case "mods": return .mods
        default: return nil
        }
    }

    /// Whether this run starts with mods installed, for the installed screens.
    static var seedsMods: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestingModsInstalled")
    }

    /// The model the app runs with: the live one, or the UI tests' own.
    @MainActor
    static func makeModel() -> AppModel {
        isUITesting ? AppModel.forUITesting(resetting: resetsStore) : AppModel.live()
    }
}

extension AppModel {

    /// The app as the UI tests drive it: a scratch store, a search engine pointed at the
    /// app's own local page server, fixed suggestion rows, and mods that never reach past
    /// the loopback interface — the directory comes from the bundled fixture, already
    /// fresh, and blocking carries no lists to download.
    static func forUITesting(resetting: Bool) -> AppModel {
        let scratch = URL(
            fileURLWithPath: NSTemporaryDirectory(), isDirectory: true
        ).appendingPathComponent("uitest-store", isDirectory: true)
        if resetting {
            try? FileManager.default.removeItem(at: scratch)
        }
        let engine = SearchEngine(
            id: "uitest", displayName: "DuckDuckGo",
            searchTemplate: "http://127.0.0.1:\(UITestEnvironment.pageServerPort)/search?q=%s",
            suggestTemplate: nil, suggestFormat: nil)
        let modStore = ModStore(io: InMemoryModStoreIO(), listSink: nil)
        if UITestEnvironment.seedsMods {
            seedMods(into: modStore)
        }
        let defaults = UserDefaults(suiteName: "uitest-blocking-\(UUID().uuidString)")
        let blocker = ContentBlocker(
            store: FilterListStore(
                lists: [],
                directory: scratch.appending(component: "lists", directoryHint: .isDirectory)),
            defaults: defaults ?? .standard)
        let model = AppModel(
            store: TabStore(persistence: FileSystemTabPersistence(directory: scratch)),
            engine: engine,
            suggestions: StubSuggestionProvider(
                rowsByPrefix: ["magpie test", "magpie test page", "magpie test search"]),
            recents: RecentSearches(),
            blocker: blocker,
            modStore: modStore,
            modDirectory: fixtureDirectory())
        model.launchSurfaceOverride = UITestEnvironment.launchSurface
        return model
    }

    /// The directory over the bundled fixture index, cached warm so nothing fetches.
    private static func fixtureDirectory() -> ModDirectory {
        ModDirectory(cache: InMemoryModDirectoryCache.warm(UITestModFixtures.directoryIndex()))
    }

    /// The installed screens' three mods, newest install last (board 13): a link-installed
    /// script, a directory filter list, and a directory script on top.
    private static func seedMods(into store: ModStore) {
        guard
            let wikiURL = UITestModFixtures.serverURL("/mod.user.js"),
            let listURL = UITestModFixtures.serverURL("/mod.list.txt"),
            let wiki = Userscript.parse(UITestModFixtures.userscript)
        else { return }
        store.install(
            ModDraft(
                id: ModLinkInstaller.linkID(for: wikiURL),
                name: "Wider Wikipedia",
                kind: .userscript,
                author: wiki.metadata.author,
                version: wiki.metadata.version,
                summary: "Lets articles use the full width.",
                icon: .linkInstall(),
                source: .link(wikiURL),
                script: wiki.metadata,
                scriptBody: wiki.body,
                listURL: nil))

        store.install(
            ModDraft(
                id: "midnight-pages",
                name: "Midnight Pages",
                kind: .filterList,
                author: "magpie",
                version: "1.0",
                summary: "Dark styles for sites that never shipped one.",
                icon: ModIconSpec(
                    glyph: "moon.fill", gradient: ["#2B3358", "#0F1226"]),
                source: .directory("midnight-pages"),
                script: nil,
                scriptBody: nil,
                listURL: listURL))

        store.install(
            ModDraft(
                id: "google-answer-box",
                name: "Google Answer Box",
                kind: .userscript,
                author: "nathannncurtis",
                version: "1.3",
                summary: "Pins the direct answer above the noise.",
                icon: ModIconSpec(glyph: "text.bubble", gradient: ["#4C8DF6", "#1A56D6"]),
                source: .directory("google-answer-box"),
                script: wiki.metadata,
                scriptBody: wiki.body,
                listURL: nil))
    }
}
