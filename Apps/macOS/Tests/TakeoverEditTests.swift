import TimeTugCore
import XCTest
@testable import TimeTug

/// A Settings edit reaches the engine as the fields the user changed, never as a whole stale copy.
final class TakeoverEditTests: XCTestCase {
    func testOnlyTheEditedFieldIsApplied() {
        var shown = TakeoverSettings()
        shown.enabled = false   // what Settings showed when the user edited
        var edited = shown
        edited.leadTime = 300

        var engine = TakeoverSettings()
        engine.enabled = true   // a Control Center toggle the engine already applied
        engine.applyEdit(from: shown, to: edited)
        XCTAssertEqual(engine.leadTime, 300)
        XCTAssertTrue(engine.enabled)
    }

    func testCalendarKeysApplyAsAddedAndRemoved() {
        var shown = TakeoverSettings()
        shown.takeoverCalendarKeys = ["eventkit/work", "google-1/old"]
        shown.hiddenCalendarKeys = ["eventkit/spam"]
        var edited = shown
        edited.takeoverCalendarKeys.insert("eventkit/home")
        edited.hiddenCalendarKeys.remove("eventkit/spam")

        var engine = shown
        engine.takeoverCalendarKeys.remove("google-1/old")   // the engine forgot a removed account's calendar
        engine.applyEdit(from: shown, to: edited)
        XCTAssertEqual(engine.takeoverCalendarKeys, ["eventkit/work", "eventkit/home"])
        XCTAssertEqual(engine.hiddenCalendarKeys, [])
    }

    func testEveryScalarFieldIsCarried() {
        let old = TakeoverSettings()
        var new = old
        new.leadTime = 0
        new.requireConferenceLink = true
        new.requireOtherAttendees = true
        new.skipAllDayEvents = false
        new.enabled = false
        new.takeoverCalendarKeys = ["a"]
        new.hiddenCalendarKeys = ["b"]
        var applied = old
        applied.applyEdit(from: old, to: new)
        XCTAssertEqual(applied, new)
    }
}
