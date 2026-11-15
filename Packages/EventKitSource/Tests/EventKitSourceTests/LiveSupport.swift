// LiveSupport.swift
import EventKit
import Foundation
import Testing
import TimeTugKit
@testable import EventKitSource

/// Live EventKit tests are opt-in: `TIMETUG_LIVE_EVENTKIT=1 swift test --package-path Packages/EventKitSource --filter eventKit`.
let liveEventKit = ProcessInfo.processInfo.environment["TIMETUG_LIVE_EVENTKIT"] == "1"

/// Creates a scratch calendar in the local ("On My Mac") source, runs `body`, then deletes the calendar and
/// everything in it. Existing calendars are never touched.
func withScratchCalendar(_ body: (EKEventStore, EKCalendar) async throws -> Void) async throws {
    let store = EKEventStore()
    guard try await store.requestFullAccessToEvents() else {
        Issue.record("calendar access was denied")
        return
    }
    guard let source = store.sources.first(where: { $0.sourceType == .local }) else {
        Issue.record("no local calendar source; enable On My Mac in Calendar settings")
        return
    }
    let calendar = EKCalendar(for: .event, eventStore: store)
    calendar.title = "TimeTug live test \(UUID().uuidString.prefix(6))"
    calendar.source = source
    try store.saveCalendar(calendar, commit: true)
    defer { try? store.removeCalendar(calendar, commit: true) }
    try await body(store, calendar)
}

func nextHour(daysAhead: Int = 2) -> Date {
    let calendar = Calendar.current
    let day = calendar.date(byAdding: .day, value: daysAhead, to: Date())!
    return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day)!
}

// The 1.x spelling of the source's calls, so the live tests read as they did against `WritableCalendarSource`.
extension EventKitSource {
    func create(_ draft: EventDraft, in calendarID: String, notify: NotifyPolicy) async throws -> CalendarEvent {
        try await create(draft: draft, calendarId: calendarID, notify: notify)
    }

    func update(_ ref: EventRef, _ patch: EventPatch, scope: RecurrenceScope, notify: NotifyPolicy) async throws -> CalendarEvent {
        try await update(reference: ref, patch: patch, scope: scope, notify: notify)
    }

    func delete(_ ref: EventRef, scope: RecurrenceScope, notify: NotifyPolicy) async throws {
        try await delete(reference: ref, scope: scope, notify: notify)
    }

    func respond(to ref: EventRef, _ response: ResponseStatus, scope: RecurrenceScope, notify: NotifyPolicy) async throws -> CalendarEvent {
        try await respond(reference: ref, response: response, scope: scope, notify: notify)
    }

    func events(in window: DateInterval) async throws -> [CalendarEvent] {
        try await eventsIn(start: window.start, end: window.end)
    }
}

/// Behaviour a writable source must have (`WritableSourceConformance` of CalendarTestSupport 1.x), run against the real
/// source and a scratch calendar. An empty result means the source conforms. It cleans up the event it creates.
func writableViolations(of source: EventKitSource, calendarID: String, window: DateInterval) async -> [String] {
    var found: [String] = []
    let caps = source.capabilities()
    if !caps.canWrite { found.append("canWrite is false on a writable source") }
    if caps.canEditAttendees != caps.writableFields.contains(.attendees) {
        found.append("canEditAttendees does not match writableFields.contains(.attendees)")
    }
    let usesLocation = caps.writableFields.contains(.location)
    let utc = TimeZone(identifier: "UTC")!
    let start = window.start.addingTimeInterval(3600)
    let draft = EventDraft(
        title: "Conformance A", timing: EventTiming(start: start, end: start.addingTimeInterval(1800), timeZone: utc, isAllDay: false),
        location: usesLocation ? "Room 1" : nil)
    let created: CalendarEvent
    do {
        created = try await source.create(draft, in: calendarID, notify: .none)
    } catch {
        return found + ["create threw \(error)"]
    }
    var latest = created
    var deleted = false
    if created.title != "Conformance A" || created.calendarID != calendarID { found.append("create returned a different title or calendar") }
    do {
        let listed = try await source.events(in: window)
        if !listed.contains(where: { $0.eventID == created.eventID }) { found.append("the created event is not returned by events") }
        let renamed = try await source.update(EventRef(latest), EventPatch(title: "Conformance B"), scope: .thisInstance, notify: .none)
        latest = renamed
        if renamed.title != "Conformance B" { found.append("update did not change the title") }
        if usesLocation && renamed.location != "Room 1" { found.append("update changed a field the patch did not touch (location)") }
        if renamed.start != created.start || renamed.end != created.end || renamed.isAllDay != created.isAllDay {
            found.append("update changed a field the patch did not touch (timing)")
        }
        if renamed.version != nil, renamed.version == created.version { found.append("update did not change the version") }

        let unchanged = try await source.update(EventRef(renamed), EventPatch(), scope: .thisInstance, notify: .none)
        latest = unchanged
        if unchanged.title != "Conformance B" { found.append("an empty patch changed the event") }
        if renamed.version != nil, unchanged.version != renamed.version { found.append("an empty patch changed the version") }

        if !caps.writableFields.contains(.attendees) {
            do {
                _ = try await source.update(
                    EventRef(renamed), EventPatch(attendees: AttendeeChanges(add: [AttendeeDraft(email: "a@b.c")], remove: [])),
                    scope: .thisInstance, notify: .none)
                found.append("an unwritable field (attendees) was accepted")
            } catch FfiError.Write(.unsupported) {
            } catch {
                found.append("an unwritable field threw \(error) instead of .unsupported")
            }
        }

        try await source.delete(EventRef(latest), scope: .thisInstance, notify: .none)
        deleted = true
        let remaining = try await source.events(in: window)
        if remaining.contains(where: { $0.eventID == created.eventID }) { found.append("the event is still present after delete") }
        do {
            try await source.delete(EventRef(latest), scope: .thisInstance, notify: .none)
            found.append("deleting a missing event did not throw")
        } catch FfiError.Write(.notFound) {
        } catch {
            found.append("deleting a missing event threw \(error) instead of .notFound")
        }
    } catch {
        found.append("threw \(error)")
    }
    if !deleted {
        do { try await source.delete(EventRef(latest), scope: .thisInstance, notify: .none) }
        catch { found.append("cleanup delete failed, the test event may be left behind: \(error)") }
    }
    return found
}
