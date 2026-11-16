import Foundation
import XCTest
@testable import TimeTug

// Ported from timetug-shared 1.x `WidgetTimelineTests` (Swift Testing) onto the app-owned types.
final class WidgetTimelineTests: XCTestCase {
    private let now = WidgetTimelineTests.date("2026-09-18T12:00:00Z")

    private static func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
    private func date(_ iso: String) -> Date { Self.date(iso) }

    private let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func event(_ id: String, _ start: String, minutes: Int = 30, allDay: Bool = false) -> WidgetEvent {
        let s = date(start)
        return WidgetEvent(id: id, title: id, start: s, end: s.addingTimeInterval(TimeInterval(minutes * 60)), isAllDay: allDay)
    }

    private func snapshot(_ events: [WidgetEvent]) -> WidgetSnapshot { WidgetSnapshot(generatedAt: now, events: events) }

    func testChangeDatesIncludeFutureStartsEndsAndMidnights() {
        let s = snapshot([event("a", "2026-09-18T13:00:00Z"), event("b", "2026-09-18T11:00:00Z")])
        let dates = WidgetTimeline.changeDates(snapshot: s, now: now, calendar: utcCalendar, limit: 20)
        XCTAssertEqual(dates.first, date("2026-09-18T13:00:00Z"))
        XCTAssertTrue(dates.contains(date("2026-09-18T13:30:00Z")))
        XCTAssertTrue(dates.contains(date("2026-09-19T00:00:00Z")))
        XCTAssertFalse(dates.contains(date("2026-09-18T11:00:00Z")))
        XCTAssertFalse(dates.contains(date("2026-09-18T11:30:00Z")))
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(Set(dates).count, dates.count)
    }

    func testChangeDatesRespectLimit() {
        let s = snapshot([event("a", "2026-09-18T13:00:00Z"), event("b", "2026-09-18T14:00:00Z")])
        XCTAssertEqual(WidgetTimeline.changeDates(snapshot: s, now: now, calendar: utcCalendar, limit: 2).count, 2)
    }

    func testChangeDatesForEmptySnapshotAreJustMidnights() {
        let dates = WidgetTimeline.changeDates(snapshot: snapshot([]), now: now, calendar: utcCalendar, limit: 10)
        XCTAssertEqual(dates, [date("2026-09-19T00:00:00Z"), date("2026-09-20T00:00:00Z")])
    }

    func testChangeDatesIgnoreAllDayEventBoundariesButKeepMidnights() {
        let s = snapshot([event("d", "2026-09-18T00:00:00Z", minutes: 24 * 60, allDay: true)])
        let dates = WidgetTimeline.changeDates(snapshot: s, now: now, calendar: utcCalendar, limit: 10)
        XCTAssertEqual(dates, [date("2026-09-19T00:00:00Z"), date("2026-09-20T00:00:00Z")])
    }

    func testNextUpFindsCurrentAndUpcoming() {
        let s = snapshot([event("now", "2026-09-18T11:45:00Z"), event("n1", "2026-09-18T13:00:00Z"),
                          event("n2", "2026-09-18T14:00:00Z"), event("n3", "2026-09-19T09:00:00Z"),
                          event("past", "2026-09-18T09:00:00Z")])
        let result = WidgetTimeline.nextUp(snapshot: s, now: now, upcomingLimit: 2)
        XCTAssertEqual(result.current?.id, "now")
        XCTAssertEqual(result.upcoming.map(\.id), ["n1", "n2"])
    }

    func testNextUpIgnoresAllDayEvents() {
        let s = snapshot([event("d", "2026-09-18T00:00:00Z", minutes: 24 * 60, allDay: true)])
        XCTAssertEqual(WidgetTimeline.nextUp(snapshot: s, now: now, upcomingLimit: 3), .init(current: nil, upcoming: []))
    }

    func testNextUpPicksEarliestStartedWhenMeetingsOverlap() {
        let s = snapshot([event("late", "2026-09-18T11:50:00Z"), event("early", "2026-09-18T11:40:00Z")])
        XCTAssertEqual(WidgetTimeline.nextUp(snapshot: s, now: now, upcomingLimit: 3).current?.id, "early")
    }

    func testTodayCoversOnlyTodayAndAssignsStates() {
        let s = snapshot([event("past", "2026-09-18T09:00:00Z"), event("cur", "2026-09-18T11:45:00Z"),
                          event("up", "2026-09-18T15:00:00Z"), event("tomorrow", "2026-09-19T09:00:00Z")])
        let rows = WidgetTimeline.today(snapshot: s, now: now, calendar: utcCalendar)
        XCTAssertEqual(rows.map(\.event.id), ["past", "cur", "up"])
        XCTAssertEqual(rows.map(\.state), [.past, .current, .upcoming])
    }

    func testTodayKeepsAllDayEventsAsCurrent() {
        let s = snapshot([event("d", "2026-09-18T00:00:00Z", minutes: 24 * 60, allDay: true)])
        let states = WidgetTimeline.today(snapshot: s, now: now, calendar: utcCalendar).map { $0.state }
        XCTAssertEqual(states, [.current])
    }

    // MARK: visibleToday

    private func rows(_ specs: [(String, WidgetTimeline.RowState)]) -> [WidgetTimeline.TodayRow] {
        specs.map { WidgetTimeline.TodayRow(event: event($0.0, "2026-09-18T09:00:00Z"), state: $0.1) }
    }

    func testVisibleTodayKeepsAllRowsWithinCapacity() {
        let r = rows([("a", .past), ("b", .upcoming)])
        XCTAssertEqual(WidgetTimeline.visibleToday(rows: r, capacity: 2), r)
    }

    func testVisibleTodayDropsPastRowsWhenOverCapacity() {
        let r = rows([("a", .past), ("b", .current), ("c", .upcoming)])
        XCTAssertEqual(WidgetTimeline.visibleToday(rows: r, capacity: 2).map(\.id), ["b", "c"])
    }

    func testVisibleTodayKeepsLastFinishedRowsWhenEverythingIsPast() {
        let r = rows([("a", .past), ("b", .past), ("c", .past)])
        XCTAssertEqual(WidgetTimeline.visibleToday(rows: r, capacity: 2).map(\.id), ["b", "c"])
    }

    func testVisibleTodayStaysEmptyWhenThereAreNoRows() {
        XCTAssertTrue(WidgetTimeline.visibleToday(rows: [], capacity: 2).isEmpty)
    }

    func testVisibleTodayNeverDropsTheCurrentMeeting() {
        let r = rows([("a", .past), ("b", .past), ("c", .current)])
        XCTAssertEqual(WidgetTimeline.visibleToday(rows: r, capacity: 2).map(\.id), ["c"])
    }
}
