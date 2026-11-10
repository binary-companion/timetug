# Rust phase 1: connector library — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `calendar-connectors` exists as eight Rust crates on `v2` whose behaviour equals the Swift library at the baseline tag, proven by a Rust counterpart of every Swift test, the golden vectors and the persisted-format fixtures.

**Architecture:** A file-for-file translation in dependency order: model and time first, then recurrence, stores, OAuth, iCalendar, and the four providers. HTTP stays a host seam (`HttpTransport`); there is no built-in transport. The Swift package stays in the repository untouched.

**Tech Stack:** Rust (pinned stable), `serde`/`serde_json`, `jiff`, `quick-xml`, `sha2`, `base64`, `url`, `uuid`, `getrandom`, `thiserror`, `async-trait`, `tokio` (`sync`, `time` for tests only through `test-util`).

**Spec:** [`docs/superpowers/specs/2026-11-10-rust-engine-program-design.md`](../specs/2026-11-10-rust-engine-program-design.md). **Conventions (read first, binding for every task):** [`2026-11-10-rust-port-conventions.md`](2026-11-10-rust-port-conventions.md).

All paths are in `binary-companion/calendar-connectors`; all branches are cut from `v2` and all pull requests target `v2`.

## Global Constraints

- The Swift source at the baseline tag is the specification. No behaviour change, no redesign, no new feature.
- Crates and their dependencies: design section 6.1. External crates: conventions section 3. `scripts/ci/check-crate-architecture.py` must stay green.
- `#![forbid(unsafe_code)]` everywhere in this repository.
- Parsers return errors and never panic on any input.
- Microsoft sign-in scopes stay exactly as in the Swift source (read-only, ADR 0017).
- No token, password, email address, feed link or raw provider error text enters a diagnostic that the Swift code keeps it out of.
- `Tests/PersistedFormats/**` is never edited.
- No crate reads the system clock, the environment, or the network. Time arrives as an argument or a `now` closure, as in Swift.

## Review Focus

1. **A provider response the Swift tests never showed** (a missing optional field, an unknown enum string, an extra field, `null` where a value was expected): the mapper must do what the Swift DTO decoding does, usually ignore or default, never fail the whole page. Each mapper task adds a "tolerates unknown and missing fields" test built from the Swift DTO's optionality.
2. **Garbage input to a parser** (iCalendar text, WebDAV XML, a feed that is HTML, truncated JSON, invalid UTF-8): an error, never a panic and never a hang. Tasks 7, 8 and 9 each add a test that feeds 2,000 pseudo-random byte strings and 200 truncated real samples.
3. **A URL that Foundation accepted and `url` rejects, or the reverse**: pinned by `vectors/core/url-accept.json` in Task 1.
4. **An event exactly on a DST transition or at a month end**: pinned by the zone and recurrence vectors in Tasks 1 and 3.
5. **A user's existing `connections.json` and `sync-state.json`**: pinned by the persisted-format tests in Tasks 4, 9, 10 and 11, which load every file under `Tests/PersistedFormats/`.

---

## The port procedure (used by every task below)

Each task lists Swift source files, Swift test files, vectors and task-specific decisions. For each task, do exactly this:

- [ ] **P1. Read** every listed Swift source file and Swift test file in full.
- [ ] **P2. Port the tests** into `crates/<crate>/src/tests/<swift_test_file_snake>.rs` (conventions section 8), and add the vector replay tests named in the task. Register each file in `src/tests/mod.rs`.
- [ ] **P3. Run** `cargo test -p <crate>`. Expected: compile errors or failures naming the missing items.
- [ ] **P4. Port the source files** to the Rust modules named in the task's table, declaration by declaration.
- [ ] **P5. Run** `cargo test -p <crate>`. Expected: every ported test and every vector case passes. A failing vector case is a bug in the Rust code.
- [ ] **P6. Run** `cargo fmt --all && cargo clippy --workspace --all-targets -- -D warnings && cargo test --workspace`.
- [ ] **P7. Update** `docs/rust-port/test-parity.md` (each ported test's row: Rust path and `ported`) and `docs/rust-port/file-map.md` (one row per Swift file). Run `python3 scripts/ci/check-test-parity.py`.
- [ ] **P8. Commit** (`port: <task title>`), push, open the pull request against `v2`, and run the `deepseek-review` skill with the Swift files, the Rust files, both test sets and the conventions as inputs. Verify each finding against the Swift source before acting.

A task is done when its pull request is green on all Rust jobs and all Swift jobs.

---

### Task 1: `calendar-core` — time, text and JSON foundations

No Swift file maps here one to one; these are the helpers the conventions define. They come first because every later file uses them.

**Files:**
- Create: `crates/calendar-core/src/time.rs` (`Zone`, `DateInterval`, `add_seconds`, `seconds_between`)
- Create: `crates/calendar-core/src/civil.rs` (Gregorian arithmetic matching Foundation)
- Create: `crates/calendar-core/src/url_string.rs` (`UrlString`)
- Create: `crates/calendar-core/src/json.rs` (`f64_swift`, `swift_reference_date`, `millis_since_1970`, optional variants of both date modules)
- Create: `crates/calendar-core/src/files.rs` (`write_atomic`)
- Create: `crates/calendar-core/src/failure.rs` (`Failure`)
- Create: `crates/calendar-core/src/tests/{time_vectors,url_vectors,json_helpers,files}.rs`

**Interfaces (produced; later tasks use exactly these):**

```rust
// time.rs
pub struct Zone(/* private */);
impl Zone {
    pub fn named(identifier: &str) -> Option<Zone>;        // TimeZone(identifier:)
    pub fn fixed(seconds_from_gmt: i32) -> Option<Zone>;   // TimeZone(secondsFromGMT:)
    pub fn utc() -> Zone;
    pub fn identifier(&self) -> &str;
    pub fn offset_seconds(&self, at: Timestamp) -> i32;    // secondsFromGMT(for:)
    pub fn as_jiff(&self) -> &jiff::tz::TimeZone;
}
pub struct DateInterval { pub start: Timestamp, pub end: Timestamp }
impl DateInterval {
    pub fn new(start: Timestamp, end: Timestamp) -> DateInterval;
    pub fn duration(&self) -> f64;
    pub fn contains(&self, t: Timestamp) -> bool;           // start <= t <= end
    pub fn intersects(&self, other: &DateInterval) -> bool; // touching counts
}
pub fn add_seconds(t: Timestamp, seconds: f64) -> Timestamp;
pub fn seconds_between(from: Timestamp, to: Timestamp) -> f64;

// civil.rs  (Gregorian only)
pub struct Components { pub year: i64, pub month: i64, pub day: i64, pub hour: i64, pub minute: i64, pub second: i64, pub weekday: i64 /* 1 = Sunday */ }
pub fn components(t: Timestamp, zone: &Zone) -> Components;
pub fn start_of_day(t: Timestamp, zone: &Zone) -> Timestamp;
pub fn date_from(year: i64, month: i64, day: i64, hour: i64, minute: i64, second: i64, zone: &Zone) -> Option<Timestamp>;
pub enum Unit { Second, Minute, Hour, Day, Month, Year }
pub fn add(unit: Unit, n: i64, to: Timestamp, zone: &Zone) -> Option<Timestamp>;

// url_string.rs
pub struct UrlString(/* private String */);
impl UrlString {
    pub fn parse(text: &str) -> Option<UrlString>;   // accepts what Foundation URL(string:) accepts
    pub fn as_str(&self) -> &str;                    // the original text
    pub fn parsed(&self) -> Option<url::Url>;
    pub fn scheme(&self) -> Option<String>;          // lowercased, like URL.scheme?.lowercased() call sites expect
    pub fn host(&self) -> Option<String>;
}

// failure.rs
pub enum Failure { Source(SourceError), Write(WriteError), Cancelled, Host(String) }
pub type Outcome<T> = Result<T, Failure>;
```

`SourceError` and `WriteError` are defined in Tasks 2 and 5; until then `failure.rs` holds only `Cancelled` and `Host` and the later tasks add the variants.

**Vectors replayed:** `zones/offsets.json`, `zones/known.json`, `core/url-accept.json`.

**Decisions:**
- `Zone::named` must accept and reject exactly the identifiers in `zones/known.json`, and `identifier()` must return the Swift canonical text for each. Where `jiff` differs (aliases, case), add a small alias table generated from the vector.
- `Zone` equality, ordering and hashing use `identifier()`.
- `civil::date_from` and `civil::add` resolve a nonexistent local time (DST gap) and an ambiguous one (overlap) as Foundation does; `zones/wall-clock.json` is replayed in Task 3 through `WallClock`, and that is the pin. Read `WallClock.date` in `RuleExpander.swift` before writing `date_from`.
- `UrlString::parse`: start from "non-empty and `url::Url::parse` succeeds or the text is a valid relative reference", then adjust until every case of `core/url-accept.json` matches. `scheme()` and `host()` must match the vector's fields.
- `json::f64_swift`: integral and `abs < 9_007_199_254_740_992.0` is written as an integer; everything else through `serde_json`'s `f64` writer. Test: `120.0` gives `120`, `0.5` gives `0.5`, `-3.0` gives `-3`, `1e300` round-trips.
- `json::swift_reference_date`: `Timestamp` to and from `f64` seconds since 2001-01-01T00:00:00Z. Test with `821692200` (must be 2027-01-15T06:30:00Z) and a fractional value.
- `files::write_atomic`: conventions section 5. Tests: content replaced; no `.tmp-` file remains; a missing parent directory is an error, not a panic.

- [ ] Follow P2 to P8 (P1 and P4's "Swift source" are the conventions and the vectors here; nothing is added to the parity table).

### Task 2: `calendar-core` — model and source types

| Swift source | Rust module |
|---|---|
| `CalendarCore/Model.swift` | `model.rs` |
| `CalendarCore/AllDay.swift` | `all_day.rs` |
| `CalendarCore/CalendarUserAddress.swift` | `calendar_user_address.rs` |
| `CalendarCore/SourceTypes.swift` | `source_types.rs` |
| `CalendarCore/HTTP.swift` | `http.rs` |
| `CalendarCore/DiagnosticLog.swift` | `diagnostic_log.rs` |
| `CalendarCore/JoinURLPolicy.swift` | `join_url_policy.rs` |
| `CalendarCore/ConferenceDetector.swift` | `conference_detector.rs` |
| `CalendarCore/WindowsTimeZones.swift` | `windows_time_zones.rs` |

**Swift tests:** `CalendarCoreTests/`: `ModelTests`, `AllDayTests`, `CalendarUserAddressTests`, `DiagnosticLogTests`, `ConferenceDetectorTests`, `TransportCacheTests`, `TransportRedirectTests`, `TestHelpers`.

**Vectors replayed:** `zones/all-day.json`, `zones/windows-names.json`, `core/conference.json`.

**Decisions:**
- `http.rs`: `HttpRequest { url: UrlString, method: String, headers: BTreeMap<String, String>, body: Option<Vec<u8>> }`, `HttpResponse { status: i64, headers, body: Vec<u8> }` with `HttpResponse::new` lowercasing header names (last one wins) and `header(name)` lowercasing the lookup. `#[async_trait] pub trait HttpTransport: Send + Sync { async fn send(&self, request: HttpRequest) -> Outcome<HttpResponse>; }`.
- **`URLSessionTransport` is not ported.** Mark `TransportCacheTests` and `TransportRedirectTests` rows `n/a: URLSessionTransport is host code; the host supplies HTTP`. Add to the doc comment of `HttpTransport` the contract those tests pinned: the transport performs no caching and, where a connector says so, must not follow redirects (it returns the 3xx response).
- `CalendarSource`: `#[async_trait] pub trait CalendarSource: Send + Sync` with `fn id(&self) -> String`, `fn display_name(&self) -> String`, `fn capabilities(&self) -> SourceCapabilities`, `async fn calendars(&self) -> Outcome<Vec<CalendarDescriptor>>`, `async fn events_in(&self, interval: DateInterval) -> Outcome<Vec<CalendarEvent>>`, `fn changes(&self) -> tokio::sync::mpsc::UnboundedReceiver<CalendarChange>`, `async fn notices(&self) -> Vec<SourceNotice>` (provided, returns empty). `PollingCalendarSource` and `SeriesSource` are separate traits; a source exposes them through `fn as_polling(&self) -> Option<&dyn PollingCalendarSource>` and `fn as_series(&self) -> Option<&dyn SeriesSource>` provided methods on `CalendarSource` returning `None` (Rust has no `as?` cast for trait objects). Task 5 adds `as_writable` the same way.
- `SourceError` goes into `Failure::Source`.
- `WindowsTimeZones`: port the table as a `static` sorted slice; both directions must match the vector for every row.
- `ConferenceDetector`: the one regular-expression-like scan in the Swift code is ported as a hand-written scanner; no `regex` crate.
- `DiagnosticLog`: `pub trait DiagnosticLog: Send + Sync { fn log(&self, event: DiagnosticEvent); }`; `NullDiagnosticLog`, `RingBufferDiagnosticLog`, `FanOutDiagnosticLog` ported with their capacities and redaction exactly.

- [ ] Follow P1 to P8.

### Task 3: `calendar-core` — recurrence

| Swift source | Rust module |
|---|---|
| `CalendarCore/Recurrence/RecurrenceRule.swift` | `recurrence/rule.rs` |
| `CalendarCore/Recurrence/RuleExpander.swift` | `recurrence/expander.rs` (includes `WallClock`) |
| `CalendarCore/Recurrence/RecurrenceSet.swift` | `recurrence/set.rs` |
| `CalendarCore/Recurrence/RecurrenceSet+Occurrences.swift` | `recurrence/occurrences.rs` |

**Swift tests:** `RecurrenceRuleTests`, `RuleExpanderTests`, `RecurrenceSetTests`, `RecurrenceSetOccurrencesTests`.

**Vectors replayed:** `zones/wall-clock.json`, `recurrence/rule-parse.json`, `recurrence/rule-instances.json`, `recurrence/set-occurrences.json`.

**Decisions:**
- The expander does its own day arithmetic on `CalendarDate` (`daysBetween`, `daysInMonth`, `weekStart`, `weekNumber`). Port those functions literally, including integer division and remainder: Swift `%` and Rust `%` both truncate toward zero, and Swift `/` on `Int` truncates like Rust's. Do not replace them with `jiff` date arithmetic.
- Only `WallClock::date` touches a zone; it calls `civil::date_from`.
- Keep the iteration limits and the `truncated` flag exactly; a rule that never terminates in Swift's loop bound must terminate at the same bound in Rust.

- [ ] Follow P1 to P8. Gate for this task: all 2,000 `rule-instances` cases and all 600 `wall-clock` cases pass.

### Task 4: `calendar-core` — connections, stores, helpers

| Swift source | Rust module |
|---|---|
| `CalendarCore/Connection.swift` | `connection.rs` |
| `CalendarCore/ExternalTokens.swift` | `external_tokens.rs` |
| `CalendarCore/FileConnectionStore.swift` | `file_connection_store.rs` |
| `CalendarCore/FileSyncStateStore.swift` | `file_sync_state_store.rs` |
| `CalendarCore/ChangeMonitor.swift` | `change_monitor.rs` |
| `CalendarCore/SharedConnectorHelpers.swift` | `shared_connector_helpers.rs` |

**Swift tests:** `ConnectionTests`, `ExternalTokenTests`, `FileStoresTests`, `ChangeMonitorTests`, `SharedConnectorHelpersTests`, `PersistedFormatTests` (CalendarCore).

**Decisions:**
- Traits: `CredentialStore`, `SyncStateStore`, `OAuthRedirectSession`, `AuthorizationInteraction`, `ConnectorKind`, `ExternalTokenSource`, each `#[async_trait] ... : Send + Sync` with the Swift method names in snake case and `Outcome<T>` for `throws`. `ConnectorKind::make_source` returns `Outcome<Arc<dyn CalendarSource>>`.
- `InMemoryCredentialStore`, `InMemorySyncStateStore`: `std::sync::Mutex` inside; same revision rule (`update_refresh_token` returns `false` on a revision mismatch).
- `ConnectorRegistry`: `BTreeMap<String, Arc<dyn ConnectorKind>>`; `kinds_for(platform)` sorted by id.
- `Platform` is an option set in Swift: port as a `u8` bit-flag newtype with the same constants and `is_disjoint`.
- Persisted formats are family A (conventions section 6). `PersistedFormatTests` reads `Tests/PersistedFormats/<version>/*.json` from the repository root: locate it with `concat!(env!("CARGO_MANIFEST_DIR"), "/../../Tests/PersistedFormats")`. When phase 3 removes the Swift tree, these files move to `fixtures/persisted-formats/` in one commit and the path changes with them.
- `FileConnectionStore` writes pretty-printed JSON with sorted keys through `write_atomic`. `FileSyncStateStore` ignores write failures, as Swift's `try?` does.
- Add a round-trip test for each store: load every fixture, save to a temp file, reload, compare values.

- [ ] Follow P1 to P8.

### Task 5: `calendar-core` — write model

| Swift source | Rust module |
|---|---|
| `CalendarCore/Write/WriteTypes.swift` | `write/types.rs` |
| `CalendarCore/Write/EventDraft.swift` | `write/event_draft.rs` |
| `CalendarCore/Write/EventPatch.swift` | `write/event_patch.rs` |
| `CalendarCore/Write/PatchMerge.swift` | `write/patch_merge.rs` |
| `CalendarCore/Write/WritableCalendarSource.swift` | `write/writable_source.rs` |

**Swift tests:** `WriteTypesTests`, `EventDraftTests`, `EventPatchTests`, `PatchMergeTests`, `WritableSourceTests`, `AllDayConformanceTests`.

**Decisions:**
- `FieldUpdate<T>` (Swift generic enum: keep, set, clear or the cases the file defines) stays generic in Rust.
- `WriteError` goes into `Failure::Write`.
- `WritableCalendarSource` is a trait extending `CalendarSource`; `CalendarSource` gains provided `fn as_writable(&self) -> Option<&dyn WritableCalendarSource>`.
- `WritableSourceTests` and `AllDayConformanceTests` use `CalendarTestSupport`. Port the parts of Task 6 they need first, in the same pull request, if that is simpler than stubbing.

- [ ] Follow P1 to P8. After this task: `python3 scripts/ci/check-test-parity.py --require-complete CalendarCoreTests` passes.

### Task 6: `calendar-test-support`

| Swift source | Rust module |
|---|---|
| `CalendarTestSupport/FakeTransport.swift` | `fake_transport.rs` |
| `CalendarTestSupport/FakeWritableSource.swift` | `fake_writable_source.rs` |
| `CalendarTestSupport/FakeExternalTokenSource.swift` | `fake_external_token_source.rs` |
| `CalendarTestSupport/CollectingDiagnosticLog.swift` | `collecting_diagnostic_log.rs` |
| `CalendarTestSupport/AllDayConformance.swift` | `all_day_conformance.rs` |
| `CalendarTestSupport/ProvidedFieldsConformance.swift` | `provided_fields_conformance.rs` |
| `CalendarTestSupport/WritableSourceConformance.swift` | `writable_source_conformance.rs` |

**Decisions:** This crate is a normal library (other repositories' tests use it), so it must not use `#[cfg(test)]` for its public items and it follows the same lints, with `#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]` at the crate root because its assertions are meant to fail tests. Swift conformance helpers that call `#expect` become functions that `assert!`.

- [ ] Follow P1 to P8 (the Swift tests of this target are the ones that use it; no rows of its own).

### Task 7: `calendar-oauth`

| Swift source | Rust module |
|---|---|
| `CalendarOAuth/PKCE.swift` | `pkce.rs` |
| `CalendarOAuth/OAuth.swift` | `oauth.rs` |
| `CalendarOAuth/OAuthConnections.swift` | `oauth_connections.rs` |
| `CalendarOAuth/AccessTokenSupplying.swift` | `access_token_supplying.rs` |
| `CalendarOAuth/AccessTokenProvider.swift` | `access_token_provider.rs` |
| `CalendarOAuth/ExternalAccessTokenProvider.swift` | `external_access_token_provider.rs` |
| `CalendarOAuth/SHA256Hashing.swift` | not ported |

**Swift tests:** `PKCETests`, `OAuthTests`, `OAuthConnectionsTests`, `AccessTokenProviderTests`, `ExternalAccessTokenProviderTests`, `SHA256Tests`.

**Vectors replayed:** `oauth/pkce.json`.

**Decisions:**
- `pkce::challenge(verifier: &str) -> String` uses `sha2::Sha256` and URL-safe base64 without padding, as the Swift code produces (read `PKCE.swift` for the exact alphabet handling). The verifier generator uses `getrandom`.
- `SHA256Tests` rows: `n/a: the SHA256Hashing seam is removed; sha2 is used and pinned by vectors/oauth/pkce.json`.
- `AccessTokenProvider` is an actor in Swift that coalesces concurrent refreshes into one request. Port that with a stored shared future or a `tokio::sync::Notify`; the tests that assert "one refresh for N callers" are the pin. Refresh-token rotation goes through `CredentialStore::update_refresh_token` with the expected revision, exactly as in Swift.
- The token endpoint's error body is never copied into `Failure` text or diagnostics beyond what Swift copies.
- Review Focus 2 applies to the token-response decoder: add the garbage-input test.

- [ ] Follow P1 to P8.

### Task 8: `calendar-ical`

| Swift source | Rust module |
|---|---|
| `ICalendar/ContentLine.swift` | `content_line.rs` |
| `ICalendar/Component.swift` | `component.rs` |
| `ICalendar/ICalText.swift` | `ical_text.rs` |
| `ICalendar/ICalValues.swift` | `ical_values.rs` |
| `ICalendar/TimeZoneResolver.swift` | `time_zone_resolver.rs` |
| `ICalendar/VTimeZoneWriter.swift` | `vtimezone_writer.rs` |
| `ICalendar/AlarmMapper.swift` | `alarm_mapper.rs` |
| `ICalendar/AttendeeMapper.swift` | `attendee_mapper.rs` |
| `ICalendar/EventResource.swift` | `event_resource.rs` |
| `ICalendar/EventReader.swift` | `event_reader.rs` |
| `ICalendar/EventWriter.swift` | `event_writer.rs` |
| `ICalendar/SeriesEditor.swift` | `series_editor.rs` |

**Swift tests:** `ICalendarTests/`: `ContentLineTests`, `ValuesTests`, `TimeZoneTests`, `AlarmMapperTests`, `EventReaderTests`, `EventWriterTests`, `SeriesEditorTests`, `Fixtures`.

**Vectors replayed:** `ical/content-lines.json`, `ical/timezones.json`.

**Decisions:**
- `ICalParser::parse(data: &[u8])` and `parse_text(&str)`: invalid UTF-8 follows the Swift fallback (read `ContentLine.swift` lines 9 to 25; if Swift tries Latin-1 after UTF-8, do the same).
- Line folding is at 75 **octets** in RFC 5545 but the Swift serializer decides; port its counting unit exactly (the vector pins it with non-ASCII lines).
- `VTimeZoneWriter` output is compared as text in `EventWriterTests`; match it byte for byte.
- `TimeZoneResolver` maps Windows display names through `WindowsTimeZones`; unresolvable `TZID`s follow the Swift fallback order.
- Add the garbage-input test (Review Focus 2) for `ICalParser::parse` and `EventReader`.

- [ ] Follow P1 to P8.

### Task 9: `calendar-ical-subscription`

| Swift source | Rust module |
|---|---|
| `ICalSubscription/FeedLocation.swift` | `feed_location.rs` |
| `ICalSubscription/FeedFetcher.swift` | `feed_fetcher.rs` |
| `ICalSubscription/FeedParser.swift` | `feed_parser.rs` |
| `ICalSubscription/RetentionWindow.swift` | `retention_window.rs` |
| `ICalSubscription/ICalSubscriptionSource.swift` | `source.rs` |
| `ICalSubscription/ICalSubscriptionKind.swift` | `kind.rs` |

**Swift tests:** `ICalSubscriptionTests/`: all 13 files (`LiveTests` becomes `#[ignore]`).

**Decisions:**
- The feed link is a credential (ADR 0018). `LeakTests` and `DiagnosticsTests` are ported first and must pass before the pull request is opened.
- `FeedFetcher` follows redirects itself, hop by hop, with the Swift limits (count, scheme downgrade refusal, size cap). The transport must not follow redirects; state that in the constructor's doc comment. There is no default transport: `ICalSubscriptionKind::new(transport: Arc<dyn HttpTransport>, ...)`. `makeDefaultTransport` and `feedSessionConfiguration` are not ported; their test rows are `n/a: host transport configuration`, and the settings they pinned (timeouts, no cookies, no cache) are listed in the doc comment as the host's obligation and copied into `docs/host-http-contract.md` (create it in this task; Tasks 10 to 12 add to it).
- `webcal://` to `https://` rewriting and the size cap are pinned by `FeedLocationTests` and `FeedFetcherTests`.

- [ ] Follow P1 to P8, plus the garbage-input test on `FeedParser`.

### Task 10: `calendar-caldav`

| Swift source | Rust module |
|---|---|
| `CalDAVCalendar/XMLTree.swift` | `xml_tree.rs` |
| `CalDAVCalendar/DAVXML.swift` | `dav_xml.rs` |
| `CalDAVCalendar/WebDAVClient.swift` | `webdav_client.rs` |
| `CalDAVCalendar/CalDAVDiscovery.swift` | `discovery.rs` |
| `CalDAVCalendar/CalDAVAccountConfig.swift` | `account_config.rs` |
| `CalDAVCalendar/CalDAVCalendarSource.swift` | `source.rs` |
| `CalDAVCalendar/CalDAVCalendarSource+Sync.swift` | `source_sync.rs` |
| `CalDAVCalendar/CalDAVCalendarSource+Series.swift` | `source_series.rs` |
| `CalDAVCalendar/CalDAVCalendarSource+Split.swift` | `source_split.rs` |
| `CalDAVCalendar/CalDAVCalendarSource+Write.swift` | `source_write.rs` |
| `CalDAVCalendar/CalDAVConnectorKinds.swift` | `connector_kinds.rs` |

**Swift tests:** `CalDAVCalendarTests/`: all 12 files (`ICloudLiveSmokeTests` becomes `#[ignore]`; `FakeCalDAVServer` and `Harness` go to `src/tests/support.rs`).

**Decisions:**
- `XMLTree` is built with `quick-xml` in namespace-aware mode. It must give the same tree as Foundation's `XMLParser` with namespace processing on: element local name, namespace URI, attributes, text with entity references resolved and CDATA included, whitespace-only text handled as Swift's builder does. Add a test with a default namespace, a prefixed namespace, a redeclared prefix, CDATA and `&amp;`.
- Swift `extension CalDAVCalendarSource` files become `impl` blocks in separate modules of the same crate.
- The password never appears in an error or diagnostic (`WebDAVClientTests` pin it). HTTP Basic uses `base64` standard alphabet with padding.
- No default transport; add the "must not follow redirects" obligation to `docs/host-http-contract.md`.
- Add the garbage-input test on `XMLTree` and on the multistatus reader in `DAVXML`.

- [ ] Follow P1 to P8.

### Task 11: `calendar-google`

| Swift source | Rust module |
|---|---|
| `GoogleCalendar/GoogleDTOs.swift` | `dtos.rs` |
| `GoogleCalendar/GoogleAPIClient.swift` | `api_client.rs` |
| `GoogleCalendar/GoogleEventMapper.swift` | `event_mapper.rs` |
| `GoogleCalendar/GoogleWriteMapper.swift` | `write_mapper.rs` |
| `GoogleCalendar/GoogleCalendarSource.swift` | `source.rs` |
| `GoogleCalendar/GoogleCalendarSource+Series.swift` | `source_series.rs` |
| `GoogleCalendar/GoogleCalendarSource+Write.swift` | `source_write.rs` |
| `GoogleCalendar/GoogleConnectorKind.swift` | `connector_kind.rs` |

**Swift tests:** `GoogleCalendarTests/`: all 10 files, 201 tests.

**Decisions:**
- DTOs are family C. Every Swift optional is `Option` with `#[serde(default)]`; unknown enum strings map as the Swift mapper maps them.
- Query strings: port the exact percent-encoding set of `GoogleAPIClient` (conventions section 7). A test compares full request URLs as strings with the Swift tests' expected URLs.
- Google RFC 3339 timestamps: parse with a hand-written parser equal to the Swift one (which `ISO8601DateFormatter` options does the Swift code set? fractional seconds or not; read it and match, with a test for both forms).
- Rate limiting, 410 sync-token reset and 401 handling follow `SourceTests` and `ChangeDetectionTests`.
- Split this task into two pull requests if it helps review: read path (DTOs, client, mapper, source, kind) then write path (write mapper, write source, series, split).
- Add the "tolerates unknown and missing fields" test (Review Focus 1) for events, calendars and the token response.

- [ ] Follow P1 to P8.

### Task 12: `calendar-microsoft`

| Swift source | Rust module |
|---|---|
| `MicrosoftCalendar/GraphDTOs.swift` | `dtos.rs` |
| `MicrosoftCalendar/GraphTime.swift` | `graph_time.rs` |
| `MicrosoftCalendar/GraphAPIClient.swift` | `api_client.rs` |
| `MicrosoftCalendar/GraphEventMapper.swift` | `event_mapper.rs` |
| `MicrosoftCalendar/GraphRecurrenceMapper.swift` | `recurrence_mapper.rs` |
| `MicrosoftCalendar/GraphWriteMapper.swift` | `write_mapper.rs` |
| `MicrosoftCalendar/MicrosoftCalendarSource.swift` | `source.rs` |
| `MicrosoftCalendar/MicrosoftCalendarSource+Sync.swift` | `source_sync.rs` |
| `MicrosoftCalendar/MicrosoftCalendarSource+Series.swift` | `source_series.rs` |
| `MicrosoftCalendar/MicrosoftCalendarSource+Split.swift` | `source_split.rs` |
| `MicrosoftCalendar/MicrosoftCalendarSource+Write.swift` | `source_write.rs` |
| `MicrosoftCalendar/MicrosoftConnectorKind.swift` | `connector_kind.rs` |
| `MicrosoftCalendar/MicrosoftBrokeredConnectorKind.swift` | `brokered_connector_kind.rs` |

**Swift tests:** `MicrosoftCalendarTests/`: all 14 files, 146 tests.

**Vectors replayed:** `microsoft/graph-time.json`.

**Decisions:**
- Scopes: copy the scope strings verbatim. Port `scripts/ci/check-repository-contracts.py`'s scope check so it also reads the Rust file (add the Rust path to the script and its test); it must fail if the Rust scopes differ from the pinned list.
- The brokered kind stores no credential and uses `ExternalTokenSource`; the "same mailbox through both kinds is one account" rule lives in the engine, not here.
- Delta links and stored delta positions are opaque strings in `sync-state.json`; `PersistedFormatTests` pins that the stored ones still parse.
- Add the "tolerates unknown and missing fields" test for events, calendars, `/me` and the mailbox time-zone response.

- [ ] Follow P1 to P8.

### Task 13: Phase close-out

**Files:**
- Modify: `docs/api.md` (add a "Rust API (2.x)" part: the eight crates, their public modules and the host obligations of `docs/host-http-contract.md`), `AGENTS.md` (the Rust section becomes the main description on `v2`), `README.md` on `v2`.
- Modify (in `timetug`): the tracker.

- [ ] **Step 1: Completeness.** `python3 scripts/ci/check-test-parity.py --require-complete CalendarCoreTests --require-complete CalendarOAuthTests --require-complete ICalendarTests --require-complete ICalSubscriptionTests --require-complete CalDAVCalendarTests --require-complete GoogleCalendarTests --require-complete MicrosoftCalendarTests`. Expected: PASS. Add this exact command to the `rust-lint` job.
- [ ] **Step 2: Count.** `cargo test --workspace 2>&1 | grep -E '^test result'`: the sum of passed tests is at least the number of `ported` rows. Record both numbers in the tracker.
- [ ] **Step 3: `n/a` review.** List every `n/a` row with its reason in the pull request description; the reviewer (`deepseek-review`, then the owner) confirms each is a removed seam or host code, not skipped behaviour. Expected categories only: `URLSessionTransport`, default transport configuration, `SHA256Hashing`.
- [ ] **Step 4: Parity ledger.** Read `docs/rust-port/parity-ledger.md`. Port every unchecked entry now (each as its own small pull request following P1 to P8), or record in the tracker why it waits for phase 3.
- [ ] **Step 5: Size check.** `cargo build --release -p calendar-google -p calendar-microsoft -p calendar-caldav -p calendar-ical-subscription` and record the `.rlib` sizes in the tracker as an early warning only.
- [ ] **Step 6: Update the tracker**: phase 1 `done`, links, Now moves to phase 2, session log. Pull request in `timetug`.
