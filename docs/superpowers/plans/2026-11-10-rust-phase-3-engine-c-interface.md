# Rust phase 3: engine and C interface — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Rust `TimeTugEngineC` library that the unchanged C header, the unchanged C# wrapper and the unchanged .NET tests accept in place of the Swift one, inside the 8 MB budget, published as the prerelease `TimeTug.Engine` `2.0.0-alpha.1`.

**Architecture:** `timetug-engine` is a translation of the Swift `Engine` actor and its helpers onto one `tokio` current-thread runtime. `timetug-engine-protocol` is the JSON contract v1. `timetug-engine-c` owns one engine thread and one delivery thread per engine and exports the four `tt_engine_*` functions. After the gates pass, the Swift sources leave `v2` and the CI and release workflows build Rust.

**Tech Stack:** Rust (pinned stable), `tokio` (`rt`, `time`, `sync`, `macros`), `serde_json`, C11 (the smoke and concurrency harness), .NET 8 (the existing wrapper and tests), PowerShell (packaging), GitHub Actions.

**Spec:** [`docs/superpowers/specs/2026-11-10-rust-engine-program-design.md`](../specs/2026-11-10-rust-engine-program-design.md), sections 6.3 to 6.5, 7 and 8; [`docs/engine-protocol.md`](../../engine-protocol.md); the phase 4 design of record `docs/superpowers/specs/2026-10-15-phase-4-engine-c-interface-design.md`. **Conventions (binding):** [`2026-11-10-rust-port-conventions.md`](2026-11-10-rust-port-conventions.md). **Procedure:** steps P1 to P8 of the [phase 1 plan](2026-11-10-rust-phase-1-connectors.md#the-port-procedure-used-by-every-task-below).

All paths are in `binary-companion/timetug-shared`; branches from `v2`, pull requests to `v2`.

## Global Constraints

- `include/timetug_engine.h` is not edited. `dotnet/TimeTug.Engine/**` and `dotnet/TimeTug.Engine.Tests/**` are not edited, except the one file-list change in Task 9 that the plan names. `Conformance/**` is not edited.
- Wire protocol stays `v: 1`. Every golden fixture round-trips to an equal JSON value.
- Library file names: `TimeTugEngineC.dll`, `libTimeTugEngineC.dylib`, `libTimeTugEngineC.so`.
- `tt_engine_send` and `tt_engine_reply` never block, from any thread, including inside a callback. Callbacks are serialized and ordered on one delivery thread. States coalesce (newest wins, and never ahead of an event queued before them). No callback runs after `tt_engine_destroy` returns when it is called outside a callback; called inside one, it returns at once and no further callback starts. `NULL`, stale and unknown handles and unknown request ids are ignored.
- The engine never keeps, frees or returns host memory. Every string passed to the host is engine-owned and valid only during the callback.
- `unsafe` appears only in `crates/timetug-engine-c/src/c_interface.rs` and `delivery.rs` (the callback call). Each `unsafe` block has a `// SAFETY:` comment.
- The only code that touches `tokio::time` is `SystemClock` in `timetug-engine`. Everything else sleeps through `EngineClock`.
- Size budget: the native payload per Windows architecture is at most 8,388,608 bytes uncompressed. CI fails above it.
- Diagnostics privacy as in the Swift engine: no token, email, account id or host exception text in `event.diagnostic`.
- Release profile only for everything the gates run against: the scenarios, the harness, `c-smoke` and the .NET suite use `target/release`.

## Review Focus

1. **A host that calls `tt_engine_destroy` while another thread is inside `tt_engine_send`, or from inside its own callback**: no crash, no callback afterwards. Pinned by the concurrency harness (Task 8).
2. **A host that never answers a service request** (the app hangs on a dialog): requests with a timeout fail with `network` at 60 seconds on the engine clock; requests without one end on `account.cancel` and on destroy with `cancelled`. Pinned by `RemoteHostServicesTests` and the `http-timeout` and `destroy-while-signin-pending` scenarios; add a harness case that destroys with ten requests pending.
3. **Malformed input from the host** (a command that is not JSON, not an object, the wrong `v`, an unknown `type`, a reply for an unknown id, invalid UTF-8 in a C string): a diagnostic or silence exactly as Swift, never a panic. Pinned by the `invalid-command` scenario and the `edge-*` fixtures; add a test feeding 2,000 pseudo-random byte strings to `send` and `reply`.
4. **A data directory written by engine 1.8** (settings, ledger, dedup state, connections, sync state): everything loads; nothing is lost on the first save. Pinned by `LegacyFixtureTests` plus a new end-to-end test (Task 5, step for it).
5. **The machine sleeps for hours, or the clock or zone changes while a takeover is pending**: the takeover fires late once, or is withdrawn, as the `late-takeover-after-wake`, `time-zone-change` and `takeover-after-clock` scenarios say; add a `SystemClock` test with a paused `tokio` clock that advances 26 hours in one step.

---

### Task 1: `timetug-engine` — types, clock, persistence

| Swift source | Rust module |
|---|---|
| `TimeTugEngine/EngineClock.swift` | `clock.rs` |
| `TimeTugEngine/EngineDiagnostic.swift` | `diagnostic.rs` |
| `TimeTugEngine/EngineSettings.swift` | `settings.rs` |
| `TimeTugEngine/EngineCommand.swift` | `command.rs` |
| `TimeTugEngine/EngineEvent.swift` | `event.rs` |
| `TimeTugEngine/EngineState.swift` | `state.rs` |
| `TimeTugEngine/EngineHost.swift` | `host.rs` |
| `TimeTugEngine/EngineActivity.swift` | `activity.rs` |
| `TimeTugEngine/Persistence/JSONFile.swift` | `persistence/json_file.rs` |
| `TimeTugEngine/Persistence/FileSettingsStorage.swift` | `persistence/file_settings_storage.rs` |
| `TimeTugEngine/Persistence/LedgerStore.swift` | `persistence/ledger_store.rs` |
| `TimeTugEngine/Persistence/DedupStateStore.swift` | `persistence/dedup_state_store.rs` |
| `TimeTugEngine/Scheduling/UITickPolicy.swift` | `scheduling/ui_tick_policy.rs` |
| `TimeTugEngine/Scheduling/LaunchAcknowledgement.swift` | `scheduling/launch_acknowledgement.rs` |

**Swift tests:** `TimeTugEngineTests/`: `EngineClockTests`, `EngineTypesTests`, `LegacyFixtureTests`, `Persistence/*` (4 files), `Scheduling/*` (2 files), and `Support/ManualClock.swift`, `Support/Fakes.swift` (to `src/tests/support/`).

**Interfaces (produced):**

```rust
#[async_trait]
pub trait EngineClock: Send + Sync {
    fn now(&self) -> Timestamp;
    /// Returns when now() reaches `deadline`; at once for a past deadline; Err(Failure::Cancelled) if cancelled.
    async fn sleep_until(&self, deadline: Timestamp) -> Outcome<()>;
}
pub struct SystemClock;                      // sleeps in chunks of at most 86,400 s, re-reading now() each chunk

pub trait SettingsStorage: Send + Sync { fn load(&self) -> EngineSettings; fn save(&self, settings: &EngineSettings); /* plus whatever the Swift protocol declares */ }
#[async_trait] pub trait SignInPrompting: Send + Sync { /* prepare, last_non_secret_values */ }
#[async_trait] pub trait TextGenerator: Send + Sync { /* availability, generate */ }
pub type EngineDiagnosticSink = Arc<dyn Fn(EngineDiagnostic) + Send + Sync>;

pub struct EngineHost {
    pub data_directory: PathBuf,
    pub settings: Arc<dyn SettingsStorage>,
    pub credentials: Arc<dyn CredentialStore>,
    pub interaction: Arc<dyn AuthorizationInteraction>,
    pub sign_in: Arc<dyn SignInPrompting>,
    pub registry: ConnectorRegistry,
    pub unconfigured_kind_ids: Vec<String>,
    pub build_system_source: Option<Arc<dyn Fn() -> Arc<dyn timetug_core::CalendarSource> + Send + Sync>>,
    pub request_system_access: Option<Arc<dyn Fn() -> Pin<Box<dyn Future<Output = ()> + Send>> + Send + Sync>>,
    pub text_generator: Option<Arc<dyn TextGenerator>>,
    pub diagnostics: EngineDiagnosticSink,
    pub clock: Arc<dyn EngineClock>,
    pub zone: Arc<dyn Fn() -> Zone + Send + Sync>,   // Swift: calendar: () -> Calendar
}
```

**Decisions:**
- `EngineCommand::ApplySettings` carries a Swift closure `(inout EngineSettings) -> Void`. In Rust: `ApplySettings(Box<dyn FnOnce(&mut EngineSettings) + Send>)`. The protocol crate builds that closure from a settings patch.
- `SystemClock::sleep_until` loops: compute remaining seconds from `now()`; return if not positive; `tokio::time::sleep` for `min(remaining, 86_400)`. It re-reads the wall clock every chunk so a clock change or a long suspend is noticed at the latest one chunk later; the engine additionally re-plans on `SystemEvent` (wake, clock, zone, day), as Swift does. Add the Review Focus 5 test.
- `JSONFile` writes through `calendar_core::files::write_atomic` and reports failures as `.error` diagnostics exactly as the Swift doc comments say (false return plus diagnostic).
- `LegacyFixtureTests` loads `Tests/TimeTugEngineTests/Fixtures/*.json` (path through `CARGO_MANIFEST_DIR`, moved to `fixtures/engine/` in Task 10).

- [ ] Follow P1 to P8.

### Task 2: `timetug-engine` — accounts

| Swift source | Rust module |
|---|---|
| `TimeTugEngine/Accounts/AccountManager.swift` | `accounts/account_manager.rs` |
| `TimeTugEngine/Accounts/SourceReconciler.swift` | `accounts/source_reconciler.rs` |
| `TimeTugEngine/Accounts/SourceRefreshCoordinator.swift` | `accounts/source_refresh_coordinator.rs` |

**Swift tests:** `Accounts/AccountManagerTests` (32), `SourceReconcilerTests`, `SourceRefreshCoordinatorTests`, `Support/AccountFakes.swift`.

**Decisions:**
- `AccountManager` is a public actor with a nested `Status` type; port per the actor rule. Its user-facing failure messages (for example "... is already added.", the "was not accepted" sentence built from field labels at line 227) are engine-produced text that the Windows and Mac apps show: copy every string literally, including the lowercase-first-letter transformation.
- Line 362 uses `error.localizedDescription` for an unknown error. Rust has no equivalent text; use the `Display` of `Failure`, and make `Failure`'s `Display` for `Source` and `Write` variants produce the strings Swift's `localizedDescription` gives for those enums in the tests that assert on them. Where no test asserts, use a fixed sentence and list the site in the pull request.
- Account-name comparison is case-insensitive (`vectors/text/case-compare.json`).
- Cancelling an authorization (`cancelAuthorization`) must end a pending `authorize` future and run the Swift cleanup (close the redirect session): use the drop-guard rule of conventions section 10, item 11.

- [ ] Follow P1 to P8.

### Task 3: `timetug-engine` — inference

| Swift source | Rust module |
|---|---|
| `TimeTugEngine/Inference/TextGenerator.swift` | `inference/text_generator.rs` |
| `TimeTugEngine/Inference/PromptBuilder.swift` | `inference/prompt_builder.rs` |
| `TimeTugEngine/Inference/TextGeneratorAdjudicator.swift` | `inference/text_generator_adjudicator.rs` |

**Swift tests:** `Inference/PromptBuilderTests`, `Inference/TextGeneratorAdjudicatorTests`, `EngineInferenceTests`.

**Vectors replayed:** `inference/prompts.json`.

**Decisions:**
- `PromptBuilder` formats dates with `DateFormatter` fixed to `en_US_POSIX` and explicit format strings. Read the two format strings and implement exactly those patterns by hand (English weekday and month names in a `const` table); the prompt vectors compare whole prompt texts.
- No email address enters a prompt beyond what Swift puts there; port the related test first.

- [ ] Follow P1 to P8.

### Task 4: `timetug-engine` — the engine

| Swift source | Rust module |
|---|---|
| `TimeTugEngine/Engine.swift` (803 lines) | `engine/mod.rs` (construction, `start`, `send`, subscriptions), `engine/commands.rs` (the command handlers), `engine/takeover.rs` (ledger, fire guard, scheduling loop), `engine/refresh.rs` (refresh coalescing, system events), `engine/dedup.rs` (merge, unmerge, separate, forget), `engine/publish.rs` (state building and revision) |

Splitting one Swift file into six Rust files is the one exception to "one file, one module"; the split follows the `// MARK:` sections of `Engine.swift`. Record each Swift line range in `file-map.md`.

**Swift tests:** `EngineRefreshTests`, `EngineSettingsCommandTests`, `EngineSystemEventTests`, `EngineTakeoverTests` (18), `EngineReviewFixTests`, `ConformanceTests`, and `Support/EngineHarness.swift`, `Support/TimelineRecorder.swift`.

**Interfaces (produced):**

```rust
pub struct Engine { /* private */ }
impl Engine {
    pub fn new(host: EngineHost) -> Arc<Engine>;
    pub fn states(&self) -> tokio::sync::watch::Receiver<EngineState>;          // newest wins
    pub fn events(&self) -> tokio::sync::mpsc::UnboundedReceiver<EngineEvent>;  // never dropped; each call a new receiver
    pub fn current_state(&self) -> EngineState;
    pub async fn start(&self);
    pub async fn send(&self, command: EngineCommand);
}
```

**Decisions:**
- All engine work runs on the runtime the caller provides (`Engine` methods are `async` and spawn with `tokio::spawn`); the engine creates no runtime and no thread. The C and bindings crates own the runtime.
- State lives in `std::sync::Mutex<EngineInner>`; the actor rule applies to every `await` in `Engine.swift`. Go through the Swift file and mark each `await` in a comment in the Rust code (`// await point (Engine.swift:NNN)`), so a reviewer can check lock release against the original.
- `revision` increases by one per published state, as in Swift; `publish` is the only place that sends on the `watch` channel.
- The scheduling loop is one task: compute `Scheduler::next`, `clock.sleep_until`, fire through the guard, repeat; it is cancelled and restarted wherever Swift cancels and restarts its task. Keep the `JoinHandle` and call `abort()`.
- `host.zone()` replaces every `host.calendar()` call (10 call sites listed by `grep -n 'host.calendar' Engine.swift`).
- `ConformanceTests` in this target replays engine-level timelines with `TimelineRecorder`; port the recorder literally, since its output format is compared as text.

- [ ] Follow P1 to P8. Gate: `check-test-parity.py --require-complete TimeTugEngineTests`; add the flag to `rust-lint`.

### Task 5: `timetug-engine-protocol`

| Swift source | Rust module |
|---|---|
| `TimeTugEngineProtocol/JSONValue.swift` | not ported: use `serde_json::Value` |
| `TimeTugEngineProtocol/Envelope.swift` | `envelope.rs` |
| `TimeTugEngineProtocol/MessageCatalog.swift` | `message_catalog.rs` |
| `TimeTugEngineProtocol/Config.swift` | `config.rs` |
| `TimeTugEngineProtocol/WireTypes.swift` | `wire_types.rs` (includes `WireDates`) |
| `TimeTugEngineProtocol/CommandMapping.swift` | `command_mapping.rs` |
| `TimeTugEngineProtocol/StateMapping.swift` | `state_mapping.rs` |
| `TimeTugEngineProtocol/ServiceMessages.swift` | `service_messages.rs` |

**Swift tests:** `TimeTugEngineProtocolTests/`: `EnvelopeTests`, `CommandMappingTests`, `MappingTests`, `FixtureTests` (25), `GoldenMessages.swift`, `Support.swift`.

**Vectors replayed:** `wire/dates.json`.

**Decisions:**
- `WireConfig::parse(json: &str) -> Result<WireConfig, Invalid>` with the six `Invalid` cases and the same validation order: not JSON, unsupported version, empty data directory, unknown platform (`windows`, `linux`, `macos`), unknown zone (through `Zone::named`), invalid test clock start.
- `FixtureTests` reads `Conformance/Fixtures/golden/*.json`. For each of the 74 files: decode into its wire type where the catalog gives one, encode, and compare as `serde_json::Value` with the file's value. Additionally honour `TT_BASELINE_FIXTURES=<dir>` exactly as the Swift test does (decode the baseline's fixtures with current code and require the superset relation defined in `AGENTS.md`); the Rust `compat` job in Task 10 uses it.
- The superset comparison is one function, `protocol::compat::is_superset(current: &Value, baseline: &Value) -> bool`, with the definition copied from `AGENTS.md` ("Additive has one exact meaning for JSON") into its doc comment, and its own tests (object gains a member: true; array length differs: false; number becomes string: false; `null` stays `null`: true).
- State mapping decides which optional members are omitted and which are `null`: the fixtures `edge-state-empty.json`, `edge-state-all-day-only.json` and `edge-state-sources-each-status.json` are the pin. Use `f64_swift` for every number that Swift writes from a `Double` or `TimeInterval`.
- Add an end-to-end data-directory test (Review Focus 4): copy `fixtures` of 1.x (`connections.json`, `sync-state.json` from `calendar-connectors` `Tests/PersistedFormats/1.2.0/`, vendored into `crates/timetug-engine-protocol/src/tests/data/legacy-data-dir/` together with the three engine fixtures under the file names the Swift engine uses on disk; read those names from `Engine.swift` and `AccountManager.swift`) into a temp directory, build an engine over it with fakes, start it, and assert the accounts, settings, ledger entries and lessons that the state reports.

- [ ] Follow P1 to P8. Gate: `--require-complete TimeTugEngineProtocolTests`.

### Task 6: `timetug-engine-c` — session, delivery, request table

| Swift source | Rust module |
|---|---|
| `TimeTugEngineC/HandleRegistry.swift` | `handle_registry.rs` |
| `TimeTugEngineC/Delivery.swift` | `delivery.rs` (`HostCallback`, `Delivery`, `Outbox`) |
| `TimeTugEngineC/RequestTable.swift` | `request_table.rs` |
| `TimeTugEngineC/RemoteHostServices.swift` | `remote_host_services.rs` |
| `TimeTugEngineC/ManualEngineClock.swift` | `manual_engine_clock.rs` |
| `TimeTugEngineC/Connectors.swift` | `connectors.rs` |
| `TimeTugEngineC/EngineSession.swift` | `engine_session.rs` |
| `TimeTugEngineC/CInterface.swift` | `c_interface.rs` |

**Swift tests:** `TimeTugEngineCTests/`: `LifecycleTests` (16), `RemoteHostServicesTests` (15), `RemoteExternalTokenSourceTests` (27), `ScenarioTests` (5), `ScenarioRunner.swift`, `EngineSupport.swift`, `Support.swift`.

**Decisions:**
- **Threads.** Per engine: one **engine thread** that owns a `tokio` current-thread runtime with time enabled and runs until shutdown; one **delivery thread** (a plain `std::thread`) that calls the host. `tt_engine_create` builds both and returns; nothing is delivered until `start`.
- **Intake.** `EngineSession::send(json: String)` pushes onto a `tokio::sync::mpsc::UnboundedSender<String>`; the intake task on the engine thread decodes in order and dispatches to lanes exactly as the Swift doc comment of `EngineSession` describes (lanes, and `account.cancel` and `test.advanceClock` acting at once). `reply` calls `RequestTable::fulfill` directly from the calling thread (it only takes a `std::sync::Mutex` and completes a `tokio::sync::oneshot`).
- **Delivery.** A `std::sync::Mutex<Queue>` plus `Condvar`. Queue entries are `Message(String)` or `State(String)`; `enqueue_state` removes a waiting `State` (if any) and pushes the new one at the back. `close(wait_for_callback)`: set closed, notify; when called from a thread other than the delivery thread and `wait_for_callback` is true, block until the delivery thread is not inside a callback (a second `Condvar` on an `in_callback` flag). "Am I on the delivery thread" compares `std::thread::current().id()` with the stored id.
- **The callback call.** `CString::new(message)` (messages are JSON and contain no NUL; if one does, drop it and emit a diagnostic), then `unsafe { (callback.function)(callback.context, c_string.as_ptr()) }`. `HostCallback` holds `extern "C" fn(*mut c_void, *const c_char)` and `*mut c_void`, with `unsafe impl Send`.
- **Handles.** A process-wide `static REGISTRY: Mutex<HandleRegistryInner>`; tokens start at 16 and step by 16, never reused; the handle is the token cast to `*mut tt_engine`. Lookups clone an `Arc<EngineSession>` out and release the registry lock before using it.
- **Exports.** Four functions with the C names, `extern "C"`, the no-mangle attribute in the form the pinned edition requires, `catch`-free. Null `config_json` or null `on_message` returns null. C strings are read with `CStr::from_ptr(...).to_string_lossy()` and copied before returning; a null `command_json` or `reply_json` is the empty string, as in Swift.
- **Shutdown.** `tt_engine_destroy` removes the handle, then `shutdown()`: fail all requests with `cancelled`, close delivery (waiting if outside a callback), signal the engine thread to stop and, when outside a callback, join it with the same bound Swift uses (read `shutdown()` in `EngineSession.swift` for the number). Inside a callback: cancel and return at once; the threads end on their own and are detached.
- **Version.** `EngineBuild::VERSION` is `env!("TIMETUG_ENGINE_VERSION")` supplied by `build.rs` from the environment variable of the same name, defaulting to `"0.0.0-dev"`. `scripts/release/stamp-engine-version.py` is replaced in Task 9 by setting that variable in the release workflow.
- `RequestTable` timeouts run on the engine clock, so `test.advanceClock` drives them.
- `ScenarioTests` reads `Conformance/Scenarios/*.json` and honours `TT_BASELINE_SCENARIOS=<dir>` as the Swift test does. Port `ScenarioRunner.swift` literally; the scenario step vocabulary (`send`, `expect.events`, `expect.state`, replies, clock advances) is defined only by that file. These tests live in `crates/timetug-engine-c/tests/scenarios.rs` and call the four exported functions through their Rust symbols.
- Add the Review Focus 3 garbage test here.

- [ ] Follow P1 to P8. Gate: `--require-complete TimeTugEngineCTests`; all 13 scenario files pass.

### Task 7: `c-smoke` against the Rust library

**Files:**
- Modify: `c-smoke/run.sh`, `scripts/ci/run-c-smoke.ps1`
- Modify: `.github/workflows/ci.yml` (the Rust jobs run the smoke)

- [ ] **Step 1: Add a `--rust` mode** to both scripts: build with `cargo build --release -p timetug-engine-c`, take the library from `target/release`, keep the export check (`nm -gU` on macOS, `nm -D --defined-only` on Linux, `dumpbin /exports` on Windows) and the compile-and-run of `c-smoke/smoke.c`, and drop the Swift runtime rpath. On Windows link against `TimeTugEngineC.dll.lib` (the import library `cargo` writes next to the DLL; confirm the file name in `target/release`).
- [ ] **Step 2: Run** `c-smoke/run.sh --rust` on macOS. Expected: `exports: tt_engine_create tt_engine_send tt_engine_reply tt_engine_destroy` and the smoke's success line.
- [ ] **Step 3: Call it** from `rust-macos`, `rust-linux`, `rust-windows-x64`, `rust-windows-arm64`.
- [ ] **Step 4: Commit; pull request.**

### Task 8: Concurrency harness

**Files:**
- Create: `c-harness/harness.c`, `c-harness/run.sh`, `scripts/ci/run-c-harness.ps1`
- Modify: `.github/workflows/ci.yml`

`harness.c` is C11 with a tiny thread shim (`pthread` on POSIX, `CreateThread`/`CRITICAL_SECTION` on Windows, selected with `#ifdef _WIN32`). It links the engine library, uses `testing: true` configs with a temp data directory, answers service requests from the callback thread or from a helper thread as each case says, and exits non-zero with the case name on the first failed assertion. Each case has a 30-second watchdog.

Cases (each a function, each run 200 times in a loop unless stated):

| Case | Asserts |
|---|---|
| `ordered_events` | 4 threads each send 500 `takeover.test` and `refresh` commands; callbacks never overlap (an atomic `in_callback` flag is never seen set on entry); `state` revisions seen are strictly increasing |
| `state_coalescing` | the callback sleeps 50 ms on each `state`; 2,000 commands that each change state are sent; the number of `state` callbacks is far below 2,000 (assert below 200) and the last one has the highest revision the engine published (learned from a final `refresh` round trip) |
| `events_not_dropped` | the callback sleeps 5 ms; 300 `takeover.test` commands produce exactly 300 `event.takeoverDue` |
| `send_from_callback` | every callback calls `tt_engine_send` with `refresh` (bounded to 1,000 total); no deadlock |
| `reply_from_other_thread` | service requests are answered by a helper thread after 1 ms; all complete |
| `destroy_outside_callback` | another thread hammers `send` while the main thread calls `destroy`; after `destroy` returns, a flag is set; no callback observes the flag set |
| `destroy_inside_callback` | the first `state` callback calls `destroy`; returns at once; no further callback starts (checked for 200 ms) |
| `destroy_with_pending_requests` | ten service requests pending (the host never answers); `destroy` returns within 5 s |
| `stale_handles` | `send`, `reply`, `destroy` on NULL, on a destroyed handle and on the value `0x1234` do nothing |
| `double_destroy` | two threads call `destroy` on the same handle at once |
| `many_engines` | 16 engines created, started and destroyed concurrently, each with its own data directory |

- [ ] **Step 1: Write the harness and scripts.** To produce service requests without real accounts, use the request shapes the `add-account-oauth` scenario triggers (read that scenario for the command and the first `service.*` request it causes).
- [ ] **Step 2: Run against the Swift library first** (`c-harness/run.sh --swift`): every case must pass there. A case that fails on Swift is a wrong test; fix the test. This is the proof the harness encodes the existing contract.
- [ ] **Step 3: Run against Rust** (`c-harness/run.sh --rust`). Expected: all pass. Fix the Rust session or delivery code for any failure.
- [ ] **Step 4: Run under ThreadSanitizer once locally on macOS or Linux** for the Rust library: build with the nightly toolchain's `-Zsanitizer=thread` in a throwaway checkout (not committed, not in CI; the pinned toolchain stays stable). Record the result in the pull request. Any report in engine code is a bug.
- [ ] **Step 5: Add to CI** in the four Rust platform jobs (Rust library only).
- [ ] **Step 6: Commit; pull request.**

### Task 9: The .NET package on the Rust library

**Files:**
- Modify: `dotnet/pack/assemble-native.ps1`, `dotnet/pack/measure-size.ps1`, `scripts/ci/run-dotnet-tests.ps1`, `dotnet/pack/TimeTug.Engine.nuspec.props` (the native file list only)
- Modify: `scripts/ci/tests/test_pack_inventory.py`
- Create: `THIRD-PARTY-NOTICES.md`, `scripts/ci/check-third-party-notices.py`, its test
- Create: `docs/rust-port/size.md`

- [ ] **Step 1: `assemble-native.ps1 -Rust`**: copy only `target/<triple>/release/TimeTugEngineC.dll` (triples `x86_64-pc-windows-msvc`, `aarch64-pc-windows-msvc`) to `-Out`; check the four exports with `dumpbin /exports`; check with `dumpbin /dependents` that every dependency is a Windows system DLL (allow-list as a constant in the script: `KERNEL32.dll`, `ntdll.dll`, `bcryptprimitives.dll`, `ADVAPI32.dll`, `USERENV.dll`, `WS2_32.dll`, `api-ms-win-*.dll`, `bcrypt.dll`; anything else fails, and the fix is to find which crate pulled it in, not to extend the list without review). No `VCRUNTIME*.dll` or `MSVCP*.dll` may appear: that proves the static C runtime.
- [ ] **Step 2: Static C runtime.** In `.cargo/config.toml` (tracked): `[target.x86_64-pc-windows-msvc] rustflags = ["-C", "target-feature=+crt-static"]` and the same for `aarch64-pc-windows-msvc`.
- [ ] **Step 3: `measure-size.ps1`**: `$TriggerBytes` becomes `8MB` applied to the **uncompressed** native set per architecture, and exceeding it is an error (`exit 1`), not a warning. Keep the Markdown table.
- [ ] **Step 4: Package contents.** Update the native file list so the package carries exactly one native file per architecture; update `test_pack_inventory.py` to expect that.
- [ ] **Step 5: Third-party notices.** `THIRD-PARTY-NOTICES.md` lists every crate in `cargo tree -e normal --prefix none -p timetug-engine-c` with version, licence and the licence text. `check-third-party-notices.py` fails when a crate in the tree is missing from the file or a listed one is no longer in the tree. Include the file in the NuGet package next to the header.
- [ ] **Step 6: Run the .NET suite on macOS** against Rust: build the library, then run `dotnet test dotnet/TimeTug.Engine.sln` with the library-path environment variable `NativeMethods.cs` reads (find its name at the `LibraryVariable` constant) pointing at `target/release/libTimeTugEngineC.dylib`. Expected: every test passes with **no edit** to the C# code. A failure here is a Rust bug (most likely JSON number forms or omitted-versus-null members).
- [ ] **Step 7: Run it on Windows ARM64 in the VM and on the x64 runner** through `scripts/ci/run-dotnet-tests.ps1 -NativeDir build/native/<rid>`. The test count must be at or above `scripts/ci/dotnet-test-floor.txt`.
- [ ] **Step 8: Measure.** Run `measure-size.ps1`; run the bench harness of phase 0 (`scripts/benchmarks/run-engine-bench.*`) against Rust on the same three machines, three runs each. Write `docs/rust-port/size.md` and extend `baselines.md` with a Rust column. Gates: size at most 8 MB per architecture; `readyMs`, `workingSetBytes`, `privateBytes`, `cpuMsIdle` each at or below the Swift baseline (10% tolerance on time and CPU).
- [ ] **Step 9: If the size gate fails**, in this order: confirm `opt-level = "s"`, fat LTO, one codegen unit, strip, abort are in effect (`cargo build --release -v`); run `cargo bloat --release -p timetug-engine-c --crates` (a local tool, not a dependency) and remove the largest avoidable contributor (unused `serde_json` features, `jiff` features such as its bundled database on platforms that have a system one, formatting machinery from `Debug` derives on wire types); try `opt-level = "z"` and compare the benchmark. Never drop the bundled zone database on Windows.
- [ ] **Step 10: Commit; pull request.**

### Task 10: `v2` becomes Rust-only; CI, compat and bump chain

**Files:**
- Delete: `Package.swift`, `Package.resolved`, `Sources/`, `Tests/` (after moving fixtures), `scripts/ci/install-swift-windows.ps1`, `scripts/ci/swift-windows-version.txt`, `scripts/ci/count-swift-tests.py` and its test, `scripts/ci/select-xcode.sh` (if nothing else uses it), `scripts/ci/check-architecture.sh` and its test, `scripts/ci/bump-resolved.py`, `scripts/ci/resolved-version.py` and their tests, `scripts/release/stamp-engine-version.py` and its test, the `VectorExporter` sources and the `vectors-current` job
- Move: `Tests/TimeTugEngineTests/Fixtures/*` to `fixtures/engine/`; update the two test paths
- Modify: `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `.github/workflows/bump-dependencies.yml`, `scripts/ci/compat/compat.py` and `scripts/ci/tests/test_compat.py`, `scripts/ci/check-repository-contracts.py`, `.github/dependabot.yml` (add the `cargo` ecosystem), `.qindexignore`, `AGENTS.md`, `README.md`
- Create: `scripts/ci/bump-cargo-dependency.py` and its test, `scripts/ci/cargo-dependency-version.py` and its test

Do this only when Tasks 1 to 9 are merged and the parity ledger has no unchecked entry older than a week. The same change is made in `calendar-connectors` (its own pull request, done first): delete the Swift package and Swift jobs, move `Tests/PersistedFormats/` to `fixtures/persisted-formats/`, keep the vectors.

- [ ] **Step 1: Tag the last commit that has both languages** by recording its SHA in `docs/rust-port/README.md` ("last dual-language commit"). No git tag (agents do not tag).
- [ ] **Step 2: Remove the Swift sources and Swift CI jobs.** `ci.yml` keeps: the four Rust platform jobs (each: tests, release build, `c-smoke --rust`, concurrency harness), `rust-lint`, `rust-targets`, the four `dotnet-*` jobs (now building with `cargo`), `compat`, `compat-dotnet`. Rename the jobs back to the names the branch protection requires (`macos`, `linux`, `windows-x64`, `windows-arm64`, `architecture`, ...), so the required checks keep their names; list old and new names in the pull request for the owner.
- [ ] **Step 3: Rust `compat`.** `compat.py` keeps checks 2 to 6 of `AGENTS.md` and drops check 1 (the Swift API diff):
  - wire contract: `TT_BASELINE_FIXTURES=<baseline dir> cargo test -p timetug-engine-protocol fixture`;
  - old front end, new backend: `TT_BASELINE_SCENARIOS=<baseline dir> cargo test --release -p timetug-engine-c --test scenarios`;
  - C ABI: the header declarations unchanged and the library exports the baseline's functions (the existing `header_breaks` and `library_symbols` functions, pointed at `target/release`);
  - persisted data: `fixtures/engine/` and the baseline's `Tests/TimeTugEngineTests/Fixtures/` add-only (teach `frozen_problems` the path move: a baseline file must exist unchanged at either path);
  - .NET: unchanged.
  The baseline stays "the highest `X.Y.Z` tag reachable from the base branch", which on `v2` is the last 1.x tag: that is the point, every 1.x contract file keeps passing.
- [ ] **Step 4: Connector bump.** `bump-cargo-dependency.py <version>` rewrites the `calendar-connectors` git dependency lines in the workspace `Cargo.toml` to `tag = "<version>"` and runs `cargo update -p calendar-core` (and the other connector crates) so `Cargo.lock` follows; refuses a lower version and a version that is not `X.Y.Z` or `X.Y.Z-alpha.N`. `cargo-dependency-version.py Cargo.lock calendar-connectors` prints the pinned tag (the replacement for `resolved-version.py`; `timetug`'s bump workflow will read it in phase 6). `bump-dependencies.yml` calls the new script. Tests mirror the deleted ones.
- [ ] **Step 5: Release workflow.** `release.yml` on `v2`:
  - the native job builds with `cargo build --release --locked -p timetug-engine-c --target <triple>` with `TIMETUG_ENGINE_VERSION=$VERSION`;
  - `workflow_dispatch` gains an input `prerelease` (string, for example `alpha.1`). With it, on ref `v2` only, the version is `2.0.0-<prerelease>`, the tag is created on the `v2` commit, a GitHub prerelease is published, the NuGet package is pushed as a prerelease, and **no** `library-released` dispatch is sent. `scripts/release/next-version.sh` learns the prerelease form (tests first, in `scripts/release/tests/`);
  - the release notes line becomes "Built and tested with calendar-connectors <tag from Cargo.lock>".
  The same prerelease path is added to `calendar-connectors`' `release.yml` (tag and GitHub prerelease only; it has no package).
- [ ] **Step 6: Documentation.** `AGENTS.md` on `v2` describes the Rust workspace as the library: rules (design section 6.3), backward compatibility (the five remaining checks), verify commands, release flow including prereleases. `README.md` likewise.
- [ ] **Step 7: Run everything locally**, then open the pull request. Gate: every job green on all platforms.

### Task 11: First prerelease and phase close-out

- [ ] **Step 1: (owner)** In `calendar-connectors`, dispatch `Release` on `v2` with `prerelease: alpha.1`. Add to the tracker's owner items with the command: `gh workflow run Release --repo binary-companion/calendar-connectors --ref v2 -f prerelease=alpha.1`.
- [ ] **Step 2:** In `timetug-shared`, run `python3 scripts/ci/bump-cargo-dependency.py 2.0.0-alpha.1`; pull request; CI green.
- [ ] **Step 3: (owner)** Dispatch `Release` on `v2` of `timetug-shared` with `prerelease: alpha.1`: `gh workflow run Release --repo binary-companion/timetug-shared --ref v2 -f prerelease=alpha.1`.
- [ ] **Step 4: Verify the package**: download `TimeTug.Engine` `2.0.0-alpha.1` from nuget.org; `unzip -lv`; exactly one native file per architecture; sizes within budget; the header, fixtures and notices present.
- [ ] **Step 5: Gate check** (design section 9, phase 3): fixtures, scenarios, concurrency harness, `c-smoke`, unchanged .NET suite green on Windows x64, Windows ARM64, macOS, Linux; size within 8 MB; prerelease published. Record links in the tracker.
- [ ] **Step 6: Update the tracker**: phase 3 `done`; Now to phase 4 (and phase 5 may start).
