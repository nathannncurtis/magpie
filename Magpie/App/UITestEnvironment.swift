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

    /// A screen the UI tests open directly while no flow reaches it: the archive or the
    /// bookmarks, through `-uiTestingSurface=<name>`.
    enum Surface: String {
        case archive
        case bookmarks
    }

    /// The screen the UI tests asked for, if any.
    static var surface: Surface? {
        let prefix = "-uiTestingSurface="
        for argument in ProcessInfo.processInfo.arguments where argument.hasPrefix(prefix) {
            return Surface(rawValue: String(argument.dropFirst(prefix.count)))
        }
        return nil
    }

    /// Whether the seeded lists stay empty, for the empty states.
    static var listsEmpty: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestingListState=empty")
    }

    /// The model the app runs with: the live one, or the UI tests' own.
    @MainActor
    static func makeModel() -> AppModel {
        isUITesting ? AppModel.forUITesting(resetting: resetsStore) : AppModel.live()
    }

    /// Opens the UI tests' chosen screen once the saved state has landed.
    @MainActor
    static func applySurfaceOverride(to model: AppModel) {
        switch surface {
        case .archive: model.showArchive()
        case .bookmarks: model.showBookmarks()
        case nil: break
        }
    }
}

extension AppModel {

    /// The app as the UI tests drive it: a scratch store, a search engine pointed at the
    /// app's own local page server, fixed suggestion rows, and the seeded lists.
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
        let store = TabStore(persistence: FileSystemTabPersistence(directory: scratch))
        let bookmarks = BookmarkStore(
            persistence: FileSystemBookmarkPersistence(directory: scratch))
        let model = AppModel(
            store: store,
            bookmarks: bookmarks,
            engine: engine,
            suggestions: StubSuggestionProvider(
                rowsByPrefix: ["magpie test", "magpie test page", "magpie test search"]),
            recents: RecentSearches())
        seedLists(on: model, empty: UITestEnvironment.listsEmpty)
        return model
    }

    /// The seeded archive and bookmarks, fixed content with no network.
    private static func seedLists(on model: AppModel, empty: Bool) {
        guard !empty, let surface = UITestEnvironment.surface else { return }
        switch surface {
        case .archive: seedArchive(in: model.store, now: .now)
        case .bookmarks: seedBookmarks(in: model.bookmarks, now: .now)
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
