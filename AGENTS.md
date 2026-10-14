# TimeTug agent guide

Start with [current architecture](docs/architecture.md), then [development and verification](docs/development.md). The [original core design](docs/superpowers/specs/2026-09-18-timetug-core-design.md) is historical where later code or [ADRs](docs/decisions/README.md) differ. The shared agent rules cover semantic indexing and Serena; repository-specific task procedures live in [`.agents/skills`](.agents/skills/).

## Boundaries

- `Packages/TimeTugCore` answers what and when. Pass `now: Date`; keep UI, Apple imports and display strings out of Core. Test each Core behavior with Swift Testing, writing the failing test first.
- The connector library is its own repository, [binary-companion/calendar-connectors](https://github.com/binary-companion/calendar-connectors), consumed by released version (`Apps/macOS/project.yml` pins it with `exactVersion`; the local packages say `from:`); to change it, use the `working-across-timetug-repos` skill. It is portable and dependency-free. Its `CalendarCore` model underpins Google, Microsoft, CalDAV, iCal subscriptions and Core. `CalendarOAuth` handles PKCE and refresh. `Packages/CalendarBridge` connects library sources to Core; `EventKitSource` and `CalendarApple` contain Apple adapters. Only `AppleIntelligenceInference` imports Foundation Models.
- `Apps/macOS` composes sources, UI, widgets and Sparkle. `AppConnectors.swift` registers providers; the app owns credentials, source configuration and presentation. The direct and App Store targets share an App Group but must use separate build directories. Keep Sparkle imports inside `#if !APPSTORE`.
- Calendar writes are opt-in through `WritableCalendarSource`; unsupported fields throw `WriteError.unsupported`, and stale versions are resolved per touched field. Microsoft sign-in currently requests read-only scopes under [ADR 0017](docs/decisions/0017-microsoft-read-only-scopes.md); its library write implementation remains. Do not change scopes or capabilities incidentally.
- App state belongs in the App Group; credentials belong in Keychain. Use `AppSupportFiles.url(_:)` for app state and `WidgetSnapshotStore` for the widget snapshot; never construct a path under the real home directory for a sandboxed build. Keep secrets and certificates out of git. Record significant decisions in `docs/decisions/`.

## Repositories

- `calendar-connectors`: the connector library (MIT). Tags `X.Y.Z`, released automatically on every merge to `main`.
- `timetug-shared` (phase 2) and `timetug-windows` (later) join it per the [program design](docs/superpowers/specs/2026-10-09-windows-program-design.md).
- `timetug` (this repository): the Mac app, the Apple adapters and the product website.

A library release sends this repository a "Bump calendar-connectors to X.Y.Z" pull request: the library's `notify` job dispatches to `.github/workflows/bump-dependencies.yml`, which runs `scripts/ci/bump-pin.sh` and opens the pull request as `timetug-bot` so CI runs on it; the owner merges, and the bot never does. The pin is never edited by hand except through `bump-pin.sh`: it always moves `exactVersion` and raises the `from:` floors in the five `Packages/*/Package.swift` only on a major bump. Raise a floor by hand only when the code needs a new version; `scripts/ci/check-shared-pins.py` verifies that every floor is at most the pin and within one major. For work across both repositories, `scripts/dev/use-local-connectors.sh` points the app at a library checkout; never commit its output. The `working-across-timetug-repos` skill has the steps and the recovery when a bump does not arrive.

## Verify

Run `scripts/dev/verify.sh affected` for local changes, or choose `core`, `connectors`, `app`, `release-tools`, or `all`. `affected --base <ref>` includes changes since a base. `scripts/dev/affected-tests.sh` prints the narrower dependency-ordered commands when useful. Logs and a per-run summary go to `build/verify/`. `all` runs package, app and release-tool checks. Linux portability is a required CI job; [manual macOS UI checks](docs/manual-tests/macos-checklist.md) and live provider writes remain separate evidence. The wrapper never enables live tests. See [development](docs/development.md) for prerequisites and checkpoints.

`xcodegen generate --spec Apps/macOS/project.yml` regenerates the ignored Xcode project. `project.yml` owns generated Info.plist properties for both distributions and widgets. Do not discard privacy descriptions, entitlements, OAuth substitutions or Sparkle keys. Use the [operations runbook](docs/development/runbooks/operations.md) and the task skills under `.agents/skills/` for signing, OAuth, widgets, CI and live-test procedures.

## Release boundary

PR CI and website validation do not deploy or sign releases. Merged `site/` changes deploy through Firebase Hosting; beta and release workflows use protected environments after merge. A green local check is not a merge, deployed site or published release. Follow [release rules](docs/release.md) and the [site guide](site/README.md) for deployment and production checks.
