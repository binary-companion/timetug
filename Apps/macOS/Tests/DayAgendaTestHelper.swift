import Foundation
import TimeTugKit

extension DayAgenda {
    /// Builds a `DayAgenda` the way the Swift engine's `DayAgenda.make` did, for tests that need one without an
    /// engine (the engine builds the real agenda from the same rules; its own tests cover them).
    static func make(events: [TimeTugCalendarEvent], settings: TakeoverSettings, now: Date, calendar: Calendar) -> DayAgenda {
        let dayStart = calendar.startOfDay(for: now)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let today = allDayDateOf(instant: dayStart, zone: calendar.timeZone)

        /// The first covered date and the exclusive end, in the event's own zone; a same-date range is one day.
        func allDayDates(_ event: TimeTugCalendarEvent) -> AllDayDates? {
            guard event.isAllDay else { return nil }
            let dates = TimeTugKit.allDayDates(start: event.start, end: event.end, zone: event.timeZone)
            if dates.endExclusive <= dates.first {
                return AllDayDates(first: dates.first, endExclusive: calendarDateAddingDays(date: dates.first, days: 1))
            }
            return dates
        }

        let items = events
            .filter { !$0.allCalendarKeys.isSubset(of: settings.hiddenCalendarKeys) }
            .filter { !(settings.skipAllDayEvents && $0.isAllDay) }
            .filter { event in
                if let dates = allDayDates(event) { return dates.first <= today && today < dates.endExclusive }
                if event.end > dayStart && event.start < nextDayStart { return true }
                return !event.isAllDay && event.start >= nextDayStart
                    && now >= event.start.addingTimeInterval(-settings.leadTime)
            }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
            .map { event -> DayAgendaItem in
                let state: DayAgendaItemState
                if let dates = allDayDates(event) {
                    state = dates.endExclusive <= today ? .past : (dates.first <= today ? .current : .upcoming)
                } else {
                    state = event.end <= now ? .past : (event.start <= now ? .current : .upcoming)
                }
                return DayAgendaItem(event: event, state: state)
            }
        let next = items.first { !$0.event.isAllDay && $0.event.start > now }?.event
        return DayAgenda(items: items, next: next)
    }
}
