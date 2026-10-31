import Foundation

/// Groups archived tabs into the list's day bands: Today, Yesterday, Earlier this week,
/// then one band per month, newest first; a month outside the current year carries its
/// year ("October 2025"), one inside it doesn't ("October"). Rows are grouped and timed
/// by when the tab was last read, so the archive reads like a history of being there.
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
            if day >= startOfToday {
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
        if !today.isEmpty { groups.append(Group(title: title(.today, now: now, calendar: calendar), tabs: today)) }
        if !yesterday.isEmpty {
            groups.append(Group(title: title(.yesterday, now: now, calendar: calendar), tabs: yesterday))
        }
        if !earlierThisWeek.isEmpty {
            groups.append(Group(title: title(.earlierThisWeek, now: now, calendar: calendar), tabs: earlierThisWeek))
        }
        for month in byMonth.keys.sorted(by: >) {
            groups.append(Group(title: title(.month(month), now: now, calendar: calendar), tabs: byMonth[month] ?? []))
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
            return tab.lastActive.formatted(
                Date.FormatStyle(date: .omitted, time: .shortened).in(calendar))
        }
        if day >= startOfWeek {
            return tab.lastActive.formatted(Date.FormatStyle.dateTime.weekday(.abbreviated).in(calendar))
        }
        return tab.lastActive.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted).in(calendar))
    }

    private static func monthStart(of day: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: day)?.start ?? day
    }

    /// The band titles, in the copy's natural case; the list uppercases them. A month band
    /// names its year only when it isn't the current one, in the locale's own order.
    private static func title(_ band: Band, now: Date, calendar: Calendar) -> String {
        switch band {
        case .today: String(localized: "Today")
        case .yesterday: String(localized: "Yesterday")
        case .earlierThisWeek: String(localized: "Earlier this week")
        case .month(let start):
            if calendar.isDate(start, equalTo: now, toGranularity: .year) {
                start.formatted(Date.FormatStyle.dateTime.month(.wide).in(calendar))
            } else {
                start.formatted(Date.FormatStyle.dateTime.month(.wide).year().in(calendar))
            }
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

private extension Date.FormatStyle {
    /// The style read in the calendar's own zone: the bands are cut in that calendar, so
    /// the names they carry must come from it too, not from the device's.
    func `in`(_ calendar: Calendar) -> Self {
        var style = self
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return style
    }
}
