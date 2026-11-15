import Foundation
import TimeTugKit

/// Which menu bar icon to show: the light/dark puppy, or the color puppy while a tug-worthy meeting is near.
enum MenuBarIconState: Equatable {
    case idle
    case soon

    /// The asset-catalog image for this state. The idle puppy has a light and a dark variant that keep their
    /// detail on light and dark menu bars; the color puppy reads on either, so `darkMenuBar` is ignored.
    func assetName(darkMenuBar: Bool) -> String {
        switch self {
        case .idle: darkMenuBar ? "MenuBarPuppyDark" : "MenuBarPuppyLight"
        case .soon: "MenuBarPuppyColor"
        }
    }

    /// How far ahead of the start the icon turns color.
    static let soonWindow: TimeInterval = 10 * 60

    /// `.soon` when the next pending takeover starts within `soonWindow` (or already started and not ended).
    /// `nextPendingStart` is the engine's `EngineState.nextPendingStart`: the start of the event the old scheduler
    /// returned, whether or not a takeover is on screen.
    static func resolve(nextPendingStart: Date?, now: Date) -> MenuBarIconState {
        guard let nextPendingStart, nextPendingStart.timeIntervalSince(now) <= soonWindow else { return .idle }
        return .soon
    }
}
