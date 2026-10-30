import Foundation
import SwiftUI

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

    /// The appearance the tests ask for by launch argument (`-AppleInterfaceStyle Dark`),
    /// applied by the app itself so every run lands in the scheme it asked for. Nil when
    /// the tests set no preference, and always nil outside the UI tests.
    static var colorScheme: ColorScheme? {
        guard isUITesting,
            let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
        else { return nil }
        return style.lowercased() == "dark" ? .dark : .light
    }

    /// The model the app runs with: the live one, or the UI tests' own.
    @MainActor
    static func makeModel() -> AppModel {
        isUITesting ? AppModel.forUITesting(resetting: resetsStore) : AppModel.live()
    }
}

extension AppModel {

    /// The app as the UI tests drive it: a scratch store, a search engine pointed at the
    /// app's own local page server, and fixed suggestion rows.
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
        return AppModel(
            store: TabStore(persistence: FileSystemTabPersistence(directory: scratch)),
            engine: engine,
            suggestions: StubSuggestionProvider(
                rowsByPrefix: ["magpie test", "magpie test page", "magpie test search"]),
            recents: RecentSearches())
    }
}
