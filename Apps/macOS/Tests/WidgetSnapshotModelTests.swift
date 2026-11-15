import Foundation
import XCTest
@testable import TimeTug

/// The decoding parts of timetug-shared 1.x `WidgetSnapshotTests` (round trip, staleness) on the app-owned model, plus
/// the compatibility check against a file written by the last Swift release.
final class WidgetSnapshotModelTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-18T12:00:00Z")!

    func testSnapshotRoundTripsThroughJSON() throws {
        let snapshot = WidgetSnapshot(generatedAt: now, events: [
            WidgetEvent(id: "e", title: "Standup", start: now, end: now.addingTimeInterval(1800), isAllDay: false,
                        colorHex: "#FF0000", joinURL: URL(string: "https://meet.google.com/aaa-bbbb-ccc")),
        ])
        let decoded = try WidgetSnapshot.makeDecoder().decode(WidgetSnapshot.self,
                                                              from: WidgetSnapshot.makeEncoder().encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
    }

    func testSnapshotIsStaleAfterMaxAge() {
        let snapshot = WidgetSnapshot(generatedAt: now, events: [])
        XCTAssertFalse(snapshot.isStale(now: now.addingTimeInterval(WidgetSnapshot.maxAge)))
        XCTAssertTrue(snapshot.isStale(now: now.addingTimeInterval(WidgetSnapshot.maxAge + 1)))
    }

    /// `Fixtures/agenda-snapshot-2.x.json` has invented content in the format the last Swift release wrote.
    func testDecodesSnapshotFileWrittenByTheLastSwiftRelease() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "agenda-snapshot-2.x", withExtension: "json"))
        let snapshot = try WidgetSnapshot.makeDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: url))
        let iso = ISO8601DateFormatter()
        XCTAssertEqual(snapshot.generatedAt, iso.date(from: "2027-02-03T09:15:00Z"))
        XCTAssertEqual(snapshot.events.map(\.id), ["fixture-standup", "fixture-offsite", "fixture-review"])
        let standup = snapshot.events[0]
        XCTAssertEqual(standup.title, "Team standup")
        XCTAssertEqual(standup.start, iso.date(from: "2027-02-03T09:30:00Z"))
        XCTAssertEqual(standup.end, iso.date(from: "2027-02-03T09:45:00Z"))
        XCTAssertFalse(standup.isAllDay)
        XCTAssertEqual(standup.colorHex, "#4C8DF6")
        XCTAssertEqual(standup.joinURL, URL(string: "https://meet.example.com/xyz-abcd-efg"))
        let offsite = snapshot.events[1]
        XCTAssertTrue(offsite.isAllDay)
        XCTAssertNil(offsite.colorHex)
        XCTAssertNil(offsite.joinURL)
        XCTAssertEqual(snapshot.events[2].colorHex, "#E5484D")
    }

    func testStoreReadsTheFixtureFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "agenda-snapshot-2.x", withExtension: "json"))
        try FileManager.default.copyItem(at: url, to: dir.appendingPathComponent(WidgetSnapshotStore.fileName))
        XCTAssertEqual(WidgetSnapshotStore(directory: dir).read()?.events.count, 3)
    }
}
