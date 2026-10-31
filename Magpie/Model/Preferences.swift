import Foundation
import Observation

/// The user's choices, backed by UserDefaults: the search engine, the two search rows,
/// the archive interval, and whether the first-launch flow has run (04 · 03, 04 · 11).
///
/// Every value loads once in the init and writes through on change, so the defaults
/// instance is injectable and tests stay isolated from the app's own store.
@MainActor
@Observable
final class Preferences {

    /// The archive-after steps Settings offers. On by default; Off is not among them.
    static let archiveIntervalSteps: [TimeInterval] = [
        12 * 60 * 60,
        24 * 60 * 60,
        3 * 24 * 60 * 60,
        7 * 24 * 60 * 60,
        14 * 24 * 60 * 60,
        30 * 24 * 60 * 60,
    ]

    /// The step a fresh install archives after: one day.
    static let defaultArchiveInterval = archiveIntervalSteps[1]

    private enum Key {
        static let engineID = "searchEngineID"
        static let engineName = "searchEngineName"
        static let engineTemplate = "searchEngineTemplate"
        static let suggestionsEnabled = "suggestionsEnabled"
        static let skimEnabled = "skimEnabled"
        static let archiveInterval = "archiveInterval"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    /// The engine searches run on.
    var searchEngine: SearchEngine {
        didSet {
            guard oldValue != searchEngine else { return }
            defaults.set(searchEngine.id, forKey: Key.engineID)
            defaults.set(searchEngine.displayName, forKey: Key.engineName)
            defaults.set(searchEngine.searchTemplate, forKey: Key.engineTemplate)
        }
    }

    /// Whether the search sheet asks the engine for suggestion rows.
    var suggestionsEnabled: Bool {
        didSet {
            guard oldValue != suggestionsEnabled else { return }
            defaults.set(suggestionsEnabled, forKey: Key.suggestionsEnabled)
        }
    }

    /// Whether the Skim pill offers to read a search's pages.
    var skimEnabled: Bool {
        didSet {
            guard oldValue != skimEnabled else { return }
            defaults.set(skimEnabled, forKey: Key.skimEnabled)
        }
    }

    /// How long a tab sits untouched before it archives.
    var archiveInterval: TimeInterval {
        didSet {
            let snapped = Self.nearestStep(to: archiveInterval)
            guard oldValue != snapped else { return }
            archiveInterval = snapped
            defaults.set(snapped, forKey: Key.archiveInterval)
        }
    }

    /// Whether the Welcome and engine-picker screens have run.
    var hasCompletedOnboarding: Bool {
        didSet {
            guard oldValue != hasCompletedOnboarding else { return }
            defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(
            defaults: [
                Key.suggestionsEnabled: true,
                Key.skimEnabled: true,
                Key.archiveInterval: Self.defaultArchiveInterval,
                Key.hasCompletedOnboarding: false,
            ])

        if let engine = Self.engine(
            id: defaults.string(forKey: Key.engineID),
            name: defaults.string(forKey: Key.engineName),
            template: defaults.string(forKey: Key.engineTemplate))
        {
            searchEngine = engine
        } else {
            searchEngine = .default
        }
        suggestionsEnabled = defaults.bool(forKey: Key.suggestionsEnabled)
        skimEnabled = defaults.bool(forKey: Key.skimEnabled)
        archiveInterval = Self.nearestStep(to: defaults.double(forKey: Key.archiveInterval))
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
    }

    /// The step nearest any interval, so a stored value outside the steps still reads as one.
    static func nearestStep(to interval: TimeInterval) -> TimeInterval {
        archiveIntervalSteps.min {
            abs($0 - interval) < abs($1 - interval)
        } ?? defaultArchiveInterval
    }

    /// The engine a stored id, name and template resolve to: a built-in by id, or the
    /// user-supplied one by its `%s` URL. Nil when neither parses.
    private static func engine(id: String?, name: String?, template: String?) -> SearchEngine? {
        if let id, let builtin = SearchEngine.builtins.first(where: { $0.id == id }) {
            return builtin
        }
        guard let template, let other = SearchEngine.other(template: template) else { return nil }
        let storedName = name ?? ""
        return SearchEngine(
            id: id ?? other.id,
            displayName: storedName.isEmpty ? other.displayName : storedName,
            searchTemplate: other.searchTemplate,
            suggestTemplate: other.suggestTemplate,
            suggestFormat: other.suggestFormat)
    }

    /// "1 day", "12 hours": the Settings row's value and the picker's rows.
    static func archiveIntervalLabel(_ interval: TimeInterval) -> String {
        let hours = interval / 3600
        if hours < 24 {
            let value = Int(hours)
            return String(localized: "\(value) hours")
        }
        let days = Int(hours / 24)
        if days % 7 != 0 {
            return String(localized: "\(days) days")
        }
        let weeks = days / 7
        return String(localized: "\(weeks) weeks")
    }
}
