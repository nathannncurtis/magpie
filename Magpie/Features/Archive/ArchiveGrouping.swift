import Foundation

/// Groups archived tabs into the list's day bands: Today, Yesterday, Earlier this week,
/// then one band per month, newest first. Rows are grouped and timed by when the tab was
/// last read, so the archive reads like a history of being there.
enum ArchiveGrouping {

    /// One band of the list, holding its rows.
    struct Group: Equatable {
        var title: String
        var tabs: [Tab]
    }

    /// The tabs grouped for the list: the special day bands first, then months newest
    /// first, with each band's rows newest first.
    static func groups(of tabs: [Tab], now: Date, calendar: Calendar) -> [Group] {
        let ordered = tabs.sorted { $0.lastActive > $1.lastActive }
        var today: [Tab] = []
        var yesterday: [Tab] = []
        var earlierThisWeek: [Tab] = []
        var byMonth: [Date: [Tab]] = [:]

        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday =
            calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday

        for tab in ordered {
            let day = calendar.startOfDay(for: tab.lastActive)
            if day == startOfToday {
                today.append(tab)
            } else if day == startOfYesterday {
                yesterday.append(tab)
            } else if day >= startOfWeek {
                earlierThisWeek.append(tab)
            } else {
                byMonth[monthStart(of: day, calendar: calendar), default: []].append(tab)
            }
        }

        var groups: [Group] = []
        if !today.isEmpty { groups.append(Group(title: title(.today), tabs: today)) }
        if !yesterday.isEmpty {
            groups.append(Group(title: title(.yesterday), tabs: yesterday))
        }
        if !earlierThisWeek.isEmpty {
            groups.append(Group(title: title(.earlierThisWeek), tabs: earlierThisWeek))
        }
        for month in byMonth.keys.sorted(by: >) {
            groups.append(Group(title: title(.month(month)), tabs: byMonth[month] ?? []))
        }
        return groups
    }

    /// The time a row carries: a time for the last two days, a weekday for the rest of
    /// this week, a date for anything older.
    static func rowTime(of tab: Tab, now: Date, calendar: Calendar) -> String {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday =
            calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
        let day = calendar.startOfDay(for: tab.lastActive)

        if day >= startOfYesterday {
            return tab.lastActive.formatted(date: .omitted, time: .shortened)
        }
        if day >= startOfWeek {
            return tab.lastActive.formatted(.dateTime.weekday(.abbreviated))
        }
        return tab.lastActive.formatted(date: .abbreviated, time: .omitted)
    }

    private static func monthStart(of day: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: day)?.start ?? day
    }

    /// The band titles, in the copy's natural case; the list uppercases them.
    private static func title(_ band: Band) -> String {
        switch band {
        case .today: String(localized: "Today")
        case .yesterday: String(localized: "Yesterday")
        case .earlierThisWeek: String(localized: "Earlier this week")
        case .month(let start):
            start.formatted(.dateTime.month(.wide))
        }
    }

    private enum Band {
        case today
        case yesterday
        case earlierThisWeek
        case month(Date)
    }
}

/// The archive search: titles and addresses, matched the way someone would type.
enum ArchiveSearch {

    /// Whether the tab matches the typed query. An empty query matches everything.
    static func matches(_ tab: Tab, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return [tab.title, tab.url?.absoluteString ?? "", tab.host ?? ""]
            .contains { $0.localizedStandardContains(trimmed) }
    }
}
