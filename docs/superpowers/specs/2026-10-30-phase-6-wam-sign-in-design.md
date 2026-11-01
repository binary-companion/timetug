# Phase 6: WAM sign-in ("Microsoft account on this PC")

Status: draft for the owner's review (2026-10-30). Parent: [program design](2026-10-09-windows-program-design.md), roadmap row 6 and section 4.5 (the approved design). The program design wins where the two disagree, except for the amendments in "Decisions". Predecessors: [phase 5](2026-10-16-phase-5-windows-app-core-design.md) (the app and its accounts flows), [phase 4](2026-10-15-phase-4-engine-c-interface-design.md) (the contract this phase extends). Facts about MSAL and WAM were checked against Microsoft's documentation (Sources); everything the documentation does not settle is a spike task (slice 0), not an assumption.

## Purpose

Let a Windows user connect the Microsoft account Windows already knows with one native Windows dialog, no browser and no stored refresh token, and keep it connected the way Windows keeps it. Windows owns the tokens, the password, MFA and company policy; TimeTug only asks for short-lived access tokens.

**Principle (owner):** the Mac asks once for calendar access (EventKit) and then the calendars are there. The Windows equivalent is one consent per Microsoft account, asked at first run, after which the calendars are there.

**Anti-goal (owner):** a tug that never appears because a sign-in quietly broke. A broker failure is an account status the person can see and fix ("Sign in again"); it never blocks the engine, the tug or other accounts.

## What the owner will see

1. **First run, no accounts:** the welcome window (phase 5) lists "Microsoft account on this PC" first. One click on it; Windows shows its own dialog asking to let TimeTug read calendars for the Windows account (or an account picker when Windows has none). Allow and the welcome window moves to step 2 as today ("Microsoft, 3 calendars, next: Design review at 2:30 PM"). Decline or close the dialog: nothing is added, no error is shown, the window stays on step 1.
2. **Settings > Accounts > Add an Account:** "Microsoft account on this PC", "Another Microsoft account" (the Windows account picker, which lists every account on the PC and can add one), and the existing "Microsoft" card, relabelled "Microsoft (browser)" when the other two exist. Google, iCloud and CalDAV are unchanged.
3. **When Windows needs the person again** (password changed, MFA or sign-in-frequency policy, consent withdrawn, account removed from Windows): the account's status becomes the existing "Sign in again", the flyout shows its problem row, and "Sign in again" in Settings > Accounts opens the Windows dialog for that account.
4. **When Windows sign-in cannot be used** (broker missing or blocked by policy): the card shows why and a "Use your browser instead" button; the browser flow of phase 5 is unchanged.

## Not in this phase

- Widgets (7), on-device AI (8), Store submission (9). Google, iCloud and CalDAV sign-in. Write scopes: the Microsoft scopes stay read-only (ADR 0017; `check-repository-contracts.py` pins them).
- No change to the Mac app (it only receives bump pull requests) and no change to existing public API, message, fixture or persisted-file meaning. Everything is additive under the backward-compatibility rule.
- iOS (Microsoft Authenticator) and Android (account broker) implementations. Only the library seam is generic enough for them.
- Moving an existing browser-signed-in account to WAM automatically (see D2).

## Facts checked, and what the spike must still prove

Checked in Microsoft's documentation: WAM is reached from .NET through `Microsoft.Identity.Client` plus `Microsoft.Identity.Client.Broker` (MSAL 4.52 or later); `BrokerOptions(BrokerOptions.OperatingSystems.Windows)` with `WithBroker`; a parent window handle is required (`WithParentActivityOrWindow`); `PublicClientApplication.OperatingSystemAccount` signs in silently with the Windows account and throws `MsalUiRequiredException` when that is not possible; `BrokerOptions.ListOperatingSystemAccounts` lets `GetAccountsAsync` list MSA, work and school accounts; with an authority that includes personal accounts WAM shows the system account picker; consent is asked when the app was never used or needs more permission; the registration needs `ms-appx-web://microsoft.aad.brokerplugin/{client_id}` under "Mobile and desktop applications"; WAM supports Microsoft Entra ID and, through the account picker, personal Microsoft accounts, not ADFS or B2C, and must run in an interactive user session; Microsoft's own guidance is to give context first, authenticate on a user action, and try silent before interactive. The native runtime ships as `msalruntime.dll` (with an `msalruntime_arm64.dll` in the NativeInterop package); MSAL issue 3740 (an MSIX that could not find `msalruntime`) was fixed in 4.50 and issue 4974 (sign-in failing in virtual machines) in 4.67 with NativeInterop 0.17.1, so the pin must be at least those.

Not settled by documentation, proved in slice 0 on the Windows 11 ARM VM (and one x64 CI run): the broker package builds and loads inside our `net10.0-windows10.0.22621.0` MSIX on x64 and ARM64 with `msalruntime` present in the package; what `GetAccountsAsync` returns with `ListOperatingSystemAccounts` before consent (for a local-only Windows sign-in, a Windows-sign-in Microsoft account, and a Microsoft account added under Settings > Accounts > Email & accounts); the exact exception and error code of a silent request with no account, with no consent, and after a password change; whether `HomeAccountId.Identifier` is stable across restarts and `GetAccountAsync(id)` finds the account again (fallback: match `Username` to the stored email); whether `WithForceRefresh` is honoured by the broker; whether cancelling the token closes the Windows dialog; whether a hidden owner window can parent the dialog (D3 depends on it).

## Decisions

Owner decisions are marked (O); my calls (C) are open to change.

| Topic | Decision |
|---|---|
| Shape in the library | (C) A second, generic connector kind `microsoft-brokered` in `MicrosoftCalendar`, next to the unchanged `microsoft`; it shares the Graph source and takes its access tokens from a host-supplied `ExternalTokenSource`. Not a mode flag on `microsoft`: `ConnectorKind.authorize` has no way to carry a mode, so a mode flag would need a new engine command or a new public enum case, which the compatibility check can flag. A second kind id needs neither. Cost: switching a mailbox between modes is remove and re-add (D2). |
| Auth mode in the record | (C) The `kindID` (`microsoft-brokered`) is authoritative; the connection's `config` also carries `authMode: "external"` and `externalAccountID` (the host's opaque account id; for MSAL its home account id) so a reader needs no knowledge of kind ids. No secret is stored for such a connection. |
| Engine message kinds | (C) Three new host-service requests, `service.token.get` (silent, never shows UI, 60 s engine timeout), `service.token.signIn` (interactive, no timeout, ended by `account.cancel`) and `service.token.cancelSignIn` (best effort, like `closeRedirect`). "Interaction required" is a result status, not a new error kind (new error kinds would add a case to a public enum). |
| Opt-in | (C) Like text generation: a config flag `externalTokens` (default false) set by the host when it provides tokens, echoed in `ready.capabilities.externalTokens`. Without it the engine registers no brokered kind, so the Mac and every existing host see no difference. |
| Windows host | (C) MSAL and the broker live only in `TimeTug.Platform`, behind `IBrokerClient`, a thin interface that returns our own result type, so every rule is tested with fakes. Presentation stays free of Windows and MSAL references (architecture test). |
| First-run consent trigger | (O, amends section 4.5) 4.5 says the dialog appears automatically. Recommended: the welcome window pre-selects "Microsoft account on this PC" and the person presses one button, then Windows asks. Reason: Microsoft's guidance is to authenticate on a user action with context first, a tray app that pops a system dialog unasked looks like phishing, and the Mac's EventKit prompt is also tied to a visible app. Cost: one click more than 4.5. Alternative: open the dialog as soon as the welcome window is visible (still never before a window exists). |
| Reconnect surface | (C) "Sign in again" for a `microsoft-brokered` account runs from Settings > Accounts or the welcome window only. The flyout closes when it loses focus and WAM's dialog needs a stable parent window, so its problem row says "Open Accounts" for these accounts (phase 5 already does this for rows the flyout cannot fix). Revisit after spike task on hidden owner windows. |
| Same mailbox twice | (C) An optional library protocol `AccountIdentityFamily` (default: the kind id) lets the engine's "already added" check treat `microsoft` and `microsoft-brokered` with the same email as one account. Without it the same mailbox in both modes would duplicate every event. |
| Versions | (C) Minor releases everywhere: `calendar-connectors` 1.2.0, `timetug-shared` and `TimeTug.Engine` 1.8.0 (today 1.1.0, 1.7.0 and 1.7.0 in `Directory.Packages.props`). None needs the `semver:major` label; if the compatibility checks demand it, the design is wrong and comes back to the owner. |
| MSAL pin | (C) Exact versions of `Microsoft.Identity.Client` and `Microsoft.Identity.Client.Broker`, at least 4.67 (the 4.91.0 shown on Microsoft's reference pages of 2026-10-15 is the starting point), chosen in slice 0 and pinned in `Directory.Packages.props`. No MSAL token-cache file and no MSAL log callback with account data. |
| Section 4.5 | (C) Otherwise stands. Its "externally managed token mode" becomes the second kind above; its "interaction required becomes needs-reconnect" is the table under "Engine and contract design"; its browser fallback is the "Browser fallback" section. |
| Models | (O) Implementation work uses Sonnet 5.5; reviews use the `deepseek-review` skill. |

## Library design (`calendar-connectors`, release 1.2.0)

New public API, all additions (no existing symbol changes):

- `CalendarCore`: `ExternalAccount` (`id`), `ExternalAccessToken` (`accessToken`, `expiresAt`), `ExternalSignInRequest` (`account: ExternalAccount?`, `email: String?`, `scopes`), `ExternalSignInResult` (`account`, `token`), protocol `ExternalTokenSource` with two methods, `accessToken(for:scopes:forceRefresh:)` (silent) and `signIn(_:)` (interactive), and protocol `AccountIdentityFamily` (`identityFamily`). Structs, not enums, so later options are additive.
- `CalendarOAuth`: protocol `AccessTokenSupplying` (`accessToken()`, `invalidate()`), adopted by the existing `AccessTokenProvider` (a conformance is additive), and a new actor `ExternalAccessTokenProvider` with the same behaviour as `AccessTokenProvider` where it applies: a cached token until 60 s before `expiresAt`, concurrent callers share one in-flight request, `invalidate()` makes the next request `forceRefresh`.
- `MicrosoftCalendar`: `MicrosoftBrokeredConnectorKind` (id `microsoft-brokered`, display name "Microsoft", `.oauth` so no new `AuthorizationMethod` case, all platforms; the host decides by registering it). `scopes` is `MicrosoftConnectorKind.scopes` without `offline_access` (a broker keeps the refresh token itself), so the read-only pin keeps covering it. `GraphAPIClient` (internal) takes an `AccessTokenSupplying` instead of the concrete provider.

Behaviour:

- `authorize`: `signIn` with no account, then `GET /me` with the returned token for the email (the same function the browser flow uses, so the host is never trusted for identity), then the connection `{kindID, displayName: email, config: {email, authMode: "external", externalAccountID}}`. Nothing is persisted if any step fails. `reauthorize`: `signIn` with the stored account and email as hint; a different email throws `invalidResponse("signed in as a different account")`, as today; the returned connection keeps its `connectionID` and takes the new `externalAccountID`.
- `makeSource`: a Graph source whose token provider calls `accessToken(for:scopes:forceRefresh:)`. A connection without `externalAccountID` throws `invalidResponse("the account settings are incomplete; sign in again")`, which the engine already shows as "Can't start this account" with Sign in again.
- Errors, by the existing mapping: the source throws `SourceError.authExpired` when the host says interaction is required; a 401 invalidates once and retries with `forceRefresh`, and a second 401 is `authExpired` (as `GraphAPIClient` does today); `SourceError.network` passes through; any other host failure is `invalidResponse`.
- Compatibility: the `compat` job compares the library's API with the last release, so the PR must show that no existing public symbol changed. Persisted data: a new `Tests/PersistedFormats/1.2.0/connections.json` holds a brokered connection, loaded by `PersistedFormatTests`; the `1.0.7` files are untouched. An older library reading such a connection finds no kind and reports an unknown account type, which is safe. `docs/api.md` gets a part for the seam.
- Tests: `FakeTransport` plus a fake `ExternalTokenSource`: sign-in, wrong-account reauthorize, silent refresh near expiry, one shared in-flight request, 401 then forceRefresh then `authExpired`, interaction required to `authExpired`, network passthrough, missing `externalAccountID`, scopes subset of `MicrosoftConnectorKind.scopes` and without `offline_access`, the identity-family rule, and the persisted fixture.

## Engine and contract design (`timetug-shared`, release 1.8.0)

Everything here is additive; the 1.7.0 golden fixtures, scenarios, C header and NuGet API must pass unchanged in the `compat` and `compat-dotnet` jobs. One rule applies to every public Swift type touched: never add a parameter to an existing initializer (the API check treats that as a change); add a second initializer.

Messages (golden fixtures `service.token.get.json`, `service.token.signIn.json`, `service.token.cancelSignIn.json`, and `edge-reply-token-*.json`, plus `edge-ready-external-tokens.json`):

| Request (engine to host) | Payload | Result |
|---|---|---|
| `service.token.get` | `connectionID`, `accountID`, `email`, `scopes`, `forceRefresh` | `{status: "ok", accessToken, expiresAt}` or `{status: "interactionRequired", reason?}` or `{status: "unavailable", reason?}` |
| `service.token.signIn` | `signInID`, `scopes`, `accountID?`, `email?` | `{status: "ok", accountID, accessToken, expiresAt}` or `{status: "blocked", reason}` or `{status: "unavailable", reason?}` |
| `service.token.cancelSignIn` | `signInID` | empty result |

`expiresAt` is the wire's UTC millisecond string. `reason` is a documented code, never free text from Windows (`consent`, `signedOut`, `mfa`, `policy`, `accountMissing`, `adminConsentRequired`, `brokerUnavailable`, `other`); it is only logged. Errors use the existing kinds: `cancelled` when the person closes the dialog (the engine already treats it as a cancelled sign-in, no message), `network` when offline, `failed` otherwise.

How each outcome reaches the person:

| Host says | Library sees | Engine status |
|---|---|---|
| `ok` | a token | `ok` |
| `interactionRequired` | `SourceError.authExpired` | `authExpired`: "Sign in again" |
| `unavailable` (silent) | `invalidResponse` | `failing`, with the message |
| `unavailable` (sign-in) | `invalidResponse` | the attempt fails: the card shows why and the browser button (the Windows UI decides, not the engine) |
| `blocked` (sign-in) | `invalidResponse("admin approval is required")` | the attempt fails with that text |
| error `network` | `SourceError.network` | `failing`, recovers on `networkReturned` |
| error `cancelled` | `CancellationError` | nothing, no error shown |

Changes:

- `TimeTugEngineProtocol`: the three types in `ServiceMessages.types`, request and reply structs, `WireConfig.externalTokens` (read with `decodeIfPresent`, default false), and `WireReady.Capabilities.externalTokens`, which must decode as optional so the 1.7.0 `ready.json` still decodes (the compat check decodes every baseline fixture with the new code).
- `TimeTugEngineC`: `RemoteExternalTokenSource` (a `RequestTable` client; silent calls use the 60 s `hostServiceTimeout`, sign-in none; a task-cancellation handler sends `cancelSignIn`) and, in `Connectors.swift`, registration of `MicrosoftBrokeredConnectorKind` when the config sets `externalTokens` and a Microsoft client id exists; with the flag but no id the kind is listed unconfigured, as `microsoft` is. `EngineHost` is not touched, so the Mac's host is unaffected.
- `TimeTugEngine`: `AccountManager`'s "already added" check uses `AccountIdentityFamily`. No other behaviour changes: reconnect and status paths already handle `authExpired`.
- C# wrapper: a new optional interface `IExternalTokenHost` (members `GetTokenAsync`, `SignInAsync`, `CancelSignIn`) that the host object may implement; the wrapper uses `options.Host as IExternalTokenHost`, sets `ExternalTokens` in the config from it, and answers the three requests (a host without it answers `notFound`, as for text generation today). A separate interface keeps `IEngineHost` unchanged, which is certain to pass package validation (a default interface member would also be additive but is one more thing for `compat-dotnet` to judge). `EngineCapabilities` gains `ExternalTokens`.
- Tests: Swift unit tests with a scripted `RequestTable`; both scenario runners (Swift in-process and C# against the real DLL) gain a `tokens` block in the host script and run three new scenarios on recorded Graph data: `add-account-brokered` (sign in, `/me`, calendars, events; no `credentials.set`), `brokered-needs-reconnect` (silent `interactionRequired` shows `authExpired`; `account.reconnect` recovers without restart) and `brokered-cancel` (`account.cancel` sends `cancelSignIn`; no account is added). A scenario also asserts that the token and the email do not appear in any `event.diagnostic`.
- `docs/engine-protocol.md` (it lives in this repository, `timetug`) lists the new types; the protocol design of record gets a short amendment.

## Windows design (`timetug-windows`)

`TimeTug.Platform` gains `Broker/`:

- `IBrokerClient` (the only type that sees MSAL): `ListAccountsAsync`, `AcquireSilentAsync(accountId, email, scopes, forceRefresh)`, `AcquireInteractiveAsync(intent, accountId, email, scopes, ct)`, each returning a `BrokerOutcome` (`Ok`, `UiRequired(reason)`, `Cancelled`, `Blocked(reason)`, `Unavailable(reason)`, `Network`, `Failed`). `MsalBrokerClient` implements it with `PublicClientApplicationBuilder.Create(microsoftClientId)`, the personal-plus-work audience, `BrokerOptions(Windows)` with `ListOperatingSystemAccounts`, and `WithParentActivityOrWindow` from an `IBrokerParentWindow` the app implements (the welcome or Settings window handle). It maps `MsalUiRequiredException` to `UiRequired`, a user-cancel to `Cancelled`, consent and admin-approval service errors to `Blocked`, and logs only the MSAL error code.
- `BrokeredTokenHost` implements `IExternalTokenHost` over `IBrokerClient`: silent first, interactive only from `SignInAsync`. The intent ("the Windows account" or "pick an account") comes from `IBrokerSignInIntent`, set by the view model before `account.add` because the engine command carries only the kind; the intent is host-local, like `PrepareSignInAsync`'s armed form. `WindowsEngineHost` implements `IExternalTokenHost` only when the Microsoft client id exists and the broker client builds; otherwise the engine never lists the kind and the browser card stands alone.
- Account removal: nothing to delete (no secret). The app never signs the person out of Windows and never calls MSAL's account removal for an OS account. Settings > Accounts says how to withdraw consent (account.live.com/consent/Manage for personal accounts, the organization's My Apps page for work accounts), as the manual checklist already does for the browser flow.

`TimeTug.Presentation` and the app:

- `ProviderItem` gains an intent and optional secondary text; `AccountsViewModel` orders `microsoft-brokered` first, labels it by id (`Provider_microsoft-brokered` = "Microsoft account on this PC"), adds the "Another Microsoft account" item with the picker intent, builds the waiting text from the attempted kind (the engine's `waitingStyle` says `browser` for it and must not be trusted for the text; no engine change is made for this), shows an "On this PC" tag on connected rows of this kind, and on a failed attempt of this kind shows "Windows sign-in isn't available here" with the "Use your browser instead" button (which calls `ConnectAsync("microsoft")`).
- First run: the welcome window pre-selects the brokered card when the engine lists it as configured. If the broker lists a Windows account without consent (spike S2 decides whether this is possible), the card names it ("Use name@example.com"); otherwise it reads "Microsoft account on this PC". A decline returns to step 1 silently. `ShouldShowAtStartup` is unchanged.
- Flyout: a problem row for a `microsoft-brokered` account in `authExpired` shows "Open Accounts" (D3). Tray attention state is unchanged.
- The Entra consent text is Windows', not ours. TimeTug's own text before the click: "Windows will ask you to let TimeTug read your calendars. TimeTug stores no password and no sign-in token."
- Existing browser-signed-in accounts keep working untouched; there is no migration prompt.

### Browser fallback

The browser flow of phase 5 is unchanged and becomes the Microsoft path when any of these holds: the host does not provide the broker (client id missing in this build, MSAL cannot build or load the broker, `externalTokens` off), so the brokered kind is not offered; a brokered sign-in returns `unavailable` (the card explains and offers the button); the person chooses "Microsoft (browser)" on purpose; or the person is on a PC where WAM is blocked by policy (shows as `unavailable` or a MSAL error the mapper classifies). A brokered account whose broker later fails keeps its status `failing` with the reason; the fix is Remove and add again by browser (D2).

## Owner action: Entra app registration (before slice 0)

Same client id, same scopes, same supported account types, same `http://localhost` redirect. One redirect URI is added:

1. Sign in at <https://entra.microsoft.com> with `sobryan@binarycompanion.com` (the work user that administers the registration, program section 1.5).
2. Entra ID > App registrations > All applications: <https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade>. Open **TimeTug**. On Overview copy **Application (client) ID**.
3. Manage > **Authentication**. Under Platform configurations choose **Add a platform** > **Mobile and desktop applications**, tick **Custom redirect URIs**, and enter `ms-appx-web://microsoft.aad.brokerplugin/` followed by that client id with no spaces or trailing slash. Configure. Leave `http://localhost` and every other setting as they are.
4. Tell me it is done. I read the registration back with the same Graph query as in program section 1.5 and confirm the new redirect URI is present and nothing else changed.

## Testing

Without a person (CI and the agent on the VM):

- Unit and contract tests in all three repositories as listed above. In `timetug-windows`: `MsalBrokerClient` result mapping, `BrokeredTokenHost` over a fake `IBrokerClient` (silent ok, interaction required, unavailable, blocked, cancel, intent handling), `WindowsEngineHost` implements `IExternalTokenHost` exactly when the client id exists and the broker client builds (the existing every-member test of `IEngineHost` is unaffected because the interface is separate), view-model tests for ordering, labels, decline and fallback, and an architecture test that only `TimeTug.Platform` references MSAL.
- Self-test scenarios on both architectures with screenshots, over the real engine with a fake broker and recorded Graph responses (`ScriptedCalendarHost`): `welcome-brokered` (one click, step 2, decline path), `accounts-brokered` (add, "Another Microsoft account", tag, remove asks nothing of the broker), `brokered-reconnect` (clock advances, the fake says `interactionRequired`, the problem row and "Open Accounts", Sign in again, recovered), `brokered-unavailable` (the browser button). `broker-probe` loads the real MSAL broker and calls `ListAccountsAsync` (no UI) and records the result; it never fails the run on `Unavailable`, because a hosted runner may have no WAM, and the VM run reads it.
- A privacy test runs a scenario with sentinel token, email and account id values and fails if any appears in the rolling log, the ETW sink or "Copy diagnostics" output.
- `scripts/ci/check-release-package.ps1` fails a Store or Direct package that lacks `msalruntime` for its architecture.

Needs a person (listed in `docs/manual-tests/windows-checklist.md`, section 2.4 onward; the agent never types a password):

- On the VM, owner-attended: a Microsoft account added under Settings > Accounts > Email & accounts (or as the Windows sign-in) for the spike and for each manual test; a work account with MFA; a personal account; consent declined; consent withdrawn at the provider and then Sign in again; the account removed from Windows; a password change; no network during sign-in; a tenant that blocks user consent (shows "admin approval is required"); a local-only Windows account (picker path); the broker disabled by policy if a test PC allows it.
- ARM64 real run on the VM and x64 on a second PC or the CI probe; Narrator and contrast on the new cards (axe covers the structure).
- Real-account steps cannot be automated; the agent prepares the build, the steps and the expected results, the owner or the VM user runs them.

## Slices and release order

0. **Owner action** (Entra redirect URI) then **spike** (`timetug-windows`, `docs/spikes/2026-11-wam-broker.md`, throwaway, owner-attended for the real-account steps): proves the section "Facts checked" open list and fixes the MSAL pin. Outputs contain no email, id or token. Findings can change slice 3; the library and engine slices do not depend on them.
1. **`calendar-connectors`**: the library work above. Owner merges; `release.yml` publishes 1.2.0 and dispatches bump pull requests to `timetug-shared` and `timetug`.
2. **`timetug-shared`**, in this order: (a) merge the "Bump calendar-connectors to 1.2.0" pull request (`Package.resolved`); (b) the engine PR raises the dependency's lower bound to `1.2.0` and carries the contract, C layer, `AccountManager` rule, fixtures and Swift scenarios; (c) the C# wrapper and C# scenarios (may be the same PR). Owner merges; the release publishes 1.8.0 and `TimeTug.Engine` 1.8.0, then dispatches the bump to `timetug` (no code change; the Mac does not enable the flag).
3. **`timetug-windows`**: (a) merge the "Bump TimeTug.Engine to 1.8.0" pull request (safe by the backward-compatibility rule); (b) slice A: `TimeTug.Platform` broker, pins, packaging check, fakes, tests, `broker-probe`; (c) slice B: Presentation and app UI, strings, self-tests, axe, `docs/parity.md`, the checklist and `docs/store/capabilities.md` (no new capability; the sign-in sentence changes from "browser" to "Windows account broker or browser"). Each slice is runnable and merged on green; the app is released only by the owner.
4. **Live verification** with the owner on the VM, then the tracker and `docs/PROGRESS.md` updated, and the program design's section 4.5 amended with the decisions above.

Order that must hold: library release, then engine (needs the library's new minimum), then NuGet, then app. A later step can be prepared on a branch while an earlier one waits for review, but cannot merge before it. The Mac needs no release at any point.

## Parity

| Mac | Windows |
|---|---|
| EventKit is on by default; `AccountManager.start` asks for access once at launch | The Windows account is connected by one click at first run; Windows asks once per account. Same effect (calendars appear), different mechanism: Windows cannot enumerate calendars without a per-account consent, and the consent is per account, not per app |
| Calendars from internet accounts configured in System Settings appear without a TimeTug sign-in | Microsoft accounts known to Windows appear with one Windows dialog; Google and others still use the browser |
| Revoke in System Settings > Privacy | Revoke at the provider's consent page; TimeTug then shows Sign in again |

`docs/parity.md` row 42 ("Windows account sign-in (WAM) and On this PC accounts") moves from later to done, differs on purpose.

## Privacy

No access token, refresh token, email, account id, event title or link in the rolling log, ETW, `event.diagnostic` or Copy diagnostics: logs carry the step, the outcome code and the MSAL error code only. The access token crosses only the in-process `tt_engine_reply` boundary (and the existing `service.http.send` header); the wrapper's message tap is test-only. `externalAccountID` and the email are in `accounts.json` under `LocalState` as for any account and are not secrets. TimeTug stores no Microsoft credential for these accounts, so Credential Locker's size limit and the refresh-token write-back do not apply to them. No telemetry, no TimeTug server.

## Risks

- **Broker missing, blocked or failing** (policy, a stripped PC, `msalruntime` not found in the package): handled as `unavailable`; the browser path remains; the packaging check and `broker-probe` catch the build-time cases.
- **Conditional Access, MFA and sign-in frequency** make silent requests fail on schedule: expected, shown as Sign in again. This is the browser flow's behaviour too, but a refresh token hid it for longer.
- **Consent blocked by the tenant:** a tenant that limits user consent (for example to verified publishers) blocks both the broker and the browser flow until its admin approves or TimeTug's publisher verification (program section 1.5) completes. The message says "admin approval is required"; nothing is worked around.
- **Account listing and ids behave differently than the documentation suggests** (S2, S4): the id fallback is to match the stored email; the card falls back to the unlabelled text.
- **WAM dialog parenting and cancellation** (S6): worst case, a late dialog result is ignored by the engine (an answered or cancelled request id is dropped) and consent may be granted without an account being added, which is harmless.
- **Package and runtime fragility:** native `msalruntime` inside MSIX on ARM64, MSAL regressions on new .NET versions (a WAM json parse error was reported on .NET 11 in issue 6166): exact pins, the package check and the probe.
- **ARM64** is the owner's only real test machine; x64 gets CI and the probe only.
- **Release latency:** three repositories in sequence. Mitigation: each step is small, additive and safe to merge alone.
- **Same mailbox in both modes** would duplicate every event. The identity-family rule refuses the second addition (email compared in lower case), including against browser accounts added before this phase.

## Open items for the owner

Decisions (my recommendation first):

1. **D1 Consent trigger:** one button in the welcome window (recommended), or open the Windows dialog automatically when the welcome window appears (the text of 4.5)?
2. **D2 Separate kind `microsoft-brokered`:** accept that moving a mailbox between browser and Windows sign-in is remove and re-add (losing that account's Tug and hidden-calendar choices), in exchange for no change to any existing contract? The alternative is a mode on the existing kind, which needs a new command field or enum case and a possible major release.
3. **D3 Reconnect from Accounts only:** accept "Open Accounts" instead of an in-flyout Sign in again for these accounts, unless slice 0 shows a hidden owner window works?
4. **D4 Test accounts:** which Microsoft accounts may the VM spike and the manual tests use (a personal test account and a work account with MFA), and who types the passwords (the agent cannot)?

Actions:

5. Approve this spec.
6. Add the broker redirect URI to the Entra registration ("Owner action" above) before slice 0.
7. Merge the library, engine and app pull requests in the order of "Slices and release order" (release-environment approvals stay yours).

## Sources

- [Using MSAL.NET with Web Account Manager (WAM)](https://learn.microsoft.com/en-us/entra/msal/dotnet/acquiring-tokens/desktop-mobile/wam)
- [Errors associated with Web Account Manager](https://learn.microsoft.com/en-us/entra/msal/dotnet/advanced/exceptions/wam-errors)
- [BrokerOptions](https://learn.microsoft.com/en-us/dotnet/api/microsoft.identity.client.brokeroptions?view=msal-dotnet-latest)
- [PublicClientApplication.OperatingSystemAccount](https://learn.microsoft.com/en-us/dotnet/api/microsoft.identity.client.publicclientapplication.operatingsystemaccount?view=msal-dotnet-latest)
- [MSAL.NET issue 3740: msalruntime in MSIX](https://github.com/AzureAD/microsoft-authentication-library-for-dotnet/issues/3740)
- [MSAL.NET issue 4974: broker sign-in in virtual machines](https://github.com/AzureAD/microsoft-authentication-library-for-dotnet/issues/4974)
- [MSAL.NET issue 5019: native runtime files in the NativeInterop package](https://github.com/AzureAD/microsoft-authentication-library-for-dotnet/issues/5019)
- [MSAL.NET issue 6166: WAM on .NET 11](https://github.com/AzureAD/microsoft-authentication-library-for-dotnet/issues/6166)
