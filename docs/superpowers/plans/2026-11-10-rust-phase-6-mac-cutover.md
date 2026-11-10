# Rust phase 6: Mac cutover — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Mac app runs on the Rust engine through the `TimeTugKit` Swift bindings, keeps its Swift and SwiftUI code and its Apple adapters, upgrades existing users' data in place, and is ready for the owner to publish as the next major version.

**Architecture:** The app and its three local packages stop importing the Swift libraries and import `TimeTugKit`. The Apple adapters (EventKit, Keychain, loopback OAuth, Apple Intelligence, settings, diagnostics) implement the generated host interfaces. Connector registration becomes an `EngineConfig`. The widget extension stops depending on the engine. The pin and bump scripts move from two Swift libraries to one Swift package.

**Tech Stack:** Swift 6, SwiftUI, XcodeGen, SwiftPM binary target (`TimeTugKit` from `timetug-shared` 2.x), the repository's `scripts/dev/verify.sh`.

**Spec:** [`docs/superpowers/specs/2026-11-10-rust-engine-program-design.md`](../specs/2026-11-10-rust-engine-program-design.md), sections 5, 6.5, 6.6 and 7; `docs/bindings.md` in `timetug-shared`. **Tracker:** [`2026-11-10-rust-engine-program-tracker.md`](2026-11-10-rust-engine-program-tracker.md).

All paths are in `binary-companion/timetug` (this repository) unless a task says otherwise.

## Global Constraints

- The app's behaviour and appearance do not change. No view, string or setting is added, removed or reworded.
- The app keeps: UI, presentation settings, widgets, Sparkle (inside `#if !APPSTORE`), the App Group for state, Keychain for credentials, `AppSupportFiles.url(_:)` for paths. `project.yml` keeps every privacy description, entitlement, OAuth substitution and Sparkle key.
- EventKit is imported only in `Packages/EventKitSource`; Foundation Models only in `Packages/AppleIntelligenceInference`.
- For every `takeoverDue` the app still sends exactly one closing command.
- No Rust code is written in this repository. A gap in the bindings is fixed in `timetug-shared` (released as a 2.x minor) and the pin is moved with the bump script.
- Pins move only through `scripts/ci/bump-pin.sh`.
- Both distributions (direct and App Store) build, with separate build directories.
- Existing users' files are read as they are: `connections.json`, `sync-state.json`, the takeover ledger, the dedup state, the settings in UserDefaults and the App Group, Keychain items.
- Live provider writes are never enabled by `verify.sh`.

## Review Focus

1. **A user with every account kind upgrading from the last Swift release**: nothing to re-add, nothing lost. Pinned by Task 8 (synthetic data directory) and the owner's live check in Task 10.
2. **Calendar access not yet granted, or revoked while running**: the system prompt still appears on enabling Apple Calendar; the status shows the denial. Pinned by `EventKitSource` tests for `requestAccess` and by checklist items.
3. **The Mac sleeping across a meeting start, a time-zone change, a day change**: the app still reports `SystemEvent`s and now also calls `engine.setTimeZone`. Pinned by `AppCoordinator` tests in Task 5.
4. **Launch time and memory**: the app must not start slower. Pinned by Task 9's measurement against the last Swift release.
5. **The App Store build's sandbox**: the engine writes only inside the App Group container the host passes; no path under the real home directory. Pinned by Task 9's sandboxed run and App Store validation.

---

### Task 1: Inventory and surface check

**Files:**
- Create: `docs/rust-port/mac-migration-map.md` (in this repository)

- [ ] **Step 1: List every use.** For each of the 88 files that import a shared library module (`grep -rlE '^import (TimeTugEngine|TimeTugCore|CalendarBridge|CalendarCore|GoogleCalendar|MicrosoftCalendar|CalDAVCalendar|ICalSubscription|ICalendar|CalendarOAuth)' --include='*.swift' Apps Packages`), record the library symbols it uses (build the app once, then use Serena `find_referencing_symbols`, or grep the type names from `docs/bindings-surface.txt`).
- [ ] **Step 2: Classify each symbol** against `docs/bindings.md` of the pinned `timetug-shared`: same name in `TimeTugKit`; renamed (old to new); provided by a shim; replaced by config; not exposed and unused after the change; **missing**.
- [ ] **Step 3: Close every "missing"** before any code change here: each becomes a `timetug-shared` pull request (a mirror, a shim or an exposed function) and a release. Record the `TimeTugKit` version that has them all in the map.
- [ ] **Step 4: Write the map**: one table row per file with its symbols, class and the task below that changes it. Commit; pull request.

### Task 2: Pins, scripts and the package reference

**Files:**
- Modify: `Apps/macOS/project.yml` (packages: remove `CalendarConnectors`; `TimeTugShared` now provides product `TimeTugKit`), each `Packages/*/Package.swift`
- Modify: `scripts/ci/bump-pin.sh`, `scripts/ci/check-shared-pins.py`, `scripts/ci/bump-major-guard.sh`, `scripts/dev/use-local-library.sh`, `scripts/dev/use-local-connectors.sh` (delete), `.github/workflows/bump-dependencies.yml`, their tests under `scripts/ci/tests/`
- Modify: `scripts/ci/check-architecture.sh` (allowed imports), `scripts/dev/verify.sh` and `scripts/dev/affected-tests.sh` (the `connectors` group goes away; `core` checks are in `timetug-shared`)

**Interfaces (produced):**
- `bump-pin.sh timetug-shared X.Y.Z` is the only library form; `calendar-connectors` is refused with a message naming phase 6.
- `bump-dependencies.yml` handles only `library == timetug-shared`; the connector-pin logic and `resolved-version.py` call are removed; a `calendar-connectors` dispatch ends with a notice.
- `bump-major-guard.sh` now skips only a major greater than **2** (so 2.x flows and a future 3.0.0 is still held).
- `use-local-library.sh timetug-shared <path>` points the package at a local checkout whose `build/TimeTugEngineFFI.xcframework` exists (it runs `<path>/scripts/dev/build-xcframework.sh` if not).

- [ ] **Step 1: Tests first** for each script change (extend the existing shell and Python tests; one case per bullet above).
- [ ] **Step 2: Change the scripts and the workflow.**
- [ ] **Step 3: Move the pin**: `scripts/ci/bump-pin.sh timetug-shared <the version from Task 1>`; edit package product names in `project.yml` and the three `Package.swift` files (`.product(name: "TimeTugKit", package: "timetug-shared")`).
- [ ] **Step 4:** `xcodegen generate --spec Apps/macOS/project.yml`; `swift package resolve` in each local package. Expected: resolution succeeds; compilation fails on the old imports (fixed by the next tasks).
- [ ] **Step 5: Commit** on the phase branch `feature/rust-engine` (one long-lived branch for Tasks 2 to 8; a single pull request at the end, because the app does not build in between).

### Task 3: `Packages/CalendarApple`

| File | Change |
|---|---|
| `KeychainCredentialStore.swift` | conforms to `TimeTugKit.CredentialStore`; same Keychain items, same service and account names |
| `MigratingCredentialStore.swift` | same |
| `LoopbackAuthorizationInteraction.swift` | conforms to `TimeTugKit.AuthorizationInteraction` and returns a `TimeTugKit.OAuthRedirectSession` |
| `CryptoKitSHA256.swift`, `CryptoKitSHA256Tests.swift` | deleted |
| `GoogleLiveWriteSmokeTests.swift`, `MicrosoftLiveWriteSmokeTests.swift` | deleted here; ported to `calendar-connectors` as `#[ignore]` Rust tests in `crates/calendar-google/src/tests/live_write_smoke.rs` and `crates/calendar-microsoft/src/tests/live_write_smoke.rs` with the same environment variables (a `calendar-connectors` pull request); update the `running-live-calendar-tests` skill with the new commands |
| new `URLSessionHTTPTransport.swift` | the host's HTTP: a port of the library's former `URLSessionTransport` (ephemeral session, no cache, `reloadIgnoringLocalCacheData`, **does not follow redirects**, cancellation mapped to `HostError.cancelled`, other `URLError`s to `HostError.network`), plus the feed session settings from the former `ICalSubscriptionKind.feedSessionConfiguration`; obligations listed in `calendar-connectors` `docs/host-http-contract.md` |
| new `URLSessionHTTPTransportTests.swift` | the former `TransportCacheTests` and `TransportRedirectTests` from `calendar-connectors` 1.x, ported against the new type with `URLProtocol` stubs |

- [ ] **Step 1: Port the two transport test files first** (from the `1.x` branch of `calendar-connectors`), expect failure, then write `URLSessionHTTPTransport`.
- [ ] **Step 2: Change the three adapters**; keep their tests, changing only type names.
- [ ] **Step 3: Thread-safety.** Each adapter is `Sendable`; the loopback interaction's listener state is guarded as today. No method blocks the calling thread on the main actor.
- [ ] **Step 4:** `swift test --package-path Packages/CalendarApple`. Expected: PASS.
- [ ] **Step 5: Commit.**

### Task 4: `Packages/EventKitSource` and `Packages/AppleIntelligenceInference`

**EventKitSource:**

| File | Change |
|---|---|
| `EventKitSource.swift`, `+Series.swift`, `+Write.swift` | conform to `TimeTugKit.SystemCalendarSource`: `requestAccess()` (the code now in the app's `requestSystemAccess` closure moves here), `calendars()`, `events(in:)`, `series(id:calendarID:)`, `capabilities`, the write methods, `setChangeHandler(_:)` (called from the `EKEventStoreChanged` observer, replacing the `AsyncStream` continuation) |
| `EventKitMapping.swift`, `EventKitWriteMapping.swift` | build `TimeTugKit` model values; logic unchanged |
| `EventKitConnectorKind.swift` | deleted if it only existed to register the kind (the engine config's `systemCalendar: true` replaces it); if it carries display metadata the app uses, keep that part as a plain struct |
| tests | type names only; `EventKitConnectorKindTests` follows the file above |

- [ ] **Step 1:** Change mapping tests' type names; they must pass unchanged in meaning (`EventKitMappingTests`, `EventKitWriteMappingTests`, `EventKitWriteTests`).
- [ ] **Step 2:** Add tests for `requestAccess` (granted, denied, already granted, using the existing EventKit fakes or protocol seam in the package) and for `setChangeHandler` (a store-changed notification calls the handler once).
- [ ] **Step 3:** `EKEventStore` use stays on the queue or actor it uses today; the async interface methods hop there.
- [ ] **Step 4:** `swift test --package-path Packages/EventKitSource`. PASS.

**AppleIntelligenceInference:**

- [ ] **Step 5:** `AppleTextGenerator` conforms to `TimeTugKit.TextGenerator`; `AppleIntelligence.swift` keeps the compile guard for macOS 26. Tests: type names only. `swift test --package-path Packages/AppleIntelligenceInference`. PASS.
- [ ] **Step 6: Commit.**

### Task 5: The engine host in the app

**Files (in `Apps/macOS/Sources`):** `AppCoordinator.swift`, `AppConnectors.swift`, `GoogleOAuthSettings.swift`, `MicrosoftOAuthSettings.swift`, `AppCredentials.swift`, `CredentialPrompter.swift`, `AppDiagnostics.swift`, `OSLogDiagnosticLog.swift`, `EngineAdapters/EngineCommandQueue.swift`, `EngineAdapters/EngineModelMirror.swift`, `EngineAdapters/OSLogEngineDiagnostics.swift`, `EngineAdapters/UserDefaultsSettingsStorage.swift`; their tests in `Apps/macOS/Tests`.

**Decisions:**
- `AppConnectors.swift` stops registering kinds and instead builds `EngineConfig`: `dataDirectory` (the same App Group directory as today, through `AppSupportFiles`), `platform: .macos`, `googleClient` and `microsoftClient` from the existing OAuth settings types (absent when the build has no client id, which makes the kind "unconfigured" exactly as `unconfiguredKindIDs` did), `textGeneration` (true when the Apple generator is available at compile time), `externalTokens: false`, `systemCalendar: true`, `timeZone: TimeZone.current.identifier`. `AppConnectorsTests` is rewritten to assert the config for each build setting combination it covered before.
- `AppCoordinator` builds `EngineHostInterfaces` from the adapters, creates `Engine`, and keeps its command and event handling. On `NSSystemTimeZoneDidChange` it calls `engine.setTimeZone(TimeZone.current.identifier)` before sending the system event (today the engine re-read `Calendar.current` itself).
- `EngineModelMirror` and `EngineCommandQueue` keep their structure, consuming `engine.states` and `engine.events` (the shim `AsyncStream`s).
- `UserDefaultsSettingsStorage` conforms to `TimeTugKit.SettingsStorage` with **the same UserDefaults keys**; its tests are the proof.
- `CredentialPrompter` conforms to `TimeTugKit.SignInPrompting` and is used by the `AuthorizationInteraction` for `promptCredentials`, as today.
- `applySettings` call sites use the shim `engine.applySettings { ... }`.
- Diagnostics: `OSLogEngineDiagnostics` and `OSLogDiagnosticLog` conform to `TimeTugKit.DiagnosticSink`; the redaction they do today stays.

- [ ] **Step 1: Tests first**: update `AppConnectorsTests`, `EngineCommandQueueTests`, `EngineModelMirrorTests`, `UserDefaultsSettingsStorageTests`, `OSLogEngineDiagnosticsTests`, `AppDiagnosticsTests`, `AppCredentialsTests`, `CredentialPrompterTests` to the new types; add the time-zone test (a posted `NSSystemTimeZoneDidChange` results in `setTimeZone` then `.system(.timeZoneChanged)`, in that order, against a fake engine protocol the coordinator depends on; introduce that small protocol if the coordinator holds the concrete `Engine` today).
- [ ] **Step 2: Change the sources** file by file per the migration map.
- [ ] **Step 3: Build** the direct target: `xcodegen generate --spec Apps/macOS/project.yml` then the app build command from `docs/development.md`. Expected: remaining errors are only in view and model files (Task 6).
- [ ] **Step 4: Commit.**

### Task 6: Views, models and helpers

The remaining importing files (accounts UI, calendars pane, overlay, popup, menu bar state, merge badge, settings, formatting, search): `AccountNoticeText`, `AccountStatusText`, `AccountsController`, `AccountsListBox`, `AccountsListModel`, `AccountsPane`, `AppModel`, `CalendarGrouping`, `CalendarSections`, `CalendarsPane`, `CredentialSheet`, `DropdownView`, `InferenceAvailability`, `InferenceStatusText`, `MenuBarIconState`, `MergeBadge`, `OverlayController`, `OverlayView`, `PopupRowModel`, `SafeJoin`, `SettingsSearch`, `SettingsStore`, `TimeFormatting`, and their tests.

- [ ] **Step 1: Replace imports** with `import TimeTugKit` and apply the renames of the migration map. No logic changes. Where a file used a pure library function that is "not exposed" (for example `ConferenceDetector`, `JoinURLPolicy` in `SafeJoin.swift`, `DuplicateRules` helpers), the map's Task 1 decision applies: either `TimeTugKit` exposes it (preferred when the function embodies a rule, so the rule stays in one place) or the view uses a value the engine state already carries.
- [ ] **Step 2: Build both targets.** Expected: no errors, no new warnings.
- [ ] **Step 3: Run the app tests** (`scripts/dev/verify.sh app`). Expected: PASS, with the same test count as before the branch minus the deleted `CryptoKitSHA256Tests` and connector-kind tests; record both counts.
- [ ] **Step 4: Commit.**

### Task 7: Widgets

**Files:** `Apps/macOS/Shared/WidgetSnapshotStore.swift`, `Apps/macOS/Widgets/AgendaProvider.swift`, `NextUpWidget.swift`, `TodayWidget.swift`; new `Apps/macOS/Shared/WidgetSnapshotModel.swift`, `Apps/macOS/Shared/WidgetTimeline.swift`; new tests `Apps/macOS/Tests/WidgetSnapshotModelTests.swift`, `WidgetTimelineTests.swift`; `Apps/macOS/project.yml` (the widget target drops the package dependency).

- [ ] **Step 1: Port the tests first**: `WidgetTimelineTests` (14) and the decoding parts of `WidgetSnapshotTests` from `timetug-shared` `1.x` (`Tests/TimeTugCoreTests`) into the app's test target against app-owned types.
- [ ] **Step 2: Create `WidgetSnapshotModel.swift`**: `WidgetSnapshot` and `WidgetEvent` as plain `Codable` Swift structs with the same property names and the same date coding as the file on disk today (`agenda-snapshot.json`); `isStale(now:)` copied.
- [ ] **Step 3: Create `WidgetTimeline.swift`**: a copy of `TimeTugCore/Widget/WidgetTimeline.swift` from `1.x` (60 lines), using the app-owned types.
- [ ] **Step 4: The app writes the snapshot** by converting `TimeTugKit.WidgetSnapshot` (from the `widgetSnapshot` event) to the app-owned struct in `WidgetSnapshotStore`. Add a test: a `TimeTugKit` snapshot converted and encoded equals a JSON string captured from the last Swift release's encoder for the same content (put the capture snippet in the test comment).
- [ ] **Step 5: Compatibility both ways**: a test decodes a snapshot file written by the last Swift release (commit a small fixture `Apps/macOS/Tests/Fixtures/agenda-snapshot-2.x.json` with invented content).
- [ ] **Step 6: Build the widget extension**; confirm with `otool -L` and the link map that it links no `TimeTugEngineFFI`. Record the extension's binary size before and after.
- [ ] **Step 7: Commit.**

### Task 8: Upgrade in place

**Files:** new `Apps/macOS/Tests/UpgradeFromSwiftEngineTests.swift`, fixtures under `Apps/macOS/Tests/Fixtures/legacy-data/`.

- [ ] **Step 1: Build the fixture directory** from library fixtures (`timetug-shared` `fixtures/engine/*`, `calendar-connectors` `fixtures/persisted-formats/1.2.0/*`) under the file names the Mac app's data directory uses (list the real names from a development build's App Group container; file names only, never contents from a real container).
- [ ] **Step 2: Write the test**: copy the fixture to a temp directory; create the engine through the app's own factory with in-memory credential store, fake transport and no system calendar; start; assert the accounts (kind and display name each), behaviour settings from a prepared `UserDefaults` suite using today's keys, ledger entries and dedup lessons reported in state; send one settings change and one dismiss; shut down; assert every original file still parses and no file was removed.
- [ ] **Step 3: Run; fix in `timetug-shared` if it fails** (a failure here is an engine defect, not an app change).
- [ ] **Step 4: Commit.**

### Task 9: Verification, measurement and the pull request

- [ ] **Step 1:** `scripts/dev/verify.sh all`. Expected: PASS. Summary in `build/verify/`.
- [ ] **Step 2: Both distributions build** per `docs/development.md`, using the `configuring-local-app-builds` skill for signing and OAuth ids. Launch each; add no account; quit.
- [ ] **Step 3: Measure** against the last released Swift build on the same Mac, three runs each, no accounts and then one synthetic iCal-link account: app bundle size; main executable size; time from launch to menu bar item (signpost or log timestamp); resident memory after five idle minutes (`footprint`); CPU time over ten idle minutes. Record in `docs/rust-port/mac-migration-map.md`. Gate: launch time, memory and idle CPU not worse (10% tolerance); bundle size growth recorded and under 8 MB.
- [ ] **Step 4: Sandbox check**: run the App Store build; with `fs_usage` or the sandbox log, confirm no file access is denied and nothing is written outside the App Group container and the app's own container.
- [ ] **Step 5: Privacy manifest**: check whether the linked Rust library uses any required-reason API category (file timestamps, system boot time, disk space, user defaults) with `nm` against the symbol lists Apple documents; add the reasons to the app's `PrivacyInfo.xcprivacy` if so. Record the finding.
- [ ] **Step 6: App Store validation**: produce the App Store archive per `docs/release.md` and run validation (owner step if it needs credentials; add to owner items).
- [ ] **Step 7: Docs**: `docs/architecture.md` (modules: the app depends on `TimeTugKit`; adapters implement generated interfaces; the libraries are Rust), `AGENTS.md` (Boundaries and Repositories), `docs/development.md` (building needs no Rust toolchain: the XCFramework is prebuilt; local library work does), ADR `docs/decisions/0023-mac-app-on-rust-engine.md`, `docs/manual-tests/macos-checklist.md` (add an "engine cutover" section mirroring the Windows one in phase 4, Task 4), the `working-across-timetug-repos`, `running-live-calendar-tests`, `diagnosing-takeovers` and `configuring-local-app-builds` skills where they name Swift library types or commands.
- [ ] **Step 8: Version**: the Mac app's next major version, set where `docs/release.md` says.
- [ ] **Step 9: Review**: `deepseek-review` on the diff with the migration map and `docs/bindings.md` as context. Then open the pull request from `feature/rust-engine`.

### Task 10: Owner checks and close-out

- [ ] **Step 1: (owner)** Manual checklist "engine cutover" on a beta build: each account kind added and refreshed; Apple Calendar on and off with the system prompt; takeover fire, join, snooze, dismiss; sleep across a start; time-zone change; merge and unmerge; widgets and Control Center controls update; Sparkle update from the last Swift release to the beta keeps all accounts and settings (the live upgrade check).
- [ ] **Step 2: (owner)** Merge, beta, release per `docs/release.md` and the `releasing-timetug` skill.
- [ ] **Step 3: Update the tracker**: phase 6 `done`; Now to phase 7. Update the memory notes that describe the Mac app's dependencies (`timetug-project-context`, `calendar-connectors-effort`).
