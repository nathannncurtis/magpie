import Foundation
import Testing

@testable import Magpie

@Suite("Archive day grouping")
struct ArchiveGroupingTests {

    /// A Monday-first Gregorian calendar in a fixed zone, so day boundaries are exact.
    private func calendar(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.firstWeekday = 2
        return calendar
    }

    private let zone = TimeZone(identifier: "America/New_York")!

    /// A date from local parts in the suite's zone.
    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute, second: 0)
        )!
    }

    private func tab(at date: Date, title: String = "") -> Tab {
        Tab(url: URL(string: "https://\(title.isEmpty ? "a" : title).example"), title: title, lastActive: date)
    }

    private func titles(_ groups: [ArchiveGrouping.Group]) -> [String] {
        groups.map(\.title)
    }

    // 2026-10-28 is a Wednesday; the week runs from Monday the 26th.

    @Test("rows fall into today, yesterday and the rest of the week")
    func dayBands() {
        let calendar = self.calendar(in: zone)
        let now = date(2026, 10, 28, 15, 0, calendar: calendar)
        let tabs = [
            tab(at: date(2026, 10, 28, 14, 0, calendar: calendar)),
            tab(at: date(2026, 10, 28, 0, 0, calendar: calendar)),
            tab(at: date(2026, 10, 27, 23, 59, calendar: calendar)),
            tab(at: date(2026, 10, 27, 0, 30, calendar: calendar)),
            tab(at: date(2026, 10, 26, 8, 0, calendar: calendar)),
        ]

        let groups = ArchiveGrouping.groups(of: tabs, now: now, calendar: calendar)

        #expect(titles(groups) == ["Today", "Yesterday", "Earlier this week"])
        #expect(groups[0].tabs.count == 2)
        #expect(groups[1].tabs.count == 2)
        #expect(groups[2].tabs.count == 1)
    }

    @Test("the week's first day is a month band, not earlier this week")
    func beforeThisWeekIsAMonth() {
        let calendar = self.calendar(in: zone)
        let now = date(2026, 10, 28, 15, 0, calendar: calendar)
        let sunday = tab(at: date(2026, 10, 25, 10, 0, calendar: calendar))
        let september = tab(at: date(2026, 9, 30, 10, 0, calendar: calendar))

        let groups = ArchiveGrouping.groups(of: [september, sunday], now: now, calendar: calendar)

        #expect(groups.count == 2)
        #expect(titles(groups)[0] == "October")
        #expect(titles(groups)[1] == "September")
    }

    @Test("month bands run newest first, and skip months with nothing in them")
    func monthOrder() {
        let calendar = self.calendar(in: zone)
        let now = date(2026, 10, 28, 15, 0, calendar: calendar)
        let tabs = [
            tab(at: date(2026, 8, 20, 10, 0, calendar: calendar)),
            tab(at: date(2026, 10, 5, 10, 0, calendar: calendar)),
            tab(at: date(2026, 5, 1, 10, 0, calendar: calendar)),
        ]

        let groups = ArchiveGrouping.groups(of: tabs, now: now, calendar: calendar)

        #expect(titles(groups) == ["October", "August", "May"])
    }

    @Test("rows inside a band run newest first")
    func rowsNewestFirst() {
        let calendar = self.calendar(in: zone)
        let now = date(2026, 10, 28, 15, 0, calendar: calendar)
        let tabs = [
            tab(at: date(2026, 10, 27, 9, 0, calendar: calendar), title: "morning"),
            tab(at: date(2026, 10, 27, 21, 0, calendar: calendar), title: "evening"),
            tab(at: date(2026, 10, 27, 15, 0, calendar: calendar), title: "afternoon"),
        ]

        let groups = ArchiveGrouping.groups(of: tabs, now: now, calendar: calendar)

        #expect(groups[0].tabs.map(\.title) == ["evening", "afternoon", "morning"])
    }

    @Test("empty bands are left out")
    func emptyBandsSkipped() {
        let calendar = self.calendar(in: zone)
        let now = date(2026, 10, 28, 15, 0, calendar: calendar)

        let groups = ArchiveGrouping.groups(of: [], now: now, calendar: calendar)

        #expect(groups.isEmpty)
    }

    @Test("the same instant falls on different days in different zones")
    func acrossZones() {
        let newYork = self.calendar(in: zone)
        let tokyo = self.calendar(in: TimeZone(identifier: "Asia/Tokyo")!)
        // 05:00 and 16:00 UTC on one day: a single day in New York, two in Tokyo.
        let tab = Tab(title: "Zone", lastActive: Date(timeIntervalSince1970: 1_793_163_600))
        let now = Date(timeIntervalSince1970: 1_793_203_200)

        let fromNewYork = ArchiveGrouping.groups(of: [tab], now: now, calendar: newYork)
        let fromTokyo = ArchiveGrouping.groups(of: [tab], now: now, calendar: tokyo)

        #expect(titles(fromNewYork) == ["Today"])
        #expect(titles(fromTokyo) == ["Yesterday"])
    }

    @Test("row times: a clock time, a weekday, then a date")
    func rowTimes() {
        let calendar = self.calendar(in: zone)
        let now = date(2026, 10, 28, 15, 0, calendar: calendar)

        let today = tab(at: date(2026, 10, 28, 9, 14, calendar: calendar))
        let yesterday = tab(at: date(2026, 10, 27, 21, 14, calendar: calendar))
        let thisWeek = tab(at: date(2026, 10, 26, 19, 5, calendar: calendar))
        let older = tab(at: date(2026, 9, 12, 10, 0, calendar: calendar))

        #expect(ArchiveGrouping.rowTime(of: today, now: now, calendar: calendar).contains(":"))
        #expect(ArchiveGrouping.rowTime(of: yesterday, now: now, calendar: calendar).contains(":"))
        // A weekday carries no digits or colons; a date carries the day's number.
        let weekday = ArchiveGrouping.rowTime(of: thisWeek, now: now, calendar: calendar)
        let weekdayCarriesADigit = weekday.contains { $0.isNumber }
        #expect(!weekday.contains(":"))
        #expect(!weekdayCarriesADigit)
        let dateText = ArchiveGrouping.rowTime(of: older, now: now, calendar: calendar)
        #expect(dateText.contains("12"))
    }
}
