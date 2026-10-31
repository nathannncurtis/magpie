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

    /// A scripted run of steps after launch, for reproducing a flow from the command line
    /// without the UI test runner: `-uiTestingScript "open:URL;wait:MS;tabs"`. Only under
    /// the UI tests.
    static var script: [String] {
        let arguments = ProcessInfo.processInfo.arguments
        guard isUITesting, let flag = arguments.firstIndex(of: "-uiTestingScript"),
            arguments.indices.contains(flag + 1)
        else { return [] }
        return arguments[flag + 1].split(separator: ";").map(String.init)
    }

    /// Plays the script against the model: `open:` submits an address as from the launch
    /// sheet, `wait:` pauses, `tabs` shows the tabs screen.
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
