import Foundation
import Observation
import WebKit

/// What content blocking needs of the filter list store: refreshing, and the compiled
/// rule lists per set. `FilterListStore` in the app; a fixed stub under the UI tests.
protocol RuleSetProviding: Sendable {
    /// Downloads lists that have never been downloaded or are stale.
    func refreshStale() async
    /// Downloads every list now, stale or not.
    func refreshNow() async
    /// The compiled rule lists for one set, in chunk order.
    func ruleLists(for set: FilterRuleSet) async -> [CompiledRuleList]
    /// When the newest successful refresh across the lists was.
    var overallLastUpdated: Date? { get async }
    /// Each list with when it last refreshed, for the Settings page.
    func listUpdates() async -> [FilterListUpdate]
    /// Replaces the lists mod installs added; a no-op for stores without them.
    func setUserLists(_ lists: [FilterList]) async
}

/// One filter list and when it last refreshed, for the Settings "Filter lists" page.
struct FilterListUpdate: Identifiable, Sendable, Equatable {
    let list: FilterList
    let updated: Date?

    var id: String { list.id }
}

/// Where a page's compiled rule lists land. The user content controller in the app; a
/// recorder in tests.
@MainActor protocol ContentRuleApplying: AnyObject {
    func apply(_ rules: [CompiledRuleList])
    func removeAllRules()
}

extension WKUserContentController: ContentRuleApplying {
    func apply(_ rules: [CompiledRuleList]) {
        for rule in rules {
            guard let ruleList = rule.contentRuleList else { continue }
            add(ruleList)
        }
    }

    func removeAllRules() {
        removeAllContentRuleLists()
    }
}

/// The two blocking toggles and their state, backed by the filter list store (04 · 02, 04 · 11).
/// Toggles default on, persist in UserDefaults, and re-apply the rule lists when they change.
@MainActor
@Observable
final class ContentBlocker {

    private static let adsKey = "blocksAdsAndTrackers"
    private static let cookiesKey = "blocksCookieBanners"

    var blocksAdsAndTrackers: Bool {
        didSet {
            guard oldValue != blocksAdsAndTrackers else { return }
            defaults.set(blocksAdsAndTrackers, forKey: Self.adsKey)
            reapply()
        }
    }

    var blocksCookieBanners: Bool {
        didSet {
            guard oldValue != blocksCookieBanners else { return }
            defaults.set(blocksCookieBanners, forKey: Self.cookiesKey)
            reapply()
        }
    }

    /// Whether the lists mod installs block too. On while any filter-list mod is enabled;
    /// the mod store owns the lists and hands them over through `setModLists`.
    private(set) var appliesModLists = false

    /// When the filter lists last updated, for the Settings "Filter lists" row.
    private(set) var lastUpdated: Date?

    private let store: any RuleSetProviding
    private let defaults: UserDefaults
    /// Every live page's controller. Weak, so a page that goes away drops itself out.
    private var controllers: [WeakController] = []

    init(store: any RuleSetProviding, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        defaults.register(defaults: [Self.adsKey: true, Self.cookiesKey: true])
        blocksAdsAndTrackers = defaults.bool(forKey: Self.adsKey)
        blocksCookieBanners = defaults.bool(forKey: Self.cookiesKey)
    }

    /// Refreshes the lists when stale, then updates the Settings row's timestamp and
    /// re-applies the lists, which may have been recompiled under new identifiers.
    func refresh() async {
        await store.refreshStale()
        lastUpdated = await store.overallLastUpdated
        await applyEnabledSets()
    }

    /// Takes the mod-installed lists and re-applies what pages carry, so the `.mods` set
    /// follows the enabled filter-list mods: on while any of them is enabled.
    func setModLists(_ lists: [FilterList]) async {
        appliesModLists = !lists.isEmpty
        await store.setUserLists(lists)
        await applyEnabledSets()
    }

    /// "Update now": downloads every list whatever their age, then re-applies.
    func updateNow() async {
        await store.refreshNow()
        lastUpdated = await store.overallLastUpdated
        await applyEnabledSets()
    }

    /// The lists and their times, for the Settings "Filter lists" page.
    func listUpdates() async -> [FilterListUpdate] {
        await store.listUpdates()
    }

    /// Starts blocking on a page's controller: applies exactly the enabled sets' rule
    /// lists, removing whatever was there. Call again whenever a toggle changes or the
    /// lists refresh; a change takes effect without reloading the page.
    func attach(_ controller: any ContentRuleApplying) async {
        controllers.append(WeakController(controller))
        await apply(to: controller)
    }

    /// Stops tracking a page's controller; its lists go away with the page.
    func detach(_ controller: AnyObject) {
        controllers.removeAll { $0.value == nil || $0.value === controller }
    }

    private func reapply() {
        guard !controllers.isEmpty else { return }
        Task { await applyEnabledSets() }
    }

    private func applyEnabledSets() async {
        for controller in liveControllers() {
            await apply(to: controller)
        }
    }

    private func apply(to controller: any ContentRuleApplying) async {
        var sets: [FilterRuleSet] = []
        if blocksAdsAndTrackers {
            sets.append(.adsAndTrackers)
        }
        if blocksCookieBanners {
            sets.append(.cookieBanners)
        }
        if appliesModLists {
            sets.append(.mods)
        }
        controller.removeAllRules()
        for set in sets {
            controller.apply(await store.ruleLists(for: set))
        }
    }

    private func liveControllers() -> [any ContentRuleApplying] {
        controllers.removeAll { $0.value == nil }
        return controllers.compactMap(\.value)
    }

    /// "Updated 2 h ago" style text for the Settings row.
    // COPY: review
    nonisolated static func updatedText(from date: Date?, now: Date, locale: Locale? = nil) -> String {
        guard let date else { return String(localized: "Not updated yet") }
        if now.timeIntervalSince(date) < 60 { return String(localized: "Updated just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        if let locale {
            formatter.locale = locale
        }
        var relative = formatter.localizedString(for: date, relativeTo: now)
        if relative.hasSuffix("ago") {
            relative.removeLast(3)
        }
        let ago = relative.trimmingCharacters(in: .whitespaces)
        return String(localized: "Updated \(ago) ago")
    }
}

/// A weak box, so gone pages leave the blocker on their own.
private final class WeakController {
    weak var value: (any ContentRuleApplying)?

    init(_ value: any ContentRuleApplying) {
        self.value = value
    }
}
