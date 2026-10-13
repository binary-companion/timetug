---
name: working-across-timetug-repos
description: Use when a change spans the connector library and the Mac app, when the connector library (binary-companion/calendar-connectors) must change, when testing unreleased library code in the app, when a "Bump calendar-connectors" pull request appears, or when a library release did not produce a bump pull request.
---

# Working across the TimeTug repositories

The connector library is `binary-companion/calendar-connectors` (public, MIT). `timetug` pins a released `X.Y.Z` of it. Library tags are immutable and are created only by the library's own Release workflow.

## Change the library

1. Work in a checkout of `calendar-connectors`. Branch, change, `swift test`, `scripts/ci/check-architecture.sh`.
2. To try the change in the app before it is released: in `timetug`, run `scripts/dev/use-local-connectors.sh <path to a checkout named calendar-connectors>`, build and test, then `scripts/dev/use-local-connectors.sh --restore` (it is hash-guarded; `--force` discards edits made during the override). `scripts/ci/check-shared-pins.py` fails while the override is in place, so it cannot be committed.
3. Open the library pull request with one label: `semver:major` (breaks `docs/api.md`), `semver:minor` (new API) or `semver:patch` (the default). The labels of every pull request since the latest tag are considered. The owner merges.

## What happens after the merge

1. The library's Release workflow tags `X.Y.Z` and publishes release notes.
2. Its `notify` job (environment `bump`) mints a `timetug-bot` token and sends `repository_dispatch` `library-released` to `timetug`.
3. `.github/workflows/bump-dependencies.yml` (environment `bump`) runs `scripts/ci/bump-pin.sh X.Y.Z` and opens "Bump calendar-connectors to X.Y.Z" with the release notes. It is opened with the app token, so CI runs on it.
4. CI proves the app against the new version. The owner merges; the bot never does. If the change needs app code in the same step, push that code to the bump pull request's branch.

`bump-pin.sh` always sets `exactVersion` in `Apps/macOS/project.yml`. It raises the `from:` floors in `Packages/*/Package*.swift` only on a major bump; raise a floor by hand only when the code needs the new version, and keep every floor at most the pin and within one major (`scripts/ci/check-shared-pins.py`).

## When a bump does not arrive

- Run the workflow by hand: `gh workflow run "Bump dependencies" --repo binary-companion/timetug -f version=X.Y.Z`.
- If the library's `notify` job failed, re-run that job alone from the library's Actions page.
- The workflow is idempotent: with the pin already at the version, or a pull request already open for it, it does nothing. A leftover `bump/calendar-connectors-X.Y.Z` branch with no open pull request must be opened or deleted by hand.

## Rules

- Never tag or release the library by hand, and never edit `exactVersion` or a `from:` floor by hand outside the cases above (`scripts/ci/bump-pin.sh <X.Y.Z>`).
- Platform adapters (`CalendarApple`, `EventKitSource`, `AppleIntelligenceInference`) stay in `timetug`; they implement the library's seams.
- Library tests that need real accounts run from the library checkout (see `running-live-calendar-tests`).
- The agent never merges or publishes. The owner merges library and bump pull requests and publishes Mac releases.
