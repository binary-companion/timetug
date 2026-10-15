# Phase 4: C interface, contract and NuGet package — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose `TimeTugEngine` through a four-function C ABI with a versioned JSON contract, publish it as the `TimeTug.Engine` NuGet package with a C# wrapper, and prove it with one conformance suite run from Swift and C#.

**Architecture:** Two new Swift modules in `timetug-shared`: `TimeTugEngineProtocol` (wire DTOs, envelope, mapping to and from engine types) and `TimeTugEngineC` (dynamic library: session, remote host services, four `@_cdecl` functions). A `dotnet/` tree holds the managed wrapper and its tests. Scenario JSON files drive both runners. The release workflow gains a `publish-nuget` job.

**Tech Stack:** Swift 6 (SwiftPM), Foundation only; C header; .NET 8 (`net8.0`), `System.Text.Json` source generation; GitHub Actions on macOS, Linux, `windows-latest`, `windows-11-arm`.

**Spec:** `docs/superpowers/specs/2026-10-15-phase-4-engine-c-interface-design.md` (in the `timetug` repository). Parent: `docs/superpowers/specs/2026-10-09-windows-program-design.md`.

## Global Constraints

- Work happens in a clone of `binary-companion/timetug-shared` (default branch `main`), one pull request per task group, squash-merged when all checks pass. The `timetug` repository only receives this plan, the spec, the findings note and the tracker update.
- Swift tools version 6.0; Foundation only; no AppKit, Combine, OSLog, Network or WidgetKit anywhere in the new modules.
- Wire values: instants ISO 8601 UTC strings with millisecond precision; durations in seconds; all-day events as `YYYY-MM-DD` dates plus the event's zone id; enums lower-camel strings; no display strings the engine composed.
- Envelope: `{"v":1,"type":...,"id":...,"payload":...}`. Replies: `{"v":1,"result":...}` or `{"v":1,"error":{"kind","message"}}` with error kinds `network|cancelled|notFound|denied|failed`.
- ABI: exactly `tt_engine_create`, `tt_engine_send`, `tt_engine_reply`, `tt_engine_destroy`; `send` and `reply` never block; callbacks serialized and ordered; no callback after `destroy` returns; stale, `NULL` and repeated handles are ignored.
- JSON comparisons in tests compare parsed values, never bytes.
- Windows builds use `swift build --show-bin-path`, never `.build\release`.
- Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR body ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Reviews use the `deepseek-review` skill; never send secrets; DeepSeek output is unverified.
- Never read or print `~/.config/deepseek-mcp/`. The owner alone approves release environments and sets up nuget.org trusted publishing.
- New public API gets a `semver:minor` label on its pull request; the C ABI header is part of the public API.

## Review Focus

1. **Callback after destroy / reply after destroy** — expected: never delivered, never crashes (Task 7, 9).
2. **Host never answers an HTTP request** — expected: the request fails with `network` after 60 s, the source shows `failing`, other sources keep working (Task 8, 9).
3. **A command id for an event that vanished (merge of a stale id)** — expected: a `diagnostic` echoing the command id, no state change (Task 4).
4. **Slow host callback while state changes rapidly** — expected: latest state wins, events keep order and are never dropped (Task 7, 9).
5. **Non-UTC time zone and a time-zone change** — expected: agenda and takeover times follow the configured zone (Task 8, 12).

---

## File Structure

```
Package.swift                                   modify: products and targets
include/timetug_engine.h                        create: the four declarations
Sources/TimeTugEngine/Persistence/FileSettingsStorage.swift          create
Sources/TimeTugEngineProtocol/{Envelope,JSONValue,Config,WireTypes,StateMapping,CommandMapping,ServiceMessages}.swift
Sources/TimeTugEngineC/{CInterface,EngineSession,HandleRegistry,RemoteHostServices,RequestTable}.swift
Tests/TimeTugEngineProtocolTests/{EnvelopeTests,MappingTests,FixtureTests}.swift
Tests/TimeTugEngineCTests/{LifecycleTests,ScenarioRunner,ScenarioTests}.swift
Conformance/Fixtures/golden/*.json
Conformance/Scenarios/*.json
c-smoke/{smoke.c,run.sh}
dotnet/TimeTug.Engine/…  dotnet/TimeTug.Engine.Tests/…  dotnet/pack/…
scripts/ci/check-architecture.sh                modify
.github/workflows/{ci.yml,release.yml}          modify
```

---

### Task 1: File-backed settings storage

**Files:**
- Create: `Sources/TimeTugEngine/Persistence/FileSettingsStorage.swift`
- Test: `Tests/TimeTugEngineTests/FileSettingsStorageTests.swift`

**Interfaces:**
- Consumes: `SettingsStorage`, `EngineSettings`, `TakeoverSettings` (Codable), `JSONFile` helpers in `Persistence/JSONFile.swift` (read it first and reuse its atomic write).
- Produces: `public final class FileSettingsStorage: SettingsStorage, @unchecked Sendable` with `init(directory: URL, diagnostics: @escaping EngineDiagnosticSink = { _ in })`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import TimeTugEngine
import TimeTugCore

final class FileSettingsStorageTests: XCTestCase {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testMissingFileLoadsDefaults() {
        let storage = FileSettingsStorage(directory: tempDir())
        XCTAssertEqual(storage.load(), EngineSettings())
    }

    func testRoundTripAcrossInstances() {
        let dir = tempDir()
        var settings = EngineSettings()
        settings.inferenceEnabled = true
        settings.systemCalendarEnabled = false
        FileSettingsStorage(directory: dir).save(settings)
        XCTAssertEqual(FileSettingsStorage(directory: dir).load(), settings)
    }

    func testCorruptFileLoadsDefaultsAndReports() {
        let dir = tempDir()
        try! Data("{not json".utf8).write(to: dir.appendingPathComponent("settings.json"))
        let box = LockedBox<[EngineDiagnostic]>([])
        let storage = FileSettingsStorage(directory: dir) { d in box.mutate { $0.append(d) } }
        XCTAssertEqual(storage.load(), EngineSettings())
        XCTAssertEqual(box.value.count, 1)
        XCTAssertEqual(box.value.first?.level, .warning)
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock(); private var stored: T
    init(_ v: T) { stored = v }
    var value: T { lock.withLock { stored } }
    func mutate(_ f: (inout T) -> Void) { lock.withLock { f(&stored) } }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter FileSettingsStorageTests`
Expected: FAIL, `cannot find 'FileSettingsStorage'`.

- [ ] **Step 3: Implement**

`EngineSettings` is not Codable today, so persist a private Codable mirror (`takeover: TakeoverSettings`, `inferenceEnabled`, `systemCalendarEnabled`) in `settings.json` with `JSONFile`'s atomic write; on decode failure emit `EngineDiagnostic(level: .warning, category: "settings", message: "settings.json unreadable; using defaults")` and return `EngineSettings()`. Serialize access with an `NSLock`.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter FileSettingsStorageTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TimeTugEngine/Persistence/FileSettingsStorage.swift Tests/TimeTugEngineTests/FileSettingsStorageTests.swift
git commit -m "Engine: file-backed settings storage"
```

---

### Task 2: Protocol module — envelope, JSON value, config

**Files:**
- Modify: `Package.swift` (add `.library(name: "TimeTugEngineProtocol", ...)`, a target depending on `TimeTugEngine`, `TimeTugCore`, `CalendarBridge`, `CalendarCore`, and test target `TimeTugEngineProtocolTests`). Tests find `Conformance/` through `#filePath` (walk up to the package root); no SwiftPM resources, because a resource directory cannot live outside the target.
- Create: `Sources/TimeTugEngineProtocol/{Envelope.swift,JSONValue.swift,Config.swift}`
- Test: `Tests/TimeTugEngineProtocolTests/EnvelopeTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:

```swift
public enum JSONValue: Codable, Equatable, Sendable { case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue]) }

public enum MessageID: Codable, Equatable, Sendable { case number(UInt64), string(String) }

public struct Envelope: Codable, Equatable, Sendable {
    public var v: Int
    public var type: String
    public var id: MessageID?
    public var payload: JSONValue?
    public init(v: Int = 1, type: String, id: MessageID? = nil, payload: JSONValue? = nil)
}

public enum ProtocolVersion { public static let supported: [Int] = [1] }

public struct WireConfig: Codable, Equatable, Sendable {
    public var v: Int
    public var dataDirectory: String
    public var platform: String            // windows | linux | macos
    public var connectors: [String: ConnectorClient]   // "google", "microsoft"
    public var textGeneration: Bool
    public var timeZone: String?
    public var testing: Bool
    public struct ConnectorClient: Codable, Equatable, Sendable { public var clientID: String }
}
```

- [ ] **Step 1: Write the failing tests**

```swift
func testEnvelopeIgnoresUnknownFields() throws {
    let json = #"{"v":1,"type":"refresh","extra":{"a":1},"payload":null}"#
    let e = try JSONDecoder().decode(Envelope.self, from: Data(json.utf8))
    XCTAssertEqual(e.type, "refresh"); XCTAssertEqual(e.v, 1)
}
func testIDAcceptsNumberAndString() throws {
    XCTAssertEqual(try JSONDecoder().decode(MessageID.self, from: Data("7".utf8)), .number(7))
    XCTAssertEqual(try JSONDecoder().decode(MessageID.self, from: Data(#""cmd-7""#.utf8)), .string("cmd-7"))
}
func testConfigRejectsUnsupportedVersionAndEmptyDirectory() {
    XCTAssertThrowsError(try WireConfig.parse(#"{"v":2,"dataDirectory":"/x","platform":"linux"}"#))
    XCTAssertThrowsError(try WireConfig.parse(#"{"v":1,"dataDirectory":"","platform":"linux"}"#))
    XCTAssertThrowsError(try WireConfig.parse(#"{"v":1,"dataDirectory":"/x","platform":"beos"}"#))
}
func testConfigDefaults() throws {
    let c = try WireConfig.parse(#"{"v":1,"dataDirectory":"/x","platform":"windows"}"#)
    XCTAssertFalse(c.testing); XCTAssertFalse(c.textGeneration); XCTAssertNil(c.timeZone); XCTAssertTrue(c.connectors.isEmpty)
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter EnvelopeTests` → FAIL (module missing).
- [ ] **Step 3: Implement** the types above (`WireConfig.parse(_ json: String) throws -> WireConfig` decodes with defaults via a custom `init(from:)` using `decodeIfPresent`, then validates `v == 1`, non-empty `dataDirectory`, `platform` in the three allowed values, and `timeZone` resolvable by `TimeZone(identifier:)` when present).
- [ ] **Step 4: Run to verify pass.**
- [ ] **Step 5: Commit** — `git commit -m "Protocol: envelope, JSON value and config"`.

---

### Task 3: Protocol module — state and event DTOs with mapping

**Files:**
- Create: `Sources/TimeTugEngineProtocol/{WireTypes.swift,StateMapping.swift,ServiceMessages.swift}` (`ServiceMessages.swift` holds the request payload and reply DTOs for the five service groups: credentials, http, auth redirect, auth form and sign-in prompt, text; Task 6 consumes them)
- Test: `Tests/TimeTugEngineProtocolTests/MappingTests.swift`

**Interfaces:**
- Consumes: `EngineState`, `AccountKindInfo`, `EngineEvent`, `TakeoverRequest`, `WidgetSnapshot`, `EngineDiagnostic`, `TimeTugCalendarEvent`, `DayAgenda`, `CalendarInfo`, `SourceStatus`, `Connection`, `InferenceStatus`, `ScheduledTakeover`, `TakeoverLedger`, `AccountManager.Status`, `EngineSettings`.
- Produces: `WireState`, `WireEvent`, `WireTakeoverRequest`, `WireWidgetSnapshot`, `WireDiagnostic`, `WireSettings`, `WireSettingsPatch`; `extension WireState { init(_ state: EngineState) }`; `func wireMessage(for event: EngineEvent) -> Envelope`; `func wireMessage(for state: EngineState) -> Envelope`; `static func decodeStateFields` is not needed.

Mapping rules (each is a test): dates via one shared `ISO8601DateFormatter` with `.withInternetDateTime, .withFractionalSeconds` in UTC; all-day events emit `startDate`/`endDate` (`YYYY-MM-DD`, end exclusive, from `allDayDates`) and `timeZone` id and no instants; merged events list `members` as `{eventID, calendarKey, start, end}` where `eventID` comes from the member's `contentKey` index into the merged event (document the choice in the type comment); `candidates` is `[pairKey: [eventID]]`; `statuses` values are `{kind: ok|needsPermission|authExpired|failing, message?}`; `inferenceStatus` is `{kind: disabled|noEngine|unavailable|notOnDevice|active, reason?, engineID?, engineName?}`; the ledger is summarized as `{count}` only.

- [ ] **Step 1: Write the failing tests**

```swift
func testEveryEngineStatePropertyHasAWireField() {
    // Mirror lists the stored properties of EngineState; the wire type must expose each name.
    let engine = Set(Mirror(reflecting: EngineState.empty).children.compactMap(\.label))
    let wire = Set(WireState.fieldNames)
    XCTAssertEqual(engine.subtracting(wire), [], "wire state is missing engine fields")
}
func testAllDayEventUsesDatesNotInstants() throws {
    let wire = WireEvent(allDayEventFixture())
    XCTAssertEqual(wire.startDate, "2026-10-16"); XCTAssertEqual(wire.endDate, "2026-10-17")
    XCTAssertNil(wire.start)
}
func testDatesAreUTCMilliseconds() {
    XCTAssertEqual(WireDates.string(Date(timeIntervalSince1970: 1_760_000_000.123)), "2025-10-09T08:53:20.123Z")
}
func testDiagnosticCarriesNoPayloadID() {
    let env = wireMessage(for: .diagnostic(EngineDiagnostic(level: .info, category: "x", message: "m")))
    XCTAssertEqual(env.type, "event.diagnostic"); XCTAssertNil(env.id)
}
```

(`allDayEventFixture()` builds a `TimeTugCalendarEvent` with `isAllDay` true using the same helper the engine tests use — find it in `Tests/TimeTugEngineTests` or `TimeTugCoreTests` and reuse it.)

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** the DTOs and mappings. `WireState.fieldNames` is a static array that the `WireState` memberwise `CodingKeys` also uses, so it cannot drift from the encoder.
- [ ] **Step 4: Run to verify pass.**
- [ ] **Step 5: Commit** — `git commit -m "Protocol: state and event DTOs"`.

---

### Task 4: Protocol module — command decoding and mapping

**Files:**
- Create: `Sources/TimeTugEngineProtocol/CommandMapping.swift`
- Test: `Tests/TimeTugEngineProtocolTests/CommandMappingTests.swift`

**Interfaces:**
- Consumes: `Envelope`, `EngineCommand`, `SystemEvent`, `EngineSettings`, `EngineState`, `TimeTugCalendarEvent`, `MergedMember`.
- Produces:

```swift
public enum CommandOutcome: Sendable {
    case engine(EngineCommand)
    case testAdvanceClock(seconds: Double)
    case rejected(EngineDiagnostic)
}
public struct CommandDecoder: Sendable {
    public init(testing: Bool)
    /// `state` is the latest published state, used to resolve event ids.
    public func decode(_ envelope: Envelope, state: EngineState) -> CommandOutcome
}
```

Rules: `start`, `refresh`, `account.add|reconnect|remove|cancel`, `settings.apply`, `countdown.visible`, `takeover.presented|closed|join|dismiss|snooze|test`, `dedup.merge|unmerge|separate|forget`, `system.event`, `test.advanceClock` per the spec table. `dedup.merge` resolves two ids in `state.events` and `state.candidates` values; a missing id returns `.rejected` with `category: "command"` and message `"unknown event id"`. `test.advanceClock` without `testing` is `.rejected`. Unknown `type` is `.rejected` (`"unknown command type"`). A wrong `v` is `.rejected`. A payload that fails to decode is `.rejected` and never throws. `settings.apply` builds an `applySettings` closure from the patch (absent field = unchanged).

- [ ] **Step 1: Write the failing tests** (one per rule; show the three that carry the logic):

```swift
func testMergeWithUnknownIDIsRejectedWithDiagnostic() {
    let env = Envelope(type: "dedup.merge", id: .string("c1"), payload: .object(["eventIDs": .array([.string("nope"), .string("nada")])]))
    guard case .rejected(let d) = CommandDecoder(testing: false).decode(env, state: .empty) else { return XCTFail() }
    XCTAssertEqual(d.category, "command")
}
func testSettingsPatchLeavesAbsentFieldsAlone() {
    let env = Envelope(type: "settings.apply", payload: .object(["inferenceEnabled": .bool(true)]))
    guard case .engine(.applySettings(let f)) = CommandDecoder(testing: false).decode(env, state: .empty) else { return XCTFail() }
    var s = EngineSettings(); s.systemCalendarEnabled = false; f(&s)
    XCTAssertTrue(s.inferenceEnabled); XCTAssertFalse(s.systemCalendarEnabled)
}
func testAdvanceClockRequiresTestingFlag() {
    let env = Envelope(type: "test.advanceClock", payload: .object(["seconds": .number(60)]))
    guard case .rejected = CommandDecoder(testing: false).decode(env, state: .empty) else { return XCTFail() }
    guard case .testAdvanceClock(let s) = CommandDecoder(testing: true).decode(env, state: .empty) else { return XCTFail() }
    XCTAssertEqual(s, 60)
}
```

- [ ] **Step 2–4:** run (FAIL), implement, run (PASS).
- [ ] **Step 5: Commit** — `git commit -m "Protocol: command decoding"`.

---

### Task 5: Golden fixtures and round-trip tests

**Files:**
- Create: `Conformance/Fixtures/golden/*.json` (one per message type in the spec tables plus edge classes), `Tests/TimeTugEngineProtocolTests/FixtureTests.swift`
- Modify: `scripts/ci/check-repository-contracts.py` (fixture list must equal message-type list)

**Interfaces:**
- Consumes: `Envelope`, DTOs, `CommandDecoder`.
- Produces: `MessageCatalog.hostToEngine: [String]`, `.engineToHost: [String]`, `.services: [String]` and `MessageCatalog.all: [String]` (their concatenation) in the protocol module: the single list of type names that the doc table and the fixture test both read.

Fixture file naming: `<type>.json` (dots kept), edge files `edge-<name>.json`. Edge classes (spec): all-day event, no conference link, a source in each status, settings patch full and empty, reply error of each kind, unknown field, unknown type, `v` not 1.

- [ ] **Step 1: Write the failing test**

```swift
func testEveryCatalogTypeHasAFixture() throws {
    let names = Set(try fixtureNames())
    for type in MessageCatalog.all { XCTAssertTrue(names.contains("\(type).json"), "missing fixture for \(type)") }
}
func testEveryFixtureRoundTripsAsParsedJSON() throws {
    for (name, data) in try allFixtures() where !name.hasPrefix("edge-") {
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        let again = try JSONEncoder().encode(env)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: again),
                       try JSONDecoder().decode(JSONValue.self, from: data), name)
    }
}
func testUnknownTypeFixtureIsRejectedNotThrown() throws {
    let env = try JSONDecoder().decode(Envelope.self, from: fixture("edge-unknown-type.json"))
    guard case .rejected = CommandDecoder(testing: false).decode(env, state: .empty) else { return XCTFail() }
}
```

- [ ] **Step 2–4:** run (FAIL), write fixtures from the Task 3 and 4 encoders (generate once with a throwaway test helper, then review and hand-edit; commit the files), run (PASS).
- [ ] **Step 5: Commit** — `git commit -m "Protocol: golden fixtures and round-trip tests"`.

Open a pull request for Tasks 1–5 (`semver:minor`), run a DeepSeek review of the diff, fix, merge when green.

---

### Task 6: C module — request table and remote host services

**Files:**
- Modify: `Package.swift` (target `TimeTugEngineC`, depends on `TimeTugEngineProtocol`, `TimeTugEngine`; product `.library(name: "TimeTugEngineC", type: .dynamic, targets: ["TimeTugEngineC"])`; test target `TimeTugEngineCTests`)
- Create: `Sources/TimeTugEngineC/{RequestTable.swift,RemoteHostServices.swift}`
- Test: `Tests/TimeTugEngineCTests/RemoteHostServicesTests.swift`

**Interfaces:**
- Consumes: `Envelope`, `JSONValue`, `CredentialStore`, `HTTPTransport`, `AuthorizationInteraction`, `OAuthRedirectSession`, `SignInPrompting`, `TextGenerator`, `EngineClock`.
- Produces:

```swift
/// Sends one service request to the host and suspends until `fulfill` or `failAll`.
final class RequestTable: @unchecked Sendable {
    init(send: @escaping @Sendable (Envelope) -> Void, clock: any EngineClock)
    func request(type: String, payload: JSONValue, timeout: TimeInterval?) async throws -> JSONValue
    func fulfill(id: UInt64, reply: String)        // unknown or answered id: ignored
    func failAll(kind: ReplyErrorKind)             // used by destroy
}
enum ReplyErrorKind: String, Sendable { case network, cancelled, notFound, denied, failed }
struct RemoteCredentialStore: CredentialStore { … }
struct RemoteHTTPTransport: HTTPTransport { … }          // 60 s timeout → SourceError.network
struct RemoteAuthorizationInteraction: AuthorizationInteraction { … }
struct RemoteSignInPrompting: SignInPrompting { … }
struct RemoteTextGenerator: TextGenerator { … }
```

- [ ] **Step 1: Write the failing tests**

```swift
func testReplyResolvesRequest() async throws {
    let sent = LockedBox<[Envelope]>([])
    let table = RequestTable(send: { e in sent.mutate { $0.append(e) } }, clock: SystemClock())
    async let r = table.request(type: "service.x", payload: .null, timeout: nil)
    while sent.value.isEmpty { await Task.yield() }
    guard case .number(let id)? = sent.value[0].id else { return XCTFail() }
    table.fulfill(id: id, reply: #"{"v":1,"result":{"a":1}}"#)
    XCTAssertEqual(try await r, .object(["a": .number(1)]))
}
func testUnknownAndRepeatedRepliesAreIgnored() { /* fulfill(id: 999, …) and a second fulfill do not crash */ }
func testFailAllCancelsPending() async { /* request pending; failAll(.cancelled) → throws CancellationError-equivalent */ }
func testHTTPTimeoutMapsToNetworkError() async { /* manual clock advanced 61 s → SourceError.network */ }
func testHTTPBodyIsBase64OnTheWire() async { /* request body bytes appear base64 in payload */ }
```

- [ ] **Step 2–4:** run (FAIL), implement (`request` registers a continuation under a fresh `UInt64`, sends the envelope, and for a non-nil `timeout` races `clock.sleep(until:)`; replies decode `{"v":1,"result"|"error"}` and an unsupported `v` fails the request with `failed`), run (PASS).
- [ ] **Step 5: Commit** — `git commit -m "C interface: request table and remote host services"`.

---

### Task 7: C module — session, handle registry, the four functions, header

**Files:**
- Create: `Sources/TimeTugEngineC/{EngineSession.swift,HandleRegistry.swift,CInterface.swift}`, `include/timetug_engine.h`
- Test: `Tests/TimeTugEngineCTests/LifecycleTests.swift`

**Interfaces:**
- Consumes: Tasks 2–6 types, `Engine`, `EngineHost`, `FileSettingsStorage`, `ConnectorRegistry` (build per platform: read how the Mac app and `CalendarApple` register `GoogleCalendar`, `MicrosoftCalendar` and CalDAV kinds, and register the same library kinds with the config's client ids; kinds without a client id go into `unconfiguredKindIDs`).
- Produces:

```c
/* include/timetug_engine.h */
#ifndef TIMETUG_ENGINE_H
#define TIMETUG_ENGINE_H
#ifdef __cplusplus
extern "C" {
#endif
#include <stdint.h>
typedef struct tt_engine tt_engine;
typedef void (*tt_message_fn)(void *context, const char *message_json);
#if defined(_WIN32)
#define TT_EXPORT __declspec(dllexport)
#else
#define TT_EXPORT __attribute__((visibility("default")))
#endif
TT_EXPORT tt_engine *tt_engine_create(const char *config_json, tt_message_fn on_message, void *context);
TT_EXPORT void tt_engine_send(tt_engine *engine, const char *command_json);
TT_EXPORT void tt_engine_reply(tt_engine *engine, uint64_t request_id, const char *reply_json);
TT_EXPORT void tt_engine_destroy(tt_engine *engine);
#ifdef __cplusplus
}
#endif
#endif
```

```swift
@_cdecl("tt_engine_create")
public func tt_engine_create(_ config: UnsafePointer<CChar>?, _ callback: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void)?, _ context: UnsafeMutableRawPointer?) -> OpaquePointer?
```

`EngineSession` owns: the `Engine`; an `AsyncStream<Outgoing>` delivery queue consumed by one task that calls the C callback (state slot coalesces: keep only the newest pending `state`, never drop events or requests, preserve relative order of events and requests); a state-pump task (`engine.states`) and an event-pump task (`engine.events`) mapping to envelopes; the `RequestTable`; the `CommandDecoder`; the latest `EngineState`; a `generation` token. `HandleRegistry` maps opaque tokens (an incrementing integer cast to `OpaquePointer`, never a real pointer) to sessions behind a lock. `destroy` marks the session stopped, cancels pump tasks, `failAll(.cancelled)`, and waits for the delivery task only when not on the delivery task (track with a task-local flag); after stop, `send`, `reply` and the callback path check the flag.

A `.rejected` outcome from the decoder is delivered as an `event.diagnostic` whose envelope `id` is the causing command's envelope `id` (the session copies it; the decoder's diagnostic has none). Invalid JSON that cannot be parsed into an envelope produces a diagnostic with no `id`.

`ready` is emitted before the first `state`, once, after `create` plus `start`. Its payload is `{"engineVersion": <EngineBuild.version>, "protocolVersions": [1], "platform": <config platform>, "capabilities": {"systemCalendar": false, "textGeneration": <config textGeneration>}}`. `EngineBuild.version` is a constant in `TimeTugEngineC` that is `"0.0.0-dev"` in the repository and is stamped with the release tag by the release workflow before packing (Task 13). `start` runs `engine.start()` and publishes `ready` first.

- [ ] **Step 1: Write the failing tests**

```swift
func testCreateReturnsNilForBadConfig() {
    XCTAssertNil(tt_engine_create("{not json", { _, _ in }, nil))
    XCTAssertNil(tt_engine_create(nil, { _, _ in }, nil))
}
func testReadyThenStateAfterStart() async throws {
    // collect messages; expect types ["ready","state"] prefix, and the ready payload exactly:
    // engineVersion is a non-empty string, protocolVersions == [1], platform echoes the config,
    // capabilities == {systemCalendar: false, textGeneration: false}
}
func testRejectedCommandDiagnosticEchoesTheCommandID() async throws {
    // send {"v":1,"type":"nope","id":"cmd-9"}; expect event.diagnostic with envelope id "cmd-9"
}
func testNoCallbackAfterDestroyReturns() async throws {
    // slow callback (sleep 50 ms) + burst of refresh commands; destroy; record count; wait 200 ms; count unchanged
}
func testDestroyFromInsideCallbackDoesNotDeadlockOrCallAgain() async throws { /* callback calls tt_engine_destroy once */ }
func testStaleNullAndRepeatedHandlesAreIgnored() {
    tt_engine_send(nil, "{}"); tt_engine_reply(nil, 1, "{}"); tt_engine_destroy(nil)
    let h = createTestEngine(); tt_engine_destroy(h); tt_engine_destroy(h); tt_engine_send(h, "{}")
}
func testReplyForUnknownRequestIDIsIgnored() { /* reply(h, 424242, ...) → no crash, no message */ }
func testStateCoalescesButEventsKeepOrder() async throws { /* manual clock, many state changes under a slow callback */ }
func testTwoEnginesInOneProcessDoNotShareState() async throws { /* two data dirs, distinct settings */ }
```

(`createTestEngine`, a message collector class and a helper that builds a `testing: true` config in a temporary directory live in `Tests/TimeTugEngineCTests/Support.swift`.)

- [ ] **Step 2: Run to verify failure** — `swift test --filter LifecycleTests` → FAIL.
- [ ] **Step 3: Implement** as described.
- [ ] **Step 4: Run to verify pass** — all `LifecycleTests` pass; repeat the suite 20 times (`for i in $(seq 20); do swift test --filter LifecycleTests || break; done`) to expose races.
- [ ] **Step 5: Commit** — `git commit -m "C interface: session, handle registry and the four functions"`.

---

### Task 8: Scenario runner (Swift), C smoke test, first scenarios

**Files:**
- Create: `Tests/TimeTugEngineCTests/ScenarioRunner.swift`, `Tests/TimeTugEngineCTests/ScenarioTests.swift`, `Conformance/Scenarios/{start-ready.json,add-account-oauth.json,takeover-after-clock.json,http-timeout.json}`, `c-smoke/{smoke.c,run.sh}`
- Modify: `.github/workflows/ci.yml` (C smoke step on macOS, Linux, Windows)

**Interfaces:**
- Consumes: the C functions through the header, `JSONValue`.
- Produces: the scenario file format:

```json
{
  "name": "takeover-after-clock",
  "config": { "v": 1, "platform": "linux", "testing": true, "timeZone": "America/Chicago", "connectors": {} },
  "host": {
    "http": [ { "match": "https://www.googleapis.com/calendar/v3/calendars/primary/events", "status": 200, "bodyFile": "google-events-simple.json" } ],
    "credentials": { "seed": { "conn-1": { "refresh_token": "x" } } }
  },
  "steps": [
    { "send": { "type": "start" } },
    { "expect": { "events": [ { "type": "ready" } ] } },
    { "send": { "type": "test.advanceClock", "payload": { "seconds": 900 } } },
    { "expect": { "events": [ { "type": "event.takeoverDue", "payload": { "event": { "title": "Design review" } } } ] } }
  ]
}
```

The runner supplies `dataDirectory` itself (a fresh temporary directory per scenario, kept across `restart` steps) and merges it into `config`, so scenario files never name a path.

Expectation semantics: an `expect.events` list must match, in order, a subsequence of the messages received since the previous `expect`; each expected object is a subset match (every field named must be equal, extra fields ignored). `expect.state` is a subset match on the latest `state`. A step may `reply` to a named service request (`{"onRequest":"service.http.send","reply":{…}}` is declarative under `host`). The runner fails when the wait for an expectation exceeds 5 s of real time (the engine runs on a manual clock, so waits are only for delivery). Calendar response bodies live in `Conformance/Scenarios/data/` and come from the connector library's recorded test fixtures (copy the smallest Google events response and its OAuth token response; reference by `bodyFile`).

- [ ] **Step 1: Write the failing tests**

```swift
func testAllScenarioFilesPass() async throws {
    for url in try scenarioURLs() {
        let result = try await ScenarioRunner(url: url).run()
        XCTAssertEqual(result.failures, [], url.lastPathComponent)
    }
}
func testRunnerReportsAMismatch() async throws {
    let bad = Scenario.inline(steps: [.send(["type": "start"]), .expectEvents([["type": "nope"]])])
    let result = try await ScenarioRunner(scenario: bad).run()
    XCTAssertFalse(result.failures.isEmpty)
}
```

and `c-smoke/smoke.c`:

```c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "timetug_engine.h"

static int saw_ready = 0, saw_state = 0, after_destroy = 0, destroyed = 0;

static void on_message(void *context, const char *json) {
    (void)context;
    if (destroyed) after_destroy++;
    if (strstr(json, "\"type\":\"ready\"")) saw_ready = 1;
    if (strstr(json, "\"type\":\"state\"")) saw_state = 1;
}

int main(int argc, char **argv) {
    const char *dir = argc > 1 ? argv[1] : ".";
    char escaped[1024], config[1200];
    size_t j = 0;
    for (const char *c = dir; *c && j + 2 < sizeof escaped; c++) {
        if (*c == '\\' || *c == '"') escaped[j++] = '\\';
        escaped[j++] = *c;
    }
    escaped[j] = 0;
    snprintf(config, sizeof config, "{\"v\":1,\"dataDirectory\":\"%s\",\"platform\":\"linux\"}", escaped);
    tt_engine *e = tt_engine_create(config, on_message, NULL);
    if (!e) { fprintf(stderr, "create failed\n"); return 1; }
    tt_engine_send(e, "{\"v\":1,\"type\":\"start\"}");
    for (int i = 0; i < 200 && !(saw_ready && saw_state); i++) {
#ifdef _WIN32
        Sleep(25);
#else
        usleep(25000);
#endif
    }
    tt_engine_destroy(e);
    destroyed = 1;
    if (!saw_ready || !saw_state) { fprintf(stderr, "no ready/state\n"); return 2; }
    if (tt_engine_create("{bad", on_message, NULL) != NULL) return 3;
    return after_destroy == 0 ? 0 : 4;
}
```

(add `#include <windows.h>` under `_WIN32` and `<unistd.h>` otherwise; `run.sh` builds with `cc` against the built library and the header and runs it with a temporary directory; a `run.ps1` does the same with `cl`.)

- [ ] **Step 2–4:** run (FAIL), implement runner and scenarios, run (PASS); run `c-smoke/run.sh` locally.
- [ ] **Step 5: Commit** — `git commit -m "C interface: scenario runner, first scenarios and C smoke test"`.

---

### Task 9: Remaining scenarios and robustness

**Files:**
- Create: `Conformance/Scenarios/{snooze-refire.json,late-takeover-after-wake.json,settings-persist-across-restart.json,invalid-command.json,destroy-while-signin-pending.json,time-zone-change.json}`
- Modify: `Tests/TimeTugEngineCTests/ScenarioRunner.swift` (support `restart` step: destroy and create again on the same data directory)

**Interfaces:**
- Consumes: runner from Task 8.
- Produces: scenario set listed in the spec's Testing section; a `restart` step and a `"expect": {"noMoreMessagesFor": 0.2}` form for "no callback after destroy".

- [ ] **Step 1: Write the scenarios and one failing test per scenario name** (the Task 8 `testAllScenarioFilesPass` already globs the directory; add `testScenarioInventory` asserting the exact name list so a deleted scenario fails the build):

```swift
func testScenarioInventory() throws {
    let names = try scenarioURLs().map { $0.deletingPathExtension().lastPathComponent }.sorted()
    XCTAssertEqual(names, [
        "add-account-oauth", "destroy-while-signin-pending", "http-timeout", "invalid-command",
        "late-takeover-after-wake", "settings-persist-across-restart", "snooze-refire", "start-ready",
        "takeover-after-clock", "time-zone-change",
    ])
}
```

- [ ] **Step 2: Run** — FAIL (missing files, then any real defect the scenarios expose; fix defects in Tasks 6–7 code, not by weakening expectations).
- [ ] **Step 3: Implement** scenario files and runner additions.
- [ ] **Step 4: Run** the whole package suite on macOS and, via the PR, on Linux and both Windows architectures. Fix flakes with bounded waits and explicit synchronization, never sleeps.
- [ ] **Step 5: Commit** — `git commit -m "C interface: remaining scenarios and robustness tests"`.

---

### Task 10: Architecture check and CI wiring

**Files:**
- Modify: `scripts/ci/check-architecture.sh`, `scripts/ci/count-swift-tests.py` (new test targets in the Windows floor), `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: new modules.
- Produces: rules (a) `TimeTugEngineProtocol` public declarations never mention `TimeTugCalendarEvent`, `DayAgenda`, `CalendarInfo`, `Connection` or other Core/engine types (grep the `public` lines of `Sources/TimeTugEngineProtocol` against a deny list, excluding the files `StateMapping.swift` and `CommandMapping.swift` whose public API takes engine types by design: allow-list exactly those two files); (b) `@_cdecl` appears only under `Sources/TimeTugEngineC`; (c) no platform imports in the three new modules.

- [ ] **Step 1: Write the failing check** — add a deliberately violating temporary file in a throwaway branch and confirm `scripts/ci/check-architecture.sh` exits non-zero; then remove it.
- [ ] **Step 2: Implement** rules and CI steps (build `TimeTugEngineC` product; run `c-smoke` on `macos`, `linux`, `windows-x64`, `windows-arm64`).
- [ ] **Step 3: Verify** — `scripts/ci/check-architecture.sh` exits 0 on the real tree; CI green on all five jobs.
- [ ] **Step 4: Commit** — `git commit -m "CI: architecture rules and C smoke for the C interface"`.

Open a pull request for Tasks 6–10 (`semver:minor`), run a DeepSeek review (spec, plan, protocol and C module files, tests), verify findings, fix, merge when green.

---

### Task 11: Managed wrapper

**Files:**
- Create: `dotnet/TimeTug.Engine/{TimeTug.Engine.csproj,NativeMethods.cs,Engine.cs,IEngineHost.cs,Messages.cs,WireJson.cs}`, `dotnet/TimeTug.Engine.sln`

**Interfaces:**
- Consumes: the header and fixtures.
- Produces:

```csharp
namespace TimeTug.Engine;

public interface IEngine : IAsyncDisposable
{
    IAsyncEnumerable<EngineState> State { get; }
    IAsyncEnumerable<EngineEvent> Events { get; }
    ValueTask SendAsync(EngineCommand command, string? id = null);
}

public sealed class EngineOptions
{
    public required string DataDirectory { get; init; }
    public string Platform { get; init; } = "windows";
    public IReadOnlyDictionary<string, string> OAuthClientIds { get; init; } = new Dictionary<string, string>();
    public string? TimeZone { get; init; }
    public Action<Action>? Dispatcher { get; init; }
    public bool Testing { get; init; }
    public required IEngineHost Host { get; init; }
}

public interface IEngineHost
{
    ICredentialStore Credentials { get; }
    IHttpTransport Http { get; }
    IAuthorizationInteraction Authorization { get; }
    ITextGenerator? TextGenerator { get; }
    void Diagnostic(EngineDiagnostic diagnostic);
}

public static class EngineFactory { public static IEngine Create(EngineOptions options); }
```

`NativeMethods` uses `[LibraryImport("TimeTugEngineC")]` for the four functions and `[UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]` for the callback, with a `GCHandle` for the context held until `DisposeAsync` completes. `DisposeAsync` is idempotent and calls `tt_engine_destroy` exactly once; when called from within an event handler it must not wait on its own delivery. Records in `Messages.cs` are written to match the fixtures; `WireJson` is a `JsonSerializerContext` (source generated) with `JsonSerializerOptions { PropertyNamingPolicy = CamelCase, UnmappedMemberHandling = Skip }`.

- [ ] **Step 1: Write the failing test** (in Task 12's project; here, only that `dotnet build` of the wrapper fails before implementation: `dotnet build dotnet/TimeTug.Engine -c Release` → FAIL, project missing).
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify** — `dotnet build dotnet/TimeTug.Engine -c Release` succeeds with warnings-as-errors and the trimming and AOT analyzers enabled (`<IsAotCompatible>true</IsAotCompatible>`).
- [ ] **Step 4: Commit** — `git commit -m "dotnet: managed wrapper for the engine"`.

---

### Task 12: C# tests and scenario runner on both Windows architectures

**Files:**
- Create: `dotnet/pack/assemble-native.ps1` (copies the built DLL and its Swift runtime closure; see the description in Task 13, which reuses it), `dotnet/TimeTug.Engine.Tests/{TimeTug.Engine.Tests.csproj,FixtureRoundTripTests.cs,ScenarioRunner.cs,ScenarioTests.cs,Support.cs}`
- Modify: `.github/workflows/ci.yml` (jobs `dotnet-windows-x64` on `windows-latest` and `dotnet-windows-arm64` on `windows-11-arm`: setup-dotnet 8, install Swift (existing script), `swift build -c release --product TimeTugEngineC`, copy the DLL and runtime closure next to the test binary, `dotnet test`), `scripts/ci/count-swift-tests.py` (also count C# tests: fail below a floor file `scripts/ci/dotnet-test-floor.txt`)

**Interfaces:**
- Consumes: scenario files and fixtures from `Conformance/` (referenced as linked content items, so there is one copy), the managed wrapper.
- Produces: the same scenario semantics as the Swift runner (subset match, ordered subsequence, `restart`, `noMoreMessagesFor`).

- [ ] **Step 1: Write the failing tests**

```csharp
[Fact] public void EveryFixtureRoundTripsAsParsedJson()
{
    foreach (var path in Directory.EnumerateFiles(FixtureDir, "*.json").Where(p => !Path.GetFileName(p).StartsWith("edge-")))
    {
        var original = JsonNode.Parse(File.ReadAllText(path))!;
        var envelope = JsonSerializer.Deserialize(original.ToJsonString(), WireJson.Default.Envelope)!;
        var again = JsonNode.Parse(JsonSerializer.Serialize(envelope, WireJson.Default.Envelope))!;
        Assert.True(JsonNode.DeepEquals(original, again), Path.GetFileName(path));
    }
}

[Fact] public void ScenarioInventoryMatchesSwift() { /* same ten names as the Swift inventory test */ }

[Theory, MemberData(nameof(ScenarioFiles))]
public async Task ScenarioPassesThroughTheRealDll(string file)
{
    var result = await new ScenarioRunner(file).RunAsync();
    Assert.Empty(result.Failures);
}
```

- [ ] **Step 2: Run** — `dotnet test dotnet/TimeTug.Engine.Tests -c Release` → FAIL until the runner exists, then fix real defects in the wrapper or engine bridge.
- [ ] **Step 3: Implement** and run locally on the Windows ARM VM (Developer Mode or an elevated shell; the CI jobs are the reference).
- [ ] **Step 4: Verify** — add to each job a step that lists the DLL's exports (`dumpbin /exports`) and fails unless `tt_engine_create`, `tt_engine_send`, `tt_engine_reply` and `tt_engine_destroy` are all present; the macOS and Linux jobs do the same with `nm -g` on the library. Both CI jobs green; run each job twice for flake detection. Add both job names to the required checks only after two green runs on each architecture (owner's ruleset: ask the owner to add them; do not edit rulesets).
- [ ] **Step 5: Commit** — `git commit -m "dotnet: fixture and scenario tests against the real DLL"`.

---

### Task 13: Packaging, publishing job and size measurement

**Files:**
- Create: `dotnet/pack/{TimeTug.Engine.nuspec.props,measure-size.ps1}`, `docs/spikes/2026-10-phase-4-package-size.md`
- Modify: `.github/workflows/release.yml`, `dotnet/TimeTug.Engine/TimeTug.Engine.csproj` (pack metadata, `runtimes/win-x64/native`, `runtimes/win-arm64/native`, `contentFiles` for header and fixtures)

**Interfaces:**
- Consumes: Task 12 jobs' build steps.
- Produces: job `publish-nuget` (matrix of two Windows runners building native assets, one pack job on `windows-latest` that downloads both artifacts, runs the C# tests on its own architecture, `dotnet pack -p:Version=<tag>`, and pushes).

`assemble-native.ps1` (created in Task 12) copies `TimeTugEngineC.dll` from `swift build --show-bin-path` and the Swift runtime DLLs it needs: it runs `dumpbin /dependents` recursively over the DLL and the Swift runtime directory, copies each dependency that exists under the runtime directory, excludes `MSVCP140.dll`, `VCRUNTIME140*.dll` and Windows system DLLs, and fails if any dependency is found nowhere. `measure-size.ps1` prints, per architecture: uncompressed native set bytes, `Compress-Archive` (optimal) zip bytes, and the nupkg size.

Publishing step: the job needs the OIDC write permission (the `id-token` permission set to write) and the `publish` environment; it uses `NuGet/login@v1` with the owner's nuget.org user name from a repository variable `NUGET_USER`; if the variable is empty the job prints `::notice::nuget.org trusted publishing is not configured; package built and tested, not pushed` and still uploads the `.nupkg` as a workflow artifact. Push with `dotnet nuget push *.nupkg --source https://api.nuget.org/v3/index.json --skip-duplicate`. Pin third-party actions by commit SHA like the existing workflows.

- [ ] **Step 1: Write the failing check** — `pwsh dotnet/pack/assemble-native.ps1 -Rid win-x64 -Out out` on a tree without a built DLL exits non-zero with a clear message; add a Pester-free test: a script `scripts/ci/tests/test_pack_inventory.py` that unzips a produced nupkg and asserts the required entries (`runtimes/win-x64/native/TimeTugEngineC.dll`, `runtimes/win-arm64/native/TimeTugEngineC.dll`, `lib/net8.0/TimeTug.Engine.dll`, `contentFiles/any/any/include/timetug_engine.h`, at least one `fixtures/` file).
- [ ] **Step 2: Implement** scripts and workflow job.
- [ ] **Step 3: Verify** — the job runs `scripts/ci/tests/test_pack_inventory.py` on the produced nupkg before any push and stamps `EngineBuild.version` with the tag before building; run the job through a `workflow_dispatch` dry-run input (`publish: false`) on the PR branch; record sizes in `docs/spikes/2026-10-phase-4-package-size.md` with the decision against the 40 MB per-architecture trigger.
- [ ] **Step 4: Commit** — `git commit -m "Release: build and publish the TimeTug.Engine package"`.

Open a pull request for Tasks 11–13 (`semver:minor`), DeepSeek review of the workflow and wrapper (exclude token-named variables per the review notes: describe them in the background), fix, merge when green.

---

### Task 14: Release, bump chain, tracker and handoff

**Files:**
- Modify (in `timetug`): `docs/superpowers/plans/2026-10-09-windows-program-tracker.md`, memory file `windows-program.md`
- Create (in `timetug`): `docs/engine-protocol.md` (generated message catalog from `MessageCatalog`; the ABI rules; how to run the conformance suites)

- [ ] **Step 1:** Confirm the `timetug-shared` release for the merged work exists (`gh release list --repo binary-companion/timetug-shared --limit 3`) and that its `publish-nuget` job reported pushed or skipped.
- [ ] **Step 2:** Confirm the bump PR in `timetug` opens and is green; merge it (squash) when green under the standing authorization.
- [ ] **Step 3:** Write `docs/engine-protocol.md`; update the tracker (phase 4 row: built and merged, owner items: nuget.org account, trusted publisher, required-check additions); update memory.
- [ ] **Step 4:** Verify with `gh pr checks` that every PR of the phase is merged and green; report the owner to-do list (nuget.org account and id reservation, trusted-publishing policy for `release.yml` and environment `publish`, add the two C# jobs to the required checks).
- [ ] **Step 5: Commit** — `git commit -m "Tracker: phase 4 built and merged"` and open the tracker PR.

---

## Self-review notes

- Spec coverage: ABI rules (Tasks 7, 9), contract and versioning (2–5), host services and timeouts (6, 8, 9), settings file (1), time zone (2, 9), test hooks (4, 7), conformance in two runners (8, 9, 12), packaging, trusted publishing and size (13), architecture rules (10), release chain (14). The "every `EngineState` property has a wire field" test is Task 3.
- Known plan risks for the implementer: the exact member-id scheme for merged events (Task 3) and the connector-registry construction (Task 7) must be read from the current code before writing; both are called out where they occur. Scenario HTTP bodies are copied from the connector library's recorded fixtures, so Task 8 depends on their present names.
