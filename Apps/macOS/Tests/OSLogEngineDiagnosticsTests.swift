import os
import TimeTugKit
import XCTest
@testable import TimeTug

final class OSLogEngineDiagnosticsTests: XCTestCase {
    func testLevelsMapToTheSystemLogTypes() {
        XCTAssertEqual(OSLogEngineDiagnostics.osLogType(for: .info), .info)
        XCTAssertEqual(OSLogEngineDiagnostics.osLogType(for: .warning), .default)
        XCTAssertEqual(OSLogEngineDiagnostics.osLogType(for: .error), .error)
    }

    func testTheSinkAcceptsEveryLevelAndBothKindsOfLine() {
        let sink = OSLogEngineDiagnostics()
        for level in [EngineDiagnostic.Level.info, .warning, .error] {
            sink.log(diagnostic: EngineDiagnostic(level: level, category: "tests", message: "diagnostics test \(level)"))
        }
        sink.record(event: DiagnosticEvent(level: .info, category: "tests", name: "recorded", fields: [], date: Date()))
    }
}
