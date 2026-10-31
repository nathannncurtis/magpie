import Foundation
import Testing

@testable import Magpie

/// The day bands at their edges: the week's turn, midnight, the clock changes, the year.
@Suite("Archive day grouping, edges")
struct ArchiveGroupingEdgeTests {

    /// A Monday-first Gregorian calendar in a fixed zone, so day boundaries are exact.
    private func calendar(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.firstWeekday = 2
        return calendar
    }

    private let zone = TimeZone(identifier: "America/New_York")!

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0,
        _ second: Int = 0, calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        )!
    }

    private func tab(at date: Date) -> Tab {
        Tab(url: URL(string: "https://a.example"), title: "", lastActive: date)
    }

    @Test("on the week's first day, yesterday is still Yesterday and the day before is a month")
    func mondayMorning() {
        let calendar = self.calendar(in: zone)
        // Monday 2026-10-26.
        let now = date(2026, 10, 26, 9, calendar: calendar)
        let tabs = [
            tab(at: date(2026, 10, 25, 18, calendar: calendar)),
            tab(at: date(2026, 10, 24, 18, calendar: calendar)),
        ]

        let groups = ArchiveGrouping.groups(of: tabs, now: now, calendar: calendar)

        #expect(groups.map(\.title) == ["Yesterday", "October"])
    }

    @Test("midnight to the second: the first instant of today is Today")
    func midnightExactly() {
        let calendar = self.calendar(in: zone)
        let now = date(2026, 10, 28, 15, calendar: calendar)
        let tabs = [
            tab(at: date(2026, 10, 28, 0, 0, 0, calendar: calendar)),
            tab(at: date(2026, 10, 27, 23, 59, 59, calendar: calendar)),
        ]

        let groups = ArchiveGrouping.groups(of: tabs, now: now, calendar: calendar)

        #expect(groups.map(\.title) == ["Today", "Yesterday"])
        #expect(groups.map(\.tabs.count) == [1, 1])
    }

    @Test("the day the clocks go back is one whole Yesterday, all 25 hours of it")
    func clocksGoBack() {
        let calendar = self.calendar(in: zone)
        // US clocks fall back on Sunday 2026-11-01; Monday the 2nd starts a new week.
        let now = date(2026, 11, 2, 9, calendar: calendar)
        let tabs = [
            tab(at: date(2026, 11, 2, 0, 10, calendar: calendar)),
            tab(at: date(2026, 11, 1, 23, 30, calendar: calendar)),
            tab(at: date(2026, 11, 1, 0, 30, calendar: calendar)),
            tab(at: date(2026, 10, 31, 23, 30, calendar: calendar)),
        ]

        let groups = ArchiveGrouping.groups(of: tabs, now: now, calendar: calendar)

        #expect(groups.map(\.title) == ["Today", "Yesterday", "October"])
        #expect(groups.map(\.tabs.count) == [1, 2, 1])
    }

    @Test("the day the clocks go forward is one whole Yesterday, all 23 hours of it")
    func clocksGoForward() {
        let calendar = self.calendar(in: zone)
        // US clocks spring forward on Sunday 2026-03-08.
        let now = date(2026, 3, 9, 9, calendar: calendar)
        let tabs = [
            tab(at: date(2026, 3, 8, 23, 30, calendar: calendar)),
            tab(at: date(2026, 3, 8, 3, 30, calendar: calendar)),
            tab(at: date(2026, 3, 8, 0, 30, calendar: calendar)),
        ]

        let groups = ArchiveGrouping.groups(of: tabs, now: now, calendar: calendar)

        #expect(groups.map(\.title) == ["Yesterday"])
        #expect(groups[0].tabs.count == 3)
    }

    @Test("a week that straddles the new year keeps last year's days in Earlier this week")
    func weekAcrossTheYear() {
        let calendar = self.calendar(in: zone)
        // Friday 2027-01-01; the week runs from Monday 2026-12-28.
        let now = date(2027, 1, 1, 12, calendar: calendar)
        let tabs = [
            tab(at: date(2026, 12, 31, 20, calendar: calendar)),
            tab(at: date(2026, 12, 29, 20, calendar: calendar)),
            tab(at: date(2026, 12, 27, 20, calendar: calendar)),
            tab(at: date(2026, 11, 15, 20, calendar: calendar)),
        ]

        let groups = ArchiveGrouping.groups(of: tabs, now: now, calendar: calendar)

        #expect(groups.map(\.title) == ["Yesterday", "Earlier this week", "December 2026", "November 2026"])
    }

    @Test("a tab read after now, as when the clock is set back, still reads as Today")
    func readAfterNow() {
        let calendar = self.calendar(in: zone)
        let now = date(2026, 10, 28, 9, calendar: calendar)
        let tabs = [
            tab(at: date(2026, 10, 28, 18, calendar: calendar)),
            tab(at: date(2026, 10, 30, 18, calendar: calendar)),
        ]

        let groups = ArchiveGrouping.groups(of: tabs, now: now, calendar: calendar)

        #expect(groups.map(\.title) == ["Today"])
        #expect(groups[0].tabs.count == 2)
    }

    @Test("a calendar with Sunday first moves the week's turn")
    func sundayFirstWeek() {
        var calendar = self.calendar(in: zone)
        calendar.firstWeekday = 1
        // Wednesday 2026-10-28; a Sunday-first week runs from the 25th.
        let now = date(2026, 10, 28, 12, calendar: calendar)
        let tabs = [
            tab(at: date(2026, 10, 25, 12, calendar: calendar)),
            tab(at: date(2026, 10, 24, 12, calendar: calendar)),
        ]

        let groups = ArchiveGrouping.groups(of: tabs, now: now, calendar: calendar)

        #expect(groups.map(\.title) == ["Earlier this week", "October"])
    }
}
