import TimeTugKit
import XCTest
@testable import TimeTug

/// An engine whose first published state arrives only after `start()` returned, as the Rust engine's can.
private final class LateStateEngine: EngineHosting, @unchecked Sendable {
    let published: EngineState
    init(published: EngineState) { self.published = published }

    var states: AsyncStream<EngineState> {
        let published = published
        return AsyncStream { continuation in
            continuation.yield(.empty)   // the placeholder every new stream starts with
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                continuation.yield(published)
                continuation.finish()
            }
        }
    }
    var events: AsyncStream<EngineEvent> { AsyncStream { $0.finish() } }
    func start() async {}
    func send(_ command: EngineCommand) async {}
    func applySettings(_ change: (inout EngineSettings) -> Void) async {}
    func currentState() -> EngineState { .empty }
    func setTimeZone(_ identifier: String) throws {}
}

final class LaunchOnboardingTests: XCTestCase {
    private func state(takeoverCalendars: Set<String>) -> EngineState {
        var state = EngineState.empty
        state.revision = 1
        state.settings.takeover.takeoverCalendarKeys = takeoverCalendars
        return state
    }

    /// An existing user's selection is in the loaded state, not in the placeholder: no Calendars pane at launch.
    func testAnExistingSelectionLoadedAfterStartDoesNotOpenTheCalendarsPane() async {
        let engine = LateStateEngine(published: state(takeoverCalendars: ["eventkit/work"]))
        await engine.start()
        let opens = await AppCoordinator.opensCalendarsOnLaunch(engine)
        XCTAssertFalse(opens)
    }

    func testNoSelectionOpensTheCalendarsPane() async {
        let engine = LateStateEngine(published: state(takeoverCalendars: []))
        await engine.start()
        let opens = await AppCoordinator.opensCalendarsOnLaunch(engine)
        XCTAssertTrue(opens)
    }
}
