# Phase 3: TimeTugEngine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `TimeTugEngine` in `binary-companion/timetug-shared` and move the Mac app onto it with no change in behaviour.

**Architecture:** One `public actor Engine` owns account lifecycle, source reconcile and refresh, the calendar store, the takeover ledger and fire guard, dedup actions and inference, behaviour settings and widget snapshots. Hosts supply seams (storage, credentials, sign-in, HTTP, connectors, text generation, diagnostics); time comes from an injected `EngineClock` that defaults to the system clock. State and events leave through two `AsyncStream`s; commands arrive through one `EngineCommand` enum. The Mac app keeps presentation only.

**Tech Stack:** Swift 6 (SwiftPM, Swift Testing), Foundation only, `TimeTugCore`, `CalendarBridge`, `CalendarCore` from `calendar-connectors`. Mac side: XcodeGen, SwiftUI, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-15-phase-3-engine-design.md` (this repository). Parent: `docs/superpowers/specs/2026-10-09-windows-program-design.md` section 2.

## Where the work happens

- **Tasks 1 to 12** are in a clone of `https://github.com/binary-companion/timetug-shared` (branch per task group, pull requests to `main`). Clone it into the session scratchpad, never into the `timetug` worktree. Source for moved code is the Mac app at `Apps/macOS/Sources/` and `Packages/AppleIntelligenceInference/` in the `timetug` worktree (read-only for these tasks).
- **Tasks 13 and 14** are in the `timetug` worktree (`Apps/macOS`).
- Every merge to `timetug-shared` `main` releases a version through `release.yml` (the `semver:minor` label for feature pull requests, `semver:patch` for fixes) and the bump chain opens a "Bump timetug-shared to X.Y.Z" pull request in `timetug`; later bumps close earlier ones as superseded. That is expected churn, not a problem.

## Global Constraints

- Swift tools 6.0, `platforms: [.macOS(.v14)]`, no platform conditionals in `timetug-shared`.
- `TimeTugEngine` imports only `Foundation`, `TimeTugCore`, `CalendarBridge`, `CalendarCore` (and `Testing` in tests). No AppKit, Combine, OSLog, Network, WidgetKit, SwiftUI, Dispatch-based timers or `Timer`/`RunLoop`.
- Core never reads the clock: `now: Date` is passed in. In the engine the only clock read is through `EngineClock`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), failing test first.
- The engine produces no display strings.
- Data file names stay exactly `accounts.json`, `sync-state.json`, `takeover-ledger.json`, `dedup-state.json`; settings keys stay exactly `takeoverSettings.v1`, `dedupInference.v1`, `eventKitEnabled.v1`.
- The bounded resolve backstop stays `maxResolvePasses = 10`; periodic refresh stays 900 s; launch grace stays 120 s; the settings self-heal (300 s) stays in the Mac app.
- No behaviour change in the Mac app; its existing tests stay green except for tests of files that move (they move with them).
- Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; pull request descriptions end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Secrets are never printed. Reviews use the `deepseek-review` skill (never paste files into the DeepSeek MCP); verify every Critical or Important finding against the code before acting.

## Review Focus

Failure modes the spec implies that no single feature task exercises; each has a test in the named task.

1. **State files written by the current Mac app must load unchanged** (a ledger with snoozed and fired entries, a dedup state with lessons and verdicts, `accounts.json`, settings JSON with the legacy `disabled` and `skipSoloEvents` keys). Wrong: the user's snoozes, lessons or accounts silently reset. Tasks 2 and 11.
2. **Corrupt or unreadable state file** loads as empty with a `diagnostic` and never throws or overwrites an unreadable `accounts.json`. Tasks 2 and 5.
3. **A second takeover while one is visible** waits and is not marked fired; closing the first re-arms and fires the second. Task 9.
4. **Wake after sleeping past a meeting start** presents once ("late after wake"), never twice, and not for an event that already ended. Task 9.
5. **A source that fails or is removed mid-refresh** keeps the others running and never resurrects removed sources' events. Tasks 5 and 8.
6. **Inference unavailable, then available** keeps pairs pending without a retry loop and resolves them when it returns; a throwing generator yields "no verdict". Task 10.
7. **Out-of-order or stale state revisions**: the published revision never decreases and a late publication from an old refresh is dropped. Task 8.
8. **Cancelling a sign-in** discards secrets that no stored account owns and leaves existing accounts untouched. Task 5.

---

## File structure (timetug-shared)

```
Package.swift                                   modify: add TimeTugEngine + TimeTugEngineTests
Sources/TimeTugEngine/
  EngineClock.swift                             protocol, SystemClock
  DiagnosticEvent.swift                         diagnostic value + sink typealias
  EngineHost.swift                              seams bundled
  EngineSettings.swift                          behaviour settings + SettingsStorage + InMemorySettingsStorage
  EngineCommand.swift  EngineState.swift  EngineEvent.swift
  Persistence/JSONFile.swift                    load/save helper (atomic, corruption -> diagnostic)
  Persistence/LedgerStore.swift  Persistence/DedupStateStore.swift
  Scheduling/LaunchAcknowledgement.swift  Scheduling/UITickPolicy.swift
  Accounts/SourceRefreshCoordinator.swift  Accounts/SourceReconciler.swift  Accounts/AccountManager.swift
  Inference/TextGenerator.swift  Inference/PromptBuilder.swift  Inference/TextGeneratorAdjudicator.swift
  Engine.swift                                  the actor
Tests/TimeTugEngineTests/
  Support/ManualClock.swift  Support/Fakes.swift   fakes shared by all tests
  (one test file per source file) + ConformanceTests.swift + LegacyFixtureTests.swift
  Fixtures/                                     files copied from a real Mac install's formats (synthetic data)
```

---

### Task 1: Module skeleton, clock, diagnostics, architecture rule

**Files:**
- Modify: `Package.swift`, `scripts/ci/check-architecture.sh`, `scripts/ci/count-swift-tests.py` only if it hard-codes target names (read it first)
- Create: `Sources/TimeTugEngine/EngineClock.swift`, `Sources/TimeTugEngine/DiagnosticEvent.swift`
- Create: `Tests/TimeTugEngineTests/Support/ManualClock.swift`, `Tests/TimeTugEngineTests/EngineClockTests.swift`

**Interfaces:**
- Produces: `protocol EngineClock: Sendable { func now() -> Date; func sleep(until: Date) async throws }`; `struct SystemClock: EngineClock`; test-only `final class ManualClock: EngineClock, @unchecked Sendable` with `init(start: Date)`, `advance(by: TimeInterval) async`, `pendingSleeps: Int`; `struct DiagnosticEvent: Sendable, Equatable { enum Level { case info, warning, error }; var level: Level; var category: String; var message: String }`; `typealias DiagnosticSink = @Sendable (DiagnosticEvent) -> Void`.

- [ ] **Step 1: Clone and baseline**

```bash
cd "$SCRATCH" && git clone https://github.com/binary-companion/timetug-shared.git && cd timetug-shared
git checkout -b engine/skeleton
swift build --build-tests 2>&1 | tail -3 && swift test 2>&1 | tail -3
```
Expected: build and tests pass (the baseline count is recorded for the count guard).

- [ ] **Step 2: Write the failing test** `Tests/TimeTugEngineTests/EngineClockTests.swift`

```swift
import Foundation
import Testing
@testable import TimeTugEngine

@Suite struct EngineClockTests {
    @Test func manualClockWakesSleepersOnlyWhenDeadlinePasses() async throws {
        let clock = ManualClock(start: Date(timeIntervalSince1970: 1_000))
        let woke = LockedBox(false)
        let task = Task {
            try await clock.sleep(until: Date(timeIntervalSince1970: 1_060))
            woke.set(true)
        }
        await clock.waitForSleepers(1)
        await clock.advance(by: 30)
        #expect(woke.get() == false)
        await clock.advance(by: 30)
        try await task.value
        #expect(woke.get() == true)
        #expect(clock.now() == Date(timeIntervalSince1970: 1_060))
    }

    @Test func manualClockReturnsImmediatelyForPastDeadline() async throws {
        let clock = ManualClock(start: Date(timeIntervalSince1970: 1_000))
        try await clock.sleep(until: Date(timeIntervalSince1970: 900))
    }

    @Test func cancelledSleepThrows() async {
        let clock = ManualClock(start: Date(timeIntervalSince1970: 0))
        let task = Task { try await clock.sleep(until: Date(timeIntervalSince1970: 100)) }
        await clock.waitForSleepers(1)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func systemClockSleepsUntilDeadline() async throws {
        let clock = SystemClock()
        let start = Date()
        try await clock.sleep(until: start.addingTimeInterval(0.05))
        #expect(Date().timeIntervalSince(start) >= 0.04)
    }
}
```

- [ ] **Step 3: Run it to verify it fails** — `swift test --filter EngineClockTests` → FAIL (module `TimeTugEngine` missing).

- [ ] **Step 4: Implement.** `Package.swift`: add `.library(name: "TimeTugEngine", targets: ["TimeTugEngine"])`, target `TimeTugEngine` depending on `TimeTugCore`, `CalendarBridge` and `.product(name: "CalendarCore", package: "calendar-connectors")`, and `testTarget` `TimeTugEngineTests` depending on the same plus `TimeTugEngine`.

`Sources/TimeTugEngine/EngineClock.swift`:

```swift
import Foundation

/// The only place the engine reads time. Hosts normally do not supply one; tests supply a manual clock.
public protocol EngineClock: Sendable {
    func now() -> Date
    /// Returns when `now()` reaches `deadline`; returns at once for a past deadline; throws `CancellationError` if cancelled.
    func sleep(until deadline: Date) async throws
}

public struct SystemClock: EngineClock {
    public init() {}
    public func now() -> Date { Date() }
    public func sleep(until deadline: Date) async throws {
        let seconds = deadline.timeIntervalSinceNow
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
```

`Sources/TimeTugEngine/DiagnosticEvent.swift`:

```swift
import Foundation

public struct DiagnosticEvent: Sendable, Equatable {
    public enum Level: String, Sendable { case info, warning, error }
    public var level: Level
    public var category: String
    /// Never contains event titles or other calendar content.
    public var message: String
    public init(level: Level, category: String, message: String) {
        self.level = level; self.category = category; self.message = message
    }
}

public typealias DiagnosticSink = @Sendable (DiagnosticEvent) -> Void
```

`Tests/TimeTugEngineTests/Support/ManualClock.swift`: an `actor`-free lock-based class holding `current: Date` and `[(id: UUID, deadline: Date, continuation: CheckedContinuation<Void, Error>)]`. `sleep` registers a continuation inside `withTaskCancellationHandler` (cancel removes the waiter and resumes it throwing `CancellationError`); `advance(by:)` sets `current += interval`, collects waiters with `deadline <= current`, resumes them (outside the lock) and then `await Task.yield()` three times so woken tasks run; `waitForSleepers(_ n: Int) async` loops `await Task.yield()` until `pendingSleeps >= n` (bounded at 10_000 iterations, then `Issue.record`). Also add `final class LockedBox<T: Sendable>: @unchecked Sendable` with `get()`/`set(_:)` in `Support/Fakes.swift`.

- [ ] **Step 5: Add the architecture rule.** Read `scripts/ci/check-architecture.sh` and its test under `scripts/ci/tests`; add a rule that `Sources/TimeTugEngine` may import only `Foundation CalendarCore TimeTugCore CalendarBridge TimeTugEngine`, and a test case that a file importing `AppKit` there fails. Update `AGENTS.md` Rules section with one line.

- [ ] **Step 6: Verify**

```bash
swift test --filter EngineClockTests 2>&1 | tail -5
scripts/ci/check-architecture.sh && python3 -m unittest discover scripts/ci/tests 2>&1 | tail -3
```
Expected: PASS, architecture check passes.

- [ ] **Step 7: Commit and open the pull request** (title "Add the TimeTugEngine module skeleton, clock and architecture rule", label `semver:minor`). Wait for the five checks; fix with new commits; merge when green (owner's standing authorization, 2026-10-15).

---

### Task 2: Persistence and settings seam

**Files:**
- Create: `Sources/TimeTugEngine/Persistence/JSONFile.swift`, `Persistence/LedgerStore.swift`, `Persistence/DedupStateStore.swift`, `EngineSettings.swift`
- Create: `Tests/TimeTugEngineTests/Persistence/LedgerStoreTests.swift`, `DedupStateStoreTests.swift`, `EngineSettingsTests.swift`, `Fixtures/` (see below)
- Source to port: `Apps/macOS/Sources/LedgerStore.swift`, `Apps/macOS/Sources/DedupStateStore.swift`, their tests `Apps/macOS/Tests*/LedgerStoreTests.swift`, `DedupStateStoreTests.swift`

**Interfaces:**
- Consumes: `DiagnosticSink` (Task 1), `TakeoverLedger`, `DedupState`, `TakeoverSettings` (Core).
- Produces:
  - `struct JSONFile<Value: Codable>` with `init(url: URL, diagnostics: @escaping DiagnosticSink, label: String)`, `func load() -> Value?` (nil when missing, unreadable, or corrupt; corruption emits a `.warning` diagnostic and never throws) and `@discardableResult func save(_ value: Value) -> Bool` (creates the directory, writes atomically, emits an `.error` diagnostic on failure).
  - `struct LedgerStore` with `init(directory: URL, diagnostics:)`, `func load() -> TakeoverLedger`, `@discardableResult func save(_: TakeoverLedger, now: Date) -> Bool` (prunes first; same semantics as the Mac file).
  - `struct DedupStateStore` with `init(directory:diagnostics:)`, `func load() -> DedupState`, `@discardableResult func save(_: DedupState) -> Bool`.
  - `public struct EngineSettings: Equatable, Sendable { public var takeover: TakeoverSettings; public var inferenceEnabled: Bool; public var systemCalendarEnabled: Bool; public init(takeover: TakeoverSettings = .init(), inferenceEnabled: Bool = false, systemCalendarEnabled: Bool = true) }`.
  - `public protocol SettingsStorage: Sendable { func load() -> EngineSettings; func save(_ settings: EngineSettings) }` and `public final class InMemorySettingsStorage: SettingsStorage, @unchecked Sendable` (init with initial value; `saved: [EngineSettings]` history for tests).

- [ ] **Step 1: Create synthetic fixtures** in `Tests/TimeTugEngineTests/Fixtures/`: `takeover-ledger.json` and `dedup-state.json`. Produce them by running the existing Mac encoders: a throwaway test in the `timetug` worktree (not committed) that builds a `TakeoverLedger` with one fired and one snoozed entry and a `DedupState` with one lesson and one verdict, and writes `JSONEncoder().encode(...)` output; copy the output files in. Add `settings-legacy.json` by hand: `{"disabled":true,"skipSoloEvents":true,"leadTime":120}` (Core already decodes these legacy keys). Add the fixtures as test-target `resources: [.copy("Fixtures")]` in `Package.swift`. Fixtures contain no real titles.

- [ ] **Step 2: Write failing tests.** Port `LedgerStoreTests` and `DedupStateStoreTests` from the Mac test files (same assertions; replace the URL-based init with `directory:` and the logging assertions with a captured diagnostic list). Add:

```swift
@Test func loadsLedgerWrittenByTheMacApp() throws {
    let dir = try TempDir.make(copying: "takeover-ledger.json")
    let ledger = LedgerStore(directory: dir, diagnostics: { _ in }).load()
    #expect(ledger.keyCount == 2)
}

@Test func corruptLedgerLoadsEmptyAndEmitsDiagnostic() throws {
    let dir = try TempDir.make()
    try Data("{not json".utf8).write(to: dir.appendingPathComponent("takeover-ledger.json"))
    let events = LockedBox<[DiagnosticEvent]>([])
    let ledger = LedgerStore(directory: dir, diagnostics: { e in events.mutate { $0.append(e) } }).load()
    #expect(ledger.keyCount == 0)
    #expect(events.get().contains { $0.level == .warning && $0.category == "ledger" })
}

@Test func legacySettingsKeysCarryForward() throws {
    let data = try Data(contentsOf: Fixtures.url("settings-legacy.json"))
    let settings = try JSONDecoder().decode(TakeoverSettings.self, from: data)
    #expect(settings.enabled == false)
    #expect(settings.requireOtherAttendees == true)
    #expect(settings.leadTime == 120)
}
```
`TempDir` and `Fixtures` are small helpers in `Support/Fakes.swift` (add them in this task).

- [ ] **Step 3: Run to verify failure** — `swift test --filter "LedgerStoreTests|DedupStateStoreTests|EngineSettingsTests"` → FAIL (types missing).

- [ ] **Step 4: Implement** by copying the two Mac stores and replacing `TakeoverLog`/`Logger` calls with the diagnostic sink (messages: "ledger could not be read", "ledger could not be written", "dedup state could not be read", "dedup state could not be written"; the error's type name only, never its description if it can embed content). `JSONFile` factors the shared load/save. File names are fixed constants: `takeover-ledger.json`, `dedup-state.json`.

- [ ] **Step 5: Verify** — `swift test --filter "LedgerStoreTests|DedupStateStoreTests|EngineSettingsTests"` PASS, then full `swift test`.

- [ ] **Step 6: Commit** `git commit -m "Engine: ledger, dedup state and settings seams with Mac-compatible files"`; include in the Task 1 follow-up pull request or open a new one (`semver:minor`).

---

### Task 3: Scheduling helpers

**Files:**
- Create: `Sources/TimeTugEngine/Scheduling/LaunchAcknowledgement.swift`, `Scheduling/UITickPolicy.swift`
- Create: `Tests/TimeTugEngineTests/Scheduling/LaunchAcknowledgementTests.swift`, `UITickPolicyTests.swift`
- Source to port: `Apps/macOS/Sources/LaunchAcknowledgement.swift`, `UITickPolicy.swift` and their tests

**Interfaces:**
- Produces: `struct LaunchAcknowledgement` (exactly today's API: `init(launchedAt:)`, `mutating registerSources(_:now:)`, `mutating eventsToAcknowledge(in: CalendarSnapshot, now:, grace:) -> [TimeTugCalendarEvent]`); `enum UITickPolicy` with `struct Wake { let date: Date; let rebuildAgenda: Bool }` and `static func next(now: Date, countdownVisible: Bool, nextEvent: TimeTugCalendarEvent?, events: [TimeTugCalendarEvent], leadTime: TimeInterval, calendar: Calendar) -> Wake?`.

- [ ] **Step 1:** Port both test files unchanged except `mode: .iconOnly` becomes `countdownVisible: false` and `mode: .nextMeeting`/`.countdown` becomes `countdownVisible: true` (the presentation mode is a Mac type; the engine only needs to know whether second-level ticks are wanted — `mode != .iconOnly` today).
- [ ] **Step 2:** `swift test --filter "LaunchAcknowledgementTests|UITickPolicyTests"` → FAIL.
- [ ] **Step 3:** Copy the two implementations; change the `mode: MenuBarDisplayMode` parameter and the line `if mode != .iconOnly, let nextEvent, ...` to `if countdownVisible, let nextEvent, ...`. Make both types `public` only if used across modules (they are internal to the engine; keep them internal and use `@testable import`).
- [ ] **Step 4:** Run the tests → PASS; full `swift test`.
- [ ] **Step 5:** Commit "Engine: launch acknowledgement and UI tick policy".

---

### Task 4: Source refresh coordinator and reconciler

**Files:**
- Create: `Sources/TimeTugEngine/Accounts/SourceRefreshCoordinator.swift`, `Accounts/SourceReconciler.swift`
- Create: `Tests/TimeTugEngineTests/Accounts/SourceRefreshCoordinatorTests.swift`, `SourceReconcilerTests.swift`
- Source to port: `Apps/macOS/Sources/SourceRefreshCoordinator.swift`, `SourceReconciler.swift` and their tests

**Interfaces:**
- Produces: `actor SourceRefreshCoordinator` with `init(refresh: @escaping @Sendable (Set<String>?) async -> Void)` and `func signal(_ change: SourceChange)`; `actor SourceReconciler` with `struct Update { let sources: [any TimeTugCore.CalendarSource]; let failures: [ConnectionID: String] }`, `init(buildAccount: @escaping @Sendable (Connection) throws -> any TimeTugCore.CalendarSource, buildSystemSource: @escaping @Sendable () -> any TimeTugCore.CalendarSource, onChange: @escaping @Sendable (SourceChange) async -> Void)`, `func sourceID(forConnection:) -> String?`, `func reconcile(connections:systemCalendarEnabled:) -> Update`, `func rebuild(_:connections:systemCalendarEnabled:) -> Update`, `func stop()`.

- [ ] **Step 1:** Port the two Mac test files. They are `@MainActor`; change them to `async` tests on the actors. Keep every scenario (burst coalescing, one follow-up pass, failed build keeps the old source on rebuild, removed source's listener cancelled, system source key).
- [ ] **Step 2:** `swift test --filter "SourceRefreshCoordinatorTests|SourceReconcilerTests"` → FAIL.
- [ ] **Step 3:** Port the implementations, replacing `@MainActor final class` with `actor` and `Task { @MainActor in ... }` with `Task { ... }`. Rename `eventKit*` to `system*` (`buildSystemSource`, `systemCalendarEnabled`, key `"\u{0}system"`). Keep the "Task.isCancelled" guard before `onChange`.
- [ ] **Step 4:** Tests PASS; full `swift test` on macOS; push the branch and confirm the Linux and Windows jobs pass (actors and `AsyncStream` must behave the same there).
- [ ] **Step 5:** Commit "Engine: source refresh coordinator and reconciler".

---

### Task 5: AccountManager

**Files:**
- Create: `Sources/TimeTugEngine/Accounts/AccountManager.swift`, `Sources/TimeTugEngine/EngineHost.swift`
- Create: `Tests/TimeTugEngineTests/Accounts/AccountManagerTests.swift`, `Support/Fakes.swift` additions
- Source to port: `Apps/macOS/Sources/AccountsController.swift`, `Apps/macOS/Tests*/AccountsControllerTests.swift` (the logic cases; SwiftUI-state cases stay behind)

**Interfaces:**
- Consumes: `FileConnectionStore`, `ConnectorRegistry`, `CredentialStore`, `SyncStateStore`, `AuthorizationInteraction`, `ConnectorKind`, `CredentialPromptHelp` (CalendarCore); `SourceReconciler` (Task 4); `EngineSettings` (Task 2).
- Produces:
  - `public protocol SignInPrompting: Sendable { func prepare(title: String, help: CredentialHelp?, values: [String: String], error: String?) async; func lastNonSecretValues() async -> [String: String]? }` (the engine's view of the Mac `CredentialPrompter`; Windows implements the same).
  - `public struct EngineHost: Sendable` with the fields from the spec table: `dataDirectory: URL`, `settings: any SettingsStorage`, `credentials: any CredentialStore`, `interaction: any AuthorizationInteraction`, `signIn: any SignInPrompting`, `registry: ConnectorRegistry`, `unconfiguredKindIDs: [String]`, `buildSystemSource: (@Sendable () -> any TimeTugCore.CalendarSource)?`, `requestSystemAccess: (@Sendable () async -> Void)?`, `textGenerator: (any TextGenerator)?` (Task 6), `diagnostics: DiagnosticSink`, `clock: any EngineClock = SystemClock()`, `calendar: @Sendable () -> Calendar = { .current }`.
  - `actor AccountManager` with `init(host: EngineHost, reconciler: SourceReconciler, applySources: @escaping @Sendable ([any TimeTugCore.CalendarSource]) async -> Void, updateSettings: @escaping @Sendable ((inout EngineSettings) -> Void) async -> Void)`, `struct Status: Equatable, Sendable { var accounts: [Connection]; var isWorking: Bool; var buildFailures: [ConnectionID: String]; var errorMessage: String?; var waitingStyle: WaitingStyle }` with `enum WaitingStyle { case browser, inApp }`, and `func status() -> Status`, `func start() async`, `func addAccount(kindID:) async`, `func removeAccount(connectionID:) async`, `func reauthorize(connectionID:) async`, `func cancelAuthorization()`, `func setSystemCalendarEnabled(_:) async`, `func statusKey(for: Connection) -> String`.

- [ ] **Step 1: Write failing tests** with a `FakeConnectorKind` (configurable: authorization method, outcome, a counter of `makeSource` calls) and `FakeSource: CalendarSource`. Cover, each as its own `@Test`: add account stores the connection and applies sources; duplicate display name is rejected and its fresh secrets removed; cancelling a sign-in removes secrets not owned by a stored account (Review Focus 8); removal order (stored connection first, then source, then selections, then secrets and sync state) via a call log; removal failure of secrets sets the "could not be deleted" message but the account is gone; reauthorize replaces the account and rebuilds its source; reauthorize as a different account surfaces the error and leaves the old account; unreadable `accounts.json` loads none, shows the message and never writes (Review Focus 2: assert file bytes unchanged); orphaned selections are swept for known kind prefixes only; system calendar toggle off keeps stored selections; the password retry loop re-prompts with the error and the typed non-secret values until success or cancel.

```swift
@Test func cancelledSignInDiscardsUnownedSecrets() async throws {
    let credentials = InMemoryCredentialStore()
    let kind = FakeConnectorKind(id: "fake", outcome: .succeedThenCancel(connectionID: "c1"))
    let harness = try await AccountHarness(kinds: [kind], credentials: credentials)
    await harness.manager.addAccount(kindID: "fake")
    #expect(try await credentials.secrets(for: "c1") == nil)
    #expect(await harness.manager.status().accounts.isEmpty)
}
```
(`AccountHarness` builds an `EngineHost` with temp directory, in-memory stores and a recording `applySources`.)

- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3: Implement** by porting `AccountsController`: `@MainActor ObservableObject` becomes `actor`; `@Published` properties become the `Status` value returned by `status()`; `settings.takeover.removeCalendars(...)`/`settings.eventKitEnabled` go through `updateSettings`/a settings snapshot closure; `signIn(with:)` uses `host.signIn` (`prepare`, `lastNonSecretValues`); `describe(_:)` and `describeSignIn(_:fields:)` stay (they produce the error strings the Accounts pane shows today — moved verbatim, it is the one place the engine carries user-facing text, kept because the sign-in error is part of the retry loop; the Mac pane displays `errorMessage` as given). `requestEventKitAccess` becomes `host.requestSystemAccess`.
- [ ] **Step 4:** Tests PASS; full suite; push and watch the Linux and Windows jobs.
- [ ] **Step 5:** Commit "Engine: account lifecycle (AccountManager) and the host seam bundle".

---

### Task 6: Inference seam, prompt builder, adjudicator

**Files:**
- Create: `Sources/TimeTugEngine/Inference/TextGenerator.swift`, `Inference/PromptBuilder.swift`, `Inference/TextGeneratorAdjudicator.swift`
- Create: `Tests/TimeTugEngineTests/Inference/PromptBuilderTests.swift`, `TextGeneratorAdjudicatorTests.swift`
- Source to port: `Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/PromptBuilder.swift` and `Packages/AppleIntelligenceInference/Tests/.../PromptBuilderTests.swift`; the loop in `AppleIntelligence.swift` (`FoundationModelsAdjudicator.judge`)

**Interfaces:**
- Produces:

```swift
public enum TextGeneratorAvailability: Equatable, Sendable {
    case available(EngineInfo)
    case unavailable(reason: String)      // permanent for now: not supported, not enabled, model not ready
    case temporarilyUnavailable(reason: String)   // e.g. energy saver; pairs stay pending
}

public protocol TextGenerator: Sendable {
    var availability: TextGeneratorAvailability { get async }
    /// Returns the model's one-word answer for `prompt` given `instructions`. Throws on failure or cancellation.
    func generate(instructions: String, prompt: String) async throws -> String
}
```
and `struct TextGeneratorAdjudicator: DuplicateAdjudicator` with `init(generator: any TextGenerator, clock: any EngineClock, timeZone: @Sendable () -> TimeZone)`, a per-call deadline of 30 s and `prefix(20)` requests as today.

Core's `DuplicateAdjudicator.availability` is synchronous (`var availability: AdjudicatorAvailability { get }`), but `TextGenerator.availability` is async (a host may need to ask a service). The adjudicator therefore caches the last value in a small lock-protected box that `refreshAvailability() async` updates; the engine calls it before `inferenceStatus()` and each resolve pass. `.temporarilyUnavailable` maps to `AdjudicatorAvailability.unavailable(reason:)` with the reason prefixed `"temporary: "` so the engine can tell the two apart (Core has no separate case; check `AdjudicatorAvailability` in `Adjudication.swift` and map accordingly without changing Core).

- [ ] **Step 1:** Port `PromptBuilderTests` unchanged (the builder is pure). Add adjudicator tests with a `FakeTextGenerator` scripted with answers: parses `same`, `different`, `unsure`, trims whitespace and lowercases; an unparseable answer yields no verdict for that request and the others still resolve; a throwing generator yields no verdict and logs a diagnostic with the error type name only; cancellation stops the loop; the 30-second deadline uses the injected clock (ManualClock) and stops after the deadline; `temporarilyUnavailable` makes `judge` return `[]` without calling the generator (Review Focus 6).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Copy `PromptBuilder` verbatim (it uses `DateFormatter`, available in swift-corelibs-foundation; if a Windows job disagrees on `en_US_POSIX` formatting, record it and use `Calendar`/`ISO8601`-free manual formatting — verify on the Windows jobs). Implement the adjudicator: build `PromptBuilder.prompt(for:timeZone:)`, call `generate`, map the trimmed lowercase answer to `AdjudicationVerdict.Answer(rawValue:)`.
- [ ] **Step 4:** Tests PASS; push; confirm the Windows x64 and ARM64 jobs pass the prompt tests (formatter locale behavior).
- [ ] **Step 5:** Commit "Engine: text generation seam, prompt builder and adjudicator".

---

### Task 7: Commands, state and events

**Files:**
- Create: `Sources/TimeTugEngine/EngineCommand.swift`, `EngineState.swift`, `EngineEvent.swift`
- Create: `Tests/TimeTugEngineTests/EngineTypesTests.swift`

**Interfaces:**
- Produces (all `public`, `Sendable`):

```swift
public enum SystemEvent: Equatable, Sendable { case wake, clockChanged, timeZoneChanged, dayChanged, networkReturned, displayChanged }

public enum EngineCommand: Sendable {
    case start
    case refresh
    case addAccount(kindID: String)
    case removeAccount(connectionID: String)
    case reauthorizeAccount(connectionID: String)
    case cancelAuthorization
    case applySettings(@Sendable (inout EngineSettings) -> Void)
    case settingsChangedExternally
    case setCountdownVisible(Bool)
    case takeoverPresented(eventID: String, onScreen: Bool)   // onScreen false = fallback toast
    case takeoverClosed(eventID: String)
    case join(eventID: String)
    case snooze(eventID: String, seconds: TimeInterval)
    case dismiss(eventID: String)
    case testTug
    case merge(TimeTugCalendarEvent, TimeTugCalendarEvent)
    case unmerge(TimeTugCalendarEvent)
    case separate(TimeTugCalendarEvent, members: [MergedMember])
    case forgetCorrections
    case system(SystemEvent)
    case stop
}

public struct EngineState: Sendable {
    public var revision: UInt64
    public var agenda: DayAgenda
    public var events: [TimeTugCalendarEvent]
    public var calendars: [CalendarInfo]
    public var statuses: [String: SourceStatus]
    public var notices: [String: [CalendarCore.SourceNotice]]
    public var sourceNames: [String: String]
    public var candidates: [String: [TimeTugCalendarEvent]]
    public var accounts: [Connection]
    public var accountStatus: AccountManager.Status   // made public in this task
    public var settings: EngineSettings
    public var inferenceStatus: InferenceStatus
    public var ledger: TakeoverLedger
    public var nextTakeover: ScheduledTakeover?
    public var takeoverVisible: Bool
    public static let empty: EngineState
}

public enum EngineEvent: Sendable {
    case takeoverDue(TakeoverRequest, calendarTitle: String?)
    case takeoverWithdrawn(eventID: String)
    case widgetSnapshot(WidgetSnapshot)
    case joinRequested(URL)
    case diagnostic(DiagnosticEvent)
}
```

`takeoverClosed`, `join`, `snooze` and `dismiss` carry the event's `id` (`TimeTugCalendarEvent.id`). `join` makes the engine emit `.joinRequested(url)` (the host opens it with its own safe-open policy) and close the takeover; `testTug` emits a `takeoverDue` for a synthetic sample event and never touches the ledger.

- [ ] **Step 1:** Write a test that constructs one of every command and event and an `EngineState.empty` (compile-level contract) and asserts `EngineState.empty.revision == 0`, `agenda == .empty`.
- [ ] **Step 2:** FAIL → **Step 3:** implement the types (make `AccountManager.Status` and `WaitingStyle` public) → **Step 4:** PASS.
- [ ] **Step 5:** Commit "Engine: command, state and event types".

---

### Task 8: Engine actor, part 1 — start, refresh, publish

**Files:**
- Create: `Sources/TimeTugEngine/Engine.swift`
- Create: `Tests/TimeTugEngineTests/EngineRefreshTests.swift`, `Support/EngineHarness.swift`
- Source of behaviour: `AppCoordinator.start()`, `refresh(sourceIDs:)`, `apply(_:)`, `periodicRefresh`, `launchGrace`

**Interfaces:**
- Consumes: Tasks 2 to 7.
- Produces: `public actor Engine { public init(host: EngineHost); public var states: AsyncStream<EngineState> { get }; public var events: AsyncStream<EngineEvent> { get }; public func start() async; public func send(_ command: EngineCommand) async; public func currentState() -> EngineState }`. `states` is a latest-value stream (buffering policy `.bufferingNewest(1)`); a new subscriber receives the current state first. `events` buffers `.unbounded`.

- [ ] **Step 1: Failing tests** in `EngineRefreshTests` using `EngineHarness` (ManualClock, `InMemorySettingsStorage`, fake connector kind registered under id `"fake"` whose source returns scripted events, temp data directory, captured diagnostics):
  1. `start` loads state, builds sources, refreshes once and publishes a state with the day's agenda and `statuses["fake-c1"] == .ok`.
  2. A source `eventsChanged(sourceID:calendarIDs:)` signal triggers one refresh limited to that source id; a burst of three signals while a refresh is running causes exactly one follow-up pass (count `events(in:)` calls).
  3. The periodic refresh (900 s) fires through `ManualClock.advance(by: 900)`.
  4. Published revisions are strictly increasing, and a publication whose `CalendarSnapshot.revision` is not greater than the last is dropped (Review Focus 7): drive it by completing two overlapping refreshes in reverse order with a gated fake source.
  5. Launch acknowledgement: a meeting that started 10 minutes before launch is marked fired in the ledger when its source first reports `.ok`, and no `takeoverDue` is emitted for it; a meeting that started 30 seconds before launch (inside the 120 s grace) is not acknowledged.
  6. A failing source keeps its last good events and status `.failing`; removing the account mid-refresh does not resurrect its events (Review Focus 5).
  7. The ledger is persisted after acknowledgement and survives a new `Engine` over the same directory.

```swift
@Test func startPublishesAgendaAndOkStatus() async throws {
    let h = try await EngineHarness(events: [.sample(id: "e1", startsIn: 600)])
    await h.engine.send(.start)
    let state = await h.waitForState { $0.statuses["fake-c1"] == .ok }
    #expect(state.agenda.items.count == 1)
    #expect(state.revision > 0)
}
```

- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3: Implement.** The actor holds: `store: CalendarStore` (created with `adjudicator`, `calendar: host.calendar()`, `passClock: { host.clock.now() }`), `settings: EngineSettings` (loaded from `host.settings`), `ledger`, `launchAcknowledgement`, the `SourceReconciler`/`SourceRefreshCoordinator`/`AccountManager` trio, `snapshot`, `revision`, stream continuations, and a `periodicTask`. `start()`: load ledger (prune, persist), load dedup state into the store, set inference, start the account manager (it applies sources and refreshes), arm the periodic refresh with `host.clock.sleep(until:)` in a loop. `refresh(sourceIDs:)` calls `store.refresh(now: clock.now(), leadTime: settings.takeover.leadTime, sourceIDs:, onPublication: { await self.apply($0) })`, then applies the result, then starts inference resolution in a detached child `Task` (Task 10). `apply(_:)` ports `AppCoordinator.apply` (revision guard, ledger prune, launch acknowledgement with `launchGrace = 120`, rearm, publish state, emit widget snapshot). Rearm, fire and publish helpers are stubs until Task 9; leave `rearm()` empty and `publish()` complete.
- [ ] **Step 4:** Tests PASS; full suite; push; check Linux and Windows jobs.
- [ ] **Step 5:** Commit "Engine: start, refresh and state publication".

---

### Task 9: Engine actor, part 2 — takeover scheduling

**Files:**
- Modify: `Sources/TimeTugEngine/Engine.swift`
- Create: `Tests/TimeTugEngineTests/EngineTakeoverTests.swift`
- Source of behaviour: `AppCoordinator.rearm()`, `fire(_:)`, `present(_:)`, `closeOverlay()`, `fireTest()`

- [ ] **Step 1: Failing tests** (ManualClock drives everything):
  1. An event starting in 10 minutes with lead time 60 s emits exactly one `takeoverDue` when the clock reaches `start - 60`, and the ledger marks it fired and persists.
  2. The re-check: the event is edited out of the snapshot before the timer fires → no takeover (`notInSnapshot`); declined or opted-out → none.
  3. Review Focus 3: two events whose fire times coincide; the first `takeoverDue` is emitted, then (host reports `takeoverPresented(eventID:onScreen: true)`) the second waits and is not marked fired; `takeoverClosed` re-arms and the second is emitted.
  4. Review Focus 4: advance the clock 3 hours past a meeting's start while its end is still in the future → one `takeoverDue` whose reason is late; an event that already ended produces none; running the same wake twice produces one.
  5. Snooze 5 minutes: ledger snoozed, takeover closed, re-armed at `now + 300`, emitted again then; `snoozeOptions` in the request exclude durations that end after the meeting.
  6. `join` emits `.joinRequested(url)` and closes; `dismiss` closes without joining.
  7. `testTug` emits a `takeoverDue` with the sample event ("test" ids) and the ledger is byte-identical afterwards.
  8. Settings change (`applySettings` setting lead time to 0 or `enabled = false`) re-arms or withdraws the pending takeover (`takeoverWithdrawn`).
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: Implement.** `rearm()`: cancel `fireTask`; if `takeoverVisible` return; compute `Scheduler.next(events:settings:ledger:now:)`; spawn a task `try await clock.sleep(until: next.fireAt)` then `fire(next.event)`. `fire` ports the Mac method line for line, including the reason strings used only for the diagnostic (`"snooze expired"`, `"late after wake"`, `"lead time"`; diagnostics never include titles). On `.present`: `ledger.markFired`, persist, set `pendingTakeoverEventID`, emit `.takeoverDue(request, calendarTitle:)`. `takeoverPresented(onScreen:)` sets `takeoverVisible = true` (both on-screen and toast count as visible, per spec: "a second takeover waits while one is visible"); `takeoverClosed`/`dismiss`/`snooze`/`join` clear it, persist, re-arm and publish.
- [ ] **Step 4:** PASS; full suite; push; Linux and Windows.
- [ ] **Step 5:** Commit "Engine: takeover scheduling, fire guard, snooze and test tug".

---

### Task 10: Engine actor, part 3 — inference, dedup actions, settings, system events, ticks, widget snapshots

**Files:**
- Modify: `Sources/TimeTugEngine/Engine.swift`
- Create: `Tests/TimeTugEngineTests/EngineInferenceTests.swift`, `EngineSystemEventTests.swift`, `EngineSettingsCommandTests.swift`
- Source of behaviour: `AppCoordinator.resolvePending`, `setInference`, `merge/unmerge/separate/forgetLessons`, `persistDedup`, `publishWidgetSnapshot`, `observeSystemEvents`, `updateUI`, `settings` sinks

- [ ] **Step 1: Failing tests:**
  1. Inference on with an available fake generator: look-alike pairs resolve in at most 10 passes, each verdict republishes state, and dedup state is persisted once at the end (Review Focus 6).
  2. Generator `temporarilyUnavailable` → no calls, `inferenceStatus == .unavailable`, pairs stay pending; flipping it to available and sending `.refresh` resolves them with no extra retry loop (count generate calls).
  3. A throwing generator: no verdict, a diagnostic with the error type name, no crash, pair retried on the next refresh only.
  4. `merge`, `unmerge`, `separate`, `forgetCorrections` each publish a new revision and persist dedup state only when it changed; a manual merge diagnostic contains counts, never titles.
  5. System events: `.wake`, `.clockChanged`, `.timeZoneChanged`, `.dayChanged` call `store.setCalendar(host.calendar())` then refresh; `.networkReturned` refreshes; the engine does not refresh on `.displayChanged` but emits a state with a new revision.
  6. `applySettings` persists through `host.settings`; `settingsChangedExternally` re-reads storage and republishes (and does not write back); a change to `inferenceEnabled` calls `store.setInferenceEnabled` then resolves; `systemCalendarEnabled` goes through the account manager.
  7. `setCountdownVisible(true)` makes the engine publish a state on each `UITickPolicy` wake (advance the clock by 60 s and assert a new revision with the same agenda; at an event boundary assert the agenda is rebuilt).
  8. A `widgetSnapshot` event is emitted on every applied snapshot and settings change (with `WidgetSnapshot.make(events:calendars:settings:now:calendar:)`), and equal consecutive event lists are still emitted (the Mac side decides whether to reload timelines).
- [ ] **Step 2:** FAIL → **Step 3:** implement by porting the named Mac methods, replacing Combine sinks with the command handlers, `Timer` with `clock.sleep`, `Task { @MainActor }` with actor-isolated tasks → **Step 4:** PASS, full suite, push, Linux and Windows.
- [ ] **Step 5:** Commit "Engine: inference, dedup actions, settings, system events, ticks and widget snapshots".

---

### Task 11: Conformance suite and legacy-file compatibility

**Files:**
- Create: `Tests/TimeTugEngineTests/ConformanceTests.swift`, `LegacyFixtureTests.swift`
- Modify: `scripts/ci/count-swift-tests.py` only if it needs the new target name (read first)

- [ ] **Step 1:** Write scripted-timeline scenarios that run a full day through one engine (start; two accounts; overlapping meetings; wake gap; account removal; settings toggle; inference becomes available) and assert the exact ordered list of `takeoverDue`, `takeoverWithdrawn`, `widgetSnapshot` events and the final `EngineState` fields. Each scenario is built from the harness; assert with `#expect` on whole arrays so a change in ordering fails.
- [ ] **Step 2:** `LegacyFixtureTests`: start an engine over a data directory pre-populated with the Task 2 fixtures plus an `accounts.json` produced by `FileConnectionStore` and assert: the accounts load, the ledger's fired event does not take over again, the dedup lesson is present in `states`, the legacy settings produce `enabled == false`, nothing is rewritten on `start` except through normal saves (compare fixture bytes where the engine only reads) (Review Focus 1).
- [ ] **Step 3:** Run → expected PASS on the first run for most (the engine exists); any FAIL is a real defect — fix in `Engine.swift` with a minimal change and a test, then re-run. Update the test count guard so the Windows jobs' expected count matches.
- [ ] **Step 4:** Commit "Engine: conformance suite and legacy file compatibility tests".

---

### Task 12: Review, release, bump

- [ ] **Step 1: DeepSeek review of the whole engine diff.** Use the `deepseek-review` skill from the `timetug-shared` clone with the spec, this plan's Review Focus and the diff (`git diff origin/main...HEAD` per merged group is already merged, so review `Sources/TimeTugEngine` and `Tests/TimeTugEngineTests` as whole files). Exclude nothing with token-like names. Verify every Critical or Important finding against the code; fix real ones with tests; record false ones in the progress ledger.
- [ ] **Step 2:** Confirm all five CI jobs are green on `main` after the last merge and that the latest `timetug-shared` release exists (`gh release list --repo binary-companion/timetug-shared -L 3`).
- [ ] **Step 3:** Confirm the bump pull request "Bump timetug-shared to X.Y.Z" exists in `timetug` and is green; keep it as the base for Task 13 (the engine is now consumable). Do not merge it separately if Task 13 supersedes it.
- [ ] **Step 4:** Tracker: set phase 3 to "in progress: engine released, Mac switch pending" and add a session-log line (commit with Task 13).

---

### Task 13: The Mac switch pull request

**Files (in the `timetug` worktree):**
- Modify: `Apps/macOS/project.yml` (add `TimeTugEngine` product reference from the `TimeTugShared` package), `Apps/macOS/Sources/AppCoordinator.swift`, `AccountsController.swift`, `SettingsStore.swift`, `AppDiagnostics.swift`, `Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/AppleIntelligence.swift`
- Create: `Apps/macOS/Sources/EngineAdapters/UserDefaultsSettingsStorage.swift`, `AppleTextGenerator.swift`, `OSLogEngineDiagnostics.swift`, `EngineModelMirror.swift`
- Delete: `Apps/macOS/Sources/LedgerStore.swift`, `DedupStateStore.swift`, `UITickPolicy.swift`, `LaunchAcknowledgement.swift`, `SourceReconciler.swift`, `SourceRefreshCoordinator.swift`, `Packages/AppleIntelligenceInference/Sources/.../PromptBuilder.swift` and their tests (the same files now tested in `timetug-shared`)
- Docs: `AGENTS.md`, `docs/architecture.md`, tracker, `docs/PROGRESS.md` if it still exists

**Interfaces:**
- Consumes: the released `timetug-shared` engine (pin `exactVersion` updated by the bump pull request).
- Produces: `AppCoordinator` as a thin host: it creates one `Engine`, forwards commands, and mirrors `EngineState` into `AppModel`/`SettingsStore` on the main actor.

- [ ] **Step 1: Branch from the bump pull request's branch** (so the pin is current): `git fetch && git checkout -b engine/switch origin/<bump-branch>`; run the app's existing test command (see `AGENTS.md` and `scripts/dev/verify.sh`) to record the green baseline and the test count.
- [ ] **Step 2: Adapters, one failing test each** (XCTest in the app test target):
  - `UserDefaultsSettingsStorage` conforms to `SettingsStorage` over `GroupDefaults.suite` and `SharedSettings`, reproducing `SettingsStore.init`'s precedence exactly (`shared.bool(.skipAllDay)` and `.enableTug` override the stored takeover JSON; `.useIntelligence` falls back to `defaults.bool(forKey: "dedupInference.v1")`; `eventKitEnabled.v1` defaults to true) and `save` mirroring (`skipAllDay`/`enableTug` only when changed, `useIntelligence`). Tests: load with a pre-seeded suite equals today's `SettingsStore` values; save mirrors only changed keys.
  - `AppleTextGenerator: TextGenerator` wraps `SystemLanguageModel`/`LanguageModelSession` behind `#if canImport(FoundationModels)` (availability mapping: `.available` → `.available(EngineInfo(id: "apple-intelligence", ...))`, otherwise `.unavailable`; the energy-saver case is not reported on Mac). Tests via `#if` guard and a protocol-level fake of the session where feasible; the real model is not called in CI.
  - `OSLogEngineDiagnostics` maps `DiagnosticEvent` to `Logger(subsystem: "com.timetug.app", category: event.category)` with `privacy: .public` on the message (the engine guarantees no content). Test: level mapping.
- [ ] **Step 3: Switch `AppCoordinator`.** Replace the stored services with `let engine: Engine`; `start()` builds the `EngineHost` (data directory = `AppSupportFiles.url("")` parent so file names are unchanged; `credentials`, `interaction`, `CredentialPrompter` as `SignInPrompting`, `registry` from `AppConnectors.makeRegistry`, `buildSystemSource = { ConnectedSource(eventKit) }`, `requestSystemAccess`, `AppleTextGenerator`, diagnostics) then `await engine.send(.start)` and consumes `engine.states` and `engine.events` in two `Task`s that hop to the main actor:
  - states → `AppModel` (`calendars`, `statuses`, `notices`, `sourceNames`, `candidates`, `agenda`, `inferenceStatus`, `leadTime`) and the status item title/icon (`MenuBarIconState.resolve(events:settings:ledger:now:)` from `state.events`, `state.settings.takeover`, `state.ledger`); `publishInferenceAvailability` stays here (it writes the shared suite and reloads Control Center).
  - events → `.takeoverDue` shows the overlay (`overlay.show(request, calendarTitle:, actions:)` with actions that send `.join`, `.snooze`, `.dismiss`; after `show` send `.takeoverPresented(eventID:onScreen: true)`; `overlay` close sends `.takeoverClosed`), `.joinRequested(url)` calls `SafeJoin.open`, `.widgetSnapshot` writes `WidgetSnapshotStore` and reloads timelines with the existing 2-second debounce and `lastWidgetEvents` comparison, `.diagnostic` is already logged by the sink.
  - System notifications (`NSWorkspace.didWake`, clock, time zone, day changed, `NWPathMonitor` return) send `.system(...)`; the `periodicRefresh` and `settingsSelfHeal` timers: the engine owns the 900 s refresh; the 300 s `settings.reloadFromShared()` self-heal stays in the app and sends `.settingsChangedExternally`; the `SettingsChangeSignal.Observer` sends the same.
  - Presentation settings that change the countdown need (`menuBarMode`) send `.setCountdownVisible(mode != .iconOnly)`.
  - `SettingsStore` keeps `menuBarMode`, `appearanceMode`, `popupCardStyle` and becomes a mirror of the engine's behaviour settings: its `takeover`/`inferenceEnabled`/`eventKitEnabled` setters send `.applySettings { ... }` and its values are updated from `state.settings` (guard against echo with the existing `isApplyingSharedValues` flag).
  - `AccountsController` becomes a mirror: the same `@Published` properties updated from `state.accountStatus`; its methods send commands (`addAccount`, `removeAccount`, `reauthorize`, `cancelAuthorization`, `setSystemCalendarEnabled`).
  - `fireTest()` sends `.testTug`; `unmerge/separate/merge/forgetCorrections` send the commands.
- [ ] **Step 4: Delete** the moved files and their tests; update `project.yml` and run `xcodegen generate` (restore the two checked-in Info.plists with `git checkout` afterwards, never commit them; if the worktree DerivedData holds a stale package file list, clear only this worktree's `~/Library/Developer/Xcode/DerivedData/TimeTug-<hash>`).
- [ ] **Step 5: Verify:** the app's full test suite (record the count before and after: it falls by exactly the moved tests and rises by the adapter tests), `scripts/ci/check-architecture.sh`, `scripts/dev/verify.sh` (or the repo's documented equivalent), App Store build and DMG build via CI. Launch a Debug build locally and drive the golden path with osascript (open popover, Test tug, snooze, join) if accessibility is granted; do not `pkill -x TimeTug`.
- [ ] **Step 6: DeepSeek review** of the switch diff (`deepseek-review` skill; whole changed files plus the spec); verify findings; fix.
- [ ] **Step 7: Open the pull request** ("Move the Mac app onto TimeTugEngine"), body listing: what moved, what stayed, test counts before and after, how upgrade compatibility is proven (fixture tests), and the owner's manual checklist item. When all checks pass and the review is approved, merge (standing authorization). Do not publish a release.

---

### Task 14: Close out

- [ ] **Step 1: Docs.** `AGENTS.md` (timetug and timetug-shared): engine responsibilities and the presentation/engine split; `docs/architecture.md`: new diagram; tracker: phase 3 row to "done pending the owner's manual checklist and beta" with PR links, owner-checklist items (manual checklist, beta verification, the Mac release), session log line.
- [ ] **Step 2: Memory.** Update the `windows-program` memory with the phase 3 status, the merge links and the ledger path (`.superpowers/sdd/2026-10-15-phase-3-engine/progress.md`, git-ignored).
- [ ] **Step 3: Report** to the owner: what merged, what they must do (run `docs/manual-tests/macos-checklist.md`, verify the beta, publish the release), and that phase 4 is next (its spec and plan do not exist yet).

---

## Self-review

- **Spec coverage:** module and layout (Task 1), clock (1), settings split and persistence (2), data files and legacy compatibility (2, 11), launch acknowledgement and tick policy (3), reconcile and refresh (4), account lifecycle and sign-in retry (5), host seams (5), text generation and prompt building (6), commands, state, events (7), start, refresh, publication (8), takeovers (9), inference, dedup, settings, system events, ticks, widget snapshots (10), conformance (11), review and release (12), Mac switch (13), docs and close-out (14). The spec's "dedup benchmark fixtures" is already in `timetug-shared`; the benchmark's model runner is unchanged in this phase.
- **Types:** `SignInPrompting`, `SettingsStorage`/`EngineSettings`, `TextGenerator`/`TextGeneratorAvailability`, `EngineHost`, `EngineCommand`, `EngineState`, `EngineEvent` are each defined once (Tasks 2, 5, 6, 7) and used with the same names in 8 to 13. `systemCalendarEnabled` replaces `eventKitEnabled` inside the engine; the Mac adapter maps it to the `eventKitEnabled.v1` key.
- **Known deliberate deviations from the spec, to record in its "As built":** (1) `SignInPrompting` seam added to the host table (the password retry loop needs it); (2) the engine carries sign-in error strings from `AccountsController` verbatim; (3) `EngineState` exposes the ledger so the Mac can compute its menu-bar icon state unchanged; (4) the countdown wake is requested with `setCountdownVisible`.
