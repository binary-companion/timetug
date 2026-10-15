import Foundation
import TimeTugEngine

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

    private struct Item {
        let command: EngineCommand
        let completion: (@MainActor @Sendable () -> Void)?
    }

    private let deliver: @Sendable (EngineCommand) async -> Void
    private var lanes: [Lane: AsyncStream<Item>.Continuation] = [:]

    init(deliver: @escaping @Sendable (EngineCommand) async -> Void) {
        self.deliver = deliver
    }

    /// `completion` runs on the main actor once the engine has handled the command.
    func send(_ command: EngineCommand, lane: Lane? = nil, completion: (@MainActor @Sendable () -> Void)? = nil) {
        let item = Item(command: command, completion: completion)
        guard let lane else {
            let deliver = deliver
            Task { @MainActor in
                await deliver(item.command)
                item.completion?()
            }
            return
        }
        continuation(for: lane).yield(item)
    }

    private func continuation(for lane: Lane) -> AsyncStream<Item>.Continuation {
        if let existing = lanes[lane] { return existing }
        let (stream, continuation) = AsyncStream.makeStream(of: Item.self)
        let deliver = deliver
        Task { @MainActor in
            for await item in stream {
                await deliver(item.command)
                item.completion?()
            }
        }
        lanes[lane] = continuation
        return continuation
    }
}
