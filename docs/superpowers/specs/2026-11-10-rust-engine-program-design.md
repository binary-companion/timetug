# Rust engine program design

Status: draft for owner approval, 2026-11-10. Lines marked **(agent call)** are decisions the agent made; everything else the owner stated or the repositories show.

## 1. Intent

TimeTug will run on many platforms: Mac and Windows now, then Linux, iOS and Android. The owner wants one core engine for all of them, as small and as light on memory and CPU as it can be. The shared code is Swift today. Swift is free on Apple platforms, where the runtime is part of the system, and expensive everywhere else, where the runtime ships inside the app.

The program rewrites the two shared libraries in Rust:

- `binary-companion/calendar-connectors`: the calendar connector library.
- `binary-companion/timetug-shared`: `TimeTugCore`, `CalendarBridge`, `TimeTugEngine`, the wire protocol and the C interface.

The apps stay native: the Mac app stays Swift and SwiftUI, the Windows app stays C# and WinUI. The work is phased, Windows first. It is a major version for every component.

## 2. Measured starting point (2026-11-10)

| Item | Value |
|---|---|
| `calendar-connectors` 1.2.0 sources | 88 files, about 11,000 lines of Swift; tests about 12,400 lines |
| `timetug-shared` 1.8.0 sources | 59 files, about 6,500 lines of Swift; tests about 10,400 lines |
| Imports | Foundation, FoundationNetworking, FoundationXML only |
| Windows x64 native payload of `TimeTug.Engine` 1.8.0 | about 70.5 MB uncompressed, about 27 MB compressed, 17 DLLs |
| of which the engine (`TimeTugEngineC.dll`) | 13.0 MB uncompressed, 3.7 MB compressed |
| of which the Swift runtime and Foundation | about 57 MB uncompressed (`_FoundationICU.dll` alone 36.5 MB) |
| Mac app use of the libraries | 88 files import them; 108 of the 214 public types are named in the app and its packages |
| Language-neutral contract | 4 C functions, JSON protocol v1, 74 golden fixtures, 13 scenarios with 8 data files, the .NET test suite |

Facts that shape the design:

- The C interface already keeps HTTP, credentials, sign-in UI, text generation and access tokens on the host side (`service.*` requests). The engine itself needs no network or TLS stack.
- The connector library already has seams for HTTP (`HTTPTransport`), hashing (`SHA256Hashing`), credentials, sync state, OAuth interaction and diagnostics.
- The Windows app talks to the engine only through the `TimeTug.Engine` NuGet package. It names no Swift type.
- The Mac app uses the Swift types directly and implements several seams in Swift: EventKit as a `CalendarSource` (read, series and write), Keychain, loopback OAuth, Apple Intelligence as the `TextGenerator`, settings storage, diagnostics.
- Time zones matter: 190 uses of `TimeZone` in the connector library, a Windows time-zone name table, an iCalendar `VTIMEZONE` resolver and a client-side recurrence expander.

## 3. Goals

1. One Rust implementation of the connector library and of Core, Bridge, Engine, protocol and C interface, with behaviour equal to the Swift baseline.
2. Windows: the native payload falls from about 70 MB to at most 8 MB uncompressed per architecture **(agent call: the budget; the expected result is 3 to 6 MB)**. CI fails above the budget.
3. Memory and CPU at or below the Swift baseline on Windows, measured, with the numbers recorded.
4. Generated bindings (UniFFI) for Swift and Kotlin, so Mac, iOS and Android hosts use typed values instead of JSON.
5. The Mac app keeps its Swift and SwiftUI code and its Apple adapters, and moves onto the Rust engine through the Swift bindings.
6. Users upgrade in place. Every file the 1.x libraries wrote on a user's disk is read by 2.x with the same meaning.
7. Each phase ends in something that works and can be shipped or stopped at.

## 4. Non-goals

- An Android, iOS or Linux app. The program proves the engine builds and its bindings compile for those targets; it builds no front end.
- Changing behaviour, adding features or redesigning the model during the port. The port is a translation.
- Changing the wire protocol. It stays `v: 1` **(agent call)**; the major version is the package version, because the implementation and the Swift API change, not the JSON.
- A Swift source API for third parties. After the program the public form of the libraries is Rust crates, the C interface and the generated bindings.
- Publishing to crates.io. `timetug-shared` depends on `calendar-connectors` by git tag **(agent call)**; publication can come later without a design change.
- A built-in HTTP client. Hosts keep supplying HTTP, as they do today.
- Downgrade: a 1.x app reading files written by 2.x is not promised. 2.x keeps the same file formats wherever it has no reason to change them.

## 5. Anti-goals (failure even if it works)

- A user loses accounts, calendar choices, merge decisions, settings or takeover history on upgrade.
- A takeover fires twice, fails to fire, or fires at a different time than the Swift engine would have.
- The Windows app has to change its own code to accept the Rust engine, beyond the package version and packaging lists.
- A token, password, email address or feed link reaches a log or diagnostic that the Swift engine kept it out of.
- Rust dependencies grow until the size goal is lost, or bring a licence the apps cannot ship.
- The Mac app becomes slower to start, or its code becomes harder to read, because of the boundary.

## 6. Target architecture

### 6.1 Crates

One Cargo workspace per repository. Crates mirror today's Swift products one to one **(agent call)**, so each Swift file has an obvious home and the architecture check keeps its meaning.

`calendar-connectors`:

| Crate | Replaces | Depends on |
|---|---|---|
| `calendar-core` | `CalendarCore` | (external crates only) |
| `calendar-oauth` | `CalendarOAuth` | `calendar-core` |
| `calendar-ical` | `ICalendar` | `calendar-core` |
| `calendar-google` | `GoogleCalendar` | `calendar-core`, `calendar-oauth` |
| `calendar-microsoft` | `MicrosoftCalendar` | `calendar-core`, `calendar-oauth` |
| `calendar-caldav` | `CalDAVCalendar` | `calendar-core`, `calendar-ical` |
| `calendar-ical-subscription` | `ICalSubscription` | `calendar-core`, `calendar-ical` |
| `calendar-test-support` | `CalendarTestSupport` | `calendar-core` |

`timetug-shared`:

| Crate | Replaces | Kind |
|---|---|---|
| `timetug-core` | `TimeTugCore` | library |
| `timetug-bridge` | `CalendarBridge` | library |
| `timetug-engine` | `TimeTugEngine` | library |
| `timetug-engine-protocol` | `TimeTugEngineProtocol` | library |
| `timetug-engine-c` | `TimeTugEngineC` | `cdylib` and `staticlib` with `[lib] name = "TimeTugEngineC"`, so the files stay `TimeTugEngineC.dll`, `libTimeTugEngineC.dylib` and `libTimeTugEngineC.so` (the C# wrapper loads that name); exports the four `tt_engine_*` functions |
| `timetug-engine-ffi` | (new) | UniFFI bindings crate; `staticlib` and `cdylib` |
| `dedup-benchmark` | `DedupBenchmark` | binary |

Dependency direction is unchanged: `calendar-connectors` <- `timetug-shared` <- the apps.

### 6.2 External crates **(agent call)**

The connector library's rule "no package dependencies" becomes "only the crates on this list". Additions need a decision record.

| Need | Crate | Note |
|---|---|---|
| JSON | `serde`, `serde_json` | |
| Time zones, civil time, DST arithmetic | `jiff` | zone database bundled on Windows, iOS and Android; the system database on macOS and Linux. Phase 0 verifies each target and records the size of the bundled database |
| XML (CalDAV) | `quick-xml` | |
| SHA-256 (PKCE) | `sha2` | the `SHA256Hashing` seam goes away; the Mac no longer supplies CryptoKit |
| Random bytes, identifiers | `getrandom`, `uuid` | |
| Percent-encoding and URL handling | `url` | |
| Error types | `thiserror` | |
| Async traits behind `dyn` | `async-trait` | |
| Async runtime | `tokio` with only `rt`, `time`, `sync`, `macros` | one current-thread runtime on the engine thread; never `net`, `fs`, `process` or `rt-multi-thread`. A CI script reads `cargo tree -e features` and fails on any other `tokio` feature |
| Base64 (PKCE, HTTP Basic) | `base64` | |
| Bindings | `uniffi` | only in `timetug-engine-ffi` |

Licences allowed: MIT, Apache-2.0, BSD, ISC, Unicode, Zlib. `cargo-deny` enforces licences, the crate list and known advisories in CI.

### 6.3 Rules carried over

- Core never reads the clock; `now` is passed in. The engine reads time only through `EngineClock`.
- No UI, no platform frameworks, no display strings in any crate.
- `#![forbid(unsafe_code)]` in every crate except `timetug-engine-c` and `timetug-engine-ffi` **(agent call)**.
- Parsers (iCalendar, XML, JSON from providers) return errors and never panic on any input.
- The diagnostics privacy rules of the Swift engine hold word for word.
- Microsoft sign-in scopes stay read-only (ADR 0017). The contract check that pins them is ported.
- The engine uses only the Gregorian calendar and a time zone. The Swift code reads nothing else from the host's `Calendar` (no first weekday, no locale); the one formatter is fixed to `en_US_POSIX`. So a zone identifier is the whole of the host's calendar input.
- C interface threading: `tt_engine_send` and `tt_engine_reply` copy the string and push onto an unbounded channel, so they never block and work from any thread and from inside a callback. The engine never keeps, frees or returns host memory, and the host never frees engine memory; that is what makes a statically linked C runtime safe.

### 6.4 Build profile **(agent call)**

Release builds use `opt-level = "s"`, `lto = "fat"`, `codegen-units = 1`, `strip = "symbols"`, `panic = "abort"`. Abort matches today: a Swift trap also ends the process. No code relies on unwinding at the boundary. The conformance scenarios, `c-smoke` and the .NET suite run against the release-profile library, so the shipped profile is the tested one. The static library for the XCFramework keeps the symbols the linker needs (strip only what the final link does not need; phase 5 settles the exact setting). Windows builds link the C runtime statically (`+crt-static`), so the engine is one DLL with no redistributable.

The toolchain is the stable Rust current when phase 0 starts, pinned in `rust-toolchain.toml` in both repositories and raised only by a reviewed pull request.

Targets: `aarch64-apple-darwin`, `x86_64-apple-darwin`, `aarch64-apple-ios`, `aarch64-apple-ios-sim` (the simulator slice is arm64 only), `x86_64-pc-windows-msvc`, `aarch64-pc-windows-msvc`, `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`, and `aarch64-linux-android` as a build-only check.

### 6.5 Hosts

Two front doors onto the same `timetug-engine`:

1. **C interface** (`timetug-engine-c`): the header `include/timetug_engine.h` and JSON protocol v1, unchanged. Windows uses it through the existing C# wrapper. Linux and any other C-capable host can use it.
2. **Generated bindings** (`timetug-engine-ffi`): a typed API for Swift and Kotlin. Mac and iOS use it; Android will.

The bindings surface is the engine level and the model, not the connectors' internals:

- Values: `EngineState`, `EngineCommand`, `EngineEvent`, `EngineSettings`, `SystemEvent`, the agenda and event model (`TimeTugCalendarEvent`, `CalendarEvent` and the types it is built from), account and source status, diagnostics, widget snapshot, the write model (`EventDraft`, `EventPatch`, `WriteError`).
- An `Engine` object: create from a config and a host, send commands. State and events arrive through an observer interface the host passes at creation (UniFFI has no subscription primitive), with the same ordering and coalescing rules as the C interface.
- Host interfaces implemented in Swift or Kotlin: credential store, authorization interaction and redirect session, sign-in prompting, settings storage, HTTP transport, text generator, diagnostics sink, external token source, and a system calendar source (EventKit on Apple: read, series and write, plus the request for system calendar access that `EngineHost.requestSystemAccess` is today).
- Host interfaces are async, foreign-implemented UniFFI traits. Every implementor must be thread-safe; the Mac adapters that touch main-actor or EventKit state hop to their own actor or queue inside the method.
- The clock is not a host interface. The engine owns `SystemClock`; the manual clock stays behind the `testing` config flag, as in the C interface.
- UniFFI has no generics, associated types or overloads. Where a Swift type uses them, the generated type is a plain record or enum and a thin hand-written Swift extension in the Swift package restores the old spelling.
- Connector registration becomes configuration (client ids, redirect details, which kinds are enabled), as it already is in the C interface config. Hosts no longer construct `GoogleConnectorKind` and friends.
- The host passes the current time-zone identifier and reports changes; C hosts keep today's behaviour.

Names in the generated Swift match today's Swift names wherever UniFFI allows, to keep the Mac change mechanical.

### 6.6 What moves on the Mac

- `Packages/CalendarApple`: Keychain store, loopback OAuth stay, implementing the generated host interfaces. `CryptoKitSHA256` is deleted. The Google and Microsoft live write smoke tests move to Rust tests in `calendar-connectors` (off by default, as today).
- `Packages/EventKitSource`: stays Swift; implements the generated system calendar source interface.
- `Packages/AppleIntelligenceInference`: stays Swift; implements the generated text generator interface.
- `Apps/macOS`: imports the generated module in place of `TimeTugCore`, `TimeTugEngine`, `CalendarCore`, `CalendarBridge` and the connector products.
- Widgets do not link the engine **(agent call)**. `WidgetSnapshot` JSON is the contract; the widget's Swift types and the 60-line `WidgetTimeline` become app code in `Apps/macOS/Shared`, with their tests.
- Distribution: `timetug-shared` releases an XCFramework (macOS universal, iOS, iOS simulator) and the generated Swift as a Swift package with a binary target; the Mac app pins it with `exactVersion` as today.

## 7. Proof of equal behaviour

The port is accepted on evidence, in this order of authority:

1. **The existing contract, unchanged.** The 74 golden fixtures round-trip; every file in `Conformance/Scenarios` passes through the real C functions; `c-smoke` builds and runs; the .NET test suite passes against the Rust library with no edit to the C# wrapper or its tests.
2. **Persisted formats.** Every file under `Tests/PersistedFormats/` and `Tests/TimeTugEngineTests/Fixtures` loads with the same meaning. These files stay add-only.
3. **Concurrency harness.** A C-level test drives `send`, `reply` and `destroy` from several threads at once and asserts the header's rules: ordered and serialized callbacks, newest-state-wins coalescing, no callback after `destroy` returns, `destroy` inside a callback. It runs in CI on all four platforms.
4. **Test-for-test port.** Every Swift test has a Rust test. A parity table in each repository (`docs/rust-port/test-parity.md`) lists each Swift test and its Rust counterpart; a CI script fails when a Swift test at the baseline tag has no row. A test may be marked "not applicable" only with a reason (for example a test of a Swift-only seam). A row is a claim that the Rust test makes the same assertions; the phase review samples rows against the Swift source.
5. **Golden vectors from the Swift code.** Where exact Foundation behaviour decides the answer (recurrence expansion, time-zone conversion and DST edges, all-day handling, `VTIMEZONE` resolution, Windows zone names, duplicate detection including its case and diacritic folding, takeover scheduling), a small Swift executable in each repository at the baseline tag writes input and output pairs to JSON. The files are committed and the Rust tests replay them. Target: at least 2,000 recurrence cases and 500 zone cases **(agent call)**.
6. **Measured resources.** Size per architecture, idle memory, idle CPU over ten minutes, startup time to `ready` and the dedup benchmark, each compared with the Swift baseline recorded in phase 0. Size has a hard budget; the others must not be worse than baseline.
7. **The Windows app's own self-test scenarios** on x64 and ARM64, and its manual checklist.
8. **The Mac app's tests and manual checklist**, and a live check with real Google, Microsoft, iCloud and EventKit accounts before each app release.

## 8. Versions, branches and releases

- Baseline: the latest release of each library when phase 0 starts (`calendar-connectors` 1.2.x, `timetug-shared` 1.8.x). Its tag is recorded in the tracker.
- Both libraries become `2.0.0`. `TimeTug.Engine` on nuget.org becomes `2.0.0`. The Windows app and the Mac app each take their next major version when they adopt it.
- **Branches (agent call).** Each library gets a long-lived `v2` branch. Rust work merges there by pull request; CI runs on pull requests to `v2`. `main` keeps releasing 1.x Swift for the Mac app until the Mac moves. The Swift sources stay on `v2`, untouched, until the end of phase 3, so the existing Swift `compat` jobs keep passing there. When the Swift sources go, the `compat` jobs are replaced by Rust ones that keep the language-neutral checks against the 1.x baseline (wire fixtures, baseline scenarios through the C functions, the C header and exports, persisted data add-only, .NET package validation) and drop the Swift API diff.
- **Keeping `v2` current.** Only tooling paths (`.github`, `scripts`, docs) are merged from `main` into `v2`. Swift source changes on `main` are never merged; they go on the parity ledger and are ported by hand.
- **Prereleases (agent call).** The release workflow gains a manual path that tags `2.0.0-alpha.N` from `v2` and publishes a prerelease `TimeTug.Engine` package. The Windows app tests against prereleases; nothing ships to users from them.
- **Cutover.** When Windows is proven, `v2` merges to `main` with `semver:major` and releases `2.0.0`. The last Swift state of `main` is kept as branch `1.x`, which can still release `1.x.y` fixes for the Mac until the Mac moves. 
- **Bump chain.** Phase 0 teaches `timetug`'s bump workflow to ignore 2.x releases of either library (today it would open a pull request that breaks the Mac build), with a test. Phase 3 replaces `timetug-shared`'s connector bump on `v2`: it moves the `calendar-connectors` git tag in `Cargo.toml` and refreshes `Cargo.lock`. `timetug-windows` already receives `TimeTug.Engine` updates through Dependabot; phase 4 only adds a check that a prerelease version is never pinned on its default branch. Phase 6 lets `timetug` accept 2.x. After cutover, fixes on the `1.x` branches are bumped by hand through the existing manual workflow inputs, because release dispatches reach only the default branch.
- **Drift (agent call).** Swift keeps changing during the port (Windows phases 6 to 9 are in flight). Every behaviour change to the Swift libraries after the baseline is listed in `docs/rust-port/parity-ledger.md` in that repository with its tests, fixtures or scenarios. Cutover requires an empty ledger: each entry ported and checked off.
- Existing rules hold: tags are created only by release workflows; the owner merges and publishes; agents do not.

## 9. Phases

Each phase gets its own detailed plan and ends with a gate. The tracker is `docs/superpowers/plans/2026-11-10-rust-engine-program-tracker.md`.

| Phase | Work | Gate |
|---|---|---|
| 0. Foundations | ADR for the move to Rust; the `timetug` bump workflow ignores 2.x; baseline numbers (size, idle memory, idle CPU, startup, benchmark); `v2` branches; Cargo workspaces; Rust CI on macOS, Linux, Windows x64 and ARM64; `cargo-deny`; architecture check for crates; Swift vector exporters and committed vectors; parity tables seeded from the baseline tests | CI green on an empty workspace on all four platforms; vectors committed; baselines recorded |
| 1. Connector library | Port the eight crates in dependency order: core model and recurrence, time zones, OAuth, iCalendar, subscriptions, CalDAV, Google, Microsoft, test support, stores | every connector test has a passing Rust counterpart; vectors pass; persisted formats load |
| 2. Core and Bridge | Port `timetug-core` (store, dedup, takeover, agenda, widget) and `timetug-bridge`; port the benchmark | parity table complete for Core and Bridge; benchmark no slower than Swift |
| 3. Engine and C interface | Port `timetug-engine`, `timetug-engine-protocol`, `timetug-engine-c`; point the .NET package at the Rust library; the concurrency harness; Rust `compat` jobs; the Cargo connector bump; size measurement with the 8 MB budget | fixtures, scenarios, the concurrency harness, `c-smoke` and the unchanged .NET suite pass on Windows x64 and ARM64, macOS and Linux; first `2.0.0-alpha` prerelease |
| 4. Windows cutover | Windows app takes the prerelease; packaging lists shrink to one DLL; self-test, manual checklist; memory, idle CPU and startup measured against baseline; a no-prerelease-pin check in `timetug-windows`; ledger emptied; `v2` to `main` | libraries `2.0.0` released; Windows major release ready for the owner to publish |
| 5. Generated bindings | `timetug-engine-ffi`; Swift package with XCFramework; Kotlin bindings compiled in CI; Android and iOS build checks; binding tests in Swift that drive the engine through fake hosts | a Swift test target drives a full scenario through the bindings on macOS; iOS simulator build links; Kotlin compiles |
| 6. Mac cutover | Mac app and its three packages move to the bindings; widgets detach; bump chain accepts 2.x; live checks | Mac tests and checklist pass; upgrade from a 1.x data directory verified; Mac major release ready for the owner to publish |
| 7. Retire Swift | Delete the `1.x` branches' release path, Swift CI jobs and Swift-only scripts; update AGENTS files, skills, architecture docs, code index settings, third-party notices | no workflow, doc or skill refers to the Swift libraries as current |

Phases 1 to 3 touch only the library repositories' `v2` branches, so the Mac and Windows apps keep shipping from 1.x throughout. Phase 5 can start as soon as phase 3 is done and may overlap phase 4.

## 10. Risks

| Risk | Answer |
|---|---|
| Foundation date arithmetic differs from `jiff` at DST gaps, month ends, week starts | golden vectors from Swift (section 7.5); differences are fixed in Rust, never accepted |
| Unicode handling differs: `DuplicateRules` folds with `.caseInsensitive` and `.diacriticInsensitive` and no locale, and account names compare case-insensitively | vectors exported from Swift over a wide character set; the Rust folding is written to match them, with a table if no crate does |
| JSON encoding details differ (date strings, number forms, optional and null members) | golden fixtures and persisted-format files are byte-for-meaning checks; protocol types get explicit serde attributes, no defaults relied on |
| Engine concurrency: Swift actors to one Rust engine thread | the lifecycle and race tests are ported first in phase 3; the header's ordering and destroy rules are test cases |
| The Swift engine drifts during the port | the parity ledger (section 8) |
| UniFFI cannot express a type as today's Swift does (generics, associated values, protocol composition) | phase 5 starts with a spike on the hardest types (the event model, the system calendar source with writes, async host callbacks) before the full surface |
| A typed boundary copies large agendas on every state change | measure in phase 5; state is already revisioned and coalesced; if needed, split state into parts fetched on demand |
| iOS or App Store rules for a Rust static library (privacy manifest, required-reason APIs) | checked in phase 5 with an App Store validation of the Mac build in phase 6 |
| Long-lived `v2` branch rots | weekly merge of `main` tooling changes into `v2`; Swift sources on `v2` are deleted only at the end of phase 3 so comparisons stay easy |

## 11. Left to the builder

- Module layout inside each crate, as long as each Swift file's content has a traceable home (the parity table records it).
- Exact Rust type shapes, provided serialized forms and the generated Swift names meet sections 6.5 and 7.
- The form of the vector exporters and the vector file layout.
- How the engine thread, timers and request table are built on `tokio`, provided the header's rules hold.
- How the XCFramework and Swift package are produced in the release workflow.

## 12. Agent calls for the owner to check

1. Size budget 8 MB per Windows architecture, failing CI above it.
2. Wire protocol stays `v: 1`.
3. Git-tag dependency between the libraries; no crates.io.
4. The external crate list (section 6.2), including `tokio` (current-thread only) and `jiff`.
5. `panic = "abort"` and a statically linked C runtime on Windows.
6. One crate per current Swift product.
7. `v2` branches with prereleases; `main` stays Swift 1.x until the Windows cutover; a `1.x` branch serves the Mac until phase 6.
8. No freeze on the Swift libraries; a parity ledger instead.
9. Widgets do not link the engine.
10. Phase order: Windows cutover (4) before bindings (5) and the Mac (6).
11. The iOS simulator slice is arm64 only (no Intel Mac support for iOS development).
