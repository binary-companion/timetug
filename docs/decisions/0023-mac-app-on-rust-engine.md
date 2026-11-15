# 0023: The Mac app runs on the Rust engine

Status: accepted, 2026-11-15 (the Mac cutover, phase 6 of the [Rust engine program](../superpowers/specs/2026-11-10-rust-engine-program-design.md)). Plan: [phase 6, Mac cutover](../superpowers/plans/2026-11-10-rust-phase-6-mac-cutover.md). Follows [ADR 0022](0022-shared-libraries-in-rust.md).

## Context
Both shared libraries became Rust in 2.0.0 (2026-11-14) and the Windows app moved to them. The Mac app still pinned the Swift 1.x libraries, so every engine fix had to be made twice (a Swift fix on the `1.x` branches for the Mac, a Rust one on `main`), tracked by a parity ledger. The generated Swift package `TimeTugKit` (`timetug-shared` 2.1.1) exposes the Rust engine to Swift with a prebuilt static `TimeTugEngineFFI.xcframework`.

## Decision
- The Mac app and its three local packages import `TimeTugKit` and nothing else of the libraries. `Apps/macOS/project.yml` pins `timetug-shared` 2.x with `exactVersion`; the connectors come inside it, so the `calendar-connectors` pin and `use-local-connectors.sh` are gone.
- The app stays Swift and SwiftUI. Its Apple adapters (EventKit, Keychain, loopback OAuth, URLSession transport, Apple Intelligence, UserDefaults settings, OSLog diagnostics) implement the interfaces UniFFI generates. `AppCoordinator` builds one `Engine` from `AppConnectors.makeConfig` and sends commands and renders state; for every `takeoverDue` it sends exactly one closing command.
- Existing users upgrade in place: the engine reads `connections.json`, `sync-state.json`, the takeover ledger, the dedup state, the UserDefaults settings and the Keychain items as the Swift engine wrote them. Behaviour and appearance do not change; no view, string or setting is added, except the "Third-party notices" link below.
- The engine is statically linked, so the shipped app carries the licence notices of every crate in it (UniFFI is MPL-2.0, accepted by the owner on 2026-11-15; see `docs/licensing.md` of `timetug-shared`). A build phase (`scripts/ci/copy-licence-notices.sh`, both app targets) copies `THIRD-PARTY-NOTICES.md` and `LICENSE` from the resolved XCFramework and KeyboardShortcuts' licence into `Contents/Resources/Licenses/` and fails the build when one is absent. The About window and Settings > General > About have a "Third-party notices" link (owner decision, 2026-11-15; the Windows About has the same) that shows them.
- Privacy manifest: the Rust library uses `stat`-family calls (file timestamps) inside the App Group container, so the app declares `NSPrivacyAccessedAPICategoryFileTimestamp` with reason `C617.1`; it also declares its existing UserDefaults use (`CA92.1`, `1C8F.1`). The engine reads no boot time, disk space or user-defaults API (`docs/rust-port/mac-migration-map.md`, "Task 9 findings").
- Building the app needs no Rust toolchain. Local engine work uses `scripts/dev/use-local-library.sh timetug-shared <checkout>`.
- The release that ships this is a major version: the newest stable tag is `v2.2.1`, so `v3.0.0` (docs/release.md, "Choosing the version"). The version comes from the tag; nothing in the repository is edited to set it. The `1.x` branches of both libraries no longer serve the Mac once it ships.

## Consequences
- One engine on every platform: an engine fix is one Rust change, released as a 2.x version and bumped here by the "Bump timetug-shared" pull request (`bump-major-guard.sh` holds 3.0.0).
- The app bundle grows by the size of the static library and the notices (recorded in the migration map); the Swift runtime is part of the OS, so there is no runtime to ship, as for the other Apple platforms.
- A crash in the engine is a crash of the app (one process); the engine writes only inside the App Group container the host passes, which is what keeps the App Store sandbox intact.
- Supersedes the parts of ADR 0001 and ADR 0012 that make the shared code and the connector library Swift for the Mac; they stay accurate for the retired `1.x` line.

## Verified by
| Rule | Check |
|---|---|
| The app imports only `TimeTugKit` | `scripts/ci/check-architecture.sh` and its test |
| One pin, one major | `scripts/ci/check-shared-pins.py`, `scripts/ci/tests/test-bump-major-guard.sh` |
| Upgrade from the Swift engine's data | the synthetic-data upgrade test in the app tests; the "Engine cutover" checklist |
| The notices are in the app | `scripts/ci/tests/test-copy-licence-notices.sh`, `ThirdPartyNoticesTests`, the `app-store-build` CI step, `scripts/release/verify-dmg.sh` |
| App Store sandbox and validation | the sandboxed run and the validation recorded in the migration map |
