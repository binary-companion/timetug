# Rust phase 2: Core and Bridge — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `timetug-core`, `timetug-bridge` and `dedup-benchmark` exist as Rust crates on `v2` of `timetug-shared`, equal in behaviour to `TimeTugCore`, `CalendarBridge` and `DedupBenchmark` at the baseline tag.

**Architecture:** A file-for-file translation on top of the phase 1 connector crates: model, takeover rules, duplicate detection, the calendar store, agenda and widget data, then the bridge. Core is pure: no clock, no I/O, no async runtime of its own.

**Tech Stack:** Rust (pinned stable), `serde`, `jiff` (through `calendar-core`), `tokio` (`sync` only, for the store's change streams), `async-trait`.

**Spec:** [`docs/superpowers/specs/2026-11-10-rust-engine-program-design.md`](../specs/2026-11-10-rust-engine-program-design.md). **Conventions (binding):** [`2026-11-10-rust-port-conventions.md`](2026-11-10-rust-port-conventions.md). **Procedure:** steps P1 to P8 of the [phase 1 plan](2026-11-10-rust-phase-1-connectors.md#the-port-procedure-used-by-every-task-below), with `timetug-shared` paths.

All paths are in `binary-companion/timetug-shared`; branches from `v2`, pull requests to `v2`.

## Global Constraints

- The Swift source at the baseline tag is the specification.
- `timetug-core` depends only on `calendar-core` (plus `serde`, `tokio` `sync`, `async-trait`, `thiserror`). It never reads the clock: every function that needs the time takes `now: Timestamp`. `scripts/ci/check-crate-architecture.py` enforces the dependency; a new lint script (Task 1) enforces the clock rule.
- No display strings beyond those the Swift Core already produces (for example `detailSummary`); no localization.
- `Tests/TimeTugEngineTests/Fixtures/*` is never edited.
- The connector crates are consumed at the pinned `rev`; a needed connector change is a pull request in `calendar-connectors` first, then a `rev` bump here.

## Review Focus

1. **Titles that differ only by case, accents, width or spacing** must merge or not exactly as in Swift: pinned by `vectors/text/fold.json` and `vectors/dedup/pair-decisions.json` (Task 3).
2. **Forty near-duplicate events at once** (a shared calendar seen through four accounts): the resolver must give the same groups and stay fast. Pinned by `vectors/dedup/resolutions.json` and the benchmark gate (Tasks 3 and 7).
3. **A takeover whose lead time crosses a DST change or midnight**: pinned by `vectors/takeover/scheduler.json` (Task 2).
4. **A source that fails or returns nothing after having returned events** must keep the last good events, as `CalendarStore` does in Swift: pinned by `CalendarStoreTests` and `CalendarStoreSourcesTests`; add one test with three sources where the middle one fails twice in a row.
5. **An all-day event viewed from a zone on the other side of the date line**: pinned by `vectors/agenda/day-agenda.json` and `vectors/widget/snapshot.json` (Tasks 5).

---

### Task 1: `timetug-core` — model and the clock lint

| Swift source | Rust module |
|---|---|
| `TimeTugCore/Model/TimeTugCalendarEvent.swift` | `model/event.rs` |
| `TimeTugCore/Model/TimeTugCalendarEvent+AllDay.swift` | `model/event_all_day.rs` |
| `TimeTugCore/Model/CalendarInfo.swift` | `model/calendar_info.rs` |
| `TimeTugCore/Model/MergeTypes.swift` | `model/merge_types.rs` |
| `TimeTugCore/Model/TakeoverSettings.swift` | `model/takeover_settings.rs` |
| `TimeTugCore/Sources/CalendarSource.swift` | `sources.rs` |

**Swift tests:** `TimeTugCoreTests/`: `ModelTests`, `TimeTugCalendarEventTests`, `AllDayDatesTests`, `CalendarInfoTests`, `CalendarInfoColorTests`, `SettingsRulesTests`, `TakeoverSettingsRemovalTests`, `Support`.

**Vectors replayed:** `text/dedup-key.json`.

**Files also created:** `scripts/ci/check-no-clock.py`, `scripts/ci/tests/test_check_no_clock.py`.

**Decisions:**
- `TimeTugCalendarEvent` wraps `calendar_core::CalendarEvent` and forwards its fields through accessor methods with the Swift property names in snake case; it does not implement `Deref`.
- `TimeTugCore.CalendarSource` (Core's own protocol, distinct from the library's) becomes `timetug_core::CalendarSource`. Keep the two names distinct in code by always importing the library's as `calendar_core::CalendarSource as LibrarySource` in files that see both.
- `TakeoverSettings` has a legacy decoding path (`settings-legacy.json`: `{"disabled":true,"skipSoloEvents":true,"leadTime":120}`); `TakeoverSettingsRemovalTests` and phase 3's `LegacyFixtureTests` pin it. Port the hand-written `init(from:)` key by key.
- `check-no-clock.py` fails if any file under `crates/timetug-core/src` or `crates/timetug-bridge/src` (tests excluded) contains `Timestamp::now`, `SystemTime`, `Instant::now`, `Zoned::now`, `tokio::time`, or `std::env`. Test it with one clean and one offending fixture file. Add it to `rust-lint`.

- [ ] Follow P1 to P8.

### Task 2: `timetug-core` — takeover

| Swift source | Rust module |
|---|---|
| `TimeTugCore/Takeover/TakeoverRequest.swift` | `takeover/request.rs` |
| `TimeTugCore/Takeover/TakeoverPolicy.swift` | `takeover/policy.rs` |
| `TimeTugCore/Takeover/TakeoverLedger.swift` | `takeover/ledger.rs` |
| `TimeTugCore/Takeover/TakeoverGuard.swift` | `takeover/guard.rs` |
| `TimeTugCore/Takeover/Scheduler.swift` | `takeover/scheduler.rs` |

**Swift tests:** `TakeoverPolicyTests`, `TakeoverLedgerTests`, `TakeoverGuardTests`, `SchedulerTests`.

**Vectors replayed:** `takeover/scheduler.json`, `takeover/ledger.json`.

**Decisions:**
- The ledger is persisted (family A): keys like `"s/a/1800000000"`, entries `{"fired":{}}` and `{"snoozed":{"until":<reference seconds>}}`, `end` and `recordedAt` as reference-date numbers. Write the serde for `Entry` by hand and test it against `Tests/TimeTugEngineTests/Fixtures/takeover-ledger.json` now (load, compare to expected values, save, reload), even though the store that reads the file is phase 3.
- Pruning rules and the fire guard window are copied as constants with the Swift names.

- [ ] Follow P1 to P8.

### Task 3: `timetug-core` — duplicate detection

| Swift source | Rust module |
|---|---|
| (new) | `text.rs` (`fold`) |
| `TimeTugCore/Dedup/DuplicateRules.swift` | `dedup/rules.rs` |
| `TimeTugCore/Dedup/DuplicateResolver.swift` | `dedup/resolver.rs` |
| `TimeTugCore/Dedup/LessonBook.swift` | `dedup/lesson_book.rs` |
| `TimeTugCore/Dedup/Adjudication.swift` | `dedup/adjudication.rs` |

**Swift tests:** `DuplicateRulesTests`, `DuplicateResolverTests`, `DuplicateResolverEquivalenceTests`, `BaselineDuplicateResolver` (a test-only reference implementation: port it to `src/tests/baseline_duplicate_resolver.rs`), `LessonBookTests`, `AdjudicationTests`, `ManualMergeTests`.

**Vectors replayed:** `text/fold.json`, `text/case-compare.json`, `dedup/pair-decisions.json`, `dedup/resolutions.json`.

**Decisions:**
- `text::fold(&str) -> String` reproduces `folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)`. Build it in this order and stop at the first step that passes every case of `text/fold.json`: (1) Unicode canonical decomposition, drop combining marks (general category Mn), lowercase; (2) add a table of the remaining differences generated from the vector. The decomposition data may not come from a new crate: if step 1 needs data `std` lacks, generate one table `static FOLD: &[(char, &str)]` from the vector file with a small script committed under `scripts/dev/`, and use it for all non-ASCII input. ASCII takes a fast path.
- `DuplicateRules::normalize` then applies the rest of the Swift function (whitespace, punctuation) literally.
- The resolver's data structures (the interval tree in `init(_ events:)`, the union-find, `hasBlockedPair`) are ported literally, with indexes as `usize`. Do not replace them with library structures; the equivalence test against `BaselineDuplicateResolver` and the vectors are the proof.
- `Adjudication.swift` line 172: its encoder uses sorted keys and **milliseconds since 1970**. `LessonBook` uses the default reference-date encoding (see `dedup-state.json`: `"lastUsed" : 821692800`). Test both against `Tests/TimeTugEngineTests/Fixtures/dedup-state.json`.
- `DuplicateAdjudicator` (the seam the engine's text generator implements) becomes `#[async_trait] pub trait DuplicateAdjudicator: Send + Sync`.

- [ ] Follow P1 to P8. Gate: all four vector files pass in full.

### Task 4: `timetug-core` — calendar store

| Swift source | Rust module |
|---|---|
| `TimeTugCore/Store/CalendarStore.swift` | `store/calendar_store.rs` |

**Swift tests:** `CalendarStoreTests`, `CalendarStoreSourcesTests`, `CalendarStoreNoticesTests`, `CalendarStoreInferenceTests`.

**Decisions:**
- `CalendarStore` is a Swift actor. Port per conventions section 4: `std::sync::Mutex<State>`, async methods, no lock held across an await. The Swift method bodies show where the awaits are; each `await` in Swift is a point where Rust must have released the lock, and state read before it must be re-read after it wherever Swift re-reads.
- Sources are refreshed concurrently in Swift (task group). Core has no runtime (`tokio` `sync` only) and the `futures` crate is not on the allowed list, so run them concurrently on the caller's task with a small hand-written `pub(crate) async fn join_all<T>(futures: Vec<Pin<Box<dyn Future<Output = T> + Send>>>) -> Vec<T>` in `store/join_all.rs` (built on `std::future::poll_fn`; test: three futures finishing in reverse order return in input order, and all three are polled before any completes). Result order is source order, as Swift's collection is.
- `set_calendar` in Swift takes a `Calendar`; in Rust it is `set_zone(zone: Zone)`. Record the rename in `file-map.md`.
- The snapshot type (`CalendarSnapshot`) and the store's change notifications keep their Swift shapes; `changes` is an unbounded `mpsc`.
- Add the Review Focus 4 test.

- [ ] Follow P1 to P8.

### Task 5: `timetug-core` — agenda and widget data

| Swift source | Rust module |
|---|---|
| `TimeTugCore/Agenda/DayAgenda.swift` | `agenda/day_agenda.rs` |
| `TimeTugCore/Widget/WidgetSnapshot.swift` | `widget/snapshot.rs` |
| `TimeTugCore/Widget/WidgetTimeline.swift` | `widget/timeline.rs` |

**Swift tests:** `DayAgendaTests`, `WidgetSnapshotTests`, `WidgetTimelineTests`.

**Vectors replayed:** `agenda/day-agenda.json`, `widget/snapshot.json`.

**Decisions:**
- `WidgetSnapshot` and `WidgetEvent` are `Codable` and written by the Mac app into the App Group (`agenda-snapshot.json`) and read by the widget extension. Their JSON is a contract with shipped widgets: family A dates (reference seconds) unless the Swift code sets a strategy at the write site (check `WidgetSnapshotStore.swift` in `timetug`'s `Apps/macOS/Shared` and match it). Add a test with a snapshot JSON string copied from a Swift encode of a fixed value (put the Swift snippet that produced it in the test's comment).
- Every `calendar: Calendar` parameter becomes `zone: &Zone`.

- [ ] Follow P1 to P8. After this task: `check-test-parity.py --require-complete TimeTugCoreTests` passes; add that flag to `rust-lint`.

### Task 6: `timetug-bridge`

| Swift source | Rust module |
|---|---|
| `CalendarBridge/EventMapper.swift` | `event_mapper.rs` |
| `CalendarBridge/ConnectedSource.swift` | `connected_source.rs` |

**Swift tests:** `CalendarBridgeTests/`: `EventMapperTests`, `ConnectedSourceTests`.

**Decisions:**
- `ConnectedSource` holds `Arc<dyn calendar_core::CalendarSource>` and implements `timetug_core::CalendarSource`. Error and change translation is a literal port; cancelled events are dropped in `EventMapper`.

- [ ] Follow P1 to P8. Add `--require-complete CalendarBridgeTests` to `rust-lint`.

### Task 7: `dedup-benchmark` and the performance gate

**Files:**
- Modify: `crates/dedup-benchmark/src/main.rs` (port of `Sources/DedupBenchmark/main.swift`)
- Modify: `scripts/benchmarks/run-dedup.sh` (add `--rust`; default stays Swift while Swift exists)
- Modify: `docs/rust-port/baselines.md`

- [ ] **Step 1: Port `main.swift`** so the Rust binary builds the same synthetic inputs (same sizes, same generator constants) and prints lines in the same format.
- [ ] **Step 2: Run both** on the same Mac, three times each, release builds: `scripts/benchmarks/run-dedup.sh` and `scripts/benchmarks/run-dedup.sh --rust`.
- [ ] **Step 3: Record** the medians in `baselines.md` next to the Swift numbers.
- [ ] **Step 4: Gate.** Each Rust median must be at or below the Swift median times 1.10. If not, profile (`cargo build --release` with `debug = true` in a local profile, `sample` or Instruments), fix the hot spot without changing results, and re-run the vectors.
- [ ] **Step 5: Commit; pull request against `v2`.**

### Task 8: Phase close-out

- [ ] **Step 1:** `python3 scripts/ci/check-test-parity.py --require-complete TimeTugCoreTests --require-complete CalendarBridgeTests`. Expected: PASS.
- [ ] **Step 2:** List every `n/a` row in the pull request; none is expected in this phase.
- [ ] **Step 3:** Port open parity-ledger entries that touch Core or Bridge.
- [ ] **Step 4:** Update the tracker in `timetug` (phase 2 `done`, counts, benchmark numbers, Now to phase 3).
