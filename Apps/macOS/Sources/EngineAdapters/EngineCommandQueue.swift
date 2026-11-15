import Foundation
import TimeTugKit

/// Sends commands to the engine from the main actor. Commands in the same lane reach the engine one after another,
/// in the order they were sent (a takeover's `takeoverPresented` before its close; two quick edits of one setting in
/// order). Lanes do not wait for each other, so a slow command (a setting that waits for the on-device model or the
/// calendar permission prompt) never holds up a takeover. Commands without a lane are sent at once, unordered.
@MainActor
final class EngineCommandQueue {
    enum Lane: Hashable {
        /// Takeover presentation and closing, and the test tug.
        case takeover
        /// Merge, unmerge, separate, forget corrections.
        case dedup
        /// `setCountdownVisible`.
        case countdown
        /// `settingsChangedExternally`.
        case externalSettings
        /// One behaviour setting (`takeover`, `inference`, `systemCalendar`).
        case behaviour(String)
    }

    /// A settings edit: applied to the engine's settings as they are when its turn comes (not when it was sent), so
    /// two quick edits of one setting compose in order.
    typealias SettingsChange = @Sendable (inout EngineSettings) -> Void

    private enum Work {
        case command(EngineCommand)
        case settings(SettingsChange)
    }

    private struct Item {
        let work: Work
        let completion: (@MainActor @Sendable () -> Void)?
    }

    private let deliver: @Sendable (EngineCommand) async -> Void
    private let deliverSettings: @Sendable (SettingsChange) async -> Void
    private var lanes: [Lane: AsyncStream<Item>.Continuation] = [:]

    init(
        deliver: @escaping @Sendable (EngineCommand) async -> Void,
        deliverSettings: @escaping @Sendable (SettingsChange) async -> Void = { _ in }
    ) {
        self.deliver = deliver
        self.deliverSettings = deliverSettings
    }

    /// `completion` runs on the main actor once the engine has handled the command.
    func send(_ command: EngineCommand, lane: Lane? = nil, completion: (@MainActor @Sendable () -> Void)? = nil) {
        enqueue(Item(work: .command(command), completion: completion), lane: lane)
    }

    /// Sends a settings edit (the engine's `applySettings { }`) on `lane`; `completion` as for `send`.
    func sendSettings(_ change: @escaping SettingsChange, lane: Lane, completion: (@MainActor @Sendable () -> Void)? = nil) {
        enqueue(Item(work: .settings(change), completion: completion), lane: lane)
    }

    private func enqueue(_ item: Item, lane: Lane?) {
        guard let lane else {
            let run = runner
            Task { @MainActor in await run(item) }
            return
        }
        continuation(for: lane).yield(item)
    }

    private var runner: @Sendable @MainActor (Item) async -> Void {
        let deliver = deliver
        let deliverSettings = deliverSettings
        return { item in
            switch item.work {
            case .command(let command): await deliver(command)
            case .settings(let change): await deliverSettings(change)
            }
            item.completion?()
        }
    }

    private func continuation(for lane: Lane) -> AsyncStream<Item>.Continuation {
        if let existing = lanes[lane] { return existing }
        let (stream, continuation) = AsyncStream.makeStream(of: Item.self)
        let run = runner
        Task { @MainActor in
            for await item in stream { await run(item) }
        }
        lanes[lane] = continuation
        return continuation
    }
}
