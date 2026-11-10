# Rust phase 0: foundations — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Everything the port needs before the first line of ported code: recorded baselines, `v2` branches with Rust CI on four platforms, empty Cargo workspaces, the parity table, and golden vectors exported from the Swift code.

**Architecture:** No product code. Each library gets a Cargo workspace beside its untouched Swift package on a `v2` branch; CI gains Rust jobs; a Swift executable exports reference answers that later Rust tests replay.

**Tech Stack:** Rust (stable, pinned), cargo-deny, GitHub Actions, Swift 6 (the exporters), Python 3 (CI scripts, as the repositories already use), .NET 8 (the bench harness).

**Spec:** [`docs/superpowers/specs/2026-11-10-rust-engine-program-design.md`](../specs/2026-11-10-rust-engine-program-design.md), sections 6.1 to 6.4, 7 and 8. **Conventions:** [`2026-11-10-rust-port-conventions.md`](2026-11-10-rust-port-conventions.md).

## Global Constraints

- The Swift packages (`Package.swift`, `Sources/`, `Tests/`) are not edited in this phase, except to add the `VectorExporter` executable target (Tasks 8 and 9).
- Nothing in this phase may change what `main` of either library releases.
- Crate names, kinds and dependencies are exactly those of design section 6.1. The C interface library is named `TimeTugEngineC`.
- External crates are exactly those of conventions section 3.
- Release profile and lints are exactly those of conventions section 2.
- Agents never push to `v2` or `main`, never tag, never merge.
- Python scripts follow the repositories' pattern: standard library only, a `unittest` file under `scripts/ci/tests/`.

## Review Focus

1. **A 2.x release reaching the Mac app.** A `library-released` dispatch for `2.0.0` must open no pull request in `timetug`. Pinned by Task 2's shell test.
2. **A vector exporter that is not deterministic.** Two runs must produce byte-identical files. Pinned by Task 8, step 6 and the CI job in Task 8, step 7.
3. **A `tokio` feature creeping in through a dependency.** Pinned by `check-tokio-features.py` and its test (Task 4).
4. **A crate depending on a crate it must not.** Pinned by `check-crate-architecture.py` and its test (Task 4).
5. **A Swift test missing from the baseline inventory** (nested suites, `@Test` with a display name, tests in extensions). Pinned by the inventory script's unit test with those three shapes (Task 6).

---

### Task 1: Record the baseline

**Files:**
- Modify (in `timetug`): `docs/superpowers/plans/2026-11-10-rust-engine-program-tracker.md` (the Baseline table)

- [ ] **Step 1: Read the latest release tag of each library**

Run: `gh release view --repo binary-companion/calendar-connectors --json tagName -q .tagName` and the same for `binary-companion/timetug-shared`.
Expected: two `X.Y.Z` tags (1.2.x and 1.8.x or later).

- [ ] **Step 2: Measure the published package**

Download `https://api.nuget.org/v3-flatcontainer/timetug.engine/<version>/timetug.engine.<version>.nupkg` into a scratch directory; `unzip -lv`; sum uncompressed and compressed bytes of `runtimes/win-x64/native/*` and `runtimes/win-arm64/native/*`.
Expected for 1.8.0: about 70.5 MB uncompressed for x64.

- [ ] **Step 3: Fill the Baseline table** in the tracker with the two tags, the package version and the four sizes. Leave the test counts and the bench numbers for Tasks 6 and 7.

- [ ] **Step 4: Commit** (`docs: record the Rust program baseline`) on a branch in `timetug`; open a pull request.

### Task 2: `timetug` ignores 2.x library releases

**Files (in `timetug`):**
- Create: `scripts/ci/bump-major-guard.sh`
- Create: `scripts/ci/tests/test-bump-major-guard.sh`
- Modify: `.github/workflows/bump-dependencies.yml` (the step that validates `LIBRARY` and `VERSION`)
- Modify: `AGENTS.md` (Repositories section), `.claude/skills/working-across-timetug-repos/SKILL.md`

**Interfaces:**
- Produces: `scripts/ci/bump-major-guard.sh <library> <X.Y.Z>` prints `proceed` or `skip` and exits 0; exits 2 with a message on stderr for a bad argument. It reads the library's current `exactVersion` from `Apps/macOS/project.yml` (keys `CalendarConnectors`, `TimeTugShared`) and prints `skip` when the new major is greater than the pinned major.

- [ ] **Step 1: Write the failing test** `scripts/ci/tests/test-bump-major-guard.sh`. It builds a temporary directory with a minimal `Apps/macOS/project.yml` pinning `TimeTugShared` at `1.8.0` and `CalendarConnectors` at `1.2.0`, runs the guard from there, and asserts:

```
timetug-shared 1.8.1      -> proceed
timetug-shared 1.9.0      -> proceed
timetug-shared 2.0.0      -> skip
calendar-connectors 2.0.0 -> skip
calendar-connectors 1.3.0 -> proceed
timetug-shared 2.0.0-alpha.1 -> exit 2
other-lib 1.0.0           -> exit 2
```

- [ ] **Step 2: Run it.** `bash scripts/ci/tests/test-bump-major-guard.sh`. Expected: FAIL, the script does not exist.
- [ ] **Step 3: Write `bump-major-guard.sh`.** Reuse the version parsing already in `scripts/ci/bump-pin.sh` (same `X.Y.Z` regular expression, same key mapping).
- [ ] **Step 4: Run the test.** Expected: PASS.
- [ ] **Step 5: Call the guard in the workflow** immediately after the validation step. On `skip`: `echo "::notice::<library> <version> is a new major version; the Mac app adopts it in phase 6 of the Rust program"` and end the job successfully without opening a pull request (set a step output and gate the remaining steps on it).
- [ ] **Step 6: Add the test to wherever the repository runs its shell tests** (find the list with `grep -rn "test-bump" scripts .github`), and run `scripts/dev/verify.sh release-tools`. Expected: PASS.
- [ ] **Step 7: Document** in `AGENTS.md` and the skill: one sentence each, "2.x releases of the libraries are skipped until phase 6 of the Rust program (see the tracker)".
- [ ] **Step 8: Commit and open a pull request.** The owner merges before any 2.0.0 is released; add this to the tracker's open owner items.

### Task 3: `v2` branches and CI triggers

**Files (in each library, on a branch cut from the baseline tag):**
- Modify: `.github/workflows/ci.yml` (`on.push.branches`)
- Modify: `.github/pull_request_template.md`
- Create: `docs/rust-port/parity-ledger.md`, `docs/rust-port/README.md`

- [ ] **Step 1: (owner) Create the branches.** Add to the tracker's open owner items, with the exact commands:

```bash
git -C ~/Source/binary-companion/calendar-connectors push origin refs/tags/<connectors baseline>^{commit}:refs/heads/v2
```
```bash
git -C ~/Source/binary-companion/timetug-shared push origin refs/tags/<shared baseline>^{commit}:refs/heads/v2
```

Stop until both exist (`git ls-remote --heads origin v2`).

- [ ] **Step 2: In each library, branch from `v2`** and change `on.push.branches` in `ci.yml` from `[main]` to `[main, v2]`. Do not touch `release.yml`: it must keep reacting to `main` only.
- [ ] **Step 3: Create `docs/rust-port/README.md`**: five lines saying what the directory holds and linking the tracker and conventions in `timetug`.
- [ ] **Step 4: Create `docs/rust-port/parity-ledger.md`**:

```markdown
# Parity ledger

Every behaviour change merged to `main` (Swift) after the baseline tag <tag> is listed here until the Rust port has it.

| Date | main pull request | What changed | Tests, fixtures or scenarios that pin it | Ported in |
|---|---|---|---|---|
```

- [ ] **Step 5: Add a checkbox to the pull request template on `v2`** and, in a separate pull request, on `main`: "- [ ] If this changes behaviour of the Swift library, I added a line to `docs/rust-port/parity-ledger.md` on `v2`."
- [ ] **Step 6: Verify.** Push the branch, open the pull request against `v2`; the existing Swift CI jobs must run and pass unchanged.

### Task 4: Cargo workspace in `calendar-connectors`

**Files (on a branch from `v2`):**
- Create: `Cargo.toml`, `rust-toolchain.toml`, `deny.toml`, `.cargo/config.toml`
- Create: `crates/<name>/Cargo.toml` and `crates/<name>/src/lib.rs` for `calendar-core`, `calendar-oauth`, `calendar-ical`, `calendar-google`, `calendar-microsoft`, `calendar-caldav`, `calendar-ical-subscription`, `calendar-test-support`
- Create: `scripts/ci/check-crate-architecture.py`, `scripts/ci/check-tokio-features.py`, `scripts/ci/tests/test_check_crate_architecture.py`, `scripts/ci/tests/test_check_tokio_features.py`
- Modify: `.github/workflows/ci.yml`, `.gitignore` (add `/target`), `.qindexignore` (add `target/`), `AGENTS.md`

**Interfaces:**
- Produces: `check-crate-architecture.py [--metadata FILE]` reads `cargo metadata --format-version 1` (or the file) and exits 1 listing every workspace-internal dependency edge not in its `ALLOWED` table and every external crate not in `EXTERNAL`. `ALLOWED` for this repository is the "Depends on" column of the design's section 6.1 table; `calendar-test-support` may be a dev-dependency of every crate.
- Produces: `check-tokio-features.py` runs `cargo tree -e features,normal,build --prefix none -i tokio` and exits 1 if any `tokio` feature outside `rt, time, sync, macros, default-less internals` appears. The allowed set is a constant at the top of the file; internal feature names `tokio` enables for those four (read them from the pinned version's `Cargo.toml` and list them explicitly) are part of it.

- [ ] **Step 1: Pin the toolchain.** `rust-toolchain.toml` with the exact current stable version number (read it from `rustup check` or the Rust release page; never write `stable`), `components = ["rustfmt", "clippy"]`, and the targets of design section 6.4.
- [ ] **Step 2: Write the workspace `Cargo.toml`** per conventions section 2. `[workspace.dependencies]` lists every crate of conventions section 3 that this repository uses (`uniffi` excluded) at the newest released version, exact (`=x.y.z`), default features off where it builds.
- [ ] **Step 3: Create the eight crates**, each with an empty `src/lib.rs` holding only a crate doc comment naming the Swift product it replaces, and a `Cargo.toml` with `[lints] workspace = true` and the internal dependencies of the design table.
- [ ] **Step 4: Write `deny.toml`**: licences allow-list `MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, Unicode-3.0, Unicode-DFS-2016, Zlib`; `[bans]` with `multiple-versions = "deny"` and an explicit allow-list of the external crates and their transitive dependencies as `cargo tree` reports them at this commit; `[advisories]` deny.
- [ ] **Step 5: Write the two check scripts test-first.** Tests feed a hand-written `cargo metadata` JSON (architecture) and a hand-written `cargo tree` text (features): one clean input passes; an input where `calendar-core` depends on `calendar-ical` fails naming that edge; an input with crate `reqwest` fails; a `tokio` line with feature `net` fails.
- [ ] **Step 6: Add CI jobs** to `ci.yml`, each `if: hashFiles('Cargo.toml') != ''`:

| Job | Runner | Commands |
|---|---|---|
| `rust-macos` | `macos-26` | `cargo test --workspace --locked`, `cargo build --workspace --release --locked` |
| `rust-linux` | `ubuntu-latest` | same |
| `rust-windows-x64` | `windows-latest` | same |
| `rust-windows-arm64` | `windows-11-arm` | same |
| `rust-lint` | `ubuntu-latest` | `cargo fmt --all --check`, `cargo clippy --workspace --all-targets --locked -- -D warnings`, `cargo deny check`, `python3 scripts/ci/check-crate-architecture.py`, `python3 scripts/ci/check-tokio-features.py`, the Python unit tests |
| `rust-targets` | `macos-26` | `cargo build --workspace --release --locked --target <t>` for `x86_64-apple-darwin`, `aarch64-apple-ios`, `aarch64-apple-ios-sim` |

Install the toolchain with `rustup show` (it reads `rust-toolchain.toml`); install `cargo-deny` at a pinned version with `cargo install --locked cargo-deny --version <exact>` cached by version. Use only actions already on the organization's allowed list (check the existing workflow files; do not add a new third-party action).

- [ ] **Step 7: Run locally.** `cargo test --workspace && cargo clippy --workspace --all-targets -- -D warnings && cargo fmt --all --check && python3 -m unittest discover -s scripts/ci/tests -p 'test_*.py'`. Expected: all pass; zero tests run in the crates.
- [ ] **Step 8: Add an "On `v2`: Rust" section to `AGENTS.md`** (workspace layout, the commands of Step 7, a link to the conventions).
- [ ] **Step 9: Commit and open the pull request against `v2`.** Gate: all Swift jobs and all six Rust jobs green.

### Task 5: Cargo workspace in `timetug-shared`

Same as Task 4, with these differences.

**Files:** crates `timetug-core`, `timetug-bridge`, `timetug-engine`, `timetug-engine-protocol`, `timetug-engine-c`, `timetug-engine-ffi`, `dedup-benchmark`.

- [ ] **Step 1: Toolchain, workspace, lints, `deny.toml`** as in Task 4. `rust-toolchain.toml` must name the same version as `calendar-connectors`.
- [ ] **Step 2: Depend on the connector crates by git revision**: in `[workspace.dependencies]`, `calendar-core = { git = "https://github.com/binary-companion/calendar-connectors", rev = "<the v2 commit that merged Task 4>" }`, and likewise for the other connector crates the engine needs. Phase 3 switches `rev` to a prerelease tag; phase 4 to `tag = "2.0.0"`.
- [ ] **Step 3: Create the seven crates.** `timetug-engine-c`: `[lib] name = "TimeTugEngineC"`, `crate-type = ["cdylib", "staticlib"]`, `[lints.rust] unsafe_code = "allow"`. `timetug-engine-ffi`: `crate-type = ["staticlib", "cdylib", "lib"]`, `unsafe_code = "allow"`, no `uniffi` dependency yet (phase 5 adds it). `dedup-benchmark`: a binary with an empty `main`.
- [ ] **Step 4: Internal dependency table for `check-crate-architecture.py`:** `timetug-core` -> `calendar-core`; `timetug-bridge` -> `timetug-core`, `calendar-core`; `timetug-engine` -> `timetug-core`, `timetug-bridge`, `calendar-core`; `timetug-engine-protocol` -> `timetug-engine`, `timetug-core`, `timetug-bridge`, `calendar-core`; `timetug-engine-c` -> `timetug-engine-protocol`, `timetug-engine`, `timetug-core`, and all connector crates; `timetug-engine-ffi` -> the same set as `timetug-engine-c`; `dedup-benchmark` -> `timetug-core`, `calendar-core`.
- [ ] **Step 5: Add a local-override helper** `scripts/dev/use-local-connectors.sh <path>`: writes a git-ignored `.cargo/config.toml` `[patch."https://github.com/binary-companion/calendar-connectors"]` block pointing each connector crate at `<path>/crates/<name>`; `--restore` deletes it. `rust-lint` fails if a tracked `.cargo/config.toml` contains `[patch`.
- [ ] **Step 6: CI jobs** as in Task 4, plus in `rust-windows-x64` and `rust-windows-arm64`: assert the build produced `target/release/TimeTugEngineC.dll`; in `rust-macos`: `libTimeTugEngineC.dylib`; in `rust-linux`: `libTimeTugEngineC.so`.
- [ ] **Step 7: Verify and open the pull request against `v2`.**

### Task 6: Test inventory and parity table

**Files (in each library, branch from `v2`):**
- Create: `scripts/ci/swift-test-inventory.py`, `scripts/ci/check-test-parity.py`, `scripts/ci/tests/test_swift_test_inventory.py`, `scripts/ci/tests/test_check_test_parity.py`
- Create: `docs/rust-port/swift-tests-baseline.txt`, `docs/rust-port/test-parity.md`, `docs/rust-port/file-map.md`
- Modify: `.github/workflows/ci.yml` (`rust-lint` runs `check-test-parity.py`)

**Interfaces:**
- Produces: `swift-test-inventory.py <Tests dir>` prints one sorted line per test: `<Target>/<relative path>.swift::<funcName>`. A test is a `func` whose nearest preceding attribute lines include `@Test` (with or without arguments or a display name).
- Produces: `check-test-parity.py [--require-complete <Target>]...` implements conventions section 8 exactly. Reads `docs/rust-port/swift-tests-baseline.txt` and `docs/rust-port/test-parity.md`; resolves a Rust test as `<path>::<fn_name>` by checking the file exists and contains `fn <fn_name>(`.

- [ ] **Step 1: Write `test_swift_test_inventory.py`** with a fixture directory holding: a plain `@Test func a()`; `@Test("display name") func b() async throws`; `@Test(arguments: [1, 2]) func c(_ n: Int)`; a test inside `@Suite struct S { ... }`; a test inside an `extension S`; a non-test `func helper()`. Assert exactly five lines and their text.
- [ ] **Step 2: Run it; expect FAIL. Write the script. Run it; expect PASS.**
- [ ] **Step 3: Generate the baseline.** `python3 scripts/ci/swift-test-inventory.py Tests > docs/rust-port/swift-tests-baseline.txt`. Compare `wc -l` with `grep -rE '@Test' Tests | wc -l`: 915 for `calendar-connectors` 1.2.0 and 608 for `timetug-shared` 1.8.0 (or the baseline's own counts if the tag is later). Any difference means the script misses a shape: fix the script, not the file.
- [ ] **Step 4: Write `test_check_test_parity.py`**: a baseline line with no row fails; a `ported` row naming a missing file fails; a `ported` row naming a missing `fn` fails; `n/a` without a reason after the colon fails; `--require-complete T` fails on a `pending` row of `T` and passes when all rows of `T` are `ported` or `n/a: ...`.
- [ ] **Step 5: Write `check-test-parity.py`; tests pass.**
- [ ] **Step 6: Seed `test-parity.md`**: a small script-generated table with every baseline line, `-` as the Rust test and `pending` as the status. Commit the generator invocation in the file's first line as a comment.
- [ ] **Step 7: Create `file-map.md`** with the header `| Swift file | Rust module | Public renames |` and no rows; phases 1 to 3 fill it.
- [ ] **Step 8: Record the two test counts** in the tracker's Baseline table (a `timetug` pull request).
- [ ] **Step 9: Commit; pull request against `v2`.**

### Task 7: Resource baselines of the Swift engine

**Files (in `timetug-shared`, branch from `v2`):**
- Create: `dotnet/TimeTug.Engine.Bench/TimeTug.Engine.Bench.csproj`, `dotnet/TimeTug.Engine.Bench/Program.cs`
- Create: `scripts/benchmarks/run-engine-bench.ps1`, `scripts/benchmarks/run-engine-bench.sh`
- Create: `docs/rust-port/baselines.md`

**Interfaces:**
- Produces: `TimeTug.Engine.Bench --idle-seconds <n> --out <file>` writes JSON `{"engine": "<package version>", "rid": "...", "readyMs": n, "workingSetBytes": n, "privateBytes": n, "cpuMsIdle": n, "idleSeconds": n, "nativeModuleBytes": n}`. It references the `TimeTug.Engine` project in the same solution (so it runs against whichever native library the solution is built with), creates an engine with a fresh temporary data directory, `platform` of the host, `testing: false`, no connectors; sends `start`; `readyMs` is the time from `tt_engine_create` to the `ready` callback; then sleeps `idle-seconds`, sampling `Process.TotalProcessorTime` at the start and end of the sleep (`cpuMsIdle`) and memory at the end. `nativeModuleBytes` is the sum of the file sizes of loaded modules whose path is inside the application directory and whose extension is `.dll`, `.dylib` or `.so`, excluding managed assemblies.
- The host answers every `service.*` request with error kind `failed` (none is expected when no account exists).

- [ ] **Step 1: Write the harness and add it to `dotnet/TimeTug.Engine.sln`.** It is not packed and not part of the test projects.
- [ ] **Step 2: Run it on macOS** against the Swift library: `scripts/benchmarks/run-engine-bench.sh --idle-seconds 600`. Expected: a JSON file; `readyMs` under 2000.
- [ ] **Step 3: Run it on Windows ARM64** in the Parallels VM (`prlctl exec "Windows 11" --current-user`, as the `timetug-windows` VM scripts do) and on a Windows x64 CI runner through a manually dispatched workflow `bench.yml` (`workflow_dispatch` only, uploads the JSON as an artifact). Three runs each; record the median.
- [ ] **Step 4: Run the dedup benchmark**: `scripts/benchmarks/run-dedup.sh` on macOS; record its output lines.
- [ ] **Step 5: Write `docs/rust-port/baselines.md`**: a table per platform (Windows x64, Windows ARM64, macOS arm64) with `readyMs`, `workingSetBytes`, `privateBytes`, `cpuMsIdle` per 600 s, `nativeModuleBytes`, the package sizes from Task 1, and the benchmark lines; the exact commands; the machine descriptions. State the acceptance rule: the Rust engine must be at or below each number, with 10% tolerance for run-to-run noise on time and CPU, none on size.
- [ ] **Step 6: Commit; pull request against `v2`.**

### Task 8: Vector exporter and vectors, `calendar-connectors`

**Files (branch from `v2`):**
- Modify: `Package.swift` (add `.executableTarget(name: "VectorExporter", dependencies: ["CalendarCore", "ICalendar", "MicrosoftCalendar", "CalendarOAuth"])`; the exporter uses `@testable import` for internal entry points, so build it with `-Xswiftc -enable-testing`)
- Create: `Sources/VectorExporter/main.swift`, one file per area under `Sources/VectorExporter/`, `Sources/VectorExporter/LCG.swift`, `Sources/VectorExporter/VectorFile.swift`
- Create: `scripts/dev/export-vectors.sh`, `vectors/<area>/*.json`, `vectors/README.md`
- Modify: `.github/workflows/ci.yml` (new job `vectors-current`), `scripts/ci/check-architecture.sh` (allow the new target the imports it needs), `scripts/ci/compat/compat.py` product list if it enumerates targets (the exporter is not a library product, so normally nothing)

**Interfaces:**
- Produces: `scripts/dev/export-vectors.sh` builds and runs the exporter, writing every file under `vectors/`. File format: conventions section 9. `LCG` is `struct LCG { var state: UInt64; mutating func next() -> UInt64 }` with `state = state &* 6364136223846793005 &+ 1442695040888963407`, returning `state >> 33`; every generated area seeds it with a constant written in that area's file.

Areas, entry points and minimum case counts:

| Area (directory/file) | Swift entry point | Input | Expected | Cases |
|---|---|---|---|---|
| `zones/offsets.json` | `TimeZone.secondsFromGMT(for:)` | zone id, instant | offset seconds | 60 zones (list below) x 40 instants, including the second before and after every transition of 2024 to 2027 found by `nextDaylightSavingTimeTransition` |
| `zones/wall-clock.json` | `WallClock.date(_:hour:minute:second:in:)` | zone, `CalendarDate`, h, m, s | instant or null | 600, at least 150 inside DST gaps and overlaps |
| `zones/all-day.json` | `AllDay.startOfDay`, `AllDay.date(of:in:)`, `AllDay.canonical`, `AllDay.dates`, `CalendarDate.adding(days:)` | per function | per function | 500 |
| `zones/known.json` | `TimeZone(identifier:)` | every id of `TimeZone.knownTimeZoneIdentifiers` plus 30 invalid and alias ids (`US/Pacific`, `GMT+5`, `UTC`, `Etc/GMT-14`, lower-case forms, empty) | accepted or not, canonical `identifier` | all |
| `zones/windows-names.json` | `WindowsTimeZones.timeZone(for:)`, `windowsName(for:)` | every name in the table, every IANA id in the reverse table, 20 unknown names | zone id or null | all |
| `recurrence/rule-instances.json` | `RecurrenceRule.instances(...)` | rule (as the RRULE text the library parses), anchor, zone, isAllDay, window, limit | starts, truncated | 2,000: every `FREQ`, `INTERVAL` 1 to 4, `BYDAY` with and without ordinals, `BYMONTHDAY` positive and negative, `BYMONTH`, `BYSETPOS`, `BYWEEKNO`, `BYYEARDAY`, `WKST`, `COUNT`, `UNTIL`, anchors on 29 February, the 31st, and inside DST gaps |
| `recurrence/set-occurrences.json` | `RecurrenceSet.occurrences(...)`, `ruleInstanceCount(...)` | set (rules, rdates, exdates), anchor, zone, isAllDay, window | `RecurrenceExpansion` fields; count | 300 |
| `recurrence/rule-parse.json` | the `RecurrenceRule` text parser and serializer | RRULE text | parsed fields or error; re-serialized text | 300 valid, 100 malformed |
| `ical/content-lines.json` | `ICalParser.unfold`, `ICalParser.parseLine`, `ICalSerializer.contentLine` | text | lines; property or error; text | 300, with folded lines, quoted parameters, escaped text, non-ASCII, CRLF and bare LF |
| `ical/timezones.json` | `TimeZoneResolver.zone(for:)`, `.date(_:floating:)`, `.displayZone` | a `VCALENDAR` text with `VTIMEZONE`s, a tzid, a date value | zone id or null; instant | 150, including Outlook-style display names and `VTIMEZONE`s with no IANA match |
| `microsoft/graph-time.json` | `GraphTime.parse`, `.date`, `.format`, `.midnight`, `.dateText`, `.parseInstant`, `.instantText` | per function | per function | 300 |
| `core/conference.json` | `ConferenceDetector.provider(of:)`, `.conferences(...)`, `.detect(...)`, `JoinURLPolicy.isAllowed` | location, url, notes | urls, providers, origins; allowed | 400, taken from the strings in `ConferenceDetectorTests` plus generated variations (wrapped safe-links, trailing punctuation, upper-case hosts) |
| `core/url-accept.json` | `URL(string:)` and `absoluteString` | 300 strings (valid, missing scheme, spaces, non-ASCII hosts, percent-encoded, trailing dots) | accepted or not; `absoluteString`; `host`; `scheme` | 300 |
| `oauth/pkce.json` | the PKCE challenge function with the library's own SHA-256 | verifier | challenge | 50 |

The 60 zones: all zones named anywhere in the Swift tests of both libraries, plus `America/New_York`, `America/Chicago`, `America/Denver`, `America/Phoenix`, `America/Los_Angeles`, `America/Anchorage`, `Pacific/Honolulu`, `America/St_Johns`, `America/Sao_Paulo`, `America/Santiago`, `America/Havana`, `Europe/London`, `Europe/Dublin`, `Europe/Lisbon`, `Europe/Berlin`, `Europe/Paris`, `Europe/Athens`, `Europe/Moscow`, `Europe/Istanbul`, `Africa/Cairo`, `Africa/Casablanca`, `Africa/Johannesburg`, `Asia/Jerusalem`, `Asia/Tehran`, `Asia/Dubai`, `Asia/Kolkata`, `Asia/Kathmandu`, `Asia/Dhaka`, `Asia/Bangkok`, `Asia/Shanghai`, `Asia/Tokyo`, `Asia/Seoul`, `Australia/Perth`, `Australia/Adelaide`, `Australia/Sydney`, `Australia/Lord_Howe`, `Pacific/Auckland`, `Pacific/Chatham`, `Pacific/Apia`, `Pacific/Kiritimati`, `UTC`.

- [ ] **Step 1: Read each entry point's signature** in the Swift source and write each area's `input` and `expected` shapes at the top of its exporter file as a comment. That comment is the format the Rust replay test follows.
- [ ] **Step 2: Write `VectorFile.swift`** (the envelope, `JSONSerialization` with `.sortedKeys` and `.prettyPrinted`, instants as integer milliseconds) and `LCG.swift`.
- [ ] **Step 3: Write the area exporters**, hand-written cases first (copy the inputs of the existing Swift tests for that area), then generated cases.
- [ ] **Step 4: Write `export-vectors.sh`**: `swift build -c release --product VectorExporter -Xswiftc -enable-testing`, then run it with the output directory.
- [ ] **Step 5: Run it.** Expected: 14 files; each `cases` count at or above the table.
- [ ] **Step 6: Run it again and `git diff --exit-code vectors/`.** Expected: no difference.
- [ ] **Step 7: Add the CI job `vectors-current`** on `macos-26`: run the script, `git diff --exit-code vectors/`. Note in `vectors/README.md` that the job depends on the runner's zone database: if a later runner image changes a zone's rules, the job fails and the fix is to pin the cases to past dates, never to accept the new output silently.
- [ ] **Step 8: Commit; pull request against `v2`.**

### Task 9: Vector exporter and vectors, `timetug-shared`

As Task 8. The exporter target depends on `TimeTugCore`, `TimeTugEngine`, `TimeTugEngineProtocol`, `CalendarCore`.

| Area | Swift entry point | Input | Expected | Cases |
|---|---|---|---|---|
| `text/fold.json` | `DuplicateRules.normalize(_:)` | string | string | every scalar of Latin-1 Supplement, Latin Extended-A and B, Greek, Cyrillic, combining marks U+0300 to U+036F applied to `a e i o u n c`, full-width forms, 200 mixed strings (titles with punctuation, emoji, multiple spaces) |
| `text/case-compare.json` | `caseInsensitiveCompare == .orderedSame` as used in `AccountManager` | pair of strings | bool | 300 pairs including `ß`/`SS`, dotted and dotless i, Greek final sigma |
| `text/dedup-key.json` | the key built in `TimeTugCalendarEvent.swift` line 79 (`title.lowercased()|start|end`) | title, start, end | string | 100 |
| `dedup/pair-decisions.json` | `DuplicateRules.isCandidate`, `isManualCandidate`, `withinTimeGate`, `decide`, `detailScore`, `detailSummary` | two events (full JSON of the fields the rules read) | per function | 600 pairs generated from a pool that varies title, times (within and outside the gate), UID and scope, conference links, attendees, location, all-day |
| `dedup/resolutions.json` | `DuplicateResolver.resolve(...)` | list of 2 to 40 events, lessons, verdicts, manual merges and separations | merged groups (by event id), provenance, candidates | 300 |
| `takeover/scheduler.json` | `Scheduler.next(...)`, `TakeoverPolicy.qualifies` | events, settings, ledger, now, calendar zone | `ScheduledTakeover` or null; bool | 400 |
| `takeover/ledger.json` | `TakeoverLedger` operations and `TakeoverGuard` | a sequence of operations with instants | ledger JSON after each step; guard answers | 150 sequences |
| `agenda/day-agenda.json` | `DayAgenda.make(...)` | events, now, zone, settings | agenda fields | 300, including all-day events across zone changes and events spanning midnight |
| `widget/snapshot.json` | `WidgetSnapshot.make(...)`, `isStale`, `WidgetTimeline.changeDates`, `nextUp`, `today`, `visibleToday` | per function | per function | 300 |
| `wire/dates.json` | `WireDates.string`, `WireDates.date` | instant as a `Double` (including negative, sub-millisecond, `.5` ms rounding cases); text | text; instant or null | 400 |
| `inference/prompts.json` | `PromptBuilder` and the answer parser in `TextGeneratorAdjudicator` | events, zone; raw answers | prompt text; parsed decision | 150 |

- [ ] **Steps 1 to 8:** as Task 8, with 11 files.

### Task 10: Decision record and close-out

**Files (in `timetug`):**
- Create: `docs/decisions/0022-shared-libraries-in-rust.md`
- Modify: `docs/decisions/README.md`, the tracker

- [ ] **Step 1: Write ADR 0022** in the format of the neighbouring records: context (the measured sizes), decision (design sections 1, 6.1, 6.2, 6.5, 8), consequences (two languages during the transition, a crate allow-list, no size gain on Apple platforms), and what it supersedes in ADR 0001 and ADR 0012 ("dependency-free").
- [ ] **Step 2: Check the phase gate**: Rust CI green on four platforms in both libraries on `v2`; 25 vector files committed; `baselines.md` complete; Task 2 merged. Record evidence links in the tracker.
- [ ] **Step 3: Set phase 0 to `done`, move Now to phase 1, add the session log line, commit, pull request.**
