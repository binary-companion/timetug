import AppKit
import TimeTugKit
import XCTest
@testable import TimeTug

/// Records, in order, what the coordinator asks of the engine.
private final class FakeEngine: EngineHosting, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    var failTimeZone = false

    var calls: [String] { lock.withLock { log } }
    private func note(_ line: String) { lock.withLock { log.append(line) } }

    var states: AsyncStream<EngineState> { AsyncStream { $0.finish() } }
    var events: AsyncStream<EngineEvent> { AsyncStream { $0.finish() } }
    func start() async { note("start") }
    func send(_ command: EngineCommand) async { note("send \(command)") }
    func applySettings(_ change: (inout EngineSettings) -> Void) async {
        var settings = EngineSettings(takeover: TakeoverSettings(), inferenceEnabled: false, systemCalendarEnabled: true)
        change(&settings)
        note("applySettings leadTime=\(settings.takeover.leadTime)")
    }
    func currentState() -> EngineState { .empty }
    func setTimeZone(_ identifier: String) throws {
        note("setTimeZone \(identifier)")
        if failTimeZone { throw FfiError.InvalidConfig(reason: "unknown zone") }
    }
}

@MainActor
final class SystemEventRelayTests: XCTestCase {
    private func makeRelay(_ engine: FakeEngine, zone: String = "Europe/Berlin",
                           onError: @escaping @Sendable (Error) -> Void = { _ in }) -> SystemEventRelay {
        let commands = EngineCommandQueue(
            deliver: { await engine.send($0) }, deliverSettings: { await engine.applySettings($0) })
        return SystemEventRelay(engine: engine, commands: commands, currentTimeZoneIdentifier: { zone }, onTimeZoneError: onError)
    }

    func testATimeZoneChangeUpdatesTheEnginesZoneBeforeTheEventIsSent() async throws {
        let engine = FakeEngine()
        makeRelay(engine, zone: "Asia/Tokyo").report(.timeZoneChanged)
        try await waitUntil { engine.calls.count == 2 }
        XCTAssertEqual(engine.calls, ["setTimeZone Asia/Tokyo", "send system(TimeTugKitGenerated.SystemEvent.timeZoneChanged)"])
    }

    func testAPostedTimeZoneNotificationSetsTheZoneThenSendsTheEvent() async throws {
        let engine = FakeEngine()
        let center = NotificationCenter(), workspace = NotificationCenter()
        var reloads = 0
        makeRelay(engine, zone: "Pacific/Auckland").observe(center: center, workspaceCenter: workspace, beforeReport: { reloads += 1 })
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        try await waitUntil { engine.calls.count == 2 }
        XCTAssertEqual(engine.calls, ["setTimeZone Pacific/Auckland", "send system(TimeTugKitGenerated.SystemEvent.timeZoneChanged)"])
        XCTAssertEqual(reloads, 1, "the shared settings are re-read before the event is reported")
    }

    func testWakeClockAndDayNotificationsAreReported() async throws {
        let engine = FakeEngine()
        let center = NotificationCenter(), workspace = NotificationCenter()
        makeRelay(engine).observe(center: center, workspaceCenter: workspace)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        center.post(name: .NSSystemClockDidChange, object: nil)
        center.post(name: .NSCalendarDayChanged, object: nil)
        try await waitUntil { engine.calls.count == 3 }
        XCTAssertEqual(Set(engine.calls.map { String($0.split(separator: ".").last ?? "") }), ["wake)", "clockChanged)", "dayChanged)"])
        XCTAssertFalse(engine.calls.contains { $0.hasPrefix("setTimeZone") })
    }

    func testOtherSystemEventsDoNotTouchTheTimeZone() async throws {
        let engine = FakeEngine()
        let relay = makeRelay(engine)
        for event in [SystemEvent.wake, .clockChanged, .dayChanged, .networkReturned, .displayChanged] { relay.report(event) }
        try await waitUntil { engine.calls.count == 5 }
        XCTAssertFalse(engine.calls.contains { $0.hasPrefix("setTimeZone") })
        XCTAssertEqual(engine.calls.count, 5)
    }

    func testARefusedZoneIsReportedAndTheEventIsStillSent() async throws {
        let engine = FakeEngine()
        engine.failTimeZone = true
        let reported = Locked<[String]>([])
        makeRelay(engine, onError: { error in reported.update { $0.append(String(describing: error)) } }).report(.timeZoneChanged)
        try await waitUntil { engine.calls.count == 2 }
        XCTAssertEqual(reported.get().count, 1)
        XCTAssertTrue(engine.calls[1].hasPrefix("send system"))
    }

    func testASettingsEditIsAppliedToTheSettingsAsTheyAreWhenItsTurnComes() async throws {
        let engine = FakeEngine()
        let commands = EngineCommandQueue(
            deliver: { await engine.send($0) }, deliverSettings: { await engine.applySettings($0) })
        var done = false
        commands.sendSettings({ $0.takeover.leadTime = 120 }, lane: .behaviour("takeover")) { done = true }
        try await waitUntil { done }
        XCTAssertEqual(engine.calls, ["applySettings leadTime=120.0"])
    }
}

/// A value several threads read and write.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func update(_ change: (inout Value) -> Void) { lock.withLock { change(&value) } }
}
