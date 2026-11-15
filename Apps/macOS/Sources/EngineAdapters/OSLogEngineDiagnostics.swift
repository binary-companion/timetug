import Foundation
import os
import TimeTugKit

/// Writes the engine's diagnostics to the unified system log under subsystem `com.timetug.app`, category = the
/// diagnostic's category (for example `takeover`, `ledger`, `accounts`). The engine guarantees a message never holds
/// titles or other calendar content, so it is logged as public.
/// Read with: log show --predicate 'subsystem == "com.timetug.app" AND category == "takeover"' --last 1h
///
/// It is the engine's `DiagnosticSink`: `log` writes the engine's own lines to the system log, `record` hands a
/// connector's structured event (with its per-field privacy flags) to the app's diagnostics log, which writes the
/// system log with the same privacy split and keeps the "Copy Diagnostics" report.
final class OSLogEngineDiagnostics: DiagnosticSink, @unchecked Sendable {
    private let lock = NSLock()
    private var loggers: [String: Logger] = [:]
    private let events: any DiagnosticLog

    init(events: any DiagnosticLog = NullDiagnosticLog()) {
        self.events = events
    }

    static func osLogType(for level: EngineDiagnostic.Level) -> OSLogType {
        switch level {
        case .info: .info
        case .warning: .default
        case .error: .error
        }
    }

    func log(diagnostic: EngineDiagnostic) {
        logger(for: diagnostic.category)
            .log(level: Self.osLogType(for: diagnostic.level), "\(diagnostic.message, privacy: .public)")
    }

    func record(event: DiagnosticEvent) {
        events.record(event)
    }

    private func logger(for category: String) -> Logger {
        lock.withLock {
            if let existing = loggers[category] { return existing }
            let created = Logger(subsystem: OSLogDiagnosticLog.subsystem, category: category)
            loggers[category] = created
            return created
        }
    }
}
