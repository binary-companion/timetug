# ADR 0020: Core and Bridge live in the `timetug-shared` repository

**Status:** Accepted, 2026-10-15

## Context

The Windows program ([program design](../superpowers/specs/2026-10-09-windows-program-design.md)) needs the portable logic (`TimeTugCore`, `CalendarBridge`) in a repository that a Windows app can depend on, build in CI on Windows, and release on its own. Until now both packages lived in this repository next to the Mac app, so a Windows consumer would have had to depend on the Mac repository. Spike S showed they build and pass their tests on Windows ARM64; x64 was unverified. Phase 1 had already moved the connector library out under the same pattern ([ADR 0012](0012-calendar-connector-library.md), update 2026-10-13).

## Decision

- **Where:** `TimeTugCore`, `CalendarBridge`, their tests and the `DedupBenchmark` executable moved, with their history (58 commits that touch the two packages, the first dated 2026-09-18, plus the three merge commits that join them), to [binary-companion/timetug-shared](https://github.com/binary-companion/timetug-shared). The repository is public, one root `Package.swift` (package name `timetug-shared`, products `TimeTugCore` and `CalendarBridge`), plain `X.Y.Z` tags, default branch `main`. It depends on `calendar-connectors` by version range and commits `Package.resolved`.
- **License:** MIT plus the Commons Clause, the same text as this repository, holder Binary Companion LLC.
- **Proof of portability:** CI runs `macos`, `linux`, `windows-x64`, `windows-arm64` and `architecture` jobs, all required. Core's 301 tests and Bridge's 13 run on both Windows architectures; a test-count floor and a per-run minimum fail a job that silently runs too few tests. Swift is installed on the Windows runners by a script in the repository (pinned version, verified checksum) because the organization's Actions policy allows only GitHub-owned actions.
- **Releases:** every merge to `main` releases automatically, the `semver:*` labels pick the version, as in `calendar-connectors`. `1.0.0` was tagged on 2026-10-15 after all five jobs were green; `1.0.1` followed the same day (a CI-only change).
- **Consumption:** this repository pins the package with `exactVersion` in `Apps/macOS/project.yml` (key `TimeTugShared`, 1.0.0 today); `Packages/AppleIntelligenceInference` depends on it by URL with `from: "1.0.0"`. `EventKitSource` and `CalendarApple` do not use Core and are unchanged. The two in-repo packages and `scripts/benchmarks/run-dedup.sh` are deleted here.
- **Pin tooling:** `scripts/ci/check-shared-pins.py`, `scripts/ci/bump-pin.sh` and `scripts/dev/use-local-library.sh` take a library argument (`calendar-connectors` or `timetug-shared`) and apply the same rules to each: released-form URL only, floor at or below the pin within one major, nothing else in `project.yml` naming a library.
- **Required checks here:** `core`, `app`, `dmg` and `architecture`. The `core-linux` job moved to the new repository as `linux`, so the owner's pending item to make it required in this repository is dropped.

## Consequences

- A change to Core or Bridge is a pull request in `timetug-shared`, a release there, and a bump pull request here (see the `working-across-timetug-repos` skill). The local override is `scripts/dev/use-local-library.sh timetug-shared <path>`.
- The Core and Bridge tests no longer run in this repository's CI. Their evidence is `timetug-shared`'s CI, which also covers Linux and Windows.
- The Tests tree of `1.0.0` differs from the removed copy in exactly one file, `CalendarStoreInferenceTests.swift`: the timing test `disablingInferenceDiscardsAnInFlightVerdict` waited a fixed 10 ms against a 50 ms fake and failed about half the runs on Windows ARM64, so it now waits on the adjudicator through a gate. No source file changed; the `Sources` trees and the benchmark are identical.
- The automatic chain for `timetug-shared` is planned and follows in separate pull requests: its release notifying this repository, a generalized `bump-dependencies.yml`, and a bump workflow in `timetug-shared` for `calendar-connectors` releases (which edits `Package.resolved`). Until it is proven by a drill, a `timetug-shared` bump is made by hand with `bump-pin.sh`. The bump bot key for `timetug-shared` is an owner step. The Docker Hub read-only pull token is an organization secret visible to `timetug`, `calendar-connectors` and `timetug-shared`.
- The `timetug-shared` bump pull request raises the `calendar-connectors` pin here to at least the version that release was tested with, so the app and the engine run the same connector version.

## References

- [Phase 2 design](../superpowers/specs/2026-10-15-phase-2-timetug-shared-design.md) and [plan](../superpowers/plans/2026-10-15-phase-2-timetug-shared.md).
- [ADR 0012](0012-calendar-connector-library.md): the connector library and its extraction (phase 1); [ADR 0002](0002-core-source-app-boundaries.md): the layering, unchanged.
