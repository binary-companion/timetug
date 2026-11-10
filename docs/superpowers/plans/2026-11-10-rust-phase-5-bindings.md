# Rust phase 5: generated bindings — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `timetug-shared` ships a typed Swift package (`TimeTugKit`, an XCFramework plus generated Swift) and proves Kotlin bindings compile, so Apple and Android hosts can run the Rust engine without JSON.

**Architecture:** A new crate, `timetug-engine-ffi`, wraps `timetug-engine` with UniFFI proc-macros: records and enums mirror the engine's values, an `Engine` object takes commands, and the host implements async callback interfaces. A Swift package holds the generated code, a thin hand-written layer that restores today's Swift spellings, and a binary target. The C interface is untouched.

**Tech Stack:** Rust (pinned stable), `uniffi` (pinned exact version, proc-macro mode, `tokio` async runtime support), Swift 6 / SwiftPM / `xcodebuild -create-xcframework`, Kotlin (compile check only, `kotlinc` plus JNA), Android NDK through `cargo-ndk` (build check only).

**Spec:** [`docs/superpowers/specs/2026-11-10-rust-engine-program-design.md`](../specs/2026-11-10-rust-engine-program-design.md), sections 6.5 and 6.6. **Conventions:** [`2026-11-10-rust-port-conventions.md`](2026-11-10-rust-port-conventions.md).

All paths are in `binary-companion/timetug-shared`. Until phase 4's cutover, branches are from `v2`; after it, from `main`.

## Global Constraints

- **UniFFI knowledge must come from its documentation for the pinned version**, not from memory: the user guide chapters on proc-macros, records, enums, errors, objects, callback interfaces / foreign traits, async, and the Swift and Kotlin binding pages. Task 1 exists to find out what the pinned version can and cannot do; later tasks follow Task 1's written findings.
- `uniffi` is a dependency of `timetug-engine-ffi` only. No other crate gains a UniFFI attribute or dependency. Engine and core types are converted at the boundary, never annotated in place.
- The C interface, its header, the wire protocol and the NuGet package do not change in this phase.
- The bindings expose the engine level and the model (design section 6.5), not connector internals. Hosts never construct connector kinds; they pass configuration.
- State and events keep the C interface's delivery rules: one observer, calls serialized and ordered, states coalesced newest-wins, nothing after shutdown returns.
- Every host interface is async and its implementors are thread-safe.
- Generated Swift names equal today's Swift names wherever UniFFI allows; every difference is listed in `docs/bindings.md` with the Swift-side shim that hides it (or the reason there is none).
- Generated code is committed and CI fails if regeneration changes it.
- `unsafe` stays confined to what UniFFI generates and `timetug-engine-c`.
- iOS simulator slice: arm64 only.

## Review Focus

1. **A large agenda** (500 events, each with attendees and reminders) crossing the boundary on every state change: measure the time and allocations of one state delivery; it must stay under 5 ms on an Apple Silicon Mac in release. Pinned by Task 6, step 5; if it fails, apply the split described there.
2. **A host callback that throws or never returns** (Keychain locked, EventKit denied, the sign-in window closed): the engine sees an error or a cancellation, never a hang or a crash. Pinned by the fake-host tests in Task 6 with a throwing and a never-returning implementation of each interface.
3. **The host object outliving the engine, or the reverse** (the app quits during a refresh; the engine is released while a callback runs): no use-after-free, no callback after `shutdown()` returns. Pinned by Task 6's lifecycle tests, run 500 times in a loop.
4. **Main-actor adapters**: a Swift host interface implemented by a `@MainActor` type must not deadlock when the engine calls it while the main thread is waiting on the engine. Pinned by a test with a `@MainActor` fake whose methods are called during `await engine.send(...)` issued from the main actor.
5. **Text with unusual Unicode and very long strings** in titles and notes round-trips unchanged through the boundary. Pinned by a round-trip test in Task 6.

---

### Task 1: Spike — what UniFFI can express

Throwaway code on a branch that is never merged; the deliverable is a document.

**Files:**
- Create (kept): `docs/bindings-spike.md`
- Create (throwaway, branch `spike/uniffi`): a minimal `timetug-engine-ffi` with UniFFI, a Swift test package and a Kotlin compile script

- [ ] **Step 1: Choose and pin the version.** The newest released `uniffi`; record it. Read its changelog for breaking changes in async and foreign traits.
- [ ] **Step 2: Build the smallest end-to-end path**: one record, one function, generate Swift, build a static library for `aarch64-apple-darwin`, wrap it in an XCFramework, call it from a SwiftPM test. Write down the exact commands that worked (the bindgen invocation, library-mode or not, the header and modulemap names it emits, the `xcodebuild -create-xcframework` line).
- [ ] **Step 3: Probe the hard shapes**, one small experiment each, and record for each "works as is", "works with this workaround", or "does not work":

| Probe | Why |
|---|---|
| A record with 40 fields including nested records, optionals, `Vec`, `BTreeMap<String, _>` and a set | `CalendarEvent` |
| An enum with associated values, labeled and unlabeled, and an enum nested in a record | `SeriesInfo`, `Participation`, `ReminderTrigger`, `EventEdit` |
| A custom type for `Timestamp` as Swift `Date`, `Zone` as Swift `TimeZone`, `UrlString` as Swift `URL`, `Uuid` as `UUID`, `Vec<u8>` as `Data` | natural Swift types at the call site |
| An error enum thrown from Rust and caught as a typed Swift error; an error thrown by a Swift callback and received in Rust | `SourceError`, `WriteError`, host failures |
| An async Rust method called with Swift `await`, driven by a `tokio` current-thread runtime that lives on the engine thread | `engine.send` |
| An async foreign-implemented trait (Swift implements, Rust awaits), including one whose Swift implementor is `@MainActor` and one that never returns followed by Rust dropping the future | host interfaces; cancellation |
| A foreign-implemented trait passed inside a record or returned from another foreign trait method | `beginOAuthRedirect() -> OAuthRedirectSession` |
| A foreign trait with 12 methods, some returning optional records | the system calendar source with read, series and write |
| A non-async foreign trait called from the engine's delivery thread at high rate | the state and event observer |
| Kotlin generation of all of the above and `kotlinc` compilation | Android |
| Default argument values, and `Equatable`/`Hashable`/`Sendable` conformances on generated records and enums | the Mac app compares and hashes these types today |
| Two generated types that need Swift names equal to Foundation or app types (`Calendar*`, `Connection`) | name clashes |

- [ ] **Step 4: Measure** the release static library size for `aarch64-apple-darwin` with the probes in, and the per-call overhead of passing a 500-event `Vec` of the 40-field record (a loop of 1,000 calls).
- [ ] **Step 5: Write `docs/bindings-spike.md`**: the pinned version, the working commands, the probe table with results and workarounds, the measurements, and a recommendation for each "does not work" (usually: flatten the type at the boundary and restore the spelling in the Swift shim layer).
- [ ] **Step 6: Review gate.** Run `deepseek-review` on the document; then the owner reads the summary. If a "does not work" has no acceptable workaround, stop and report before Task 2.

### Task 2: Crate skeleton, conversions and custom types

**Files:**
- Modify: `crates/timetug-engine-ffi/Cargo.toml` (add `uniffi` at the pinned version, `tokio` support feature as the spike found), workspace `Cargo.toml`, `deny.toml`, `scripts/ci/check-crate-architecture.py` (allow `uniffi` for this crate only), `THIRD-PARTY-NOTICES.md`
- Create: `crates/timetug-engine-ffi/src/lib.rs`, `src/custom_types.rs`, `src/errors.rs`, `src/bin/uniffi-bindgen.rs` (if the pinned version uses an in-workspace bindgen binary; follow the spike)
- Create: `crates/timetug-engine-ffi/src/tests/custom_types.rs`

**Interfaces (produced):**
- Swift-facing custom types: `Timestamp` as `Date` (milliseconds since 1970 as `i64` on the wire), `Zone` as `TimeZone` (identifier string; an unknown identifier from the host is an error at the call, not a panic), `UrlString` as `URL` (original text), `uuid::Uuid` as `UUID`, durations as `TimeInterval` (`f64`).
- `FfiError`: one error enum for everything thrown to the host, with cases mirroring `Failure`: `Source(SourceError mirror)`, `Write(WriteError mirror)`, `Cancelled`, `Host(message)`, `InvalidConfig(reason)`.
- `HostError`: what a host callback may throw: `Network(message)`, `Cancelled`, `NotFound`, `Denied`, `Failed(message)` (the same five kinds as the C interface's reply errors), converted to `Failure` exactly as `RemoteHostServices` converts reply errors.

- [ ] **Step 1: Tests first**: round-trip conversions for each custom type, including a `Date` with sub-millisecond precision (rounds to the nearest millisecond), a fixed-offset zone, a URL with non-ASCII text, and the error mappings in both directions (table-driven, every case).
- [ ] **Step 2: Implement; `cargo test -p timetug-engine-ffi`.**
- [ ] **Step 3: Commit; pull request.**

### Task 3: Value mirrors

**Files:**
- Create: `crates/timetug-engine-ffi/src/values/{model,write,state,settings,events,commands,accounts,diagnostics,widget}.rs`, and `src/tests/value_mirrors.rs`

Each engine-level value gets a mirror type annotated for UniFFI and two conversions (`From<engine type> for Mirror` and `TryFrom<Mirror> for engine type` where the host can send it). The mirror's name is the Swift name of the original type.

| Mirror module | Types (Swift names) |
|---|---|
| `model` | `CalendarEvent`, `TimeTugCalendarEvent`, `CalendarDescriptor`, `CalendarInfo`, `Attendee`, `ConferenceInfo`, `Reminder`, `ReminderTrigger`, `ReminderType`, `StructuredLocation`, `SeriesInfo`, `Participation`, `CalendarPermissions`, `CalendarService`, `CalendarProvider`, `CalendarSeries`, `RecurrenceRule`, `RecurrenceSet`, `MergedMember`, `MergeProvenance`, `SourceCapabilities`, `SourceNotice`, `SourceStatus`, `CalendarChange`, `CalendarDate`, and every plain enum they use |
| `write` | `EventDraft`, `AttendeeDraft`, `EventPatch`, `EventEdit`, `EventRef`, `FieldUpdate` (one concrete mirror per instantiation the model uses, named in `docs/bindings.md`), `RecurrenceScope`, `WriteError`, `WriteValidation` |
| `state` | `EngineState`, `DayAgenda`, `AccountKindInfo`, `ScheduledTakeover`, `TakeoverLedger` (read-only view), `InferenceStatus`, `TakeoverRequest` |
| `settings` | `EngineSettings`, `TakeoverSettings`, `NotifyPolicy`, and a `SettingsPatch` record with one optional per setting (replacing the Swift closure in `applySettings`) |
| `events` | `EngineEvent` |
| `commands` | `EngineCommand` (with `ApplySettings(SettingsPatch)`), `SystemEvent` |
| `accounts` | `Connection`, `ConnectionID`, `CredentialField`, `CredentialHelp`, `CredentialSnapshot`, `AuthorizationMethod`, `Platform`, the account status type |
| `diagnostics` | `EngineDiagnostic`, `DiagnosticEvent`, `DiagnosticLevel` |
| `widget` | `WidgetSnapshot`, `WidgetEvent` |

- [ ] **Step 1: Generate the field lists** from the Rust engine types (they are the source of truth now), not from memory: for each type, the mirror has the same fields in the same order with mirror or custom types.
- [ ] **Step 2: Tests**: for each mirror, build a fully populated engine value (reuse the builders in the engine's test support by making them `pub` behind a `test-support` cargo feature), convert to the mirror and back, and assert equality. For types the host never sends, assert the forward conversion against a hand-written expected mirror for one rich value.
- [ ] **Step 3: Completeness check.** `scripts/ci/check-bindings-surface.py` (test first): reads a committed list `docs/bindings-surface.txt` (the 108 type names the Mac app uses today, taken from the list in the design's section 2 measurement; regenerate it with the grep in `docs/bindings.md`) and fails for any name that is neither a mirror type, a host interface, a custom type, nor listed in `docs/bindings.md` under "Not exposed" with a reason. Expected "Not exposed" entries: connector kinds and OAuth config types (replaced by `EngineConfig`), `SHA*`, `ConnectorRegistry`, in-memory stores and test-support types, `Scheduler` and other pure functions the app does not need once the engine reports state (verify each against the app's actual use before listing it; if the app calls it, expose a function).
- [ ] **Step 4: Commit; pull request.**

### Task 4: Host interfaces and configuration

**Files:**
- Create: `crates/timetug-engine-ffi/src/host/{credentials,authorization,sign_in,settings_storage,http,text_generator,diagnostics,external_tokens,system_calendar,observer}.rs`, `src/config.rs`, `src/tests/host_adapters.rs`

**Interfaces (produced; foreign-implemented, async unless noted):**

| Trait (Swift name) | Methods (Swift spelling) | Adapts to |
|---|---|---|
| `CredentialStore` | `secrets(for:)`, `setSecrets(_:for:)`, `removeSecrets(for:)`, `credentialSnapshot(for:)`, `updateRefreshToken(_:for:expectedRevision:)` | `calendar_core::CredentialStore` |
| `AuthorizationInteraction` | `beginOAuthRedirect()` returning an `OAuthRedirectSession`, `promptCredentials(_:)` | `calendar_core::AuthorizationInteraction` |
| `OAuthRedirectSession` | `redirectURI`, `authorize(at:)`, `close()` | `calendar_core::OAuthRedirectSession` |
| `SignInPrompting` | `prepare(title:help:values:error:)`, `lastNonSecretValues()` | `timetug_engine::SignInPrompting` |
| `SettingsStorage` | as the Rust trait | `timetug_engine::SettingsStorage` |
| `HTTPTransport` | `send(_:)` | `calendar_core::HttpTransport` |
| `TextGenerator` | `availability()`, `generate(...)` | `timetug_engine::TextGenerator` |
| `ExternalTokenSource` | as the Rust trait | `calendar_core::ExternalTokenSource` |
| `SystemCalendarSource` | `requestAccess()`, `calendars()`, `events(in:)`, `series(id:calendarID:)`, `capabilities`, the write methods of `WritableCalendarSource`, and `setChangeHandler(_:)` taking a small Rust-implemented callback object the host calls when the system store changes | `timetug_core::CalendarSource` through a `timetug-bridge`-style adapter; `EngineHost.build_system_source` and `request_system_access` |
| `EngineObserver` (not async) | `stateChanged(_:)`, `event(_:)` | the delivery thread |
| `DiagnosticSink` (not async) | `log(_:)` | `EngineDiagnosticSink` |

`EngineConfig` (a record): `dataDirectory`, `platform` (`macos`, `ios`, `android`, `linux`, `windows`), `googleClient` (id and secret, optional), `microsoftClient` (id, optional), `textGeneration` (bool), `externalTokens` (bool), `systemCalendar` (bool), `timeZone` (identifier), `icalRetention` (days back and ahead; default 3 and 7 as in `Connectors.swift`). Registration of connector kinds is `connectors.rs` logic shared with `timetug-engine-c`: move `ConnectorSetup::make` into `timetug-engine` (module `connector_setup`) so both front doors call one function, and adjust `timetug-engine-c` to use it. Adding `ios` and `android` to the platform list also means the connector kinds' `supported_platforms` must include them: check each kind's Swift `supportedPlatforms` and extend the `Platform` flags in `calendar-core` additively (a `calendar-connectors` pull request with tests, released before this task merges).

- [ ] **Step 1: Tests first**, with Rust-side fakes standing in for the foreign side: each adapter forwards every method, converts values both ways, and maps `HostError` to `Failure` per Task 2. For each async trait add the two Review Focus 2 cases (a fake that returns an error; a fake whose future never completes, dropped by the caller, after which the adapter's cleanup has run).
- [ ] **Step 2: Implement the adapters.**
- [ ] **Step 3: The system-calendar change path**: the host calls the handler object; the adapter turns it into `CalendarChange` on the source's `changes()` channel. Test: three handler calls produce three changes in order.
- [ ] **Step 4: Commit; pull request.**

### Task 5: The `Engine` object

**Files:**
- Create: `crates/timetug-engine-ffi/src/engine.rs`, `src/runtime.rs`, `src/tests/engine_object.rs`

**Interfaces (produced, Swift spelling):**

```swift
public final class Engine {
    public init(config: EngineConfig, host: EngineHostInterfaces, observer: EngineObserver) throws   // FfiError.invalidConfig
    public func start() async
    public func send(_ command: EngineCommand) async
    public func currentState() -> EngineState
    public func setTimeZone(_ identifier: String) throws        // then send(.system(.timeZoneChanged))
    public func shutdown()                                      // idempotent; after it returns no observer call starts
}
```

`EngineHostInterfaces` is a record of the host objects of Task 4 (optional ones optional: text generator, external tokens, system calendar).

**Decisions:**
- `runtime.rs` reuses the session design of `timetug-engine-c`: one engine thread with a `tokio` current-thread runtime, one delivery thread, the same `Delivery` coalescing queue. Move `Delivery` (minus the C callback type) from `timetug-engine-c` into `timetug-engine` as `host_delivery` with a generic sink, so both crates share one implementation and one set of tests; `timetug-engine-c` keeps passing its harness afterwards.
- Async Rust methods exposed to Swift must complete on the engine runtime: follow the pattern the spike recorded for running UniFFI async methods on a specific `tokio` runtime.
- `shutdown()` called from inside an observer call returns at once (same rule as `tt_engine_destroy`). `Drop` of the Rust object calls `shutdown()`.
- No `testing` flag or manual clock in the public surface. A cargo feature `test-clock` (off in release) adds `Engine.newForTesting(..., clockStart:)` and `advanceClock(seconds:)`, used only by the Swift tests of Task 6.

- [ ] **Step 1: Tests first** (Rust, fakes for every host interface): construct with an invalid config (each `InvalidConfig` reason); `start` then first observer call is a state; a command changes state; `shutdown` stops observer calls; `shutdown` inside an observer call; drop without shutdown.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Re-run** `c-harness/run.sh --rust` and the scenarios to prove the `Delivery` move changed nothing.
- [ ] **Step 4: Commit; pull request.**

### Task 6: Swift package `TimeTugKit`

**Files:**
- Create: `swift/TimeTugKit/Package.swift`
- Create: `swift/TimeTugKit/Sources/TimeTugKit/Generated/` (bindgen output, committed)
- Create: `swift/TimeTugKit/Sources/TimeTugKit/Shims/*.swift` (hand-written)
- Create: `swift/TimeTugKit/Tests/TimeTugKitTests/*.swift`
- Create: `scripts/dev/build-xcframework.sh`, `scripts/dev/generate-bindings.sh`
- Create: `docs/bindings.md`
- Modify: `.github/workflows/ci.yml` (job `swift-bindings`), root `Package.swift` (new, see Task 8)

**Interfaces (produced):**
- `scripts/dev/generate-bindings.sh`: builds the ffi crate for the host, runs the bindgen for Swift into `Generated/` and for Kotlin into `kotlin/generated/`.
- `scripts/dev/build-xcframework.sh [--release]`: builds `timetug-engine-ffi` as a static library for `aarch64-apple-darwin`, `x86_64-apple-darwin` (joined with `lipo`), `aarch64-apple-ios`, `aarch64-apple-ios-sim`; runs `xcodebuild -create-xcframework` with the generated header and modulemap; output `build/TimeTugEngineFFI.xcframework`. The static library keeps the symbols the final link needs: use a cargo profile `release-apple` inheriting `release` with `strip = "debuginfo"` (the spike records whether `strip = "symbols"` breaks linking).
- `Package.swift` of `TimeTugKit`: `platforms: [.macOS(.v14), .iOS(.v17)]`; `binaryTarget(name: "TimeTugEngineFFI", path: "../../build/TimeTugEngineFFI.xcframework")`; target `TimeTugKit` depending on it; test target.

**Shims** (hand-written Swift, each with a test): conformances the generator does not add (`Identifiable` on `CalendarEvent` with `id == "\(calendarID)/\(eventID)"`, `Comparable` on `CalendarDate`), computed properties the Swift model had and the app uses (`seriesID`, `originalStart`, `conference`, `myResponse`, `accessRole`, `minutesBefore`; take the list from `Model.swift` computed properties and keep only those the app references), `FieldUpdate<T>` as a generic Swift enum bridged to the concrete mirrors, a convenience `applySettings { settings in ... }` that diffs into a `SettingsPatch`, and `AsyncStream` accessors `engine.states` and `engine.events` built on an internal observer (so `EngineModelMirror` in the app keeps its shape).

- [ ] **Step 1: Generate and build**: `scripts/dev/generate-bindings.sh && scripts/dev/build-xcframework.sh && swift build --package-path swift/TimeTugKit`.
- [ ] **Step 2: Fake hosts in Swift** (`Tests/TimeTugKitTests/Fakes.swift`): an in-memory implementation of every host interface, with switches to throw and to never return.
- [ ] **Step 3: Scenario test**: drive a full path through the bindings with the test clock: start; add an iCal-link account whose HTTP the fake transport serves from a string; state shows the account and its events; advance the clock to the lead time; the observer receives `takeoverDue`; `dismiss`; shutdown. This is the phase gate's "Swift test target drives a full scenario".
- [ ] **Step 4: The Review Focus tests** 2 to 5 (throwing and never-returning hosts; lifecycle loop of 500; `@MainActor` fake; Unicode and long-string round trip).
- [ ] **Step 5: Performance test** (Review Focus 1): a state with 500 events delivered 200 times; median under 5 ms in release on Apple Silicon. If it fails: split `EngineState` delivery so the observer receives a light `EngineStateSummary` (revision, statuses, account status, next takeover, flags) and the host fetches `events`, `agenda` and `candidates` with `engine.currentEvents()` only when their sub-revision changed; record the change in `docs/bindings.md`.
- [ ] **Step 6: iOS simulator link check**: `xcodebuild build -scheme TimeTugKit -destination 'generic/platform=iOS Simulator' -packagePath swift/TimeTugKit` (or the equivalent the spike recorded). Expected: build succeeds.
- [ ] **Step 7: Write `docs/bindings.md`**: how to regenerate, the name-difference table, the "Not exposed" table, the shim list, the threading rules for host implementors (thread-safe, may be called from the engine thread, must not block it for long, main-actor work hops inside the method).
- [ ] **Step 8: CI job `swift-bindings`** on `macos-26`: regenerate and `git diff --exit-code` on `Generated/`; build the XCFramework; `swift test --package-path swift/TimeTugKit`; the iOS simulator build.
- [ ] **Step 9: Commit; pull request.**

### Task 7: Kotlin and Android proof

**Files:**
- Create: `kotlin/generated/` (committed), `kotlin/compile-check.sh`
- Modify: `.github/workflows/ci.yml` (job `kotlin-bindings`, `ubuntu-latest`)

- [ ] **Step 1: `compile-check.sh`**: downloads pinned versions of `kotlinc` and the JNA jar into a cache directory (checksums verified, versions in the script), compiles `kotlin/generated/**/*.kt`. Expected: no errors.
- [ ] **Step 2: Android build check** in the same job: install the pinned NDK and `cargo-ndk` (pinned), `cargo ndk -t arm64-v8a build --release -p timetug-engine-ffi`. Expected: `libtimetug_engine_ffi.so` exists. Record its size in `docs/rust-port/size.md`. Confirm `jiff` uses its bundled zone database or Android's `tzdata` on that target (design section 6.2) by a unit test compiled for the target if an emulator is available, otherwise by reading `jiff`'s platform documentation and recording the finding.
- [ ] **Step 3: Regeneration check**: `git diff --exit-code kotlin/generated`.
- [ ] **Step 4: Commit; pull request.**

### Task 8: Releasing the Swift package

**Files:**
- Create: root `Package.swift` (the package the Mac app will depend on by URL)
- Modify: `.github/workflows/release.yml`, `scripts/release/` (new `write-swift-package.py` and its test), `scripts/ci/compat/compat.py` (new check), `AGENTS.md`

**Design:**
- On `main`, root `Package.swift` declares product `TimeTugKit` with sources at `swift/TimeTugKit/Sources/TimeTugKit` and a **path** binary target (`build/TimeTugEngineFFI.xcframework`) for local development.
- The release workflow, for version `X.Y.Z`: builds the XCFramework on `macos-26` with `TIMETUG_ENGINE_VERSION`; zips it; computes `swift package compute-checksum`; uploads the zip as a release asset named `TimeTugEngineFFI-X.Y.Z.xcframework.zip`; runs `write-swift-package.py X.Y.Z <checksum>`, which rewrites the binary target to `url: "https://github.com/binary-companion/timetug-shared/releases/download/X.Y.Z/TimeTugEngineFFI-X.Y.Z.xcframework.zip", checksum: "<checksum>"`; commits that one-file change as a **release commit whose parent is the `main` commit being released**, and tags the release commit `X.Y.Z` (the tag is not on `main`; SwiftPM resolves tags, not branches). The existing tag-and-publish job is reordered so the asset exists before the tag is pushed. The NuGet jobs build from the same `main` commit.
- A draft release is created first, the asset uploaded, then the tag pushed and the release published, so the URL in the tagged `Package.swift` is live when the tag appears.

- [ ] **Step 1: `write-swift-package.py` test-first**: given a `Package.swift` with the path target, it produces the URL target; refuses a version that is not `X.Y.Z` or `X.Y.Z-alpha.N`; refuses a checksum that is not 64 hex characters; is idempotent.
- [ ] **Step 2: Workflow changes**; test with a dry run: `gh workflow run Release --ref <branch> -f publish=false` must build the XCFramework and the rewritten `Package.swift` as artifacts without tagging (extend the existing dry-run path).
- [ ] **Step 3: New compat check** "Swift bindings API": `swift package diagnose-api-breaking-changes <baseline>` on `TimeTugKit`, skipped until a baseline tag contains the package (the first release with it) and skipped with `semver:major`, like the other checks.
- [ ] **Step 4: Consumer smoke**: a scratch Swift package outside the repository depending on `timetug-shared` at the prerelease tag by URL builds and runs a three-line program that creates a config. Do this after the owner publishes a prerelease from the branch that has this task (`2.0.0-alpha.N` before cutover, or `2.1.0-alpha.N`-style after; add to owner items with the command).
- [ ] **Step 5: Document** in `AGENTS.md`: the release commit, the asset, how the Mac pins it.
- [ ] **Step 6: Commit; pull request.**

### Task 9: Phase close-out

- [ ] **Step 1: Gate** (design section 9, phase 5): the Swift scenario test passes on macOS; the iOS simulator build links; Kotlin compiles; the Android library builds. Links in the tracker.
- [ ] **Step 2: Sizes**: record the macOS static library slice size and the size it adds to a linked test executable in `docs/rust-port/size.md`.
- [ ] **Step 3: Update `timetug`**: `docs/architecture.md` ("Adding a platform front end": Swift and Kotlin hosts use `TimeTugKit` / the Kotlin bindings; C-capable hosts use the C interface), tracker (phase 5 `done`, Now to phase 6).
