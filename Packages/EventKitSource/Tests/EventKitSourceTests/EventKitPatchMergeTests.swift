import EventKit
import Foundation
import Testing
import TimeTugKit
@testable import EventKitSource

// The retry loop around a store write (`PatchMerge.apply` in the 1.x libraries): the field comparison is the engine's
// `patchMergeConflicts`, the loop stays here.

private let start = Date(timeIntervalSince1970: 1_790_000_000)
private func event(title: String = "Meeting", location: String? = nil, version: String?) -> CalendarEvent {
    CalendarEvent(eventID: "e", calendarID: "c", title: title, location: location, start: start, end: start.addingTimeInterval(1800), version: version)
}
private func renamePatch(from base: CalendarEvent, to title: String) -> EventPatch {
    var edited = base
    edited.title = title
    return eventPatchDiff(original: base, edited: edited)
}

private final class Writes: @unchecked Sendable {
    var versions: [String?] = []
}

@Test func aWriteThatSucceedsRunsOnce() async throws {
    let base = event(version: "1")
    let writes = Writes()
    let result = try await EventKitSource().applyPatch(
        renamePatch(from: base, to: "New"), version: "1", fetchCurrent: { base },
        write: { version in writes.versions.append(version); return .done(event(title: "New", version: "2")) })
    #expect(result.title == "New" && writes.versions == ["1"])
}

@Test func aStaleVersionWithoutOverlapRetriesOnTheFreshVersion() async throws {
    let base = event(version: "1")
    let current = event(location: "Elsewhere", version: "2")   // someone else changed the location, not the title
    let writes = Writes()
    let result = try await EventKitSource().applyPatch(
        renamePatch(from: base, to: "New"), version: "1", fetchCurrent: { current },
        write: { version in
            writes.versions.append(version)
            return version == "2" ? .done(event(title: "New", location: "Elsewhere", version: "3")) : .stale
        })
    #expect(result.title == "New" && writes.versions == ["1", "2"])
}

@Test func aStaleVersionWithAnOverlappingChangeIsAConflict() async {
    let base = event(version: "1")
    let current = event(title: "Theirs", version: "2")
    await #expect(throws: FfiError.Write(.conflict(fields: [.title]))) {
        _ = try await EventKitSource().applyPatch(
            renamePatch(from: base, to: "Mine"), version: "1", fetchCurrent: { current }, write: { _ in .stale })
    }
}

@Test func aFreshEventWithoutAVersionFailsClosedWhenTheWriteWasVersioned() async {
    let base = event(version: "1")
    await #expect(throws: FfiError.Write(.conflict(fields: [.title]))) {
        _ = try await EventKitSource().applyPatch(
            renamePatch(from: base, to: "New"), version: "1", fetchCurrent: { event(version: nil) }, write: { _ in .stale })
    }
}

@Test func anEventThatKeepsChangingIsAConflictAfterThreeWrites() async {
    let base = event(version: "1")
    let writes = Writes()
    var next = 1
    await #expect(throws: FfiError.Write(.conflict(fields: [.title]))) {
        _ = try await EventKitSource().applyPatch(
            renamePatch(from: base, to: "New"), version: "1",
            fetchCurrent: { next += 1; return event(location: "L\(next)", version: "\(next)") },
            write: { version in writes.versions.append(version); return .stale })
    }
    #expect(writes.versions.count == 3)
}
