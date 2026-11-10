# 0022: The shared libraries are rewritten in Rust

Status: accepted, 2026-11-10. Spec: [Rust engine program design](../superpowers/specs/2026-11-10-rust-engine-program-design.md). Tracker: [Rust engine program](../superpowers/plans/2026-11-10-rust-engine-program-tracker.md).

## Context
`calendar-connectors` (about 11,000 lines) and `timetug-shared` (about 6,500 lines) are Swift packages. The Windows app loads the engine through a C interface, so the published `TimeTug.Engine` 1.8.1 package carries the Swift runtime: its `win-x64` native payload is 74.6 MB uncompressed (73.1 MB on `win-arm64`), of which about 13 MB is the engine and most of the rest is the Swift runtime and Foundation (`_FoundationICU.dll` alone is 36.5 MB). The owner plans more platforms (Linux, iOS, Android, more desktop) and wants one core engine that is as small and light as possible on all of them.

## Decision
- Rewrite both libraries in Rust as file-for-file ports, one crate per Swift product (design section 6.1). The Swift source at the baseline tags (`calendar-connectors` 1.2.0, `timetug-shared` 1.8.1) is the specification.
- Keep the apps native: the Mac app stays Swift and SwiftUI, the Windows app stays C#. Only the shared libraries change language.
- Keep the existing C interface (four functions) and wire protocol v1 unchanged, so the Windows app needs only a package version change. The Mac adopts the engine through UniFFI-generated Swift bindings (phase 5); Kotlin bindings are proven but ship no Android app.
- "Dependency-free" becomes a fixed short list of Rust crates (design section 6.2), enforced in CI by `cargo-deny` and an architecture check. HTTP stays a host seam: the engine contains no TLS.
- Proof of equal behaviour is mechanical: a test-for-test parity table, golden vectors exported from the Swift code, the 74 engine fixtures and 13 scenarios replayed unchanged, and persisted-format round trips.
- Release 2.0.0 of both libraries at the Windows cutover. The Mac stays on the Swift `1.x` branch until phase 6; the Swift libraries are not frozen meanwhile (a parity ledger tracks drift).
- Size gate: at most 8 MB per Windows architecture for the native payload.

## Consequences
- Two languages in the libraries during the transition, and a parity ledger to keep Swift fixes from being lost.
- A crate allow-list replaces "no dependencies"; adding a crate is a decision recorded in the conventions.
- No size gain on Apple platforms, where the Swift runtime is part of the OS. The gain is on Windows, Linux and the platforms to come.
- Supersedes in part ADR 0001's statement that the shared code is Swift, and ADR 0012's "dependency-free" connector library; both stay accurate for the `1.x` line. Retired in full in phase 7.
- `timetug` ignores 2.x library releases until phase 6.

## Verified by
| Rule | Check |
|---|---|
| Behaviour equal to the Swift baseline | parity table check, vector replay tests, engine fixtures and scenarios in each library's CI |
| Size within 8 MB per Windows architecture | `docs/rust-port/size.md` in `timetug-shared`, phase 3 gate |
| Crate allow-list and architecture | `cargo deny`, `check-crate-architecture.py`, `check-tokio-features.py` in each library's CI |
| 2.x releases do not reach the Mac early | `scripts/ci/tests/test-bump-major-guard.sh` |
