import Foundation

/// The rule sets content blocking compiles. Ads & trackers and cookie banners are the two
/// shipped toggles; mods is where mod-installed lists land (04 · 06).
enum FilterRuleSet: String, CaseIterable, Codable, Sendable {
    case adsAndTrackers
    case cookieBanners
    case mods
}

/// One filter list feeding one rule set.
struct FilterList: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let url: URL
    let ruleSet: FilterRuleSet

    /// The lists the app ships with. Downloaded on first run, auto-updated; nothing is bundled (07-assets).
    static let builtin: [FilterList] = [
        FilterList(
            id: "easylist",
            title: "EasyList",
            url: url("https://easylist.to/easylist/easylist.txt"),
            ruleSet: .adsAndTrackers
        ),
        FilterList(
            id: "easyprivacy",
            title: "EasyPrivacy",
            url: url("https://easylist.to/easylist/easyprivacy.txt"),
            ruleSet: .adsAndTrackers
        ),
        FilterList(
            id: "easylist-cookie",
            title: "Easylist Cookie List",
            url: url("https://secure.fanboy.co.nz/fanboy-cookiemonster.txt"),
            ruleSet: .cookieBanners
        ),
    ]

    /// A list a mod installed from a URL, feeding the mods set.
    static func userAdded(id: String, title: String, url: URL) -> FilterList {
        FilterList(id: id, title: title, url: url, ruleSet: .mods)
    }

    private static func url(_ raw: String) -> URL {
        guard let url = URL(string: raw) else {
            preconditionFailure("Built-in filter list URL is not a URL: \(raw)")
        }
        return url
    }
}
