# Rust phase 7: retire Swift — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nothing in any repository, workflow, document or agent skill still treats the Swift libraries as current, and the `1.x` branches stop releasing.

**Architecture:** A clean-up phase. No behaviour changes. It starts only after the Mac major release has been public for the wait the owner chooses.

**Tech Stack:** GitHub Actions, shell, Python, Markdown.

**Spec:** [`docs/superpowers/specs/2026-11-10-rust-engine-program-design.md`](../specs/2026-11-10-rust-engine-program-design.md), section 9, phase 7. **Tracker:** [`2026-11-10-rust-engine-program-tracker.md`](2026-11-10-rust-engine-program-tracker.md).

## Global Constraints

- Nothing is deleted that a released, supported app version still needs. The owner states, in the tracker, the date after which no 1.x Swift fix will be made; no task below starts before that line exists.
- Branches are never deleted by an agent. The `1.x` branches are kept (read-only) for history.
- Release tags and published packages are never removed.

## Review Focus

1. **A user still on the last Swift-engine app version**: their app keeps working (it has no runtime dependency on the repositories) and updates to the Rust-engine version through Sparkle, the Mac App Store or the Microsoft Store. Check the Sparkle appcast still offers the path from that version.
2. **An agent following an old skill or document** into a Swift workflow that no longer exists: every such instruction is found by Task 3's search and fixed.
3. **A dispatch or scheduled workflow that still fires for a retired path** (a `library-released` event for `calendar-connectors` reaching `timetug`; Dependabot on a deleted manifest): each is removed or answers with a notice. Pinned by Task 2.
4. **The code index** still excluding or including the right paths after the language change. Pinned by Task 4.
5. **Third-party notices** in each shipped app listing what is actually inside it. Pinned by Task 5.

---

### Task 1: Owner decision

- [ ] **Step 1: (owner)** Write in the tracker's Standing rules: "No further 1.x Swift releases after <date>." Add to owner items; stop until present.

### Task 2: Stop the 1.x release paths

**Files (in each library, branch from `1.x`, pull request to `1.x`):** `.github/workflows/release.yml`, `ci.yml`, `bump-dependencies.yml`, `README.md`.

- [ ] **Step 1:** `release.yml` on `1.x`: remove the `push` trigger; keep `workflow_dispatch` with a required input `confirm: "release 1.x"` so an emergency release is still possible on purpose.
- [ ] **Step 2:** `README.md` on `1.x`: first line "This branch is the retired Swift implementation (1.x). The library is Rust on `main` from 2.0.0."
- [ ] **Step 3: (owner)** Mark `1.x` read-only with a ruleset (no pushes except by the owner). Add to owner items.

**Files (in `timetug`):** `.github/workflows/bump-dependencies.yml`, `scripts/ci/bump-pin.sh`, tests.

- [ ] **Step 4:** Confirm phase 6 left only the `timetug-shared` path. Remove any remaining `calendar-connectors` branch of the workflow and script; a dispatch for it logs a notice. In `calendar-connectors`' `release.yml` on `main`, remove `timetug` from the `notify` targets (it now notifies only `timetug-shared`); test in `scripts/release/tests/`.

### Task 3: Documents, agent guides and skills

- [ ] **Step 1: Search every repository** (`timetug`, `timetug-windows`, `timetug-shared`, `calendar-connectors`, `website`, `homebrew-tap`) for: `swift build`, `swift test`, `Package.resolved`, `Package.swift`, `sourcekit`, `Swift runtime`, `swiftCore`, `Foundation`, `TimeTugCore`, `CalendarBridge`, `CalendarCore`, `exactVersion`, `Portable Swift library`, `1.x`. For each hit decide: still true (the Mac app is Swift; `TimeTugKit` is a Swift package), history (specs, plans, ADRs, progress logs: leave unchanged), or stale (fix).
- [ ] **Step 2: Fix the stale ones.** Expected places: both libraries' `AGENTS.md` and `README.md` ("Finding code" sections say Rust, `rust-analyzer` through Serena, `cargo build` first), repository descriptions (owner step: `gh repo edit binary-companion/calendar-connectors --description "Portable Rust library for Google, Microsoft, CalDAV/iCloud and iCalendar calendars"`, and the matching one for `timetug-shared`), `timetug` `AGENTS.md`, `docs/architecture.md`, `docs/development.md`, `docs/engine-protocol.md`, the `.claude/skills` and `.agents/skills` directories in each repository.
- [ ] **Step 3: ADRs.** In `timetug` `docs/decisions/README.md`, mark ADR 0001's statement about the shared code and ADR 0012's "dependency-free" as superseded by 0022 and 0023 (add "Superseded in part by ..." lines; do not rewrite history).
- [ ] **Step 4: Program documents.** The Windows program tracker (`2026-10-09-windows-program-tracker.md`): add a line under its phase table that the engine is Rust from `TimeTug.Engine` 2.0.0 and link this program's tracker.
- [ ] **Step 5: Shared agent rules.** `~/.agents/shared.md` mentions that Swift projects must be built for sourcekit-lsp; nothing to change, but add the Rust equivalent only if the owner wants it (ask in the pull request description; do not edit a user-level file unasked).

### Task 4: Tooling

- [ ] **Step 1: Code index** in both libraries: `.qindexignore` excludes `target/`, `vectors/`, `kotlin/generated/`, `swift/TimeTugKit/Sources/TimeTugKit/Generated/`; the `Code index` workflow's language settings include Rust (compare `scripts/dev/qindex.py` with the skill's copy as the `AGENTS.md` rule says). Run the workflow once on a branch through `workflow_dispatch` if it allows, or check the next `main` run.
- [ ] **Step 2: Dependabot**: `cargo` ecosystem present in both libraries; the `swift` ecosystem entry removed where the manifest is gone (`timetug-shared` keeps one for the root `Package.swift` only if Dependabot can do anything useful with a binary target; otherwise remove).
- [ ] **Step 3: Vectors.** The vectors are now the permanent regression suite. Update `vectors/README.md` in both libraries: they were exported from Swift at the baseline tags (name them), the exporters lived in the last dual-language commit (give its SHA from `docs/rust-port/README.md`), and from now on a behaviour change is made by changing Rust code and adding new vector cases by hand, never by regenerating.
- [ ] **Step 4: Port records.** Move `docs/rust-port/` in each library to `docs/history/rust-port/`; keep `test-parity.md` and `file-map.md` (they answer "where did this Swift code go"); remove `check-test-parity.py` and its CI step (the Swift tests it compared against are gone), keeping the Rust test-count floor instead: a script `scripts/ci/check-test-count.py` with a committed floor per crate, raised with the suites, as `count-swift-tests.py` did.

### Task 5: Notices and final measurements

- [ ] **Step 1: Third-party notices.** Mac app: its acknowledgements (wherever `docs/release.md` or the app's About pane sources them) list the Rust crates from `timetug-shared`'s `THIRD-PARTY-NOTICES.md` and no longer anything Swift-library specific. Windows app: `docs/third-party.md` matches the shipped package (phase 4 did this; verify against the current engine version).
- [ ] **Step 2: Final table.** In the tracker, a closing section "Results" with, for Windows x64, Windows ARM64 and macOS: engine payload before and after, app install size before and after, idle memory, idle CPU, start time, each from `baselines.md` and the phase 4 and 6 measurements.
- [ ] **Step 3: Website.** If `website` or `site/` states sizes or technology, update the text (search for "MB" and "Swift").

### Task 6: Close the program

- [ ] **Step 1:** Tracker: every phase `done`; "Now" says the program is complete and names the two living documents for future engine work (`timetug-shared` `AGENTS.md`, `docs/bindings.md`).
- [ ] **Step 2:** Memory notes: update `windows-program`, `calendar-connectors-effort`, `timetug-project-context` and `code-navigation-tools` (Rust navigation for the libraries); remove statements that are no longer true.
- [ ] **Step 3:** Offer the owner two follow-ups as separate work, not part of this program: publishing the connector crates to crates.io, and a Linux or iOS front end on the bindings.
