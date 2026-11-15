import AppKit
import Foundation
import TimeTugKit

/// Reports what the system tells the app (wake, clock, time zone, day, network) to the engine. A time-zone change
/// first updates the engine's zone (`setTimeZone`), then sends the event so the recompute uses the new zone.
@MainActor
struct SystemEventRelay {
    let engine: any EngineHosting
    let commands: EngineCommandQueue
    var currentTimeZoneIdentifier: @Sendable () -> String = { TimeZone.autoupdatingCurrent.identifier }
    var onTimeZoneError: @Sendable (Error) -> Void = { _ in }

    func report(_ event: SystemEvent) {
        if event == .timeZoneChanged {
            do { try engine.setTimeZone(currentTimeZoneIdentifier()) } catch { onTimeZoneError(error) }
        }
        commands.send(.system(event))
    }

    /// Reports the system's own notifications: wake (from the workspace's center), and clock, time-zone and day changes
    /// (from `center`). Timers alone are not trusted: the engine recomputes after each of these.
    func observe(center: NotificationCenter = .default, workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
                 beforeReport: @escaping @MainActor @Sendable () -> Void = {}) {
        let report: @Sendable (SystemEvent) -> Void = { event in
            Task { @MainActor in
                beforeReport()
                self.report(event)
            }
        }
        workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in report(.wake) }
        let events: [(Notification.Name, SystemEvent)] = [
            (.NSSystemClockDidChange, .clockChanged), (.NSSystemTimeZoneDidChange, .timeZoneChanged),
            (.NSCalendarDayChanged, .dayChanged),
        ]
        for (name, event) in events {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in report(event) }
        }
    }
}
