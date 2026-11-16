import Foundation
import TimeTugKit

// The engine's widget snapshot (`TimeTugKit.WidgetSnapshot`, from the `widgetSnapshot` event) becomes the app-owned
// struct the widget extension also reads. In this module `WidgetSnapshot` and `WidgetEvent` are the app-owned types, so
// the engine ones are always written with the module name.

extension WidgetEvent {
    init(_ engine: TimeTugKit.WidgetEvent) {
        self.init(id: engine.id, title: engine.title, start: engine.start, end: engine.end,
                  isAllDay: engine.isAllDay, colorHex: engine.colorHex, joinURL: engine.joinUrl)
    }
}

extension WidgetSnapshot {
    init(_ engine: TimeTugKit.WidgetSnapshot) {
        self.init(generatedAt: engine.generatedAt, events: engine.events.map(WidgetEvent.init))
    }
}

extension WidgetSnapshotStore {
    /// Converts the engine's snapshot and writes it.
    func write(_ snapshot: TimeTugKit.WidgetSnapshot) throws {
        try write(WidgetSnapshot(snapshot))
    }
}
