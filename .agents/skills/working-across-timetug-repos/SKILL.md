---
name: working-across-timetug-repos
description: Use when a change spans a shared library and the Mac app, when the connector library (binary-companion/calendar-connectors) or Core and Bridge (binary-companion/timetug-shared) must change, when testing unreleased library code in the app, when a "Bump calendar-connectors" pull request appears, or when a library release did not produce a bump pull request.
---

# Working across the TimeTug repositories

Two libraries live outside `timetug` (public, released as plain `X.Y.Z` tags, which are immutable and created only by each library's own Release workflow):

- `binary-companion/calendar-connectors` (MIT): the connector library.
- `binary-companion/timetug-shared` (MIT plus the Commons Clause): `TimeTugCore` and `CalendarBridge`, with their tests and the dedup benchmark. It depends on `calendar-connectors` by range and commits `Package.resolved`; its CI runs on macOS, Linux, Windows x64 and Windows ARM64.

`timetug` pins a released `X.Y.Z` of each in `Apps/macOS/project.yml` (`exactVersion`, keys `CalendarConnectors` and `TimeTugShared`); the local packages say `from:`.

## Change the connector library

1. Work in a checkout of `calendar-connectors`. Branch, change, `swift test`, `scripts/ci/check-architecture.sh`.
2. To try the change in the app before it is released: in `timetug`, run `scripts/dev/use-local-library.sh calendar-connectors <path to a checkout named calendar-connectors>` (`scripts/dev/use-local-connectors.sh <path>` is the same command), build and test, then `scripts/dev/use-local-library.sh --restore` (it is hash-guarded; `--force` discards edits made during the override). `scripts/ci/check-shared-pins.py` fails while the override is in place, so it cannot be committed. One override at a time.
3. Open the library pull request with one label: `semver:major` (breaks `docs/api.md`), `semver:minor` (new API) or `semver:patch` (the default). The labels of every pull request since the latest tag are considered. The owner merges.

## A change in Core or Bridge

1. Work in a checkout of `timetug-shared`. Branch, write the failing test first, change, `swift test`, `scripts/ci/check-architecture.sh`. Core never reads the clock (`now: Date` is passed in) and imports only Foundation and `CalendarCore`.
2. To try the change in the app before it is released: in `timetug`, run `scripts/dev/use-local-library.sh timetug-shared <path to a checkout named timetug-shared>`, build and test (`xcodegen generate`, then the app tests), then `scripts/dev/use-local-library.sh --restore`. Same guards and refusal rules as above; never commit the result.
3. Open the `timetug-shared` pull request with one `semver:*` label as above. CI there must pass on all four platforms. The owner merges; the merge releases `X.Y.Z` automatically.
4. A bump pull request in `timetug` ("Bump timetug-shared to X.Y.Z") moves the `TimeTugShared` pin and also raises the `CalendarConnectors` pin to at least the version recorded in that release's `Package.resolved`. `.github/workflows/bump-dependencies.yml` does exactly that (it reads `Package.resolved` at the `timetug-shared` tag `X.Y.Z`, fails loudly when the tag has none or no connector version pin, runs `bump-pin.sh timetug-shared X.Y.Z` and then `bump-pin.sh --at-least calendar-connectors <that version>`, so a connector pin is never lowered). A `timetug-shared` release triggers it on its own: the release workflow's `notify` job dispatches `library-released` (`library` `timetug-shared`) to `timetug`. The chain was proven by a drill on 2026-10-15. If the dispatch did not arrive, start the workflow by hand (`gh workflow run "Bump dependencies" --repo binary-companion/timetug -f library=timetug-shared -f version=X.Y.Z`), or make the same change in an ordinary pull request with the two `bump-pin.sh` commands.
5. App code that needs the change goes in the same bump pull request (or the one that follows it), never before the release exists.

When `calendar-connectors` releases, its `notify` job dispatches to both `timetug` and `timetug-shared`. `timetug-shared` opens "Bump calendar-connectors to X.Y.Z" (its `.github/workflows/bump-dependencies.yml` edits `Package.resolved` through `scripts/ci/bump-resolved.py`; the owner merges and that releases a new `timetug-shared`). `timetug` also opens its own connector bump straight away; when the `timetug-shared` release arrives, the "Bump timetug-shared" pull request moves both pins (the connector pin to at least the version recorded in that release) and closes the earlier connector bump as superseded. Drill 2026-10-15: `calendar-connectors` 1.0.5 produced timetug#110 and timetug-shared#7; merging #7 released `timetug-shared` 1.0.5 ("Built and tested with calendar-connectors 1.0.5"), which produced timetug#112 and closed #110 and #111 (the `timetug-shared` 1.0.4 bump) as superseded.

## What happens after a `calendar-connectors` merge

1. The library's Release workflow tags `X.Y.Z` and publishes release notes.
2. Its `notify` job (environment `bump`) mints a `timetug-bot` token and sends `repository_dispatch` `library-released` to `timetug`.
3. `.github/workflows/bump-dependencies.yml` (environment `bump`) checks the library name and version, runs `scripts/ci/bump-pin.sh calendar-connectors X.Y.Z` and opens "Bump calendar-connectors to X.Y.Z" with the release notes. It is opened with the app token, so CI runs on it.
4. CI proves the app against the new version. The workflow never merges; the owner merges. If the change needs app code in the same step, you can push that code to the bump pull request's branch (`bump/calendar-connectors-X.Y.Z`); CI runs again on the branch. This has not been exercised on a real bump yet.
5. A newer bump closes the open bump pull requests of the same library for lower versions (comment "Superseded by #N", branch deleted). A `timetug-shared` bump that carried the connector pin also closes the open `bump/calendar-connectors-*` pull requests at or below that connector version.

`bump-pin.sh <library> X.Y.Z` always sets `exactVersion` for that library in `Apps/macOS/project.yml` and never touches the other library's pin. It raises the library's `from:` floors in `Packages/*/Package*.swift` only on a major bump; raise a floor by hand only when the code needs the new version, and keep every floor at most the pin and within one major (`scripts/ci/check-shared-pins.py`, which checks both libraries). `--at-least` makes it a no-op when the pin is already at or above the version.

## When a bump does not arrive

- Run the workflow by hand: `gh workflow run "Bump dependencies" --repo binary-companion/timetug -f library=<calendar-connectors|timetug-shared> -f version=X.Y.Z`.
- In `timetug-shared`, a missed connector bump is recovered the same way: `gh workflow run "Bump dependencies" --repo binary-companion/timetug-shared -f version=X.Y.Z` (connector versions only; the workflow there has no `library` input).
- If a library's `notify` job failed, re-run that job alone from the library's Actions page. Both libraries hold the `timetug-bot` credentials in their `bump` environments; a `notify` job that fails at the token step means the key or the installation needs the owner.
- The workflow is idempotent: with the pin already at the version, or a pull request already open for it, it opens nothing. A leftover `bump/<library>-X.Y.Z` branch with no open pull request (an earlier run pushed it but could not open the pull request) is used: the workflow opens the pull request from it.

## Rules

- Never tag or release a library by hand.
- Never edit `exactVersion` by hand; only `scripts/ci/bump-pin.sh <library> <X.Y.Z>` moves it. Raise a `from:` floor by hand only when the code needs the new version.
- Platform adapters (`CalendarApple`, `EventKitSource`, `AppleIntelligenceInference`) stay in `timetug`; they implement the libraries' seams.
- The library's iCloud smoke test runs from a library checkout; the Google and Microsoft smoke tests run from timetug's `Packages/CalendarApple` (see `running-live-calendar-tests`).
- The agent never merges or publishes. The owner merges library and bump pull requests and publishes Mac releases.
