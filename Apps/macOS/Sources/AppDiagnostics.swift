import Foundation
import TimeTugKit

/// Where the app sends a connector's structured diagnostic events (the engine delivers them through
/// `DiagnosticSink.record`). Adapters live in the app: the system log and an in-memory report. `record` is
/// synchronous, never throws and must not block.
protocol DiagnosticLog: Sendable {
    func record(_ event: DiagnosticEvent)
}

extension DiagnosticLevel {
    /// The lower-case word used in rendered reports.
    var label: String {
        switch self {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .warning: "warning"
        case .error: "error"
        }
    }
}

extension DiagnosticField {
    /// The value as text, ignoring `isPrivate`. For tests and for a report that has already decided what to show.
    var unredactedText: String {
        switch value {
        case .int(let number): String(number)
        case .double(let number): String(number)
        case .bool(let flag): flag ? "true" : "false"
        case .string(let text): text
        }
    }
}

/// Discards everything.
struct NullDiagnosticLog: DiagnosticLog {
    func record(_ event: DiagnosticEvent) {}
}

/// Sends each event to every log, in order.
struct FanOutDiagnosticLog: DiagnosticLog {
    private let logs: [any DiagnosticLog]
    init(_ logs: [any DiagnosticLog]) { self.logs = logs }
    func record(_ event: DiagnosticEvent) {
        for log in logs { log.record(event) }
    }
}

/// Keeps the last `capacity` events in memory, for an in-app report. Thread-safe.
final class RingBufferDiagnosticLog: DiagnosticLog, @unchecked Sendable {
    static let defaultCapacity = 500

    private let capacity: Int
    private let lock = NSLock()
    private var events: [DiagnosticEvent] = []

    init(capacity: Int = RingBufferDiagnosticLog.defaultCapacity) {
        self.capacity = max(capacity, 1)
    }

    func record(_ event: DiagnosticEvent) {
        lock.withLock {
            events.append(event)
            if events.count > capacity { events.removeFirst(events.count - capacity) }
        }
    }

    /// The kept events, oldest first.
    func snapshot() -> [DiagnosticEvent] { lock.withLock { events } }

    func clear() { lock.withLock { events.removeAll() } }

    /// A plain-text report, one line per event, oldest first:
    /// `2026-10-06T17:00:00Z info icalsub.fetchCompleted status=200 uid=<private>`.
    /// Private fields show `<private>` unless `includePrivate`.
    func render(includePrivate: Bool = false) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return snapshot().map { event in
            let fields = event.fields.map { field in
                "\(field.name)=\(field.isPrivate && !includePrivate ? "<private>" : Self.text(field))"
            }
            return ([formatter.string(from: event.date), event.level.label, "\(event.category).\(event.name)"] + fields).joined(separator: " ")
        }.joined(separator: "\n")
    }

    /// A string value with a space, quote, equals sign or line break is quoted so a line stays one line.
    private static func text(_ field: DiagnosticField) -> String {
        guard case .string(let value) = field.value,
              value.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "=" }) else { return field.unredactedText }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }
}

/// The app-wide diagnostics log: events go to the system log and to a short in-memory ring buffer that backs
/// "Copy Diagnostics". Nothing is written to disk or sent anywhere.
final class AppDiagnostics: @unchecked Sendable {
    static let shared = AppDiagnostics()

    private let buffer: RingBufferDiagnosticLog
    let log: any DiagnosticLog
    private let appVersion: String
    private let appBuild: String
    private let now: @Sendable () -> Date

    init(capacity: Int = 500, extra: [any DiagnosticLog] = [], bundle: Bundle = .main, now: @escaping @Sendable () -> Date = { Date() }) {
        let buffer = RingBufferDiagnosticLog(capacity: capacity)
        self.buffer = buffer
        self.log = FanOutDiagnosticLog([OSLogDiagnosticLog(), buffer] + extra)
        self.appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        self.appBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        self.now = now
    }

    /// A plain-text report safe to share: private fields show `<private>`.
    func report() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        let header = [
            "TimeTug diagnostics",
            "App version: \(appVersion) (\(appBuild))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Generated: \(formatter.string(from: now()))",
            "",
        ]
        return (header + [buffer.render(includePrivate: false)]).joined(separator: "\n")
    }

    func clear() { buffer.clear() }
}
