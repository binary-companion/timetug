import os
import TimeTugKit
import XCTest
@testable import TimeTug

/// The field spellings the connector library used (strings private unless said otherwise), for these tests.
private extension DiagnosticField {
    static func int(_ name: String, _ value: Int64, private isPrivate: Bool = false) -> DiagnosticField {
        DiagnosticField(name: name, value: .int(value), isPrivate: isPrivate)
    }
    static func bool(_ name: String, _ value: Bool, private isPrivate: Bool = false) -> DiagnosticField {
        DiagnosticField(name: name, value: .bool(value), isPrivate: isPrivate)
    }
    static func string(_ name: String, _ value: String, private isPrivate: Bool = true) -> DiagnosticField {
        DiagnosticField(name: name, value: .string(value), isPrivate: isPrivate)
    }
}

final class AppDiagnosticsTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    func testOSLogRenderingSplitsPublicAndPrivateFields() {
        let event = DiagnosticEvent(level: .info, category: "icalsub", name: "fetchCompleted",
                                    fields: [.int("status", 200), .bool("conditional", false), .string("uid", "abc"), .string("reason", "network", private: false)],
                                    date: date)
        let rendering = OSLogRendering(event: event)
        XCTAssertEqual(rendering.publicText, "fetchCompleted status=200 conditional=false reason=network")
        XCTAssertEqual(rendering.privateText, "uid=abc")
        XCTAssertFalse(rendering.publicText.contains("abc"))
    }

    func testStringFieldsArePrivateByDefaultInPieces() {
        let event = DiagnosticEvent(level: .info, category: "c", name: "n", fields: [.string("k", "v"), .int("n", 1)], date: date)
        XCTAssertEqual(OSLogRendering.pieces(for: event), [
            .init(text: "n", isPrivate: false), .init(text: "k=v", isPrivate: true), .init(text: "n=1", isPrivate: false),
        ])
    }

    func testEventWithoutPrivateFieldsHasEmptyPrivateText() {
        let rendering = OSLogRendering(event: DiagnosticEvent(level: .debug, category: "c", name: "n", fields: [], date: date))
        XCTAssertEqual(rendering.publicText, "n")
        XCTAssertEqual(rendering.privateText, "")
    }

    func testLevelMapping() {
        XCTAssertEqual(OSLogDiagnosticLog.osLogType(for: .debug), .debug)
        XCTAssertEqual(OSLogDiagnosticLog.osLogType(for: .info), .info)
        XCTAssertEqual(OSLogDiagnosticLog.osLogType(for: .notice), .default)
        XCTAssertEqual(OSLogDiagnosticLog.osLogType(for: .warning), .error)
        XCTAssertEqual(OSLogDiagnosticLog.osLogType(for: .error), .fault)
    }

    func testReportHasHeaderAndRedactsPrivateFields() {
        let diagnostics = AppDiagnostics(capacity: 10, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        diagnostics.log.record(DiagnosticEvent(level: .notice, category: "icalsub", name: "rruleUnreadable",
                                               fields: [.string("uid", "secret-uid"), .int("count", 2)], date: date))
        let report = diagnostics.report()
        XCTAssertTrue(report.contains("App version:"))
        XCTAssertTrue(report.contains("macOS:"))
        XCTAssertTrue(report.contains("Generated: 2027-01-15T08:00:00Z"))
        XCTAssertTrue(report.contains("icalsub.rruleUnreadable uid=<private> count=2"))
        XCTAssertFalse(report.contains("secret-uid"))
    }

    func testClearEmptiesTheReportEvents() {
        let diagnostics = AppDiagnostics(capacity: 10)
        diagnostics.log.record(DiagnosticEvent(level: .info, category: "icalsub", name: "feedParsed", fields: [], date: date))
        XCTAssertTrue(diagnostics.report().contains("feedParsed"))
        diagnostics.clear()
        XCTAssertFalse(diagnostics.report().contains("feedParsed"))
    }

    // MARK: Ported from the connector library (the ring buffer, fan-out and report rendering moved into the app)

    func testRingBufferKeepsTheNewestEventsOldestFirst() {
        let buffer = RingBufferDiagnosticLog(capacity: 2)
        for name in ["a", "b", "c"] { buffer.record(DiagnosticEvent(level: .info, category: "c", name: name, fields: [], date: date)) }
        XCTAssertEqual(buffer.snapshot().map(\.name), ["b", "c"])
        buffer.clear()
        XCTAssertTrue(buffer.snapshot().isEmpty)
    }

    func testRenderShowsPrivateFieldsOnlyWhenAsked() {
        let buffer = RingBufferDiagnosticLog()
        buffer.record(DiagnosticEvent(level: .warning, category: "icalsub", name: "fetchFailed",
                                      fields: [.string("host", "feeds.example.com", private: false), .string("uid", "abc")], date: date))
        XCTAssertEqual(buffer.render(), "2027-01-15T08:00:00Z warning icalsub.fetchFailed host=feeds.example.com uid=<private>")
        XCTAssertEqual(buffer.render(includePrivate: true), "2027-01-15T08:00:00Z warning icalsub.fetchFailed host=feeds.example.com uid=abc")
    }

    func testRenderQuotesAStringThatWouldBreakTheLine() {
        let buffer = RingBufferDiagnosticLog()
        buffer.record(DiagnosticEvent(level: .info, category: "c", name: "n",
                                      fields: [.string("reason", "two words \"quoted\"\nnext", private: false)], date: date))
        XCTAssertEqual(buffer.render(), "2027-01-15T08:00:00Z info c.n reason=\"two words \\\"quoted\\\"\\nnext\"")
    }

    func testFanOutSendsEveryEventToEveryLogInOrder() {
        let first = RingBufferDiagnosticLog(), second = RingBufferDiagnosticLog()
        let fanOut = FanOutDiagnosticLog([first, second])
        fanOut.record(DiagnosticEvent(level: .info, category: "c", name: "one", fields: [], date: date))
        fanOut.record(DiagnosticEvent(level: .info, category: "c", name: "two", fields: [], date: date))
        XCTAssertEqual(first.snapshot().map(\.name), ["one", "two"])
        XCTAssertEqual(second.snapshot().map(\.name), ["one", "two"])
    }

    func testTheEngineSinkHandsConnectorEventsToTheEventLogAndKeepsEngineLinesOutOfIt() {
        let buffer = RingBufferDiagnosticLog()
        let sink = OSLogEngineDiagnostics(events: buffer)
        sink.record(event: DiagnosticEvent(level: .info, category: "icalsub", name: "feedParsed", fields: [.int("events", 12)], date: date))
        sink.log(diagnostic: EngineDiagnostic(level: .info, category: "takeover", message: "armed"))
        XCTAssertEqual(buffer.snapshot().map(\.name), ["feedParsed"])
        XCTAssertEqual(buffer.snapshot().first?.fields, [.int("events", 12)])
    }
}
