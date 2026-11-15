import Foundation

// The agenda snapshot the app writes to the App Group container and the widgets read. The widget extension links no
// engine, so these are plain Swift types. The file format is the one the Swift releases (1.x libraries) wrote: keys are
// the property names below and dates are ISO 8601 (`.iso8601` strategy, whole seconds, UTC). Do not change either.

/// One event as a widget needs it. Times are the ones shown to the user.
struct WidgetEvent: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let colorHex: String?
    let joinURL: URL?

    init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
         colorHex: String? = nil, joinURL: URL? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.colorHex = colorHex
        self.joinURL = joinURL
    }
}

/// The agenda the app hands to widgets: today plus the next days, already merged, filtered and sorted.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Days of events included, counting today.
    static let horizonDays = 3
    /// A snapshot older than this is treated as missing by widgets.
    static let maxAge: TimeInterval = 12 * 3600

    var generatedAt: Date
    var events: [WidgetEvent]

    init(generatedAt: Date, events: [WidgetEvent]) {
        self.generatedAt = generatedAt
        self.events = events
    }

    func isStale(now: Date) -> Bool {
        now.timeIntervalSince(generatedAt) > Self.maxAge
    }
}

extension WidgetSnapshot {
    /// The coding strategies of the file on disk.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
