import Foundation
import SwiftUI

/// What the UI tests ask of the app through launch arguments: the same app, pointed at
/// its own local page server and a scratch tab store.
enum UITestEnvironment {

    /// The launch arguments the hooks read; empty in Release, so every hook below stays
    /// off and the page server never starts in the shipped app.
    private static var launchArguments: [String] {
        #if DEBUG
            ProcessInfo.processInfo.arguments
        #else
            []
        #endif
    }

    /// The page server's port, shared by the engine's search template.
    static let pageServerPort: UInt16 = 53117

    /// Whether the app runs under the UI tests.
    static var isUITesting: Bool {
        launchArguments.contains("-uiTesting")
    }

    /// Whether this run starts from a clean slate; only the first launch of a flow passes it.
    static var resetsStore: Bool {
        launchArguments.contains("-uiTestingResetStore")
    }

    /// Whether the run skips the first-launch flow (Welcome and the engine picker).
    static var skipsOnboarding: Bool {
        launchArguments.contains("-uiTestingSkipOnboarding")
    }

    /// A screen the UI tests open directly while no flow reaches it: the archive, the
    /// bookmarks, Settings, the mods, or one of the Skim screens, through
    /// `-uiTestingSurface=<name>`.
    enum Surface: String {
        case archive
        case bookmarks
        case settings
        case mods
        case skimWorking
        case skimPage
        case skimFailed
    }

    /// The screen the UI tests asked for, if any.
    static var surface: Surface? {
        let prefix = "-uiTestingSurface="
        for argument in launchArguments where argument.hasPrefix(prefix) {
            return Surface(rawValue: String(argument.dropFirst(prefix.count)))
        }
        return nil
    }

    /// A link the search sheet finds on the pasteboard (`-uiTestingPasteboard=<url>`), so
    /// the tests never depend on the system's paste prompt.
    static var pasteboardLink: String? {
        let prefix = "-uiTestingPasteboard="
        for argument in launchArguments where argument.hasPrefix(prefix) {
            return String(argument.dropFirst(prefix.count))
        }
        return nil
    }

    /// Whether the seeded lists stay empty, for the empty states.
    static var listsEmpty: Bool {
        launchArguments.contains("-uiTestingListState=empty")
    }

    /// Whether this run starts with mods installed, for the installed screens.
    static var seedsMods: Bool {
        launchArguments.contains("-uiTestingModsInstalled")
    }

    /// Whether the UI tests force Skim on, with the fixture page behind it.
    static var skimFaked: Bool {
        launchArguments.contains("-uiTestingSkim")
    }

    /// How many photos the seeded Skim page carries (`-uiTestingSkimState=`):
    /// photos3, photo1, none.
    static var skimPhotoCount: Int {
        let prefix = "-uiTestingSkimState="
        for argument in launchArguments where argument.hasPrefix(prefix) {
            switch String(argument.dropFirst(prefix.count)) {
            case "photo1": return 1
            case "none": return 0
            default: return 3
            }
        }
        return 3
    }

    /// Whether the landed install's check holds past its beat, so the UI test's shot can
    /// catch it whatever the runner's latency; the released app clears it on time.
    static var holdsInstallCheck: Bool {
        launchArguments.contains("-uiTestingHoldInstallCheck")
    }

    /// Whether the UI tests force Reduce Motion on (`-uiTestingReduceMotion`), injected
    /// where `accessibilityReduceMotion` is read; nil outside the UI tests.
    static var reduceMotionOverride: Bool? {
        guard isUITesting else { return nil }
        return launchArguments.contains("-uiTestingReduceMotion")
    }

    /// Whether the launch intro's phases hold past their beats, so the UI tests' shots
    /// can catch each one whatever the runner's latency; the released app plays them
    /// on time.
    static var holdsLaunchIntro: Bool {
        launchArguments.contains("-uiTestingHoldIntro")
    }

    /// The appearance the tests ask for by launch argument (`-AppleInterfaceStyle Dark`),
    /// applied by the app itself so every run lands in the scheme it asked for. Nil when
    /// the tests set no preference, and always nil outside the UI tests.
    static var colorScheme: ColorScheme? {
        guard isUITesting,
            let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
        else { return nil }
        return style.lowercased() == "dark" ? .dark : .light
    }

    /// A scripted run of steps after launch, for reproducing a flow from the command line
    /// without the UI test runner: `-uiTestingScript "open:URL;wait:MS;tabs"`. Only under
    /// the UI tests.
    static var script: [String] {
        let arguments = launchArguments
        guard isUITesting, let flag = arguments.firstIndex(of: "-uiTestingScript"),
            arguments.indices.contains(flag + 1)
        else { return [] }
        return arguments[flag + 1].split(separator: ";").map(String.init)
    }

    /// Plays the script against the model: `open:` submits an address as from the launch
    /// sheet, `wait:` pauses, `tabs` shows the tabs screen, `mods` the mods screen.
    @MainActor
    static func play(_ steps: [String], on model: AppModel) async {
        for step in steps {
            if step.hasPrefix("open:"), let url = URL(string: String(step.dropFirst(5))) {
                SnapshotLog.event("script open \(url.absoluteString)")
                model.openFromLaunch(url)
            } else if step.hasPrefix("wait:"), let ms = Int(step.dropFirst(5)) {
                try? await Task.sleep(for: .milliseconds(ms))
            } else if step == "tabs" {
                SnapshotLog.event("script tabs")
                model.showTabs()
            } else if step == "mods" {
                SnapshotLog.event("script mods")
                model.showMods()
            } else if step.hasPrefix("card:"), let index = Int(step.dropFirst(5)),
                model.store.tabs.indices.contains(index)
            {
                SnapshotLog.event("script card \(index)")
                model.openTab(model.store.tabs[index].id)
            }
        }
    }

    /// The model the app runs with: the live one, or the UI tests' own.
    @MainActor
    static func makeModel() -> AppModel {
        isUITesting ? AppModel.forUITesting(resetting: resetsStore) : AppModel.live()
    }

    /// Seeds the chosen list and opens its screen, once the saved state has landed:
    /// seeding before the loads would let a half-written index file overwrite it.
    @MainActor
    static func applySurfaceOverride(to model: AppModel) {
        switch surface {
        case .archive:
            AppModel.seedLists(on: model, empty: listsEmpty)
            model.showArchive()
        case .bookmarks:
            AppModel.seedLists(on: model, empty: listsEmpty)
            model.showBookmarks()
        case .settings:
            model.showSettings()
        case .mods:
            model.showMods()
        case .skimWorking:
            model.showSkimRun(seededSkimRun(on: model, state: seededWorking))
        case .skimPage:
            model.showSkimRun(
                seededSkimRun(on: model, state: .finished(SkimFixture.page(photoCount: skimPhotoCount))))
        case .skimFailed:
            model.showSkimRun(
                seededSkimRun(
                    on: model,
                    state: .failed(SkimFailure(line: SkimFailureLines.tooFew(read: 1, attempted: 3)))))
        case nil: break
        }
    }

    /// The seeded working state: two of three pages read.
    @MainActor
    private static var seededWorking: SkimRunState {
        .working(
            SkimProgress(plannedHosts: SkimFixture.hosts, readCount: 2, plannedCount: 3))
    }

    /// A run landed on a fixed state, with nothing running behind it.
    @MainActor
    private static func seededSkimRun(on model: AppModel, state: SkimRunState) -> SkimRun {
        let run = SkimRun(
            query: SkimFixture.query, engine: model.engine,
            dependencies: model.skimDependencies)
        run.land(state)
        return run
    }
}

extension AppModel {

    /// The app as the UI tests drive it: a scratch store, a search engine pointed at the
    /// app's own local page server, fixed suggestion rows, and mods that never reach past
    /// the loopback interface — the directory comes from the bundled fixture, already
    /// fresh. The engine and the onboarding flag persist across a flow's launches, so
    /// `-uiTestingResetStore` clears them too. Blocking reads a fixed tiny rule list,
    /// except for the mods runs, whose installs compile into a real store.
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
        let modStore = ModStore(io: InMemoryModStoreIO(), listSink: nil)
        if UITestEnvironment.seedsMods {
            seedMods(into: modStore)
        }
        let blockerStore: any RuleSetProviding =
            UITestEnvironment.seedsMods
            ? FilterListStore(
                lists: [],
                directory: scratch.appending(component: "lists", directoryHint: .isDirectory))
            : UITestRuleSets()
        let blockingDefaults =
            UserDefaults(suiteName: "uitest-blocking-\(UUID().uuidString)") ?? .standard
        return AppModel(
            store: TabStore(persistence: FileSystemTabPersistence(directory: scratch)),
            preferences: preferences,
            blocker: ContentBlocker(store: blockerStore, defaults: blockingDefaults),
            bookmarks: BookmarkStore(
                persistence: FileSystemBookmarkPersistence(directory: scratch)),
            history: HistoryStore(persistence: FileSystemHistoryPersistence(directory: scratch)),
            suggestions: StubSuggestionProvider(
                rowsByPrefix: ["magpie test", "magpie test page", "magpie test search"]),
            recents: RecentSearches(),
            modStore: modStore,
            modDirectory: fixtureDirectory(),
            skimAvailable: UITestEnvironment.skimFaked)
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

    /// The seeded archive and bookmarks, fixed content with no network, once the saved
    /// state has loaded.
    fileprivate static func seedLists(on model: AppModel, empty: Bool) {
        guard !empty, let surface = UITestEnvironment.surface else { return }
        switch surface {
        case .archive: seedArchive(in: model.store, now: .now)
        case .bookmarks: seedBookmarks(in: model.bookmarks, now: .now)
        case .settings, .mods, .skimWorking, .skimPage, .skimFailed: break
        }
    }

    /// An address for the seeds, which are all well formed.
    private static func url(_ address: String) -> URL {
        URL(string: address) ?? URL(fileURLWithPath: "/")
    }

    /// Archived tabs across the day bands, over one open tab.
    private static func seedArchive(in store: TabStore, now: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        func day(_ offset: Int, hour: Int, minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func add(_ url: String, _ title: String, at date: Date) {
            store.newTab(url: URL(string: url), title: title, now: date)
        }

        // Yesterday.
        add(
            "https://seriouseats.com/how-to-season-carbon-steel-pan",
            "How to season a carbon steel pan", at: day(-1, hour: 21, minute: 14))
        add("https://git-scm.com/docs/rebase", "rebase vs merge · git docs", at: day(-1, hour: 16, minute: 2))
        add("https://en.wikipedia.org/wiki/Eurasian_magpie", "Eurasian magpie", at: day(-1, hour: 11, minute: 40))
        add(
            "https://reddit.com/r/eink/comments/night-reading",
            "Best e-reader for night reading?", at: day(-1, hour: 10, minute: 5))
        add(
            "https://debuyer.com/caring-for-mineral-b-pan",
            "Caring for your Mineral B pan", at: day(-1, hour: 9, minute: 51))

        // Earlier this week, when the calendar still holds it.
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let earlier = [
            ("https://bonappetit.com/resting-a-steak", "Resting a steak", day(-2, hour: 19, minute: 5)),
            (
                "https://mobileread.com/night-mode-for-eink", "Night mode for e-ink readers",
                day(-3, hour: 8, minute: 40)
            ),
        ]
        for (address, title, date) in earlier
        where calendar.startOfDay(for: date) >= weekStart {
            add(address, title, at: date)
        }

        // Last month.
        add(
            "https://knifesteelnerds.com/knife-steel-explained",
            "Knife steel, explained", at: day(-32, hour: 15, minute: 30))
        add("https://transit.example/route-14", "Route 14 timetable", at: day(-33, hour: 12, minute: 0))

        // The open tab the archive sits over, which the sweep never takes.
        add("https://quietweb.org/the-web-read-slowly", "The web, read slowly", at: now)
        store.archiveStale(now: now, after: 0)
    }

    /// The board's folders and a mix of saved pages, newest first in the list.
    private static func seedBookmarks(in store: BookmarkStore, now: Date) {
        let kitchen = store.newFolder(name: "Kitchen", tint: .orange)
        let reading = store.newFolder(name: "Reading", tint: .blue)
        let work = store.newFolder(name: "Work", tint: .sage)

        store.add(
            url: url("https://quietweb.org/the-web-read-slowly"),
            title: "The web, read slowly", folder: reading.id, now: now - 3_600)
        store.add(
            url: url("https://magpie.test/skim/seasoning-carbon-steel"),
            title: "Seasoning carbon steel", folder: kitchen.id,
            kind: .skim(sourceHosts: ["seriouseats.com", "debuyer.com", "reddit.com"]),
            now: now - 2 * 3_600)
        store.add(
            url: url("https://seriouseats.com/pan-sauce-any-night"),
            title: "Pan sauce, any night", folder: kitchen.id, now: now - 86_400)
        store.add(
            url: url("https://git-scm.com/book/en/v2/chapter-3"),
            title: "Pro Git, chapter 3", folder: work.id, now: now - 2 * 86_400)
        store.add(
            url: url("https://mobileread.com/night-mode-for-eink"),
            title: "Night mode for e-ink readers", folder: reading.id, now: now - 4 * 86_400)
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

    func setUserLists(_ lists: [FilterList]) async {}
}
