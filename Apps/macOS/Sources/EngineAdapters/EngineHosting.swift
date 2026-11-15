import Foundation
import TimeTugKit

/// What the coordinator needs from the engine. `ObservedEngine` is the real one; tests substitute a fake to check
/// what the coordinator sends and in which order.
protocol EngineHosting: AnyObject, Sendable {
    var states: AsyncStream<EngineState> { get }
    var events: AsyncStream<EngineEvent> { get }
    func start() async
    func send(_ command: EngineCommand) async
    /// `applySettings { $0.takeover.leadTime = 120 }` against the engine's latest settings.
    func applySettings(_ change: (inout EngineSettings) -> Void) async
    func currentState() -> EngineState
    /// Tells the engine the system time zone changed; follow with `.system(.timeZoneChanged)`.
    func setTimeZone(_ identifier: String) throws
}

extension ObservedEngine: EngineHosting {}

extension EngineState {
    /// The state before the engine's first publication (revision 0): nothing known about this Mac yet.
    static let empty = EngineState(
        revision: 0, agenda: .empty, events: [], calendars: [], statuses: [:], notices: [:],
        sourceNames: [:], candidates: [:], accounts: [], accountStatus: .empty,
        settings: EngineSettings(takeover: TakeoverSettings(), inferenceEnabled: false, systemCalendarEnabled: true),
        inferenceStatus: .noEngine, ledger: TakeoverLedger(keyCount: 0), nextTakeover: nil, takeoverVisible: false,
        nextPendingStart: nil, availableAccountKinds: [])
}

extension AccountStatus {
    static let empty = AccountStatus(
        accounts: [], isWorking: false, buildFailures: [:], errorMessage: nil, waitingStyle: .browser)
}

extension DayAgenda {
    /// No events today.
    static let empty = DayAgenda(items: [], next: nil)
}
