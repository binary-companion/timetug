# Rust port conventions

Every phase plan of the [Rust engine program](../specs/2026-11-10-rust-engine-program-design.md) includes this file by reference. An implementer reads it once before any task. Where a phase plan and this file disagree, the phase plan wins and the disagreement is a defect to report.

The port is a **translation**. The Swift source at the baseline tag is the specification of behaviour. When this file, a plan and the Swift source leave something open, do what the Swift code does, and say so in the pull request.

## 1. Working rules

1. Read the Swift file and its Swift tests completely before writing the Rust file. Port the tests first, see them fail to compile or fail, then port the code.
2. One Swift source file becomes one Rust module file unless the plan's mapping table says otherwise. Keep the order of declarations, the names (in Rust case) and the doc comments. Do not improve, simplify, rename or reorder while porting; record ideas in the pull request under "Not done".
3. Never change a test's expected value to make it pass. If a ported test fails, the Rust code is wrong, or the test port is wrong. If you believe Swift and Rust must differ, stop and report.
4. Before using any API of an external crate, read its documentation for the pinned version on docs.rs (or `cargo doc --open`). Do not rely on memory for `jiff`, `quick-xml`, `tokio`, `uniffi` or `url` signatures.
5. Never add a crate that is not on the list in section 3. If one seems needed, stop and report.
6. Work on a branch cut from `v2` in the library repository; open the pull request against `v2`. Never push to `v2` or `main`, never tag, never merge. Commit messages end with the attribution line the session gives.
7. In `timetug` and `timetug-windows`, branch from the default branch and open a pull request, as their agent guides say.
8. Reviews use the `deepseek-review` skill with the Swift file, the Rust file, both test files and this document as context.
9. Implementer subagents run on Sonnet 5.5; escalate to a larger model only when a task has failed review twice.
10. After each task: `cargo fmt --all`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`, then update the parity table rows for the tests you ported (section 8) in the same commit.

## 2. Repository layout (both libraries, on `v2`)

```
Cargo.toml                 workspace manifest: members, [workspace.package], [workspace.dependencies], [workspace.lints], [profile.release]
Cargo.lock                 committed
rust-toolchain.toml        pinned stable channel, components rustfmt and clippy, the targets of design section 6.4
deny.toml                  cargo-deny: licences, bans (allow-list of crates), advisories
crates/<crate-name>/       one directory per crate
  Cargo.toml
  src/lib.rs
  src/<module>.rs
  src/tests/mod.rs         #[cfg(test)] only; one file per Swift test file
  src/tests/<swift_test_file_in_snake_case>.rs
vectors/<area>/<name>.json golden vectors exported from Swift (section 9)
docs/rust-port/            swift-tests-baseline.txt, test-parity.md, parity-ledger.md, file-map.md, baselines.md
Package.swift, Sources/, Tests/   the Swift code, untouched until the end of phase 3
```

All ported tests live inside the crate (`src/tests/`), never in `tests/`, so they can reach `pub(crate)` items the way Swift's `@testable import` does. `tests/` is used only for tests that must link the built library from outside (the C interface, the bindings).

Workspace settings every crate inherits:

- `edition`, `rust-version`, `license`, `repository` from `[workspace.package]`.
- `[workspace.lints.rust] unsafe_code = "forbid"` (the two FFI crates override it to `"allow"` in their own `Cargo.toml` and carry `#![deny(unsafe_op_in_unsafe_fn)]`).
- `[workspace.lints.clippy]`: `unwrap_used`, `expect_used`, `panic`, `todo`, `unimplemented`, `dbg_macro`, `print_stdout`, `print_stderr` all `"deny"`. Test modules start with `#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]`.
- `[profile.release]`: `opt-level = "s"`, `lto = "fat"`, `codegen-units = 1`, `panic = "abort"`, `strip = "symbols"`.

## 3. Allowed external crates

`serde` (with `derive`), `serde_json`, `jiff` (with `serde`), `quick-xml`, `sha2`, `getrandom`, `uuid` (with `v4`), `url`, `thiserror`, `async-trait`, `tokio` (features `rt`, `time`, `sync`, `macros` only; `test-util` allowed in `[dev-dependencies]`), `base64`, `uniffi` (only in `timetug-engine-ffi`). `base64` is on the list because PKCE and HTTP Basic need it and the Swift code used Foundation's.

Versions are pinned once, in `[workspace.dependencies]`, in phase 0; crates say `foo = { workspace = true }`. Default features are switched off wherever the crate still builds without them.

## 4. Type mapping

| Swift | Rust | Notes |
|---|---|---|
| `Date` | `jiff::Timestamp` | Helpers in `calendar_core::time`: `add_seconds(Timestamp, f64) -> Timestamp`, `seconds_between(from, to) -> f64`. A Swift `Date` built from a `Double` is rounded to the nearest nanosecond. |
| `TimeInterval` | `f64` seconds | Keep the unit and the arithmetic of the Swift code. |
| `DateInterval` | `calendar_core::time::DateInterval { start, end }` | Foundation semantics: `contains(t)` is `start <= t <= end` (the end is included); `intersects` is true when the intervals only touch. Port the tests in `ModelTests` that pin this before using it. |
| `TimeZone` | `calendar_core::time::Zone` | A newtype over `jiff::tz::TimeZone` that is `Clone + Eq + Hash + Ord` by identifier and supports the fixed-offset form (`TimeZone(secondsFromGMT:)`). `Zone::named(&str) -> Option<Zone>` mirrors `TimeZone(identifier:)` returning nil. `Zone::identifier() -> &str`. |
| `Calendar(identifier: .gregorian)` with a zone | free functions in `calendar_core::civil` | `start_of_day`, `add(component, n, to:)`, `components(of:)`, `date(from components)`. Each matches Foundation and is pinned by the zone vectors (section 9). No `Calendar` type exists in Rust. |
| `URL` | `calendar_core::UrlString` | A validated newtype over `String` that keeps the **original text** (Foundation's `absoluteString` does; `url::Url` normalizes, which would change JSON output). `UrlString::parse(&str) -> Option<Self>` accepts exactly what the Swift call site accepted; `.parsed() -> url::Url` is for inspecting host, scheme, path and query. |
| `Data` | `Vec<u8>` (owned), `&[u8]` (borrowed) | |
| `UUID` | `uuid::Uuid` in memory | As text always **uppercase**, as Swift's `uuidString` is. Identifiers that Swift stores as `String` stay `String`. |
| `String` | `String` | See section 7 for case, folding, comparison and length. |
| `Int` | `i64` | `usize` only for indexes and lengths inside a function. |
| `Double` | `f64` | JSON output: section 6. |
| `[T]` | `Vec<T>` | |
| `Set<T>` | `BTreeSet<T>` | Deterministic iteration. |
| `[K: V]` | `BTreeMap<K, V>` | `HashMap` is allowed only when the map is never iterated or serialized. |
| `T?` | `Option<T>` | |
| `struct` | `struct` with `#[derive(Clone, Debug, PartialEq)]` plus `Eq, Hash` where Swift says `Hashable` and no `f64` field prevents it | A Swift `Hashable` struct with a `Double` gets a hand-written `Eq`/`Hash` over `to_bits()`. |
| `enum` with raw `String` values | `enum` plus `as_str()` and `from_str()` giving the Swift raw values | serde uses the raw values. |
| `enum` with associated values | `enum` with struct-like or tuple variants | serde layout: section 6. |
| `RawRepresentable` struct over `String` (`CalendarService`, `CalendarProvider`) | newtype `struct X(pub String)` with the same constants | |
| `protocol` (a seam) | `trait X: Send + Sync` with `#[async_trait]` for `async` methods; used as `Arc<dyn X>` | Protocol extension defaults become provided trait methods. |
| `actor` | `struct` holding `std::sync::Mutex<State>`, with `async fn` methods | Swift actors are **re-entrant at every `await`**. Lock, read or change state, unlock, then await. A `std` guard cannot be held across an `.await` in a `Send` future, and that compiler error is the safeguard: never switch to `tokio::sync::Mutex` to silence it. |
| `AsyncStream<T>` that coalesces (state) | `tokio::sync::watch` | |
| `AsyncStream<T>` that must not drop (events, `changes()`) | `tokio::sync::mpsc::unbounded_channel`; each call returns a new receiver | Closed senders are pruned on the next send. |
| `Task { }` | `tokio::spawn` on the engine runtime; keep the `JoinHandle` wherever Swift kept the `Task` to cancel it | |
| `now: @Sendable () -> Date` parameters | `calendar_core::time::Now = Arc<dyn Fn() -> Timestamp + Send + Sync>` | Connector kinds and sources take it exactly where Swift does. |
| `Sleeper` (`(Duration) async throws -> Void`) parameters | `calendar_core::time::Sleeper = Arc<dyn Fn(f64) -> Pin<Box<dyn Future<Output = Outcome<()>> + Send>> + Send + Sync>` (seconds) | The engine passes one built on its clock; tests pass one that returns at once and records the durations. No connector crate calls `tokio::time`. |
| `Task.sleep`, `clock.sleep(until:)` | the `EngineClock` trait only | No crate except `timetug-engine` (its `SystemClock`) calls `tokio::time`. |
| `CancellationError` | `Failure::Cancelled` | |
| `throws` (untyped) | `Result<T, calendar_core::Failure>` | `enum Failure { Source(SourceError), Write(WriteError), Cancelled, Host(String) }` with `From` for each. Each Swift error enum keeps its own Rust enum with the same cases. A test `#expect(throws: SourceError.authExpired)` becomes `assert_eq!(err, Failure::Source(SourceError::AuthExpired))`. |
| `fatalError`, `precondition`, force unwrap | no equivalent | Return an error. If the Swift code truly cannot reach the line, write `unreachable_unchecked`-free code that returns the nearest error and add a comment naming the Swift line. |

Names: types keep their Swift names. Functions and fields become `snake_case`. A Swift argument label that carries meaning joins the function name (`events(in:)` becomes `events_in`). Record every public rename in `docs/rust-port/file-map.md`.

## 5. Files and paths

- Paths are `std::path::PathBuf`. The data directory comes from the host; no crate computes a home or temp directory.
- Every Swift write with `.atomic` becomes: write to `<name>.tmp-<random>` in the same directory, `sync_all`, rename over the target. One helper, `calendar_core::files::write_atomic(path, bytes) -> std::io::Result<()>`, used everywhere.
- A Swift `try?` on a read (missing or unreadable file means "empty") stays lenient in Rust; do not start failing where Swift did not.

## 6. JSON

All JSON goes through `serde`. There are three families and they differ. Do not rely on serde defaults for any of them: every serialized type states its field names and optional handling.

**Common rules**

- Field names are the Swift property names, exactly (`#[serde(rename_all = "camelCase")]`, or `#[serde(rename = "...")]` where a Swift `CodingKeys` says otherwise).
- A Swift optional that is `nil` is **omitted** on write (Swift's synthesized `encodeIfPresent`): `#[serde(default, skip_serializing_if = "Option::is_none")]`. Where the Swift code hand-writes `encodeNil` or the fixture shows `null`, write `null`; the fixture decides.
- Unknown fields are ignored on read. Never use `deny_unknown_fields`.
- A Swift hand-written `init(from:)` with `decodeIfPresent(...) ?? default` becomes `#[serde(default = "...")]` with the same default.
- Whole numbers must be written without a fraction, as Swift writes them (`120`, not `120.0`): C# reads some of these into integers. Every `f64` field uses `#[serde(serialize_with = "calendar_core::json::f64_swift")]`, which writes an integer when the value is integral and within ±2^53, and the shortest round-trip form otherwise.
- Swift's synthesized layout for an enum with associated values is `{"caseName":{"label":value}}`; a case without values is `{"caseName":{}}`; unlabeled values are `"_0"`, `"_1"`. Reproduce it with explicit serde attributes or a hand-written `Serialize`/`Deserialize`, and pin it with the fixture.

**Family A: persisted files (on users' disks).** `connections.json`, `sync-state.json`, the takeover ledger, the dedup state, the settings file.

- `Date` is Swift's default: a number of seconds since 2001-01-01T00:00:00Z (Unix seconds minus 978,307,200), possibly fractional. Module `calendar_core::json::swift_reference_date`.
- Exception, read from the code: the adjudication store in `TimeTugCore/Dedup/Adjudication.swift` uses milliseconds since 1970. Module `calendar_core::json::millis_since_1970`.
- Output need not be byte-identical to Swift's (spacing, escaped `/`). It must parse to the same JSON value for the same content. Keep pretty printing and sorted keys where Swift set them.
- Reading every committed fixture is mandatory and tested; the fixtures are never edited.

**Family B: the wire protocol (C interface).** Envelopes, commands, state, events, service requests and replies.

- Dates are `WireDates` strings: `2025-10-09T08:53:20.123Z`, UTC, exactly three fraction digits, rounded to the nearest millisecond; reading accepts a missing fraction. Port `WireDates` by hand from `WireTypes.swift`; do not use `jiff`'s formatter for it.
- The golden fixtures in `Conformance/Fixtures/golden` round-trip to equal JSON values.

**Family C: provider payloads** (Google, Microsoft Graph, OAuth token endpoints). Port the Swift DTOs field for field. A missing field never fails the whole response unless it does in Swift.

## 7. Text

- `lowercased()` / `uppercased()`: `to_lowercase()` / `to_uppercase()`.
- `caseInsensitiveCompare(...) == .orderedSame`: compare `to_lowercase()` of both, unless a vector shows a difference; then follow the vector.
- `folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)`: implemented once as `timetug_core::text::fold(&str) -> String` and pinned by the folding vectors. Write it to match the vectors; a lookup table generated from the vectors is acceptable.
- Swift `count`, `prefix(n)`, `dropFirst(n)` on a `String` work on user-perceived characters. Use `chars()` in Rust and add a test with a combining character and an emoji sequence at that call site. If the Swift test for that site needs grapheme behaviour, stop and report (it would need a new crate).
- Swift `<` on `String` and Rust `<` on `str` can order non-ASCII text differently. Where the result of a sort is observable (state, wire, files), add a test with non-ASCII input copied from a vector.
- `trimmingCharacters(in: .whitespacesAndNewlines)`: `trim()`.
- Percent-encoding and form encoding: port the exact allowed-character set the Swift code names; do not swap in `url`'s defaults.

## 8. Tests and the parity table

- `@Test func someName()` becomes `#[test] fn some_name()`. An async test becomes `#[tokio::test(flavor = "current_thread", start_paused = true)]`.
- `@Test(arguments: [...])` becomes one test that loops over the same cases, in the same order, with the case in the assertion message.
- `#expect(a == b)` is `assert_eq!(a, b)`; `#expect(cond)` is `assert!(cond)`; `#require` is the same with an early return through `unwrap()`.
- Swift test helpers (`TestHelpers.swift`, `Support.swift`, `Harness.swift`, fakes) are ported to `src/tests/support.rs` or to `calendar-test-support`, wherever the Swift helper lives.
- Tests gated off by default in Swift (live tests needing real accounts) are ported with `#[ignore = "live: needs <VARIABLE>"]` and the same environment variables.

`docs/rust-port/swift-tests-baseline.txt` (generated in phase 0, never edited by hand) has one line per Swift test at the baseline: `<Target>/<File>.swift::<funcName>`.

`docs/rust-port/test-parity.md` has one table row per line of that file:

```
| Swift test | Rust test | Status |
|---|---|---|
| CalendarCoreTests/AllDayTests.swift::dateOfInstant | crates/calendar-core/src/tests/all_day_tests.rs::date_of_instant | ported |
| CalendarOAuthTests/SHA256Tests.swift::emptyInput | - | n/a: the SHA256Hashing seam is removed; sha2 is tested upstream |
```

Status is `pending`, `ported` or `n/a: <reason>`. `scripts/ci/check-test-parity.py` fails when a baseline line has no row, when a `ported` row names a file or `fn` that does not exist, and (with `--require-complete <Target>`) when any row of that target is still `pending`.

## 9. Golden vectors

A vector file is produced by the Swift code at the baseline and replayed by a Rust test. Format:

```json
{
  "schema": 1,
  "area": "recurrence-expand",
  "baseline": "1.2.0",
  "cases": [ { "name": "weekly-byday-dst-gap-0001", "input": { }, "expected": { } } ]
}
```

- Instants in vectors are integer Unix **milliseconds**; zones are IANA identifiers; durations are seconds.
- Exporters are deterministic: hand-written cases first, then generated cases from a fixed-seed linear congruential generator written in the exporter (never `SystemRandomNumberGenerator`).
- The exporter is a Swift executable target (`VectorExporter`) on `v2`. CI on macOS re-runs it and fails if the committed files differ, for as long as the Swift sources exist.
- A Rust vector test loads the file with `include_str!`, runs every case and reports all failing case names at once, not only the first.
- A vector is never edited by hand and never regenerated to make Rust pass.

## 10. Things that will go wrong

Each of these has already been seen in the Swift code. Check them at review.

1. **Reference-date numbers.** `821692200` in a ledger file is seconds since 2001, not since 1970.
2. **`120` versus `120.0`** in JSON written for C#.
3. **Uppercase UUID strings** in `connections.json`.
4. **URL normalization**: `url::Url` adds a trailing `/` and lowercases hosts. Keep original text (section 4).
5. **Header names**: `HTTPResponse` lowercases header names on construction; later lookups are case-insensitive.
6. **`DateInterval` end is included.**
7. **Actor re-entrancy**: holding a lock across an await changes interleavings the engine tests rely on.
8. **Month arithmetic**: Foundation clamps (31 January plus one month is the last day of February) and resolves DST gaps forward; the zone vectors pin both.
9. **All-day events** are stored as UTC midnights and displayed in the viewer's zone; port `AllDay.swift` before anything that uses dates.
10. **Order of dictionary iteration** is random in Swift, so Swift code that iterates a dictionary and produces observable output always sorts first. If you find Rust output depending on `BTreeMap` order where Swift sorted by something else, follow Swift's sort.
11. **Cancellation**: a cancelled Swift task throws at the next suspension point. In Rust a dropped future just stops. Wherever Swift code catches `CancellationError` to clean up, use a guard type whose `Drop` does the cleanup.
12. **Privacy of diagnostics**: tokens, passwords, email addresses, feed links and host exception text never enter a diagnostic. Port the `LeakTests` and the diagnostics tests early and keep them passing.
