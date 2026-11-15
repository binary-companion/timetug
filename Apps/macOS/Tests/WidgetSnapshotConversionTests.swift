import Foundation
import TimeTugKit
import XCTest
@testable import TimeTug

// Both modules declare WidgetSnapshot; the app-owned one is named by its module.
private typealias AppSnapshot = TimeTug.WidgetSnapshot

final class WidgetSnapshotConversionTests: XCTestCase {
    private func engineSnapshot() -> TimeTugKit.WidgetSnapshot {
        TimeTugKit.WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_799_999_100.75),   // sub-second part is not written
            events: [
                TimeTugKit.WidgetEvent(id: "evt-1", title: "Design review", start: Date(timeIntervalSince1970: 1_800_000_000),
                                       end: Date(timeIntervalSince1970: 1_800_001_800), isAllDay: false, colorHex: "#4C8DF6",
                                       joinUrl: URL(string: "https://meet.example.com/abc-defg-hij")),
                TimeTugKit.WidgetEvent(id: "evt-2", title: "Offsite", start: Date(timeIntervalSince1970: 1_800_006_400),
                                       end: Date(timeIntervalSince1970: 1_800_092_800), isAllDay: true, colorHex: nil,
                                       joinUrl: nil),
            ])
    }

    /// Captured from the last Swift release (timetug-shared 1.8.6, `TimeTugCore.WidgetSnapshot`) with:
    ///
    ///     let events = [
    ///       WidgetEvent(id: "evt-1", title: "Design review", start: Date(timeIntervalSince1970: 1_800_000_000),
    ///                   end: Date(timeIntervalSince1970: 1_800_001_800), isAllDay: false, colorHex: "#4C8DF6",
    ///                   joinURL: URL(string: "https://meet.example.com/abc-defg-hij")),
    ///       WidgetEvent(id: "evt-2", title: "Offsite", start: Date(timeIntervalSince1970: 1_800_006_400),
    ///                   end: Date(timeIntervalSince1970: 1_800_092_800), isAllDay: true, colorHex: nil, joinURL: nil),
    ///     ]
    ///     let snapshot = WidgetSnapshot(generatedAt: Date(timeIntervalSince1970: 1_799_999_100.75), events: events)
    ///     let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    ///     print(String(data: try encoder.encode(snapshot), encoding: .utf8)!)
    ///
    /// JSONEncoder does not fix key order, so the comparison parses both sides.
    private let capturedFromSwiftRelease = """
        {"generatedAt":"2027-01-15T07:45:00Z","events":[{"end":"2027-01-15T08:30:00Z","isAllDay":false,"joinURL":"https:\\/\\/meet.example.com\\/abc-defg-hij","id":"evt-1","title":"Design review","start":"2027-01-15T08:00:00Z","colorHex":"#4C8DF6"},{"end":"2027-01-16T09:46:40Z","start":"2027-01-15T09:46:40Z","isAllDay":true,"id":"evt-2","title":"Offsite"}]}
        """

    func testConvertedSnapshotEncodesLikeTheSwiftRelease() throws {
        let converted = AppSnapshot(engineSnapshot())
        let produced = try JSONSerialization.jsonObject(with: AppSnapshot.makeEncoder().encode(converted)) as? NSDictionary
        let expected = try JSONSerialization.jsonObject(with: Data(capturedFromSwiftRelease.utf8)) as? NSDictionary
        XCTAssertNotNil(expected)
        XCTAssertEqual(produced, expected)
    }

    func testConversionMapsEveryField() {
        let converted = AppSnapshot(engineSnapshot())
        XCTAssertEqual(converted.generatedAt, Date(timeIntervalSince1970: 1_799_999_100.75))
        XCTAssertEqual(converted.events.count, 2)
        XCTAssertEqual(converted.events[0].joinURL, URL(string: "https://meet.example.com/abc-defg-hij"))
        XCTAssertEqual(converted.events[0].colorHex, "#4C8DF6")
        XCTAssertTrue(converted.events[1].isAllDay)
        XCTAssertNil(converted.events[1].joinURL)
    }

    func testStoreWritesAnEngineSnapshotInTheFileFormat() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = WidgetSnapshotStore(directory: dir)
        try store.write(engineSnapshot())
        let data = try Data(contentsOf: dir.appendingPathComponent("agenda-snapshot.json"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: data) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: Data(capturedFromSwiftRelease.utf8)) as? NSDictionary)
        XCTAssertEqual(store.read()?.events.map(\.id), ["evt-1", "evt-2"])
    }
}
