# Rust engine program: tracker

This is the saved progress for the move of the shared libraries to Rust. It is updated at the end of every working session and committed with that session's work, so any later session or agent can resume from it.

**Spec:** [`docs/superpowers/specs/2026-11-10-rust-engine-program-design.md`](../specs/2026-11-10-rust-engine-program-design.md) (approved by the owner 2026-11-10).
**Conventions every phase uses:** [`2026-11-10-rust-port-conventions.md`](2026-11-10-rust-port-conventions.md).

## How to resume

1. Read the spec once, the conventions once, then this file.
2. Go to **Now**. The first unchecked item is the next thing to do. Items marked **(owner)** are for the owner; agents never do them (merging, publishing releases, approving deployments, changing repository settings, entering credentials).
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
| Swift tests at baseline | connectors: , shared: |
| Windows native payload (x64 / ARM64) | uncompressed 74,626,048 / 73,146,368 bytes (74.6 / 73.1 MB); compressed in the package 28,299,296 / 27,643,266 bytes. Sum of `runtimes/<rid>/native/*` in `timetug.engine.1.8.1.nupkg`. (1.8.0 measured 70.5 MB x64: the payload grew 4 MB in one patch release.) |
| Idle memory, idle CPU, time to `ready`, dedup benchmark | see `docs/rust-port/baselines.md` in `timetug-shared` |

## Phases

| Phase | Status | Plan | Gate | PRs |
|---|---|---|---|---|
| 0 Foundations | in progress | [plan](2026-11-10-rust-phase-0-foundations.md) | Rust CI green on four platforms in both libraries; vectors committed; baselines recorded; `timetug` ignores 2.x bumps | |
| 1 Connector library | not started | [plan](2026-11-10-rust-phase-1-connectors.md) | every connector test ported and passing; vectors pass; persisted formats load | |
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
- Tags are created only by release workflows. The owner merges and publishes. A standing permission to merge on green CI exists for the Windows program; it does **not** carry over to this program unless the owner says so here: _owner: (not granted)_.
- Reviews: `deepseek-review` skill. Implementers: Sonnet 5.5.

## Now

- [x] Phase 0, task 1: record the baseline
- [ ] Phase 0, task 2: `timetug` ignores 2.x bumps (pull request open; owner merges)
- [x] Phase 0, task 3, step 1: `v2` branches exist
- [ ] Phase 0, tasks 3 to 9 (see the plan)
- [ ] Phase 0, task 10 (ADR 0022) can be written now, in `timetug`

## Open owner items

- [x] `v2` branches created 2026-11-10 at the baseline tag commits (`calendar-connectors` `3405cdf` = 1.2.0, `timetug-shared` `cd8c445` = 1.8.1), at the owner's request, through the GitHub API.
- [ ] **(owner)** Merge the phase 0 task 2 pull request in `timetug` before any 2.0.0 library release.
- [ ] **(owner)** Say whether agents may merge program pull requests into the `v2` branches when CI is green (see Standing rules).
- [ ] **(owner)** Add branch protection for `v2` in `calendar-connectors` and `timetug-shared` (same required checks as `main`, once phase 0 has added the Rust jobs).

## Session log

- 2026-11-10: design approved; conventions, tracker and the eight phase plans written (PR 173, merged).
- 2026-11-10: phase 0 started. Task 1 done: baseline recorded (`calendar-connectors` 1.2.0, `timetug-shared` 1.8.1, `TimeTug.Engine` 1.8.1; the plan's "1.8.0" figures are superseded). Task 2 handed to a Sonnet implementer. `v2` branches created at the owner's request; tasks 3 to 9 are unblocked.
