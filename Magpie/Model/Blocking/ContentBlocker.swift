import Foundation
import Observation
import WebKit

/// The two blocking toggles and their state, backed by the filter list store (04 · 02, 04 · 11).
/// Toggles default on, persist in UserDefaults, and re-apply the rule lists when they change.
@MainActor
@Observable
final class ContentBlocker {

    private static let adsKey = "blocksAdsAndTrackers"
    private static let cookiesKey = "blocksCookieBanners"
    private static let modsKey = "appliesModLists"

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
    /// the mod store owns the lists themselves.
    var appliesModLists: Bool {
        didSet {
            guard oldValue != appliesModLists else { return }
            defaults.set(appliesModLists, forKey: Self.modsKey)
            reapply()
        }
    }

    /// When the filter lists last updated, for the Settings "Filter lists" row.
    private(set) var lastUpdated: Date?

    private let store: FilterListStore
    private let defaults: UserDefaults
    private weak var contentController: WKUserContentController?

    init(store: FilterListStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        defaults.register(defaults: [Self.adsKey: true, Self.cookiesKey: true, Self.modsKey: true])
        blocksAdsAndTrackers = defaults.bool(forKey: Self.adsKey)
        blocksCookieBanners = defaults.bool(forKey: Self.cookiesKey)
        appliesModLists = defaults.bool(forKey: Self.modsKey)
    }

    /// Refreshes the lists when stale, then updates the Settings row's timestamp.
    func refresh() async {
        await store.refreshIfNeeded()
        lastUpdated = await store.overallLastUpdated
    }

    /// Takes the mod-installed lists and re-applies what pages carry, so the `.mods` set
    /// follows the enabled filter-list mods.
    func setModLists(_ lists: [FilterList]) async {
        await store.setUserLists(lists)
        await applyEnabledSets()
    }

    /// Adds exactly the rule lists of the enabled sets to the controller, removing whatever was
    /// there. Call again whenever a toggle changes or the lists refresh.
    func apply(to controller: WKUserContentController) async {
        contentController = controller
        await applyEnabledSets()
    }

    private func reapply() {
        guard contentController != nil else { return }
        Task { await applyEnabledSets() }
    }

    private func applyEnabledSets() async {
        guard let controller = contentController else { return }
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
        controller.removeAllContentRuleLists()
        for set in sets {
            for compiled in await store.ruleLists(for: set) {
                if let ruleList = compiled.contentRuleList {
                    controller.add(ruleList)
                }
            }
        }
    }

    /// "Updated 2 h ago" style text for the Settings row.
    // COPY: review
    nonisolated static func updatedText(from date: Date?, now: Date, locale: Locale? = nil) -> String {
        guard let date else { return "Not updated yet" }
        if now.timeIntervalSince(date) < 60 { return "Updated just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        if let locale {
            formatter.locale = locale
        }
        var relative = formatter.localizedString(for: date, relativeTo: now)
        if relative.hasSuffix("ago") {
            relative.removeLast(3)
        }
        return "Updated \(relative.trimmingCharacters(in: .whitespaces)) ago"
    }
}
