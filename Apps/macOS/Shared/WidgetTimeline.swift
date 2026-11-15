import Foundation

/// Pure functions that turn a `WidgetSnapshot` into what a widget shows at a given instant.
enum WidgetTimeline {
    enum RowState: Equatable, Sendable { case past, current, upcoming }

    struct NextUp: Equatable, Sendable {
        let current: WidgetEvent?
        let upcoming: [WidgetEvent]
        init(current: WidgetEvent?, upcoming: [WidgetEvent]) {
            self.current = current
            self.upcoming = upcoming
        }
    }

    struct TodayRow: Equatable, Sendable, Identifiable {
        let event: WidgetEvent
        let state: RowState
        var id: String { event.id }
    }

    static func changeDates(snapshot: WidgetSnapshot, now: Date, calendar: Calendar, limit: Int) -> [Date] {
        var dates = Set<Date>()
        for event in snapshot.events where !event.isAllDay {
            if event.start > now { dates.insert(event.start) }
            if event.end > now { dates.insert(event.end) }
        }
        let dayStart = calendar.startOfDay(for: now)
        for offset in 1..<WidgetSnapshot.horizonDays {
            if let midnight = calendar.date(byAdding: .day, value: offset, to: dayStart), midnight > now {
                dates.insert(midnight)
            }
        }
        return Array(dates.sorted().prefix(limit))
    }

    static func nextUp(snapshot: WidgetSnapshot, now: Date, upcomingLimit: Int) -> NextUp {
        let timed = snapshot.events.filter { !$0.isAllDay }
        let current = timed.filter { $0.start <= now && $0.end > now }.min { $0.start < $1.start }
        let upcoming = timed.filter { $0.start > now }.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        return NextUp(current: current, upcoming: Array(upcoming.prefix(upcomingLimit)))
    }

    static func today(snapshot: WidgetSnapshot, now: Date, calendar: Calendar) -> [TodayRow] {
        let dayStart = calendar.startOfDay(for: now)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return snapshot.events
            .filter { $0.end > dayStart && $0.start < nextDayStart }
            .map { event in
                let state: RowState = event.end <= now ? .past : (event.start <= now ? .current : .upcoming)
                return TodayRow(event: event, state: state)
            }
    }

    /// The rows to show when only `capacity` fit. Over capacity, finished meetings are dropped first so the rest of
    /// the day stays visible; if everything is finished, the last `capacity` rows are kept so the day is not shown empty.
    static func visibleToday(rows: [TodayRow], capacity: Int) -> [TodayRow] {
        guard rows.count > capacity else { return rows }
        let remaining = rows.filter { $0.state != .past }
        return remaining.isEmpty ? Array(rows.suffix(capacity)) : remaining
    }
}
