import Foundation
import TimeTugKit

// Test-only conveniences with the 1.x defaults and labels (CalendarCore `WriteTypes.swift`, `EventDraft.swift`,
// `EventPatch.swift`, `RecurrenceRule`), which `TimeTugKit` does not carry: the generated initialisers need every field.
// The tests read the same as they did against CalendarCore.

extension RecurrenceRule {
    init(
        frequency: Frequency, interval: Int64 = 1, weekdays: [WeekdayOccurrence] = [], monthDays: [Int64] = [],
        months: [Int64] = [], end: End = .never, weekStart: Weekday = .monday
    ) {
        self.init(
            frequency: frequency, interval: interval, weekStart: weekStart, weekdays: weekdays, monthDays: monthDays,
            months: months, yearDays: [], weekNumbers: [], setPositions: [], hours: [], minutes: [], seconds: [], end: end,
            unrecognizedParts: [])
    }
}

extension EventRef {
    init(calendarID: String, eventID: String, version: String? = nil, seriesID: String? = nil, originalStart: Date? = nil) {
        self.init(
            calendarId: calendarID, eventId: eventID, version: version, seriesId: (seriesID?.isEmpty ?? true) ? nil : seriesID,
            originalStart: originalStart)
    }

    init(_ event: CalendarEvent) {
        self.init(
            calendarID: event.calendarID, eventID: event.eventID, version: event.version, seriesID: event.seriesID,
            originalStart: event.originalStart)
    }
}

extension AttendeeDraft {
    init(email: String, name: String? = nil, role: AttendeeRole = .required) {
        self.init(name: name, email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), role: role)
    }
}

extension EventDraft {
    init(
        title: String, timing: EventTiming, notes: String? = nil, location: String? = nil, availability: Availability = .busy,
        visibility: Visibility = .default, reminders: [Reminder]? = nil, attendees: [AttendeeDraft] = [],
        conference: ConferenceRequest = .none, recurrence: RecurrenceRule? = nil, uid: String? = nil
    ) {
        self.init(
            title: title, notes: notes, location: location, timing: timing, availability: availability, visibility: visibility,
            reminders: reminders, attendees: attendees, conference: conference, recurrence: recurrence, uid: uid)
    }
}

extension EventPatch {
    init(
        title: String? = nil, notes: FieldUpdate<String> = .keep, location: FieldUpdate<String> = .keep,
        timing: EventTiming? = nil, availability: Availability? = nil, visibility: Visibility? = nil,
        reminders: FieldUpdate<[Reminder]> = .keep, attendees: AttendeeChanges? = nil,
        recurrence: FieldUpdate<RecurrenceRule> = .keep, conference: ConferenceChange? = nil
    ) {
        self.init(
            title: title, notes: notes.mirror, location: location.mirror, timing: timing, availability: availability,
            visibility: visibility, reminders: reminders.mirror, attendees: attendees, recurrence: recurrence.mirror,
            conference: conference, base: nil)
    }
}

/// An event being edited: `patch` is the comparison of the original with the edited copy (`EventEdit` of 1.x).
struct EventEdit {
    let original: CalendarEvent
    var event: CalendarEvent
    init(_ original: CalendarEvent) {
        self.original = original
        self.event = original
    }
    var patch: EventPatch { eventPatchDiff(original: original, edited: event) }
}

/// What every source must do with an all-day event (`AllDayConformance` of 1.x): midnight in its own zone at both ends.
func allDayViolations(_ event: CalendarEvent) -> [String] {
    guard event.isAllDay else { return [] }
    let zone = event.timeZone
    var found: [String] = []
    func isMidnight(_ instant: Date) -> Bool {
        allDayStartOfDay(date: allDayDateOf(instant: instant, zone: zone), zone: zone) == instant
    }
    if !isMidnight(event.start) { found.append("start is not the start of a day in \(zone.identifier)") }
    if !isMidnight(event.end) { found.append("end is not the start of a day in \(zone.identifier)") }
    if event.end <= event.start { found.append("end is not after start") }
    return found
}

extension StructuredLocation {
    // The extra defaulted parameter keeps a call that names every field on the generated initialiser (see `Initializers.swift`).
    init(title: String? = nil, latitude: Double? = nil, longitude: Double? = nil, radius: Double? = nil, _: Void = ()) {
        self.init(title: title, latitude: latitude, longitude: longitude, radius: radius)
    }
}
