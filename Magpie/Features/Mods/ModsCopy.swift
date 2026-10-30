import Foundation

/// The mods screens' strings, gathered in one place.
enum ModsCopy {

    static var title: String { String(localized: "Mods") }
    static var done: String { String(localized: "Done") }
    static var directory: String { String(localized: "Directory") }

    /// "Installed · 3".
    static func installedSegment(_ count: Int) -> String {
        String(localized: "Installed · \(count)")
    }

    static var popularThisWeek: String { String(localized: "Popular this week") }
    static var get: String { String(localized: "Get") }
    static var installed: String { String(localized: "Installed") }
    static var installFromURL: String { String(localized: "Install from URL") }
    static var notReviewed: String { String(localized: "Not reviewed") }

    /// The line under the installed card.
    static var swipeHint: String {
        String(localized: "Swipe a mod left to remove it. Off keeps it, but it stops running.")
    }

    // The installed list's empty state.
    // COPY: review — 06 has this line to write.
    static var emptyTitle: String { String(localized: "Nothing installed") }
    static var emptyLine: String {
        String(localized: "Mods from the directory or a link show up here.")
    }

    // The install sheet.
    static var cancel: String { String(localized: "Cancel") }
    static var install: String { String(localized: "Install") }
    static var runsOn: String { String(localized: "Runs on") }
    static var can: String { String(localized: "Can") }
    static var pagesPermission: String { String(localized: "Read and change pages on that site") }

    /// The extra grants line, when a script asks for what the shim cannot honour.
    // COPY: review — 06 has this line to write.
    static var alsoGrantsLabel: String { String(localized: "Also grants") }
    static func alsoGrantsValue(_ grants: String) -> String {
        String(localized: "\(grants) — not supported yet")
    }

    /// Where a script runs when only @include rules name it.
    // COPY: review — 06 has this line to write.
    static func sitesItNames(_ patterns: String) -> String {
        String(localized: "the sites it names: \(patterns)")
    }

    /// "Script · by l.marsh · v1.2", the install sheet's preview line.
    static func scriptBy(_ author: String, version: String) -> String {
        String(localized: "Script · by \(author) · v\(version)")
    }

    static func filterListBy(_ version: String?) -> String {
        version.map { String(localized: "Filter list · v\($0)") } ?? String(localized: "Filter list")
    }

    /// "script · s.okafor", with "· from a link" on a link install.
    static func authorLine(kind: ModKind, author: String?, fromLink: Bool) -> String {
        var line: String
        switch (kind, author) {
        case (.userscript, let author?):
            line = String(localized: "script · \(author)")
        case (.userscript, nil):
            line = String(localized: "script")
        case (.filterList, let author?):
            line = String(localized: "filter list · \(author)")
        case (.filterList, nil):
            line = String(localized: "filter list")
        }
        if fromLink {
            line += " · " + String(localized: "from a link")
        }
        return line
    }

    // The install sheet's warning.
    static var notInDirectory: String { String(localized: "Not in the directory.") }
    static var warningLine: String {
        String(localized: "Nobody has reviewed this mod. Only install it if you trust where it came from.")
    }

    // The install sheet's failures.
    static var webPageTitle: String { String(localized: "That's a web page, not a mod.") }
    static var webPageLine: String {
        String(localized: "Magpie needs a link to a userscript (ending in .user.js) or a filter list.")
    }

    // COPY: review — 06 has these lines to write.
    static var unreachableTitle: String { String(localized: "No answer from that link.") }
    static var unreachableLine: String {
        String(localized: "Check the address, or try again in a moment.")
    }

    static var noRunRulesTitle: String { String(localized: "That script runs nowhere.") }
    static var noRunRulesLine: String {
        String(localized: "It names no site in @match or @include, so Magpie has nowhere to run it.")
    }

    static var remove: String { String(localized: "Remove") }
    static var on: String { String(localized: "On") }
    static var off: String { String(localized: "Off") }
}
