# Rust phase 4: Windows cutover — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Windows app runs on the Rust engine with no change to its own logic, proven on x64 and ARM64; both libraries release `2.0.0` from `main`; the Windows app's next major release is ready for the owner to publish.

**Architecture:** The Windows app only changes the `TimeTug.Engine` version it pins. All proof comes from its existing self-test scenarios, its tests, the manual checklist and resource measurements against the phase 0 baseline. Then `v2` replaces `main` in both libraries, with the last Swift state kept on a `1.x` branch for the Mac.

**Tech Stack:** .NET 10, WinUI 3, MSIX, PowerShell, the Parallels Windows 11 ARM VM (`scripts/vm/*`), GitHub Actions.

**Spec:** [`docs/superpowers/specs/2026-11-10-rust-engine-program-design.md`](../specs/2026-11-10-rust-engine-program-design.md), sections 5, 7 and 8. **Tracker:** [`2026-11-10-rust-engine-program-tracker.md`](2026-11-10-rust-engine-program-tracker.md).

## Global Constraints

- No C# source file under `src/` changes for the engine swap. If one seems to need a change, stop: that is a Rust engine defect (anti-goal, design section 5) and goes back to `timetug-shared` `v2`.
- No Windows build that depends on a `2.0.0-alpha` package is ever released or flighted. The prerelease pin lives only on a branch named `rust-engine-trial` until `2.0.0` exists.
- Agents never merge, tag, publish or change repository settings. Each owner step below is added to the tracker's owner items with its exact command or URL.
- `timetug-windows` rules hold (its `AGENTS.md`): exact package versions, no logging of calendar content, VM screenshots and dumps with real calendar text are never committed.
- The parity ledgers of both libraries must be empty (every line checked) before Task 6.

## Review Focus

1. **A user upgrading from the Swift-engine build with accounts already added**: accounts, calendars chosen, settings, merge decisions and takeover history survive. Pinned by Task 3.
2. **A machine without the Visual C++ redistributable** (a clean Windows install): the app starts. Pinned by Task 2, step 4.
3. **Sleep, lid close and resume across a meeting start**: one late takeover, not zero and not two. Pinned by the manual checklist items for resume and by Task 4, step 3.
4. **Windows on ARM64 and x64 behave the same**: every automated step runs on both.
5. **Antivirus or SmartScreen reacting to a new, unsigned-looking native DLL inside the package**: the release MSIX passes `check-release-package.ps1` and installs on a VM with Defender on. Pinned by Task 5.

---

### Task 1: Trial branch on the prerelease

**Files (in `timetug-windows`, branch `rust-engine-trial` from the default branch):**
- Modify: `Directory.Packages.props` (`TimeTug.Engine` to `2.0.0-alpha.N`, the newest prerelease)
- Modify: `docs/third-party.md`

- [ ] **Step 1: Change the one version line.** If `nuget.config` restricts sources, confirm nuget.org prereleases restore (`dotnet restore`).
- [ ] **Step 2: Build and test on the Mac-reachable parts**: `pwsh scripts/verify.ps1` where it runs, otherwise through the VM: `scripts/vm/vm-up.sh && scripts/vm/vm-sync.sh && scripts/vm/vm-run.sh 'pwsh scripts/verify.ps1'`. Expected: every test project passes.
- [ ] **Step 3: Confirm the package content in the build output**: in `src/TimeTug.App/bin/**/` there is exactly one engine native file, `TimeTugEngineC.dll`, and no `swift*.dll`, `Foundation*.dll`, `_FoundationICU.dll`, `dispatch.dll` or `BlocksRuntime.dll`.
- [ ] **Step 4: Update `docs/third-party.md`**: remove the Swift runtime and Foundation entries; add the Rust crates from the package's `THIRD-PARTY-NOTICES.md` (link to it and list names and licences).
- [ ] **Step 5: Commit; push the branch; open a draft pull request** titled "Trial: Rust engine prerelease (do not merge)". CI must be green on both architectures, including `run-selftest.ps1` and `run-a11y.ps1`.

### Task 2: Self-test and packaging on both architectures

- [ ] **Step 1: Self-test on ARM64 (VM)**: `scripts/vm/vm-selftest.sh`. Expected: every scenario in `scripts/ci/selftest-scenarios.txt` passes. Record the count.
- [ ] **Step 2: Self-test on x64**: from the draft pull request's CI run (`run-selftest.ps1` job). Same count.
- [ ] **Step 3: Development MSIX**: `scripts/ci/build-msix.ps1` for both architectures; install on the VM with `scripts/vm/vm-install.ps1`; start the app; `scripts/vm/vm-screenshot.sh` of the welcome window (no account, so no calendar text). Compare the MSIX file sizes with the last Swift-engine development MSIX from CI artifacts; record both.
- [ ] **Step 4: Clean-machine check**: in a VM snapshot without the Visual C++ redistributable (check `Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\*'` is empty, or use a fresh Windows 11 image), install the MSIX and start the app. Expected: it starts and reaches the welcome window. If no such snapshot exists, add creating one to the owner items and continue; this step must be done before Task 6.
- [ ] **Step 5: Release-flavour dry run**: dispatch `windows-release-dryrun.yml` on the trial branch (owner step if the workflow needs the protected environment; add to owner items with the command `gh workflow run windows-release-dryrun.yml --repo binary-companion/timetug-windows --ref rust-engine-trial`). Expected: `check-release-package.ps1` and `test-release-package.ps1` pass.

### Task 3: Upgrade in place

**Files (in `timetug-windows`, on the trial branch):**
- Create: `scripts/vm/vm-upgrade-check.sh`, `scripts/vm/vm-upgrade-check.ps1`

The script automates: install the last released Swift-engine development MSIX; start the app with a prepared data directory; close it; install the trial MSIX over it; start; run a self-test scenario that reports state; compare.

- [ ] **Step 1: Prepare a synthetic data directory** (no real accounts): the files of `timetug-shared` `fixtures/engine/` and `calendar-connectors` `fixtures/persisted-formats/1.2.0/`, renamed to the names the engine uses on disk, plus the app's own settings files created by running the old build once and changing three settings through the self-test hooks. Find where the Windows app puts the engine data directory (`grep -rn "dataDirectory" src/TimeTug.Platform`).
- [ ] **Step 2: Write the script.** It captures the engine `state` JSON (accounts by kind and display name, settings, ledger entry count, lesson count) before and after through the self-test's state dump (`grep -rn "selftest" src/TimeTug.App/SelfTest` for the dump switch; if none prints state, add a `CI`-configuration-only switch that writes the last state JSON to a file; that is self-test code, not app logic, and is allowed).
- [ ] **Step 3: Run it on the VM.** Expected: the two captures are equal on every listed field; the account kinds include `microsoft-brokered`; no file in the data directory was deleted or emptied.
- [ ] **Step 4: Owner check with real accounts**: add to the manual checklist (Task 4) "upgrade a machine that has real Google, Microsoft (browser and Windows account), iCloud and iCal-link accounts; all are still present and refresh".

### Task 4: Manual checklist and measurements

**Files:**
- Modify (in `timetug-windows`): `docs/manual-tests/windows-checklist.md` (a new section "Rust engine cutover")
- Modify (in `timetug-shared`, `v2`): `docs/rust-port/baselines.md`

- [ ] **Step 1: Add the checklist section** with these items, each naming the CI artifact to install: add each account kind; refresh; a takeover fires at the lead time; join, snooze (re-fires), dismiss; takeover while the screen is locked; resume from sleep across a meeting start (one late takeover); time-zone change in Settings while the app runs; duplicate merge, unmerge, separate, forget; sign out and back in to the Windows account kind; remove an account; quit and restart (state persists); the upgrade item from Task 3, step 4. Each item says what must be seen.
- [ ] **Step 2: Measure the app** on the VM (ARM64) and on an x64 machine or runner, Swift-engine build versus trial build, three runs each, same account-free state: installed size (`Get-AppxPackage` `InstallLocation` folder size), working set and private bytes of the app process five minutes after start, CPU time accumulated over ten idle minutes, time from process start to tray icon. Use `Get-Process` sampling in a script `scripts/vm/vm-measure.ps1` (create it; it takes the package name and writes JSON).
- [ ] **Step 3: Sleep test**: with a `testing`-free engine and a synthetic iCal-link account served from a local file URL is not possible (HTTP only), so use the `takeover.test` path plus `scripts/vm/vm-suspend.sh` across the scheduled minute; expected one takeover after resume. Record in the checklist as an owner-attended item if it cannot be automated.
- [ ] **Step 4: Record** the numbers in `baselines.md` under "Windows app, Swift engine versus Rust engine". Gate: installed size lower; memory, idle CPU and start time not worse (10% tolerance on time and CPU).
- [ ] **Step 5: (owner)** Run the checklist section. Add to owner items. Stop until done.

### Task 5: Dependabot and the bump path

`timetug-windows` already receives `TimeTug.Engine` updates through Dependabot (its `AGENTS.md`, Backward compatibility). No new bump workflow is needed (design section 8, Bump chain).

**Files (in `timetug-windows`, default branch, a normal pull request):**
- Modify: `.github/dependabot.yml`, `AGENTS.md`

- [ ] **Step 1: Read `.github/dependabot.yml`.** Confirm the `nuget` ecosystem is present and that major versions are not ignored for `TimeTug.Engine`. If majors are ignored, leave that as is (the cutover pull request is made by hand in Task 7) and note it in `AGENTS.md`.
- [ ] **Step 2: Update `AGENTS.md`**: `TimeTug.Engine` 2.x is the Rust engine; the package holds one native file per architecture; a prerelease version is never merged to the default branch. Add a contract to `scripts/ci/check-repository-contracts.py` (test first, in `scripts/ci/tests/`): `Directory.Packages.props` on the default branch must not pin a `TimeTug.Engine` version containing `-`.
- [ ] **Step 3: Pull request; owner merges.**

### Task 6: Library cutover to `main`

Preconditions, checked and recorded in the tracker with links: phase 3 gate met; Tasks 1 to 4 green; owner checklist done; both parity ledgers empty; `timetug` Task 2 of phase 0 merged (the Mac bump workflow skips 2.x). One more precondition is created here first: on `timetug-shared` `main` (still Swift), the bump workflow gains the same major guard as `timetug` (copy `scripts/ci/bump-major-guard.sh` and its test from `timetug`, reading the current connector version from `Package.resolved` through `scripts/ci/resolved-version.py`; a small pull request to `main`, labelled so it releases a patch; the owner merges). Without it, the `calendar-connectors` 2.0.0 release would open a connector bump against the Swift `main`.

**In each library (`calendar-connectors` first, then `timetug-shared`):**

- [ ] **Step 1: (owner) Keep the Swift line.** Create branch `1.x` from the current `main`: `git push origin origin/main:refs/heads/1.x`. Add to owner items.
- [ ] **Step 2: Release from `1.x`.** On a branch from `1.x`: change the `push` triggers of `release.yml` and `ci.yml` from `main` to `1.x`, and make `scripts/release/next-version.sh` consider only tags reachable from the branch being released (test first, in `scripts/release/tests/`: with tags `1.8.3` and `2.0.0` both present, a patch release from `1.x` is `1.8.4`). The `notify` job stays, so the Mac still receives bump pull requests for 1.x fixes. Pull request to `1.x`; the owner merges.
- [ ] **Step 3: Merge `main` into `v2` one last time** on a branch from `v2`, tooling paths only (design section 8, "Keeping `v2` current"); resolve every Swift path to deleted. CI green.
- [ ] **Step 4: Open the cutover pull request `v2` to `main`** with the label `semver:major`. Title: "2.0.0: the library in Rust". Body: the gate evidence links, the size and resource tables, the list of `n/a` parity rows with reasons, the note that the Swift API is removed and where 1.x lives. In `calendar-connectors` the `release.yml` change of Step 5 is part of this pull request.
- [ ] **Step 5: Release workflow on `main` after the merge.** The push to `main` releases `2.0.0` through the existing label logic. Confirm before merging that `next-version.sh` given the highest tag `1.x.y` and the label `semver:major` yields `2.0.0` even though `2.0.0-alpha.N` tags exist: add that exact case to `scripts/release/tests/test-next-version.sh` (prerelease tags are ignored when computing the next stable version). For `timetug-shared`, first point the connector dependency at `tag = "2.0.0"` with `bump-cargo-dependency.py 2.0.0` (after `calendar-connectors` 2.0.0 exists).
- [ ] **Step 6: (owner) Merge `calendar-connectors`' cutover pull request.** Verify: tag `2.0.0` and a GitHub release exist; the `notify` dispatches were sent; `timetug` logged the skip notice and opened no pull request; `timetug-shared` (whose `main` is still Swift at this moment) logged the skip notice and opened no pull request.
- [ ] **Step 7: (owner) Merge `timetug-shared`'s cutover pull request.** Verify: tag `2.0.0`; `TimeTug.Engine` `2.0.0` on nuget.org with one native file per architecture; `timetug` skips.
- [ ] **Step 8: Protect and tidy.** Owner items: branch protection for `1.x`; delete `v2` after confirming `main` equals it; update required check names if Task 10 of phase 3 changed any.

### Task 7: Windows app adopts 2.0.0

**Files (in `timetug-windows`, a new branch from the default branch):**
- Modify: `Directory.Packages.props` (`TimeTug.Engine` to `2.0.0`), `docs/third-party.md`, `docs/parity.md` (a line under engine: "Rust engine from 2.0.0"), `docs/release.md` (version note)
- Cherry-pick from the trial branch: `scripts/vm/vm-upgrade-check.*`, `scripts/vm/vm-measure.ps1`, the checklist section

- [ ] **Step 1: Make the changes; close the trial draft pull request.**
- [ ] **Step 2: Full verification**: `scripts/verify.ps1` (VM), self-test on both architectures, `run-a11y.ps1`, the upgrade check, the release dry run. All green.
- [ ] **Step 3: Version.** The Windows app's next release is a major version; set it wherever `docs/release.md` says the version is set (read the "version" section; do not guess a file).
- [ ] **Step 4: Pull request**; the owner merges and publishes the release or Store flight per `docs/release.md`.

### Task 8: Phase close-out

- [ ] **Step 1: Update `timetug`**: `docs/engine-protocol.md` ("The package" section: one native library per architecture, about N MB, Rust), `docs/architecture.md` (the libraries are Rust from 2.0.0; the Mac still pins 1.x until phase 6), `AGENTS.md` (Repositories: `1.x` branches serve the Mac), the `working-across-timetug-repos` skill (Swift changes go to `1.x`; Rust changes to `main`).
- [ ] **Step 2: Update the tracker**: phase 4 `done` with the measured before-and-after table; Now to the first open item of phase 5 or 6.
- [ ] **Step 3: Update the memory note** `windows-program` (the engine package is Rust from 2.0.0) through the session's memory directory.
