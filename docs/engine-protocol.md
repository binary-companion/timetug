# The engine's C interface and message contract

The Windows app (and any other non-Swift front end) runs the same `TimeTugEngine` as the Mac app through four C functions that exchange UTF-8 JSON. This page is the short guide; the design of record is `docs/superpowers/specs/2026-10-15-phase-4-engine-c-interface-design.md`. The code lives in `binary-companion/timetug-shared`.

## The ABI

`include/timetug_engine.h` declares exactly four functions: `tt_engine_create`, `tt_engine_send`, `tt_engine_reply`, `tt_engine_destroy`. Rules the engine keeps: `send` and `reply` never block; callbacks are serialized and ordered; no callback runs after `destroy` returns; `NULL`, stale and repeated handles are ignored; `destroy` from inside a callback is supported.

## The contract (v1)

Envelope: `{"v":1,"type":...,"id":...,"payload":...}`. Replies to host-service requests are `{"v":1,"result":...}` or `{"v":1,"error":{"kind":"network|cancelled|notFound|denied|failed","message":...}}`. Readers ignore unknown fields; a breaking change bumps `v` and the package major version.

Message types, one golden fixture each in `Conformance/Fixtures/golden/`:

- Host to engine: `start`, `refresh`, `account.add`, `account.reconnect`, `account.remove`, `account.cancel`, `settings.apply`, `countdown.visible`, `takeover.presented`, `takeover.closed`, `takeover.join`, `takeover.dismiss`, `takeover.snooze`, `takeover.test`, `dedup.merge`, `dedup.unmerge`, `dedup.separate`, `dedup.forget`, `system.event`, `test.advanceClock` (testing only).
- Engine to host: `ready`, `state`, `event.takeoverDue`, `event.takeoverWithdrawn`, `event.widgetSnapshot`, `event.joinRequested`, `event.diagnostic`.
- Host services the engine requests: `service.credentials.{get,set,remove,snapshot,updateRefreshToken}`, `service.http.send`, `service.auth.{beginRedirect,authorize,closeRedirect,promptCredentials}`, `service.signIn.{prepare,lastNonSecretValues}`, `service.text.{availability,generate}`.

## Tests that guard it

- Swift: `swift test` in `timetug-shared` (protocol round trips, lifecycle and race tests, the ten JSON scenarios in `Conformance/Scenarios/` run through the real C functions).
- C: `c-smoke/` builds a C program against the header on macOS, Linux and Windows.
- C#: `dotnet test dotnet/TimeTug.Engine.sln`, which deserializes the same golden fixtures and runs the same scenarios through P/Invoke against the real native library, on Windows x64 and ARM64 (and macOS and Linux).

## The package

`TimeTug.Engine` on nuget.org, version equal to the `timetug-shared` tag: native assets for `win-x64` and `win-arm64` with the Swift runtime DLLs, the managed wrapper (`net8.0`), the header and the fixtures. About 27 MB compressed per architecture (`docs/spikes/2026-10-phase-4-package-size.md`). The `publish-nuget` job in `release.yml` pushes it with nuget.org trusted publishing and reports a notice instead of failing while the repository variable `NUGET_USER` is unset.
