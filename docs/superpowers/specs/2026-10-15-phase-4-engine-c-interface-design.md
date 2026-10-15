# Phase 4: the C interface, the contract and the NuGet package

Status: draft for the owner's review (2026-10-15). Parent: [program design](2026-10-09-windows-program-design.md), roadmap row 4 and section 2 ("Two ways in", "Contract"). The program design wins where the two disagree, except for the amendments in "Decisions" below. Predecessors: [phase 3](2026-10-15-phase-3-engine-design.md) (the engine this phase exposes) and [phase 2](2026-10-15-phase-2-timetug-shared-design.md) (the repository, release and bump chain this phase extends). Evidence base: [Spike S](../../spikes/2026-10-09-swift-on-windows.md).

## Purpose

Let any non-Swift front end run the `TimeTugEngine` that the Mac app already runs on. Phase 3 produced a Swift actor with host seams. Phase 4 puts a stable, versioned message contract and a four-function C ABI in front of it, publishes it as a NuGet package with a managed wrapper, and proves the whole path with one conformance suite that runs in Swift and in C# against the real native library.

**Principle (owner, 2026-10-15), unchanged:** the engine decides *what and when*, each front end owns *how it looks and feels*. The contract carries data and intent, never display strings or presentation choices.

Success means:

1. `TimeTugEngineC` builds as a native library on macOS, Linux, Windows x64 and Windows ARM64, and a C program drives it through the four functions.
2. The message contract is fully specified by golden JSON fixtures that round-trip in Swift and in C#.
3. One set of scenario files runs through the C ABI from Swift and from C# (against the real DLL on both Windows architectures) with identical expected states and events.
4. A `timetug-shared` release builds and publishes the `TimeTug.Engine` package, with no stored publishing key.
5. The Mac app is untouched: it still calls the Swift API directly.

## Not in this phase

- No Windows application, tray, overlay, settings UI, Credential Locker, `HttpClient` transport or WAM code (phases 5 and 6). The C# test host in this phase is test code.
- No external-token connector mode (phase 6) and no Windows AI text generator (phase 8). The contract leaves room for both as additive messages.
- No change to `TimeTugEngine`'s Swift API or behaviour, with one exception: a file-backed `SettingsStorage` is added (see Decisions).
- No Mac change, and no Mac release.

## Decisions

| Topic | Decision |
|---|---|
| ABI | Exactly the four functions of the program design (`tt_engine_create`, `tt_engine_send`, `tt_engine_reply`, `tt_engine_destroy`), UTF-8 JSON, cdecl, plus one shipped header `timetug_engine.h`. No fifth function: version and capabilities arrive in the first message (`ready`). |
| Wire types are separate from engine types | `TimeTugEngineProtocol` defines its own Codable DTOs and maps to and from engine and Core types. Core types are not made Codable for the wire. Reason: the wire format must evolve on its own schedule (a breaking change bumps `v` and the major version); Core's persisted formats (ledger, settings) are already fixed by shipped Mac apps; `TimeTugCalendarEvent` and `DayAgenda` carry Swift-only shapes. |
| Commands by identity | Commands that carry whole events in Swift (`merge`, `unmerge`, `separate`) carry event ids on the wire. The bridge resolves them against the latest state it has published. An id that is no longer present produces a `diagnostic` carrying the command's `id`; the host retries after the next `state`. |
| Settings | `applySettings` takes a patch on the wire (every field optional; absent means unchanged), applied atomically by the bridge. Persistence in the C ABI is engine-owned: a `FileSettingsStorage` writes `settings.json` in the data directory (atomic replace, corrupt file loads defaults and emits a `diagnostic`). Windows has no shared preference store to adapt, and a host callback per settings read adds latency and failure modes for nothing. The Swift API and the Mac adapter are unchanged. |
| Time | The engine's default `SystemClock` is used. Time zone and calendar come from Foundation; the host may pass an IANA `timeZone` in the config and a new one with a `timeZoneChanged` system event, because Foundation on Windows is not yet verified to follow the Windows zone setting (risk below). |
| Test hooks | A config flag `testing: true` swaps in a manual clock and enables a `test.advanceClock` command and the in-process fake text generator. Without the flag the command is rejected with a `diagnostic`. The hooks are runtime-gated, not a separate build, so the DLL that is tested is the DLL that ships. |
| Conformance | Scenarios are JSON files (host script plus expectations) in `Conformance/Scenarios/`, run by a Swift runner and a C# runner against the same C ABI. They extend, and do not replace, the phase 3 Swift conformance suite that drives `Engine` directly. |
| Package | One NuGet package, `TimeTug.Engine`, version equal to the `timetug-shared` tag. Contains native assets for `win-x64` and `win-arm64` (the engine library plus the Swift runtime DLLs it needs), the managed wrapper (single target `net8.0`, source-generated `System.Text.Json`, trimming and AOT safe), the header and the golden fixtures. |
| Publishing | A `publish-nuget` job in the existing release workflow, on Windows runners (x64 and ARM64), using nuget.org trusted publishing (OIDC) from the `publish` environment. Skipped, with a notice and not a failure, while the owner has not configured the nuget.org trusted-publisher policy. Runs on every `timetug-shared` release, so the package version always equals the tag and a consumer can pin any released version. |
| Compressed size | Measured and recorded in this phase (the nupkg and a per-architecture zip of the native set, as a stand-in for the MSIX that phase 5 builds). Avoiding `FoundationInternationalization` (ICU is 36.2 MB of 57.4 MB) becomes work in this phase only if the compressed native payload for one architecture exceeds 40 MB; otherwise it stays a recorded option. |

## Modules and layout

```
timetug-shared/
  Package.swift                      # adds TimeTugEngineProtocol (library), TimeTugEngineC (dynamic library)
  include/timetug_engine.h           # the C declarations, shipped in the package
  Sources/TimeTugEngine/Persistence/FileSettingsStorage.swift
  Sources/TimeTugEngineProtocol/
    Envelope.swift                   # {"v","type","id","payload"}, decode and encode, version handling
    CommandMessages.swift            # host -> engine DTOs and mapping to EngineCommand
    StateMessages.swift              # state, events and their DTOs, mapping from engine types
    ServiceMessages.swift            # engine -> host requests and the reply shapes
    Config.swift                     # tt_engine_create config
  Sources/TimeTugEngineC/
    CInterface.swift                 # the four @_cdecl functions
    EngineSession.swift              # owns the Engine, message pumps, request table, lifecycle
    RemoteHostServices.swift         # CredentialStore, HTTPTransport, AuthorizationInteraction,
                                     #   SignInPrompting, TextGenerator implemented as requests
  Tests/TimeTugEngineProtocolTests/  # round-trip, versioning, golden fixtures
  Tests/TimeTugEngineCTests/         # C ABI behaviour, lifecycle, scenario runner
  Conformance/
    Fixtures/golden/*.json           # one file per message type plus edge cases
    Scenarios/*.json                 # scripted host, steps, expectations
  c-smoke/                           # a C program using only the header
  dotnet/
    TimeTug.Engine/                  # managed wrapper
    TimeTug.Engine.Tests/            # golden round-trip and the scenario runner against the DLL
    pack/                            # scripts that assemble the nupkg
```

`TimeTugEngineProtocol` imports Foundation, `TimeTugCore`, `CalendarBridge` and `TimeTugEngine` only. `TimeTugEngineC` adds nothing platform-specific; it is the only module with `@_cdecl`. The architecture check gains two rules: the protocol module never exposes a Core or engine type in a public signature, and nothing outside `TimeTugEngineC` uses `@_cdecl`.

## The ABI

```c
typedef void (*tt_message_fn)(void *context, const char *message_json);

tt_engine *tt_engine_create(const char *config_json, tt_message_fn on_message, void *context);
void       tt_engine_send(tt_engine *, const char *command_json);
void       tt_engine_reply(tt_engine *, uint64_t request_id, const char *reply_json);
void       tt_engine_destroy(tt_engine *);
```

- **Strings** are NUL-terminated UTF-8. A string passed to `on_message` is valid for the duration of that call; the host copies what it keeps. The engine copies what it keeps from `send` and `reply` before they return.
- **`create`** parses the config, builds the engine and returns a handle without starting it. It returns `NULL` for a config that is not valid JSON or fails validation (no callback is made). The host then sends `start`; the first callback is `ready`.
- **`send` and `reply` never block** and may be called from any thread, including from inside `on_message`. They enqueue.
- **Callbacks are serialized**: one delivery task, one message at a time, in order. They arrive on an engine thread; the host moves them to its UI thread.
- **`destroy`** cancels the engine and fails every pending host-service request with `cancelled`. Called from outside a callback it also waits for the delivery task to finish, and no callback runs after it returns. Called from inside a callback (the managed wrapper's event handlers can do this) it is supported: it cancels, does not wait, returns at once, and no further callback starts after the current one returns. The handle is invalid after `destroy`; handles are opaque tokens looked up in a registry, so `NULL`, an already-destroyed handle and a second `destroy` are detected and ignored by `send`, `reply` and `destroy` alike, as is a `reply` for a request id that is unknown or already answered. A `send` racing with `destroy` is either processed before cancellation or dropped, never undefined. One engine per data directory; several engines in one process are allowed, so the engine and bridge hold no process-global mutable state.
- **State** snapshots coalesce: if the host is slow, intermediate `state` messages are dropped and the latest wins, as `EngineState.revision` allows. **Events and service requests are never dropped or reordered.**
- **Unknown input never crashes**: invalid JSON, an unknown `type`, a wrong `v` or a bad payload yields a `diagnostic` event (with the command `id` when it parsed), not a trap.

## The message contract (v1)

Envelope: `{"v":1,"type":"<name>","id":<number or string, optional>,"payload":{...}}`. The host may set the envelope `id` of a command (a number or a string); the engine echoes it as the envelope `id` of any `event.diagnostic` the command causes. The engine sets the envelope `id` of a service request to a `uint64`, which the host passes back to `tt_engine_reply`. Readers ignore unknown fields (so adding a field is not breaking) and the engine ignores a host message type it does not know with a `diagnostic`. A removed or retyped field, or a changed meaning, is breaking: it bumps `v` and the package major version, and `ready` lists the versions the engine speaks.

Values: instants are ISO 8601 UTC strings with millisecond precision; durations are seconds; all-day events carry calendar dates (`YYYY-MM-DD`) and the event's own zone id, matching phase 2.5; ids are the library's strings; enums are lower-camel strings; no display strings anywhere.

**Host to engine (commands)**

| `type` | Payload | Maps to |
|---|---|---|
| `start`, `refresh` | none | `start`, `refresh` |
| `account.add` | `kindID` | `addAccount` |
| `account.reconnect` | `connectionID` | `reauthorizeAccount` |
| `account.remove` | `connectionID` | `removeAccount` |
| `account.cancel` | none | `cancelAuthorization` |
| `settings.apply` | settings patch | `applySettings` |
| `countdown.visible` | `visible` | `setCountdownVisible` |
| `takeover.presented` | `eventID`, `onScreen` (false means the front end fell back to a toast) | `takeoverPresented` |
| `takeover.closed` | `eventID` | `takeoverClosed` |
| `takeover.join`, `takeover.dismiss` | `eventID` | `join`, `dismiss` |
| `takeover.snooze` | `eventID`, `seconds` | `snooze` |
| `takeover.test` | `title`, `calendarTitle` | `testTug` |
| `dedup.merge` | `eventIDs` (two) | `merge` |
| `dedup.unmerge` | `eventID` | `unmerge` |
| `dedup.separate` | `eventID`, `memberIDs` | `separate` |
| `dedup.forget` | none | `forgetCorrections` |
| `system.event` | `kind` (`wake`, `clockChanged`, `timeZoneChanged`, `dayChanged`, `networkReturned`, `displayChanged`), optional `timeZone` | `system` |
| `test.advanceClock` | `seconds` (testing only) | the manual clock |

`settingsChangedExternally` is Mac-only (widget and Control Center edits) and is not on the wire. `stop` is `tt_engine_destroy`.

**Engine to host (messages)**

| `type` | Payload |
|---|---|
| `ready` | `engineVersion`, `protocolVersions`, `platform`, `capabilities` (for example `systemCalendar: false`) |
| `state` | the whole `EngineState`, field for field: `revision`, `agenda`, `events` (a merged event lists its members by event id and source), `calendars`, `statuses`, `notices`, `sourceNames`, `candidates` (the pending duplicate pairs, as lists of event ids resolved in `events`), `accounts`, `accountStatus`, `settings`, `inferenceStatus`, the takeover `ledger`, `nextTakeover`, `takeoverVisible`, `availableAccountKinds`. A test asserts that every stored property of `EngineState` has a wire field, so a later engine field cannot be forgotten. |
| `event.takeoverDue` | takeover request DTO, `calendarTitle` |
| `event.takeoverWithdrawn` | `eventID` |
| `event.widgetSnapshot` | widget snapshot DTO |
| `event.joinRequested` | `url` (the host opens it with its own safe-open policy) |
| `event.diagnostic` | `level`, `category`, `message` (never calendar content); the envelope `id` is the causing command's, when there is one |

**Host services (engine to host requests; the host answers with `tt_engine_reply`)**

A request is `{"v":1,"type":"service.<name>","id":<uint64>,"payload":{...}}`. A reply is `{"v":1,"result":{...}}` or `{"v":1,"error":{"kind":"network|cancelled|notFound|denied|failed","message":"..."}}`; its request is identified by the `request_id` argument of `tt_engine_reply`, so it carries no `id` of its own, and its `v` follows the same versioning rule as every other message. Replies may arrive in any order and concurrently.

| Service | Requests | Notes |
|---|---|---|
| Credentials | `service.credentials.get`, `.set`, `.remove`, `.snapshot`, `.updateRefreshToken` | The last is a compare-and-set on a revision and must be atomic in the host. |
| HTTP | `service.http.send` | Request: method, url, headers, base64 body. Reply: status, headers, base64 body. 4xx and 5xx are results; transport failures are `network` errors. The engine times a request out after 60 seconds. |
| Sign-in (browser) | `service.auth.beginRedirect`, `.authorize`, `.closeRedirect` | `beginRedirect` returns a session id and the redirect URI; `authorize` carries the URL and returns the redirect URL; no timeout (a person is involved) except `account.cancel` or `destroy`. |
| Sign-in (form) | `service.auth.promptCredentials`, `service.signIn.prepare`, `service.signIn.lastNonSecretValues` | Field descriptions carry identifiers and help keys, not display strings. |
| Text generation | `service.text.availability`, `service.text.generate` | Present only when `config.textGeneration` is true. |

The golden fixtures contain one file per message type above (v1), and at least one file for each edge class: all-day event, event with no conference link, source in each status, settings patch with every field and with none, reply error of each kind, unknown field (ignored), unknown type, `v` not 1.

## Config

`tt_engine_create` takes `{"v":1,"dataDirectory":...,"platform":"windows","connectors":{...},"textGeneration":false,"timeZone":null,"testing":false}`.

`connectors` carries the OAuth client ids the host build has (Google, Microsoft). The engine registers the library's connector kinds for the platform; a kind without a client id is listed in `availableAccountKinds` as unconfigured, exactly as on Mac. `platform` is `windows`, `linux` or `macos` and selects which kinds apply. Through this ABI the engine never has a system-calendar source (`buildSystemSource` and `requestSystemAccess` are absent on every platform), so `ready` always reports `capabilities.systemCalendar: false`. Mac EventKit is reachable only through the Swift API.

`availableAccountKinds` keeps each kind's `id`, `authorization` and `isConfigured`, and its `displayName` as the provider's product name ("Google", "Microsoft"), which is not localized; a front end that localizes keys its own labels on the `id`. `takeover.test` and `event.takeoverDue`'s `calendarTitle` carry host-supplied or calendar-supplied text, which is data, not a display string the engine composed.

## The managed wrapper

`TimeTug.Engine` exposes `IEngine` (create, `SendAsync(command)`, `State` and `Events` as `IAsyncEnumerable`, `DisposeAsync`), records for every message generated to match the fixtures, and `IEngineHost` with one small interface per service (`ICredentialStore`, `IHttpTransport`, `IAuthorizationInteraction`, `ITextGenerator`, `IDiagnosticsSink`). It owns the P/Invoke to the four functions, the unmanaged callback and its lifetime (a pinned delegate held for the engine's life), UTF-8 marshalling and request correlation. It raises on the engine thread unless `EngineOptions.Dispatcher` is given. No scheduling, dedup or settings logic lives in it.

## Building and packaging

- `TimeTugEngineC` is a dynamic library product. On Windows the build uses `swift build --show-bin-path`, never `.build\release` (Spike S: no symlink rights).
- A script computes the runtime closure of the DLL (the `dumpbin /dependents` walk from Spike S, automated) and copies exactly those Swift runtime DLLs next to it. The C runtime DLLs are not bundled; the app package takes them from the Visual C++ runtime framework.
- The `publish-nuget` job builds both architectures on native runners (`windows-latest`, `windows-11-arm`), assembles `runtimes/win-x64/native` and `runtimes/win-arm64/native`, builds the wrapper, runs the C# tests against the freshly built DLL on each architecture, packs, and pushes with `--skip-duplicate` so a re-run is safe.
- nuget.org versions are immutable. A bad release is superseded by the next patch; the old version is unlisted, not deleted.

## Testing

- **Protocol unit tests**: every DTO mapping both ways; envelope handling of unknown fields, unknown types and `v`; golden fixtures decode and re-encode to the same parsed JSON value (never compared as bytes, because Foundation escapes `/` and orders keys only on request); a test that fails when a message type exists without a fixture.
- **C ABI tests (Swift)**: lifecycle (create, start, destroy, destroy with a pending request, create returns `NULL` for bad config), no callback after destroy, serialized delivery, state coalescing, event ordering under a slow callback, host-service timeout, many engines in one process.
- **Conformance scenarios**, each a JSON file with a scripted host (canned HTTP replies by URL pattern, credential and sign-in answers, text-generation answers), steps (commands, clock advances, system events) and expectations (subset match on state and on the ordered event list): start and `ready`; add an account through the browser sign-in; refresh and takeover due after a clock advance; snooze then re-fire; late takeover after `wake`; settings patch persisted across destroy and create; invalid command yields a `diagnostic`; host never answers an HTTP request (timeout, source status `failing`, other sources unaffected); destroy while sign-in is pending.
- **C smoke**: a C program built against the header with the system C compiler, on macOS, Linux and Windows, creating an engine, reading `ready`, sending `start` and `refresh`, and destroying it.
- **C# tests**: golden round-trips, then the scenario runner through P/Invoke against the real DLL, on Windows x64 and ARM64. The Windows test-count guard learns the C# test count too.
- The existing CI jobs (macOS, Linux, Windows x64, Windows ARM64, architecture) stay required; the C# jobs are added to the required set once they have run green on both architectures.

## Sequence

1. `FileSettingsStorage` and the protocol module with the envelope, DTOs, mappings and golden fixtures (the engine is unchanged otherwise).
2. `TimeTugEngineC`: session, pumps, remote host services, the four functions, the header, the C smoke test and the Swift scenario runner with its first scenarios.
3. The remaining scenarios and the lifecycle and robustness tests.
4. The managed wrapper, the C# tests and the C# scenario runner on both Windows architectures.
5. Packaging scripts, the `publish-nuget` job, size measurement and the findings note (`docs/spikes` style, recorded in the tracker).
6. A `timetug-shared` release (semver minor) carries all of it; the bump chain opens a "Bump timetug-shared" PR in `timetug`, which changes nothing for the Mac app and is merged when green. The owner sets up nuget.org trusted publishing; until then the package job reports "skipped".

## Risks

- **Foundation on Windows differs** (time zone, file replace, `Task.sleep`). Phase 3's tests already run there; the scenarios add time zone and the settings file. Mitigation: the optional `timeZone` config and event, tests with a non-UTC zone on both architectures.
- **Callback and actor reentrancy.** A host callback that sends a command synchronously could order state and events surprisingly. Mitigation: `send` only enqueues; one delivery task; scenarios that send from inside callbacks.
- **Lifetime across the boundary** (a callback after destroy, a request answered after destroy). Mitigation: a generation check on every reply and delivery, scenarios for both, and the C smoke test.
- **Package size and per-release publishing.** About 60 MB uncompressed per architecture, published on every release. Mitigation: measurement in this phase, the 40 MB trigger above, and a path filter as a later option only if release frequency makes the volume a problem (it would then have to leave the version-equals-tag rule intact by publishing an unchanged payload under the new version, so it is not free).
- **Export limits and symbol visibility** (Swift 6.1 and later; the DLL also exports mangled public symbols). Spike S found `@_cdecl` working. Mitigation: a test that `dumpbin /exports` (or `nm`) lists the four names, and a fixed Swift toolchain version recorded in the workflow.
- **Wire drift** between the Swift DTOs and the C# records. Mitigation: records are generated from, or checked against, the golden fixtures, and the C# round-trip test fails the build on a mismatch.
- **Trusted-publishing setup is the owner's**, so the first real publish waits on a person. Mitigation: the package is built and fully tested on every qualifying release regardless, and the job's skip is visible.

## Open items for the owner

These are actions, not design questions. Nothing in the design waits on them, but a published package does.

1. Create or confirm the Binary Companion account on nuget.org and reserve the `TimeTug.Engine` id.
2. Add a trusted-publishing policy on nuget.org for `binary-companion/timetug-shared`, workflow `release.yml`, environment `publish`.
