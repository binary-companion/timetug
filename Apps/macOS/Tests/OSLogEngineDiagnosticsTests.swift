import os
import TimeTugEngine
import XCTest
@testable import TimeTug

final class OSLogEngineDiagnosticsTests: XCTestCase {
    func testLevelsMapToTheSystemLogTypes() {
        XCTAssertEqual(OSLogEngineDiagnostics.osLogType(for: .info), .info)
        XCTAssertEqual(OSLogEngineDiagnostics.osLogType(for: .warning), .default)
        XCTAssertEqual(OSLogEngineDiagnostics.osLogType(for: .error), .error)
    }

    func testTheSinkAcceptsEveryLevel() {
        let sink = OSLogEngineDiagnostics().sink
        for level in [EngineDiagnostic.Level.info, .warning, .error] {
            sink(EngineDiagnostic(level: level, category: "tests", message: "diagnostics test \(level.rawValue)"))
        }
    }
}
