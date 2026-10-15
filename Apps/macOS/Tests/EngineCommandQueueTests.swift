import TimeTugEngine
import XCTest
@testable import TimeTug

/// Records delivered commands; a command can be held to show that other lanes do not wait for it.
private actor Recorder {
    private(set) var delivered: [String] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var holding = false

    func hold() { holding = true }
    func release() { holding = false; gate?.resume(); gate = nil }

    func deliver(_ command: EngineCommand) async {
        let name = String(describing: command)
        if holding, name.hasPrefix("settingsChangedExternally") {
            await withCheckedContinuation { gate = $0 }
        }
        delivered.append(name)
    }
}

@MainActor
final class EngineCommandQueueTests: XCTestCase {
    func testOneLaneDeliversInOrderAndRunsTheCompletionAfterwards() async throws {
        let recorder = Recorder()
        let queue = EngineCommandQueue { await recorder.deliver($0) }
        var completed = false
        queue.send(.takeoverPresented(eventID: "a", onScreen: true), lane: .takeover)
        queue.send(.dismiss(eventID: "a"), lane: .takeover)
        queue.send(.testTug(title: "t", calendarTitle: "c"), lane: .takeover) { completed = true }
        try await waitUntil { completed }
        let delivered = await recorder.delivered
        XCTAssertEqual(delivered.count, 3)
        XCTAssertTrue(delivered[0].hasPrefix("takeoverPresented"))
        XCTAssertTrue(delivered[1].hasPrefix("dismiss"))
        XCTAssertTrue(delivered[2].hasPrefix("testTug"))
    }

    func testASlowLaneDoesNotHoldUpAnother() async throws {
        let recorder = Recorder()
        await recorder.hold()
        let queue = EngineCommandQueue { await recorder.deliver($0) }
        var takeoverDone = false
        queue.send(.settingsChangedExternally, lane: .externalSettings)
        queue.send(.dismiss(eventID: "a"), lane: .takeover) { takeoverDone = true }
        try await waitUntil { takeoverDone }
        var delivered = await recorder.delivered
        XCTAssertEqual(delivered.count, 1)
        XCTAssertTrue(delivered[0].hasPrefix("dismiss"))
        await recorder.release()
        for _ in 0..<200 where await recorder.delivered.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        delivered = await recorder.delivered
        XCTAssertEqual(delivered.count, 2)
    }
}
