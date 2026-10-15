import CalendarCore
import TimeTugCore
import TimeTugEngine
import XCTest
@testable import TimeTug

@MainActor
final class EngineModelMirrorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(startingIn seconds: TimeInterval, title: String = "Standup") -> TimeTugCalendarEvent {
        var event = TimeTugCalendarEvent(
            event: CalendarCore.CalendarEvent(
                eventID: "e1", calendarID: "work", title: title,
                start: now.addingTimeInterval(seconds), end: now.addingTimeInterval(seconds + 1800)),
            sourceID: "eventkit")
        event.otherAttendeeCount = 1
        return event
    }

    private func state(events: [TimeTugCalendarEvent]) -> EngineState {
        var state = EngineState.empty
        state.revision = 3
        state.events = events
        state.settings.takeover.takeoverCalendarKeys = Set(events.map(\.calendarKey))
        state.settings.takeover.leadTime = 120
        state.agenda = DayAgenda.make(events: events, settings: state.settings.takeover, now: now, calendar: .current)
        state.calendars = [CalendarInfo(sourceID: "eventkit", calendarID: "work", title: "Work")]
        state.statuses = ["eventkit": .ok]
        state.sourceNames = ["eventkit": "Calendar"]
        state.inferenceStatus = .noEngine
        return state
    }

    func testCopiesTheStateIntoTheModel() {
        let model = AppModel()
        let state = state(events: [event(startingIn: 300)])
        EngineModelMirror.apply(state, to: model)
        XCTAssertEqual(model.agenda, state.agenda)
        XCTAssertEqual(model.calendars, state.calendars)
        XCTAssertEqual(model.statuses, state.statuses)
        XCTAssertEqual(model.sourceNames, state.sourceNames)
        XCTAssertEqual(model.inferenceStatus, .noEngine)
        XCTAssertEqual(model.leadTime, 120)
    }

    func testAnUnchangedStateDoesNotRedrawTheViews() {
        let model = AppModel()
        let state = state(events: [event(startingIn: 300)])
        EngineModelMirror.apply(state, to: model)
        var changes = 0
        let observation = model.objectWillChange.sink { changes += 1 }
        defer { observation.cancel() }
        var tick = state
        tick.revision += 1
        EngineModelMirror.apply(tick, to: model)
        XCTAssertEqual(changes, 0)
    }

    func testTheStatusItemFollowsTheNextMeeting() {
        let soon = state(events: [event(startingIn: 300, title: "Standup")])
        XCTAssertEqual(EngineModelMirror.statusTitle(soon, mode: .countdown, now: now), "5m")
        XCTAssertEqual(EngineModelMirror.statusTitle(soon, mode: .nextMeeting, now: now), "Standup · 5m")
        XCTAssertNil(EngineModelMirror.statusTitle(soon, mode: .iconOnly, now: now))
        XCTAssertEqual(EngineModelMirror.iconState(soon, now: now), .soon)

        let later = state(events: [event(startingIn: 3600)])
        XCTAssertEqual(EngineModelMirror.iconState(later, now: now), .idle)
        XCTAssertEqual(EngineModelMirror.statusTitle(.empty, mode: .nextMeeting, now: now), "No Meetings")
    }
}
