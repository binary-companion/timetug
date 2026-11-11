# Rust engine program: tracker

This is the saved progress for the move of the shared libraries to Rust. It is updated at the end of every working session and committed with that session's work, so any later session or agent can resume from it.

**Spec:** [`docs/superpowers/specs/2026-11-10-rust-engine-program-design.md`](../specs/2026-11-10-rust-engine-program-design.md) (approved by the owner 2026-11-10).
**Conventions every phase uses:** [`2026-11-10-rust-port-conventions.md`](2026-11-10-rust-port-conventions.md).

## How to resume

1. Read the spec once, the conventions once, then this file.
2. Go to **Now**. The first unchecked item is the next thing to do. Items marked **(owner)** are for the owner; agents never do them (creating branches and opening pull requests is never one of them; they are merging, publishing releases, approving deployments, changing repository settings, entering credentials).
3. Open the plan of the phase that item belongs to and continue at its first unchecked step. Plans use checkboxes; check them as you go and commit the plan with the work.
4. When you finish an item here: check it, add a line to the **Session log**, commit this file.
5. When a phase's gate is met, set its status to `done`, add its pull request links, and move **Now** to the next phase.

Status values: `not started`, `in progress`, `blocked` (say on what), `done`.

## Where the work happens

| Repository | Branch for this program | Local checkout |
|---|---|---|
| `binary-companion/calendar-connectors` | `v2` (pull requests target it) | `~/Source/binary-companion/calendar-connectors` |
| `binary-companion/timetug-shared` | `v2` | clone to `~/Source/binary-companion/timetug-shared` |
| `binary-companion/timetug-windows` | default branch | clone to `~/Source/binary-companion/timetug-windows` |
| `binary-companion/timetug` | default branch (`master`) | `~/Source/timetug` |

Program documents (spec, plans, this tracker) live in `timetug`. Port records (parity table, ledger, baselines, vectors) live in the library they describe, under `docs/rust-port/` and `vectors/`.

## Baseline

Filled in by phase 0, task 1. Never changed afterwards.

| Item | Value |
|---|---|
| `calendar-connectors` baseline tag | `1.2.0` |
| `timetug-shared` baseline tag | `1.8.1` |
| `TimeTug.Engine` baseline version | `1.8.1` (NuGet, 2026-11-10) |
| Swift tests at baseline | connectors: 915, shared: 608 |
| Windows native payload (x64 / ARM64) | uncompressed 74,626,048 / 73,146,368 bytes (74.6 / 73.1 MB); compressed in the package 28,299,296 / 27,643,266 bytes. Sum of `runtimes/<rid>/native/*` in `timetug.engine.1.8.1.nupkg`. (1.8.0 measured 70.5 MB x64: the payload grew 4 MB in one patch release.) |
| Idle memory, idle CPU, time to `ready`, dedup benchmark | see `docs/rust-port/baselines.md` in `timetug-shared` |

## Phases

| Phase | Status | Plan | Gate | PRs |
|---|---|---|---|---|
| 0 Foundations | done (2026-11-10; see Session log for two open caveats) | [plan](2026-11-10-rust-phase-0-foundations.md) | Rust CI green on four platforms in both libraries; vectors committed; baselines recorded; `timetug` ignores 2.x bumps | timetug #174 #175 #176 #181; connectors #12 #13 #14 #15 #16 #17; shared #27 #28 #29 #31 #32 #33 #34 #35 |
| 1 Connector library | done (2026-11-11; see Session log) | [plan](2026-11-10-rust-phase-1-connectors.md) | every connector test ported and passing; vectors pass; persisted formats load | connectors #18 to #31 and the close-out #32; shared #36 #37 (quiet-machine and ARM64 baselines) |
| 2 Core and Bridge | not started | [plan](2026-11-10-rust-phase-2-core-bridge.md) | Core and Bridge parity complete; benchmark not slower than Swift | |
| 3 Engine and C interface | not started | [plan](2026-11-10-rust-phase-3-engine-c-interface.md) | fixtures, scenarios, concurrency harness, `c-smoke`, unchanged .NET suite pass on four platforms; size within 8 MB; first `2.0.0-alpha` | |
| 4 Windows cutover | not started | [plan](2026-11-10-rust-phase-4-windows-cutover.md) | libraries `2.0.0` released; Windows major release ready for the owner | |
| 5 Generated bindings | not started | [plan](2026-11-10-rust-phase-5-bindings.md) | Swift scenario through the bindings on macOS; iOS simulator links; Kotlin compiles | |
| 6 Mac cutover | not started | [plan](2026-11-10-rust-phase-6-mac-cutover.md) | Mac tests and checklist pass; upgrade from 1.x data verified; Mac major release ready for the owner | |
| 7 Retire Swift | not started | [plan](2026-11-10-rust-phase-7-retire-swift.md) | no workflow, doc or skill treats the Swift libraries as current | |

Order: 0, 1, 2, 3 are sequential. 4 and 5 both need 3 and may overlap. 6 needs 4 and 5. 7 needs 6.

## Standing rules

- The Swift libraries are **not frozen**. Windows and Mac work continues on `main` and releases 1.x. Every pull request to a library's `main` that changes behaviour adds a line to `docs/rust-port/parity-ledger.md` on `v2` (phase 0 adds a pull request template checkbox and a CI reminder). Cutover needs every ledger line checked off.
- No app release may depend on a `2.0.0-alpha` package.
- Tags are created only by release workflows. The owner merges and publishes. The owner has granted agents permission to merge pull requests in all affected repositories (squash-merge, on green CI); agents still never create tags or releases of the libraries.
- Reviews: `deepseek-review` skill. Implementers: Sonnet 5.5.

## Now

- [ ] Phase 2, task 1: start the Core and Bridge port in `timetug-shared` (plan: [phase 2](2026-11-10-rust-phase-2-core-bridge.md)). Phase 1 left nothing behind: the parity ledger is empty, so there is no ledger port to do before phase 3.
- [ ] Before phase 3: decide the open limitations in the phase 1 record below (the `jiff` upper bound, the no-finite-date check, the zone-name table) and whether the engine needs any of them closed.

## Open owner items

- [x] `v2` branches created 2026-11-10 at the baseline tag commits (`calendar-connectors` `3405cdf` = 1.2.0, `timetug-shared` `cd8c445` = 1.8.1), at the owner's request, through the GitHub API.
- [x] Merge permission for the `v2` branches and the other affected repositories granted by the owner (see Standing rules).
- [x] Branch protection for `v2` added 2026-11-10 (ruleset "Protect v2" in both libraries, copy of "Protect main"; connectors also requires the six Rust jobs). Still to do by an agent: add the Rust jobs to the shared ruleset once task 5 lands them.

## Session log

- 2026-11-10: design approved; conventions, tracker and the eight phase plans written (PR 173, merged).
- 2026-11-10: phase 0 started. Task 1 done: baseline recorded (`calendar-connectors` 1.2.0, `timetug-shared` 1.8.1, `TimeTug.Engine` 1.8.1; the plan's "1.8.0" figures are superseded). Task 2 handed to a Sonnet implementer. `v2` branches created at the owner's request; tasks 3 to 9 are unblocked.
- 2026-11-10: PRs 174, 175, 176 (timetug), connectors 12, 13, 14 and shared 27, 28, 29 merged by the agent at the owner's explicit request. Phase 0 tasks 1 to 4 done; ADR 0022 and the 2.x bump guard are on master.
- 2026-11-10: phase 0 done. 25 vector files (14 connectors, 11 shared) and both test inventories (915 and 608) committed; Rust CI on four platforms plus the C library names checked in both libraries; baselines in `timetug-shared` `docs/rust-port/baselines.md` (Windows x64/ARM64 and macOS measured on GitHub-hosted runners, 600 s idle, median of 3). Weekly `vectors-drift.yml` exists in both libraries but runs only after `v2` is promoted to `main` (use `workflow_dispatch` until then). **Caveats:** (1) the engine benchmark was not run on the dev Mac (no .NET SDK installed) nor in the Parallels ARM64 VM (suspended); hosted `macos-26` and `windows-11-arm` runners stand in and are the machines the Rust numbers must be compared on; (2) the dedup benchmark ran on a busy Mac (dense 5000 took 103 s), so re-run it on a quiet machine before relying on it as the phase 2 target; (3) the vectors were written on macOS 27 and trimmed to dates through 2026-11-01 (Casablanca 2026-06-01, Havana left out of the recurrence pool) because the macOS 26 runner's zone database differs.
- 2026-11-11: phase 1 done. All eight crates are on `calendar-connectors` `v2` (PRs 18 to 31; close-out PR 32 adds the Rust API part to `docs/api.md`, makes the Rust section the main description in `AGENTS.md` and `README.md`, and adds `check-test-parity.py --require-complete` for the seven connector test targets to the `rust-lint` job). **Numbers:** 903 `ported` rows in `docs/rust-port/test-parity.md` against 1098 passed tests from `cargo test --workspace` (0 failed, 2 ignored); 12 `n/a` rows: 3 URLSessionTransport, 1 default transport configuration, 7 SHA256Hashing, and 1 outside the expected categories (`EventDraftTests::timingRejectsNonFiniteDates`: a `jiff::Timestamp` cannot hold NaN or an infinity, so there is no finiteness check; the owner confirms it is removed behaviour). **Parity ledger:** empty, nothing to port; the ledger stays open for Swift `main` changes until cutover. **Size (early warning, release `.rlib`):** caldav 2,981,936 B, google 5,759,808 B, ical-subscription 1,700,168 B, microsoft 5,480,416 B (the Windows native payload budget is judged only in phase 3). **Limitations recorded in `docs/rust-port/file-map.md` that matter later:** (1) `jiff::Timestamp` ends on 9999-12-30T22:00:00Z, so Google events in the last two hours of year 9999 are dropped; (2) the Google RFC 3339 reader refuses surrounding spaces, text after the zone, hour 24 and non-existent days that Foundation accepts, and is proleptic Gregorian; Google never sends these; (3) the Microsoft `graph_time` character handling uses `char`, not Swift `Character`, differing only after a combining mark that Graph never sends; (4) `VTIMEZONE` zone choice uses a generated list of macOS 27's identifiers (`zone_data.rs`, regenerated on a Mac with `scripts/dev/ical-tables/generate.py`), so it is the same on every platform but must be re-checked when Apple's list changes; (5) there is no built-in HTTP transport: hosts (the engine in phase 3) must meet `docs/host-http-contract.md` (no redirects for CalDAV, iCloud and iCal subscription, no cache, cookies or disk, `Prefer` and `$` query names unchanged). Rust API for hosts is `docs/api.md` part 16.
