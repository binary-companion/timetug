import Foundation
import os
import TimeTugEngine

/// Writes the engine's diagnostics to the unified system log under subsystem `com.timetug.app`, category = the
/// diagnostic's category (for example `takeover`, `ledger`, `accounts`). The engine guarantees a message never holds
/// titles or other calendar content, so it is logged as public.
/// Read with: log show --predicate 'subsystem == "com.timetug.app" AND category == "takeover"' --last 1h
final class OSLogEngineDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var loggers: [String: Logger] = [:]

    static func osLogType(for level: EngineDiagnostic.Level) -> OSLogType {
        switch level {
        case .info: .info
        case .warning: .default
        case .error: .error
        }
    }

    func record(_ diagnostic: EngineDiagnostic) {
        logger(for: diagnostic.category)
            .log(level: Self.osLogType(for: diagnostic.level), "\(diagnostic.message, privacy: .public)")
    }

    /// The sink to hand to `EngineHost`.
    var sink: EngineDiagnosticSink { { [self] in record($0) } }

    private func logger(for category: String) -> Logger {
        lock.withLock {
            if let existing = loggers[category] { return existing }
            let created = Logger(subsystem: OSLogDiagnosticLog.subsystem, category: category)
            loggers[category] = created
            return created
        }
    }
}
