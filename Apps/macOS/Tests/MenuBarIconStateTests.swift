import AppKit
import TimeTugKit
import XCTest
@testable import TimeTug

final class MenuBarIconStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// The engine decides which event is next (calendar opt-in, all-day, declined, acknowledged, snoozed: its own
    /// tests cover those) and reports its start in `EngineState.nextPendingStart`; the icon only applies the window.
    private func resolve(startingIn offset: TimeInterval?) -> MenuBarIconState {
        MenuBarIconState.resolve(nextPendingStart: offset.map { now.addingTimeInterval($0) }, now: now)
    }

    func testNoPendingTakeoverIsIdle() { XCTAssertEqual(resolve(startingIn: nil), .idle) }
    func testThirtyMinutesAwayIsIdle() { XCTAssertEqual(resolve(startingIn: 30 * 60), .idle) }
    func testNineMinutesAwayIsSoon() { XCTAssertEqual(resolve(startingIn: 9 * 60), .soon) }
    func testExactlyTenMinutesIsSoon() { XCTAssertEqual(resolve(startingIn: 10 * 60), .soon) }
    func testElevenMinutesAwayIsIdle() { XCTAssertEqual(resolve(startingIn: 11 * 60), .idle) }
    func testInProgressUnacknowledgedIsSoon() { XCTAssertEqual(resolve(startingIn: -300), .soon) }

    @MainActor
    func testTheStateCarriesThePendingStartIntoTheIcon() {
        var state = EngineState.empty
        XCTAssertEqual(EngineModelMirror.iconState(state, now: now), .idle)
        state.nextPendingStart = now.addingTimeInterval(5 * 60)
        XCTAssertEqual(EngineModelMirror.iconState(state, now: now), .soon)
        // The pending start is kept while a takeover is on screen (`nextTakeover` is nil then): the icon stays color.
        state.takeoverVisible = true
        state.nextTakeover = nil
        XCTAssertEqual(EngineModelMirror.iconState(state, now: now), .soon)
    }

    func testIconAssetsExistInBundle() {
        XCTAssertNotNil(NSImage(named: "MenuBarColor"))
        XCTAssertNotNil(NSImage(named: "MenuBarTemplate"))
    }

    func testIdleUsesTheLightOrDarkPuppyForTheMenuBarAppearance() {
        XCTAssertEqual(MenuBarIconState.idle.assetName(darkMenuBar: false), "MenuBarPuppyLight")
        XCTAssertEqual(MenuBarIconState.idle.assetName(darkMenuBar: true), "MenuBarPuppyDark")
    }

    func testSoonUsesTheColorPuppyInEitherAppearance() {
        XCTAssertEqual(MenuBarIconState.soon.assetName(darkMenuBar: false), "MenuBarPuppyColor")
        XCTAssertEqual(MenuBarIconState.soon.assetName(darkMenuBar: true), "MenuBarPuppyColor")
    }

    func testPuppyIconAssetsExistInBundle() {
        for state in [MenuBarIconState.idle, .soon] {
            for dark in [false, true] {
                let name = state.assetName(darkMenuBar: dark)
                XCTAssertNotNil(NSImage(named: name), name)
            }
        }
    }
}
