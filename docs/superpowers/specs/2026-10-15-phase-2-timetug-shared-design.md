# Phase 2: the `timetug-shared` repository

Status: draft for the owner's review (2026-10-15). Parent: [program design](2026-10-09-windows-program-design.md), roadmap row 2 and sections 1 and 7. The program design wins where the two disagree, except for the amendments in "Decisions" below. Precedent: [phase 1](2026-10-12-phase-1-calendar-connectors-design.md), whose extraction, release and bump machinery this phase reuses.

## Purpose

Move `TimeTugCore` and `CalendarBridge` out of the Mac app's repository into their own public repository, `binary-companion/timetug-shared`, so that the engine (phase 3), the C interface and NuGet package (phase 4) and the Windows app have a home that is not the Mac repository. Prove on Windows x64 and ARM64, in CI, that the portable logic builds and passes its tests there. The Mac app keeps working throughout and consumes the new repository by a pinned release.

Success means: the repository exists with the history of the two packages; `1.0.0` is tagged only after macOS, Linux, Windows x64 and Windows ARM64 jobs are green; every merge to `main` releases automatically; `timetug` builds, tests and ships from the released tag; and a library release flows through the whole chain (`calendar-connectors` release, bump PR in `timetug-shared`, `timetug-shared` release, bump PR in `timetug`) without anyone editing a repository by hand.

## Not in this phase

- No behaviour change in Core, Bridge or the Mac app. The flip changes where the code comes from, not what it does.
- No `TimeTugEngine`, `TimeTugEngineProtocol` or `TimeTugEngineC` (phases 3 and 4), no NuGet package, no C#.
- No Windows app. Windows here is CI only.
- No change to how the Mac app is released.

## Decisions

| Topic | Decision |
|---|---|
| License | **MIT plus the Commons Clause, the same text as `timetug`** (owner, 2026-10-15). The Commons Clause stops anyone selling the software; `calendar-connectors` stays plain MIT. Holder: Binary Companion LLC. |
| Contents | `TimeTugCore` (20 source files, 2,017 lines; 26 test files, 3,758 lines; the `DedupBenchmark` executable) and `CalendarBridge` (2 files, 75 lines; 2 test files, 181 lines), with history. Nothing else moves. |
| Layout | One root `Package.swift`, package name `timetug-shared`, products `TimeTugCore` and `CalendarBridge`, executable `DedupBenchmark`. The same shape as `calendar-connectors`, so the engine modules of phase 3 are added beside them. |
| Dependency | `calendar-connectors` by URL with a range (`from: "1.0.0"`), as a library; `Package.resolved` is committed (program design, Pinning). |
| Tags and branch | Plain `X.Y.Z` tags, default branch `main`. |
| History | Extracted with `git filter-repo` from a fresh GitHub clone (`uvx git-filter-repo`), as in phase 1. Pull requests and issues are not carried over; `(#N)` in messages becomes `(binary-companion/timetug#N)`. |
| Mac consumption | `AppleIntelligenceInference` (the only remaining local package that needs Core) and `Apps/macOS/project.yml` depend on `timetug-shared` by URL; the app pins `exactVersion`. `EventKitSource` and `CalendarApple` do not use Core and are unchanged. |
| Windows toolchain | Swift is installed on the Windows runners by a script in the repository (pinned version, verified checksum). Third-party setup actions are not used: the organization's Actions policy allows only GitHub-owned actions and `google-github-actions/auth`. |

## The repository

```
timetug-shared/
  Package.swift            # name "timetug-shared", tools 6.0, macOS 14, no platform conditions
  Sources/TimeTugCore/  Sources/CalendarBridge/  Sources/DedupBenchmark/
  Tests/TimeTugCoreTests/  Tests/CalendarBridgeTests/
  Package.resolved         # committed
  scripts/ci/              # check-architecture.sh (+test), check-repository-contracts.py (+test),
                           # install-swift-windows.ps1, select-xcode.sh, requirements-test.txt
  scripts/release/         # next-version.sh (+tests), as in calendar-connectors
  scripts/benchmarks/run-dedup.sh
  .github/workflows/       # ci.yml, release.yml, index.yml
  .github/dependabot.yml   # github-actions, swift
  LICENSE (MIT + Commons Clause)  README.md  AGENTS.md  CLAUDE.md  SECURITY.md  CODEOWNERS
  .gitattributes  .gitignore  .qindexignore  docs/
```

Measured on 2026-10-15: 59 commits touch the two packages (first 2026-09-18); Core and Bridge import only Foundation, `CalendarCore` and each other. The architecture rules move with the code: Core imports Foundation and `CalendarCore` only, Bridge adds Core, nothing reads the clock in Core (`now: Date` is passed in), no package dependency other than the connector library.

## CI and release in the new repository

- **`ci.yml`** on pull requests and pushes to `main`, five required jobs: `macos` (`swift test`, newest Xcode), `linux` (the `swift:6.x` container with the Docker Hub login from the organization secrets), `windows-x64` (`windows-latest`), `windows-arm64` (`windows-11-arm`) and `architecture` (architecture rules, repository contracts, tests of the scripts).
- **Windows jobs** run `scripts/ci/install-swift-windows.ps1` (pinned Swift version, checksum verified, cached), then `swift test`. Scripts take the build directory from `swift build --show-bin-path` and never assume `.build\release`; failing to create SwiftPM's convenience symlink is a warning (Spike S). Tests that depend on platform quirks are skipped with a reason, never silently.
- **`release.yml`**: the same workflow as `calendar-connectors` after its hardening: label-driven bump, reachable-tag selection, tag-at-SHA guard, `publish` environment, `notify` job in the `bump` environment. The release notes record the `calendar-connectors` version from `Package.resolved` ("Built and tested with calendar-connectors X.Y.Z").
- **Rulesets and environments** as for the library: `Protect main` (pull request, the five required checks, no bypass), `Protect version tags` on `refs/tags/*` (update, deletion, non-fast-forward; creation allowed), environments `publish` and `bump` limited to `main`, admin bypass off. `scripts/security/audit-github.sh --strict` passes for the repository.
- **Code index** workflow, `.qindexignore` (plans excluded), `AGENTS.md` section (the `add-code-indexing` skill; pins by commit SHA).
- **Dependents notified on release:** `timetug` today (the Windows repository joins in phase 5).

## How `timetug` consumes it

- **Manifests:** `Packages/TimeTugCore` and `Packages/CalendarBridge` are deleted. `AppleIntelligenceInference/Package.swift` replaces `.package(path: "../TimeTugCore")` with `.package(url: "https://github.com/binary-companion/timetug-shared", from: "1.0.0")` and its product references name the package `timetug-shared`.
- **App:** `Apps/macOS/project.yml` replaces the `TimeTugCore` and `CalendarBridge` path packages with one `TimeTugShared` entry (`url` plus `exactVersion`); the 14 product references move to `package: TimeTugShared`.
- **Pin contract:** `scripts/ci/check-shared-pins.py` and `scripts/ci/bump-pin.sh` generalize from one library to a table of shared libraries (`calendar-connectors`, `timetug-shared`) with the same rules for each: released-form URL only, floor at or below the pin within one major, nothing else in `project.yml` naming a library.
- **Chain and bump flow.** `calendar-connectors` notifies `timetug-shared` as well as `timetug`. A `timetug-shared` bump PR edits `Package.resolved` with a script (version and revision of the new tag; no Swift needed on the bump runner), and its CI proves it with `swift package resolve --force-resolved-versions`. A `timetug` bump PR for `timetug-shared` also raises the `calendar-connectors` pin to at least the version recorded in that release's `Package.resolved` (read from the tag), so both apps run the connector version the engine was tested with. Superseded bump PRs are closed by the existing supersede step; the bot never merges.
- **Local work:** `scripts/dev/use-local-connectors.sh` gains a sibling for `timetug-shared` (same backup, hash guard and refusal rules), documented in the `working-across-timetug-repos` skill.
- **Guards and docs that name the old paths** are reworked in the flip PR: `check-architecture.sh` and its test (Core and Bridge rules leave; the five remaining packages may depend on `timetug-shared` by URL), `check-repository-contracts.py`, `verify.sh`, `affected-tests.sh` and their tests, `ci.yml` (`core` stops testing Core and Bridge; the `core-linux` job moves to the new repository), `scripts/benchmarks/run-dedup.sh` (moves), `AGENTS.md`, `CONTRIBUTING.md`, `README.md`, `docs/architecture.md`, `docs/development/runbooks/operations.md`, the PR template, ADR cross-references, and a new ADR recording the extraction.

## Sequence

Each step leaves the Mac app releasable.

1. **(owner)** Add the new repository to the `timetug-bot` installation and to the Docker Hub organization secrets' repository list once it exists (the agent creates the repository and the `publish` and `bump` environments and stores the bot secrets, as in phase 1).
2. Create the repository, extract the history, add the files above, rulesets, environments, index and CI. Fix anything Windows finds (x64 is unverified, program design risk) in pull requests there. Tag `1.0.0` through the dispatch input only when all five jobs are green. From extraction until step 3 merges, the in-repo copy is frozen.
3. **Flip pull request in `timetug`:** delete the two packages, switch the manifest and `project.yml`, generalize the pin tooling, rework guards and docs. Full CI including the app tests, the App Store build and the DMG must pass. The owner merges; the next beta carries it.
4. Library notify list gains `timetug-shared`; `timetug-shared` gets its bump workflow and `Package.resolved` script.
5. **Drill:** a docs-only `calendar-connectors` change must produce a green bump PR in `timetug-shared`; merging it must produce a release and a green bump PR in `timetug` (with both pins) without a manual step.
6. `calendar-connectors` gets the same Windows jobs (program design section 7), reusing the install script; tracker, `AGENTS.md` Repositories sections and the cross-repository skill updated.

## Verification

| Claim | Evidence |
|---|---|
| History preserved | `git log --follow` reaches 2026-09-18; the commit count matches the path log (plus any retained merge commits, explained). |
| Nothing lost or changed | `Sources` and `Tests` tree hashes of `1.0.0` equal those of the in-repo packages (the only differences allowed are the manifest and `Package.resolved`). |
| Portable on Windows | `windows-x64` and `windows-arm64` jobs green on `main` before `1.0.0`; the same test count as macOS (Core 301, Bridge 13 today) or a documented skip list. |
| The app is unchanged | The flip PR's diff outside manifests, `project.yml`, scripts and docs is empty; the app tests pass unchanged; a full manual checklist pass is not required for a pure source move (phase 3 requires it). |
| Tags immutable, bot cannot merge | Ruleset refusal; the bump PR needs the owner's merge. |
| Chain works | The step 5 drill. |

## Risks

| Risk | Mitigation |
|---|---|
| Core or tests fail on Windows x64 (never run there) | Windows jobs run before `1.0.0`; fixes land in the new repository's pull requests; the freeze keeps the Mac app on the in-repo copy meanwhile. |
| `windows-11-arm` runner availability or flakiness blocks merges | The job is required from the start, but the plan records the escape hatch: mark it non-required in the ruleset (owner) and open an issue; do not skip tests. |
| Swift toolchain download or install on Windows is flaky or slow | Pinned version, checksum, cache; a retry loop in the script; the version lives in one file. |
| A required check named `core-linux` still exists in `timetug`'s ruleset after the job moves | The owner's pending "add `core-linux` as a required check" item is dropped; the flip PR lists the exact required-check set (`core`, `app`, `dmg`, `architecture`, plus `release-tooling` and `app-store-build` if the owner adds them). |
| Two libraries in the pin tooling regress the phase 1 protections | The phase 1 mutation tests are kept and run for each library in the table; the pin check fails on any unlisted library URL or path. |
| `Package.resolved` drifts from `from:` in the new repository | CI uses `--force-resolved-versions`; the bump script is the only writer (tested). |
| Maintainer pushes a library tag by hand | Tag ruleset allows creation by design (the release workflow needs it); `next-version.sh` selects the latest reachable tag; documented as forbidden. |

## Owner checklist

- [ ] Review and approve this spec; the plan follows.
- [ ] After the repository exists: add it to the `timetug-bot` installation, and to the Docker Hub organization secrets.
- [ ] Merge the flip pull request and each bump pull request.
- [ ] Confirm the license text (MIT plus Commons Clause, holder Binary Companion LLC) and `CODEOWNERS` (`@darkarena1`).
