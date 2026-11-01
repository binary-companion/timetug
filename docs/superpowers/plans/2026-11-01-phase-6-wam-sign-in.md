# Phase 6: WAM sign-in ("Microsoft account on this PC") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Tasks marked **(owner)** are for the owner; agents never do them.

**Goal:** A Windows user connects the Microsoft account Windows already knows with one native Windows dialog (Web Account Manager), no browser and no stored refresh token; a broker failure is a visible, fixable account status that never blocks the engine, the tug or other accounts.

**Architecture:** A second, generic connector kind `microsoft-brokered` in `calendar-connectors` takes its access tokens from a host-supplied `ExternalTokenSource`. `timetug-shared` adds three host-service requests (`service.token.get`, `service.token.signIn`, `service.token.cancelSignIn`), an opt-in config flag and a C# interface `IExternalTokenHost`. `timetug-windows` implements that interface over MSAL.NET plus the WAM broker, confined to `TimeTug.Platform` behind `IBrokerClient`, and adds the UI. Everything is additive, so each repository releases a minor version and the Mac needs no release.

**Tech Stack:** Swift 6 / SwiftPM (library, engine, C layer) with each repository's existing test framework, System.Text.Json source generation (C# wrapper), .NET 10, WinUI 3, `Microsoft.Identity.Client` and `Microsoft.Identity.Client.Broker` (exact pins chosen by the spike), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-30-phase-6-wam-sign-in-design.md` (approved; PR 152). Parent: `docs/superpowers/specs/2026-10-09-windows-program-design.md` section 4.5. Style reference: `docs/superpowers/plans/2026-10-30-phase-5e-windows-app-slice-4-store-packaging.md`.

**Owner decisions (approved; they settle the spec's open items):** D1 first-run consent is one click in the welcome window; D2 a separate kind `microsoft-brokered` (additive, no major release; moving a mailbox between modes is remove and re-add); D3 reconnect only from Settings > Accounts (the flyout row says "Open Accounts") unless the spike shows a hidden owner window works; D4 two test accounts, one personal Microsoft account and one work account with MFA, and the owner types the passwords.

## Merge order and who does what

| Order | Repository | What | Who merges / publishes |
|---|---|---|---|
| 0 | Entra | Add the broker redirect URI (Task 0) | **(owner)** |
| 1 | `timetug-windows` | Spike findings, docs only (Tasks 1 and 1A) | owner merges |
| 2 | `calendar-connectors` | Tasks 2 to 5, release 1.2.0 | owner merges; `release.yml` publishes and dispatches bump PRs |
| 3 | `timetug-shared` | Merge "Bump calendar-connectors to 1.2.0" (Task 6), then Tasks 7 to 11, release 1.8.0 and `TimeTug.Engine` 1.8.0 (Task 12) | owner merges; release environment approval is the owner's |
| 4 | `timetug` | Docs PR (Task 12) and the automatic engine bump (no code change; the Mac does not set the flag) | owner merges |
| 5 | `timetug-windows` | Merge "Bump TimeTug.Engine to 1.8.0" (Task 13), slice A (Tasks 13 to 15), slice B (Tasks 16 to 18) | owner merges; the app is released only by the owner |
| 6 | all | Live verification on the VM, tracker, program design amendment (Task 19) | **(owner)** for the real-account steps |

A later step may be prepared on a branch while an earlier one waits for review, but cannot merge before it. Squash-merge every PR when its checks are green (`gh pr merge --squash`); no PR carries the `semver:major` label. If any compatibility check (`compat`, `compat-dotnet`, the NuGet package validation) demands a major version, stop: the design is wrong and goes back to the owner.

## Owner-only steps (flagged in the tasks)

- Task 0: the Entra redirect URI. No real-account work starts before it.
- Tasks 1 and 1A: typing passwords for the personal and the work (MFA) test accounts on the VM, approving MFA prompts, and granting or refusing the Calendar privacy consent in Task 1A. The agent never types a password.
- Tasks 5, 12, 15, 18, 19: merging PRs and approving the `publish` / `release` environments.
- Task 19: every manual verification item in `docs/manual-tests/windows-checklist.md` section 2.6 onward, on the ARM64 VM (and x64 on a second PC if available).

## Global Constraints

- Microsoft scopes stay read-only (ADR 0017; `check-repository-contracts.py` pins them): the brokered scopes are `["User.Read", "MailboxSettings.Read", "Calendars.Read", "Calendars.Read.Shared"]`, i.e. `MicrosoftConnectorKind.scopes` without `offline_access`.
- Versions are minor everywhere: `calendar-connectors` 1.2.0, `timetug-shared` 1.8.0, `TimeTug.Engine` 1.8.0 (today 1.1.0, 1.7.0, 1.7.0). The engine's lower bound on the library becomes `1.2.0`.
- Nothing existing changes: no existing public symbol, message, golden fixture, scenario, C header declaration or persisted-file meaning. Never add a parameter to an existing public initializer; add a second initializer.
- Opt-in: without `externalTokens` in the config the engine registers no brokered kind, so the Mac and every existing host see no difference.
- Silent token requests never show UI and time out after 60 s on the engine clock (`hostServiceTimeout`); sign-in requests have no timeout and end with `account.cancel` (which sends `service.token.cancelSignIn`, best effort).
- `reason` is a documented code only, never Windows free text: `consent`, `signedOut`, `mfa`, `policy`, `accountMissing`, `adminConsentRequired`, `brokerUnavailable`, `other`.
- Wire dates are the UTC millisecond string. Error kinds stay `cancelled`, `network`, `failed` (no new error kind, no new public enum case).
- Privacy: no access token, email, account id, event title or link in the rolling log, ETW, `event.diagnostic` or Copy diagnostics; logs carry the step, the outcome code and the MSAL error code only. No MSAL token-cache file; no MSAL log callback with account data.
- MSAL pins are exact and at least `Microsoft.Identity.Client` 4.67 (4.50 fixed the MSIX `msalruntime` lookup; 4.67 with NativeInterop 0.17.1 fixed sign-in in virtual machines). The 4.91.0 on Microsoft's reference pages of 2026-10-15 is the spike's starting point. Only `TimeTug.Platform` references MSAL (architecture test).
- Strings (exact): "Microsoft account on this PC", "Another Microsoft account", "Microsoft (browser)", "On this PC", "Open Accounts", "Windows sign-in isn't available here", "Use your browser instead", "Use name@example.com" (the name is the Windows account's), "admin approval is required", and the pre-click text "Windows will ask you to let TimeTug read your calendars. TimeTug stores no password and no sign-in token." The Entra consent text is Windows', not ours. The Settings > Accounts pane also says how to withdraw consent, key `Accounts_WithdrawConsent`: "To stop TimeTug reading a Microsoft account's calendars, remove its access at account.live.com/consent/Manage (personal accounts) or on your organization's My Apps page (work accounts)."
- Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR bodies end `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Implementation work uses Sonnet 5.5; each PR gets a `deepseek-review` pass (never send secrets; verify every Critical or Important finding against the repository before acting).
- Real-account steps cannot be automated: the agent prepares the build, steps and expected results; the owner or the VM user runs them.

## Decisions this plan makes (small; flagged for the owner's read)

These fill gaps the spec leaves; each is additive and local.

1. `ExternalAccount` carries `id` plus optional `email` and `connectionID` (informational; `id` is authoritative). The spec lists only `id`, but the wire request `service.token.get` carries `connectionID` and `email`, and a token source called per account would otherwise have no way to supply them.
2. `WindowsEngineHost` stays as it is. The brokered capability is a decorator `BrokeredEngineHost : IEngineHost, IExternalTokenHost` that `WindowsEngineHost.Create` returns only when the Microsoft client id exists and the broker client builds. This is how the spec's "implements `IExternalTokenHost` exactly when ..." is achievable in C#, where a class either implements an interface or not.
3. `BrokerIntent` and `IBrokerSignInIntent` live in `TimeTug.Presentation` (the view model sets them and Presentation cannot reference Platform); `BrokeredTokenHost` in Platform consumes them.
4. `ready.capabilities.externalTokens` is emitted only when true (absent otherwise), so the 1.7.0 `ready.json` stays byte-identical for existing hosts.
5. The new `WireConfig` initializer takes `externalTokens` with no default, so a call that omits it still resolves to the old initializer.
6. New manual checklist items are numbered 2.6 onward under "2. Real accounts" so existing numbers do not move.
7. The WAM spike gets an eighth question (scope spelling) beyond the spec's list.
8. Task 1A (the Windows calendar store spike) is an owner-approved addition outside the spec; it adds findings and a recommendation only, no build scope.

## Review Focus

The inputs and failure modes the spec implies that no happy-path test would exercise, most likely first. Each line names the tasks whose tests pin it.

- **The person closes, declines or cancels the Windows dialog** (X, Esc, "Cancel", account picker closed) at first run or in Add an Account: nothing is added, no error is shown, the window stays on step 1, and a late dialog result after `account.cancel` creates no account. Tasks 8 (task cancellation sends `cancelSignIn`; late answer dropped), 10 (`brokered-cancel`), 14 (`Cancelled` is not `Failed`), 16 and 17 (`welcome-brokered` decline path).
- **The same mailbox in both modes**, in any case (`Me@Example.com` vs `me@example.com`) or with `mail` missing so `userPrincipalName` is used: the second addition is refused and no event is duplicated, including against browser accounts added before this phase. Tasks 4 and 9.
- **The Windows account disappears or needs the person again** (account removed from Windows, password changed, consent withdrawn, sign-in-frequency policy) while TimeTug runs: the account becomes "Sign in again" (never a crash, never a stuck "failing"), other accounts keep working, and reconnect recovers without a restart. Tasks 8, 10 (`brokered-needs-reconnect`), 14, 17 (`brokered-reconnect`).
- **Offline during a silent refresh or a sign-in**: `SourceError.network`, status `failing`, recovery on `networkReturned`, never "Sign in again" and never a stale expired token served. Tasks 3, 8, 14.
- **Secrets in diagnostics**: a sentinel token, email and account id appear in no rolling log, ETW event, `event.diagnostic` or Copy diagnostics output, including when the broker throws an exception whose message embeds them. Tasks 8, 10, 11, 14 and 15.

---

### Task 0: Owner action: Entra broker redirect URI (owner)

**Files:** none (Microsoft Entra console).

- [ ] **Step 1 (owner):** Follow "Owner action: Entra app registration" in the spec, verbatim: sign in at <https://entra.microsoft.com> as `sobryan@binarycompanion.com`; Entra ID > App registrations > All applications <https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade> > **TimeTug**; copy **Application (client) ID** from Overview; Manage > **Authentication** > **Add a platform** > **Mobile and desktop applications**, tick **Custom redirect URIs**, enter `ms-appx-web://microsoft.aad.brokerplugin/` followed by the client id (no spaces, no trailing slash), Configure. Leave `http://localhost` and every other setting alone.
- [ ] **Step 2 (owner):** Tell the agent it is done.
- [ ] **Step 3 (agent):** Read the registration back with the Graph query used in program design section 1.5 and confirm the new redirect URI is present and nothing else changed. Record the check in the tracker's session log (no client id in the log line).

### Task 1: Spike: WAM broker findings (`timetug-windows`)

**Files:** Create `docs/spikes/2026-11-wam-broker.md`. The probe code is throwaway on a scratch branch and is not merged; only the findings document is.

**Interfaces:** Produces the decisions Tasks 13 to 17 depend on: the MSAL pin, the packaging recipe for `msalruntime`, the account listing and id behaviour, the error mapping table, and the D3 hidden-window verdict. The document contains no email, id or token.

- [ ] **Step 1:** On a scratch branch of `timetug-windows`, add `Microsoft.Identity.Client` and `Microsoft.Identity.Client.Broker` (start at the 4.91.0 line, at least 4.67; record the exact versions and any NativeInterop version) to a throwaway project and to a spike copy of the MSIX build. Answer, with the VM result (and for item 1 one x64 CI run) in the document:
  1. **S1 Packaging:** does the broker package build and load inside our `net10.0-windows10.0.22621.0` MSIX on x64 and ARM64, and which native files (`msalruntime.dll`, `msalruntime_arm64.dll`) land in the package for each architecture and for the Dev, Store and Direct flavours? Record the exact file names the package check must require.
  2. **S2 Listing:** what does `GetAccountsAsync` return with `BrokerOptions.ListOperatingSystemAccounts` before consent, for a local-only Windows sign-in, a Windows-sign-in Microsoft account and a Microsoft account added under Settings > Accounts > Email & accounts? Can the welcome card name the account ("Use name@example.com") without prior consent?
  3. **S3 Errors:** the exact exception type and `ErrorCode` of a silent request with no account, with no consent, and after a password change; of a cancelled dialog; of a tenant that blocks user consent; of no network. This becomes the mapping table in Task 14.
  4. **S4 Ids:** is `HomeAccountId.Identifier` stable across restarts and does `GetAccountAsync(id)` find the account again? If not, the fallback is matching `Username` to the stored email.
  5. **S5 Refresh:** is `WithForceRefresh` honoured by the broker?
  6. **S6 Cancellation:** does cancelling the token close the Windows dialog, and what does a late result do?
  7. **S7 Parenting:** can a hidden owner window parent the dialog (D3 depends on this), and does the dialog appear in front when the app has no visible window?
  8. **S8 Scope spelling (added by this plan):** do the short scope names in Global Constraints work with the broker, or are `https://graph.microsoft.com/`-prefixed names needed?
- [ ] **Step 2 (owner):** Attend the real-account runs on the Windows 11 ARM64 VM: add the personal test account under Settings > Accounts > Email & accounts, run S2 to S7, then repeat with the work account with MFA (the owner types both passwords and approves MFA; the password change and consent withdrawal scenarios are performed by the owner). The agent drives the probe and records outcomes only.
- [ ] **Step 3:** Write the document: findings per item, the chosen exact pins, the packaging recipe, the error table, and a verdict line per spec risk (S2, S4, S6 and S7) saying which spec fallback applies. State whether Tasks 14 to 17 change; if they do, amend this plan in the same PR.
- [ ] **Step 4: Commit and PR** — `git commit -m "Spike: WAM broker findings"`; docs-only PR to `main`; run `deepseek-review` on the document; **(owner)** merges.

### Task 1A: Spike: the Windows calendar store as a fallback source (`timetug-windows`)

Owner-approved addition. Time-boxed to one VM session alongside Task 1. It adds no scope to the build tasks (Tasks 2 to 19 are unchanged) and no product code is kept.

**Files:** Create `docs/spikes/2026-11-windows-calendar-store.md`. The probe is throwaway on the Task 1 scratch branch and is not merged.

**Interfaces:** Produces a recommendation only: whether `Windows.ApplicationModel.Appointments` is worth a later phase as a source for people without a Microsoft account. It feeds no task in this plan.

- [ ] **Step 1:** Write a throwaway probe that calls `AppointmentManager.RequestStoreAsync(AppointmentStoreAccessType.AllCalendarsReadOnly)` (this needs the `appointments` capability in the spike package manifest, or the unpackaged equivalent if the spike runs unpackaged) and, for each calendar, counts appointments in the next 14 days without recording titles, attendees, locations or any account name. Answer on the Windows 11 ARM64 VM and, if a second PC is available, on a normal everyday machine:
  1. **C1 Consent:** is access refused, silently empty, or prompted? Where is the consent shown (Settings > Privacy & security > Calendar), and is it per app or global?
  2. **C2 Contents:** on a machine with Mail & Calendar retired and new Outlook installed, which calendars does the store hold, how many appointments in the next 14 days, and which providers wrote them (counts per provider kind only)? Does a Microsoft account added under Settings > Accounts > Email & accounts, a Google account added there, and a local calendar each appear?
  3. **C3 Freshness:** does a change made in the account's own web calendar appear in the store within a few minutes without any app open?
  4. **C4 Fit:** do the fields the engine needs (start, end, all-day, recurrence expansion, organizer, location or online-meeting link) come through intact?
  5. **C5 Packaging:** does the capability change the Store submission (restricted capability, justification text in `docs/store/capabilities.md`)?
- [ ] **Step 2 (owner):** Attend the run: the owner decides which real accounts are on the VM and grants or refuses the consent prompt; the agent never types a password and records counts only.
- [ ] **Step 3:** Write the document: findings per question (counts and behaviours, no titles, emails or ids), and a recommendation in one of three forms: not worth building; worth a later phase as a "calendars on this PC" fallback source (with the engine seam it would need: a host-side source like EventKit on the Mac, behind the existing `systemCalendar` capability); or needs more data (say what). If it recommends a phase, also list the open risks.
- [ ] **Step 4: Commit and PR** — `git commit -m "Spike: Windows calendar store findings"`; docs-only PR to `main` (the same PR as Task 1 is acceptable); run `deepseek-review` on the document; **(owner)** merges. Add the recommendation, if any, to the tracker's "Open questions" in Task 19.

---

## Part A: `calendar-connectors` (release 1.2.0)

Work in a worktree of `binary-companion/calendar-connectors` off `origin/main`. Tests: `swift test --filter <Target>Tests` on macOS; the final PR must pass `macos`, `linux`, `architecture`, `windows-x64`, `windows-arm64` and `compat`.

### Task 2: Core types for externally supplied tokens

**Files:**
- Create: `Sources/CalendarCore/ExternalTokens.swift`
- Test: `Tests/CalendarCoreTests/ExternalTokenTests.swift`

**Interfaces (Produces):** all `public` and `Sendable`; structs, never enums.
- `struct ExternalAccount: Hashable` with `id: String`, `email: String?`, `connectionID: ConnectionID?`; `init(id: String, email: String? = nil, connectionID: ConnectionID? = nil)`.
- `struct ExternalAccessToken: Equatable` with `accessToken: String`, `expiresAt: Date`; `init(accessToken:expiresAt:)`.
- `struct ExternalSignInRequest` with `account: ExternalAccount?`, `email: String?`, `scopes: [String]`; `init(account: ExternalAccount? = nil, email: String? = nil, scopes: [String])`.
- `struct ExternalSignInResult` with `account: ExternalAccount`, `token: ExternalAccessToken`; `init(account:token:)`.
- `protocol ExternalTokenSource: Sendable` with `func accessToken(for account: ExternalAccount, scopes: [String], forceRefresh: Bool) async throws -> ExternalAccessToken` (silent, never interactive) and `func signIn(_ request: ExternalSignInRequest) async throws -> ExternalSignInResult` (interactive).
- `protocol AccountIdentityFamily { var identityFamily: String { get } }` (optional; adopters are found with `as?`).

- [ ] **Step 1: Write the failing tests** in `ExternalTokenTests`: `externalAccountInitDefaultsOptionalFieldsToNil`; `signInRequestWithoutAccountIsAFirstSignIn` (`account == nil`, `email == nil`); `kindWithoutIdentityFamilyYieldsNilOnCast` (a stub `ConnectorKind` that does not adopt the protocol gives `(kind as? AccountIdentityFamily) == nil`).
- [ ] **Step 2:** Run `swift test --filter ExternalTokenTests`. Expected: FAIL (types undefined).
- [ ] **Step 3:** Implement the types above in `ExternalTokens.swift`.
- [ ] **Step 4:** Re-run. Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -m "Core: external token source types"`.

### Task 3: `AccessTokenSupplying` and `ExternalAccessTokenProvider`

**Files:**
- Create: `Sources/CalendarOAuth/AccessTokenSupplying.swift`, `Sources/CalendarOAuth/ExternalAccessTokenProvider.swift`
- Modify: `Sources/CalendarOAuth/AccessTokenProvider.swift` (add the conformance only), `Sources/MicrosoftCalendar/GraphAPIClient.swift` (`tokens` becomes `any AccessTokenSupplying`); leave `Sources/GoogleCalendar/GoogleAPIClient.swift` on the concrete type
- Test: `Tests/CalendarOAuthTests/ExternalAccessTokenProviderTests.swift`; existing `AccessTokenProviderTests` and `Tests/MicrosoftCalendarTests/APIClientTests.swift` pass unchanged

**Interfaces:**
- Consumes: `ExternalTokenSource`, `ExternalAccount`, `ExternalAccessToken` (Task 2); `SourceError`.
- Produces: `public protocol AccessTokenSupplying: Sendable { func accessToken() async throws -> String; func invalidate() async }`; `extension AccessTokenProvider: AccessTokenSupplying {}`; `public actor ExternalAccessTokenProvider: AccessTokenSupplying` with `init(account: ExternalAccount, scopes: [String], source: any ExternalTokenSource, now: @escaping @Sendable () -> Date)`.

Behaviour (as `AccessTokenProvider` where it applies): serve the cached token until 60 s before `expiresAt`; concurrent callers share one in-flight request that clears itself when finished; `invalidate()` drops the cache and makes the next request pass `forceRefresh: true` (once; later requests pass false). Error mapping inside the provider: `SourceError` and `CancellationError` pass through unchanged; any other thrown error becomes `SourceError.invalidResponse("the Windows account service failed")` (no underlying description, which could carry account data).

- [ ] **Step 1: Write the failing tests** (a counting fake `ExternalTokenSource` actor local to the test file, recording `forceRefresh`): `firstCallRequestsATokenWithForceRefreshFalse`; `cachedTokenIsServedUntilSixtySecondsBeforeExpiry` (token expires at t+3600; at t+3539 one source call in total, at t+3541 a second); `concurrentCallersShareOneInFlightRequest` (ten concurrent `accessToken()`, source called once); `invalidateMakesTheNextRequestForceRefreshOnce`; `hostAuthExpiredPassesThrough`; `hostNetworkErrorPassesThrough`; `cancellationPassesThrough`; `unknownErrorBecomesInvalidResponseWithoutItsMessage` (the thrown error text contains `"secret@example.com"`; assert the resulting message does not); `alreadyExpiredTokenFromTheHostIsNotCachedAcrossCalls` (each call asks the host again; no loop inside one call).
- [ ] **Step 2:** `swift test --filter ExternalAccessTokenProviderTests`. Expected: FAIL.
- [ ] **Step 3:** Implement `AccessTokenSupplying`, the conformance and `ExternalAccessTokenProvider`; change `GraphAPIClient.tokens`'s type and keep its 401 logic (invalidate once, retry, a second 401 is `authExpired`) calling the protocol.
- [ ] **Step 4:** Run `swift test --filter CalendarOAuthTests` and `--filter MicrosoftCalendarTests`. Expected: PASS, no existing test edited.
- [ ] **Step 5: Commit** — `git commit -m "OAuth: external access token provider"`.

### Task 4: `MicrosoftBrokeredConnectorKind`

**Files:**
- Create: `Sources/MicrosoftCalendar/MicrosoftBrokeredConnectorKind.swift`, `Sources/CalendarTestSupport/FakeExternalTokenSource.swift` (a public scripted fake, for this library's tests and for hosts' tests)
- Modify: `Sources/MicrosoftCalendar/MicrosoftConnectorKind.swift` (adopt `AccountIdentityFamily` with `identityFamily == "microsoft"`; move the private `accountEmail(_:)` lookup to an internal function in `GraphAPIClient.swift` that both kinds call, behaviour unchanged)
- Test: `Tests/MicrosoftCalendarTests/BrokeredConnectorKindTests.swift`

**Interfaces:**
- Consumes: Tasks 2 and 3; `GraphAPIClient`, `MicrosoftCalendarSource`, `FakeTransport`.
- Produces: `public struct MicrosoftBrokeredConnectorKind: ConnectorKind, AccountIdentityFamily` with `static let kindID = "microsoft-brokered"`, `static let scopes: [String]` (`MicrosoftConnectorKind.scopes` minus `offline_access`), `id == kindID`, `displayName == "Microsoft"`, `supportedPlatforms` all four platforms, `authorization == .oauth`, `identityFamily == "microsoft"`, and `init(tokenSource: any ExternalTokenSource, transport: any HTTPTransport = URLSessionTransport(), now: @escaping @Sendable () -> Date = { Date() }, sleep: @escaping Sleeper = defaultSleeper, pollInterval: Duration = .seconds(60))`. `FakeExternalTokenSource` scripts `signIn` and `accessToken` results or errors and records the calls.

Behaviour (spec, "Library design / Behaviour"). `authorize`: `signIn` with no account and `scopes: Self.scopes`; then `GET /me` (`$select=mail,userPrincipalName`) with the returned token; email is `mail` else `userPrincipalName`, lowercased; then `Connection(kindID: kindID, connectionID: UUID().uuidString, displayName: email, config: ["email": email, "authMode": "external", "externalAccountID": result.account.id])`. No credential is stored, and nothing is persisted when any step fails. `reauthorize`: `signIn` with the stored account (`id` from `externalAccountID`, plus `email` and `connectionID`) and the stored email as hint; a different email throws `invalidResponse("signed in as a different account")`; the returned connection keeps its `connectionID` and takes the new `externalAccountID`. `makeSource`: a Graph source with an `ExternalAccessTokenProvider`; a missing or empty `externalAccountID` throws `invalidResponse("the account settings are incomplete; sign in again")`.

- [ ] **Step 1: Write the failing tests** (`FakeTransport` for Graph, `FakeExternalTokenSource`): `authorizeSignsInThenReadsMeAndBuildsTheConnection` (config equals `["email": "me@example.com", "authMode": "external", "externalAccountID": "acct-1"]`; the credential store stays empty); `authorizeUsesUserPrincipalNameWhenMailIsMissing`; `authorizeLowercasesTheEmail` (`Me@Example.com` gives `me@example.com`); `authorizeIgnoresAnEmailTheHostClaims` (the host result carries another email; the connection uses Graph's); `authorizeFailureStoresNothing` (sign-in throws, then `/me` answers 500; credentials empty both times); `reauthorizeKeepsConnectionIDAndTakesNewExternalAccountID`; `reauthorizeWithADifferentEmailThrowsInvalidResponse`; `makeSourceWithoutExternalAccountIDThrowsIncompleteSettings` (also for `""`); `sourceRefreshesSilentlyNearExpiry` (a sync after 3541 s calls `accessToken(for:scopes:forceRefresh: false)` again); `a401InvalidatesOnceThenForceRefreshesThenAuthExpired` (two 401s: calls with `false`, `true`, then `SourceError.authExpired`); `hostAuthExpiredSurfacesAsAuthExpired`; `networkErrorPassesThrough`; `otherHostFailureIsInvalidResponse`; `scopesAreASubsetOfTheBrowserKindsScopesWithoutOfflineAccess`; `identityFamilyIsMicrosoftForBothKinds`; `scopesStayReadOnly` (no scope contains `ReadWrite`).
- [ ] **Step 2:** `swift test --filter BrokeredConnectorKindTests`. Expected: FAIL.
- [ ] **Step 3:** Implement the kind and the fake; refactor the `/me` lookup without changing the browser flow.
- [ ] **Step 4:** `swift test --filter MicrosoftCalendarTests` then the full `swift test`. Expected: PASS; existing Microsoft tests unchanged.
- [ ] **Step 5: Commit** — `git commit -m "Microsoft: brokered connector kind (external tokens)"`.

### Task 5: Persisted fixture, API doc, compatibility, release

**Files:**
- Create: `Tests/PersistedFormats/1.2.0/connections.json` (one `microsoft-brokered` connection with the three config keys); the `1.0.7` files stay untouched.
- Modify: `Tests/MicrosoftCalendarTests/PersistedFormatTests.swift` (load the `1.2.0` fixture and assert kind id, display name and config keys), `docs/api.md` (a part for the external-token seam: the types, the two protocols, the new kind, the contract of `ExternalTokenSource`).

- [ ] **Step 1: Write the failing test** `brokeredConnectionFromRelease120Decodes` and the fixture. Run: FAIL until the fixture is wired, then PASS.
- [ ] **Step 2:** Write the `docs/api.md` part. Run `python3 scripts/ci/check-repository-contracts.py` and the `compat` job's command locally (as `.github/workflows/ci.yml` runs it). Expected: additions only, no changed existing symbol. If it flags a change, fix the code, never the baseline.
- [ ] **Step 3:** Run `deepseek-review` on the full diff; verify findings against the repository; fix real defects test-first.
- [ ] **Step 4: Commit, push, PR** — `git commit -m "Library: persisted fixture and API docs for brokered Microsoft"`; one PR to `main` titled "Brokered Microsoft connector (external token source)" with checks green. **(owner)** merges; `release.yml` publishes 1.2.0 and dispatches bump PRs to `timetug-shared` and `timetug`.

---

## Part B: `timetug-shared` (release 1.8.0, `TimeTug.Engine` 1.8.0)

Work in a worktree of `binary-companion/timetug-shared` off `origin/main`. Tests: `swift test --filter <Target>Tests`; C#: `scripts/ci/run-dotnet-tests.ps1` (or `dotnet test dotnet/TimeTug.Engine.sln`) against a real build of the engine DLL. The 1.7.0 golden fixtures, scenarios, C header and NuGet API pass unchanged in `compat` and `compat-dotnet`.

### Task 6: Library bump and lower bound

**Files:** `Package.resolved` (via the bump PR), `Package.swift` (dependency lower bound).

- [ ] **Step 1 (owner):** Merge "Bump calendar-connectors to 1.2.0" in `timetug-shared` (`Package.resolved`). Verify with `python3 scripts/ci/resolved-version.py` that 1.2.0 is pinned.
- [ ] **Step 2:** In the first commit of the engine PR, raise the `calendar-connectors` dependency's lower bound in `Package.swift` to `1.2.0`; `swift build` passes. Commit — `git commit -m "Require calendar-connectors 1.2.0"`.

### Task 7: Protocol layer: messages, config flag, capability

**Files:**
- Modify: `Sources/TimeTugEngineProtocol/ServiceMessages.swift` (three new types in `ServiceMessages.types`, request and reply structs), `Sources/TimeTugEngineProtocol/Config.swift` (`externalTokens`, second initializer), `Sources/TimeTugEngineProtocol/MessageCatalog.swift` (`WireReady.Capabilities.externalTokens: Bool?`, second initializer)
- Create fixtures in `Conformance/Fixtures/golden/`: `service.token.get.json`, `service.token.signIn.json`, `service.token.cancelSignIn.json`, `edge-reply-token-ok.json`, `edge-reply-token-interaction-required.json`, `edge-reply-token-unavailable.json`, `edge-reply-token-blocked.json`, `edge-ready-external-tokens.json`
- Test: `Tests/TimeTugEngineProtocolTests/GoldenMessages.swift` (register the fixtures), `FixtureTests.swift`, `MappingTests.swift`

**Interfaces (Produces):**
- Types appended to `ServiceMessages.types`: `"service.token.get"`, `"service.token.signIn"`, `"service.token.cancelSignIn"`.
- `TokenGetRequest { connectionID: String, accountID: String, email: String?, scopes: [String], forceRefresh: Bool }`; `TokenGetReply { status: String, accessToken: String?, expiresAt: String?, reason: String? }` (`status`: `ok`, `interactionRequired`, `unavailable`).
- `TokenSignInRequest { signInID: String, scopes: [String], accountID: String?, email: String? }`; `TokenSignInReply { status: String, accountID: String?, accessToken: String?, expiresAt: String?, reason: String? }` (`status`: `ok`, `blocked`, `unavailable`); `TokenCancelSignInRequest { signInID: String }`.
- `WireConfig.externalTokens: Bool`, decoded with `decodeIfPresent` (default false); a second `init(v: Int = 1, dataDirectory: String, platform: String, connectors: [String: ConnectorClient] = [:], textGeneration: Bool = false, externalTokens: Bool, timeZone: String? = nil, testing: Bool = false, testClockStart: String? = nil)`; the existing initializer stays as it is.
- `WireReady.Capabilities.externalTokens: Bool?` (nil is omitted from the JSON); a second `init(systemCalendar:textGeneration:externalTokens:)`; the existing two-argument initializer stays.

- [ ] **Step 1: Write the failing tests:** the catalog test fails because the three types have no fixture; add `configWithoutExternalTokensDecodesAsFalse` (the 1.7.0 config text); `configWithExternalTokensTrueRoundTrips`; `oldReadyFixtureStillDecodesAndReencodesIdentically` (`ready.json` byte-equal after decode and encode, `externalTokens == nil`); `readyWithExternalTokensTrueRoundTrips` (`edge-ready-external-tokens.json`); `tokenReplyWithUnknownStatusParsesAsIs` (the engine, not the parser, decides; Task 8); `tokenReplyErrorKindsParse` (existing kinds only).
- [ ] **Step 2:** `swift test --filter TimeTugEngineProtocolTests`. Expected: FAIL.
- [ ] **Step 3:** Implement the structs, types, config and capability changes and write the fixtures (shaped like the neighbouring `service.credentials.*` fixtures).
- [ ] **Step 4:** Re-run the protocol tests and `swift test --filter TimeTugEngineCTests` (existing scenarios pass untouched). Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -m "Protocol: external token messages, config flag and capability"`.

### Task 8: C layer: `RemoteExternalTokenSource` and registration

**Files:**
- Modify: `Sources/TimeTugEngineC/RemoteHostServices.swift` (add `RemoteExternalTokenSource`), `Sources/TimeTugEngineC/Connectors.swift` (`ConnectorSetup.make` takes the source and registers the kind), `Sources/TimeTugEngineC/EngineSession.swift` (builds the source when `config.externalTokens`, passes it, sets `externalTokens: true` in `ready` only then)
- Test: `Tests/TimeTugEngineCTests/RemoteHostServicesTests.swift`, `Tests/TimeTugEngineCTests/LifecycleTests.swift`

**Interfaces:**
- Consumes: `RequestTable.call(_:payload:timeout:)`, `hostServiceTimeout` (60), Task 7 types, `ExternalTokenSource` (library).
- Produces: `struct RemoteExternalTokenSource: ExternalTokenSource { let table: RequestTable }`. `accessToken(for:scopes:forceRefresh:)` calls `service.token.get` with `timeout: hostServiceTimeout` and the account's `connectionID`, `id` and `email`; `signIn(_:)` calls `service.token.signIn` with `timeout: nil` and a fresh `signInID` per call, inside `withTaskCancellationHandler` whose handler sends `service.token.cancelSignIn` (best effort `try?`, 60 s timeout, in an unstructured `Task`).
- Mapping (spec table): `ok` with a non-empty `accessToken` and a parseable `expiresAt` is the token; `ok` missing either, or an unknown status, is `SourceError.invalidResponse("the host's token answer was incomplete")`; `interactionRequired` is `SourceError.authExpired`; silent `unavailable` is `invalidResponse("Windows sign-in is not available")`; sign-in `unavailable` the same text; sign-in `blocked` is `invalidResponse("admin approval is required")`; reply error `network` is `SourceError.network`; `cancelled` is `CancellationError`; the 60 s silent timeout is `SourceError.network`; any other error is `invalidResponse`. A `reason` is logged through the diagnostics sink as a code only when it is one of the documented codes, otherwise dropped. No token, email or account id reaches any diagnostic.
- Registration: `ConnectorSetup.make` registers `MicrosoftBrokeredConnectorKind(tokenSource:transport:now:sleep:)` when `externalTokens` is true and a non-empty client id exists in `config.connectors["microsoft"]` (the same entry that configures the browser kind; there is no separate brokered entry); with the flag but no id it appends `"microsoft-brokered"` to `unconfiguredKindIDs` (as `microsoft` is); without the flag it does neither.

- [ ] **Step 1: Write the failing tests** (scripted `RequestTable`, as the existing `RemoteHostServicesTests`): `getOkReturnsTheTokenAndExpiry`; `getInteractionRequiredIsAuthExpired`; `getUnavailableIsInvalidResponse`; `getOkWithoutAccessTokenIsInvalidResponse`; `getOkWithGarbageExpiresAtIsInvalidResponse`; `getUnknownStatusIsInvalidResponse`; `getNetworkErrorIsSourceNetwork`; `getCancelledErrorIsCancellation`; `getTimesOutAfterSixtySecondsOnTheEngineClock` (manual clock; `SourceError.network`); `signInHasNoTimeout` (advance the clock 10 minutes; still pending); `signInOkReturnsAccountAndToken`; `signInBlockedIsAdminApprovalRequired`; `signInUnavailableIsInvalidResponse`; `cancellingTheSigningInTaskSendsCancelSignInWithTheSameSignInID`; `lateSignInAnswerAfterCancelIsDropped`; in `LifecycleTests`: `kindRegisteredOnlyWithFlagAndMicrosoftClientId` (flag and id: listed configured; flag without id: listed unconfigured; no flag: absent from `availableAccountKinds`) and `readyAdvertisesExternalTokensOnlyWhenTheFlagIsSet`; `diagnosticsNeverContainTokenOrAccountID` (sentinels in a successful and a failing exchange; scan every emitted diagnostic).
- [ ] **Step 2:** `swift test --filter TimeTugEngineCTests`. Expected: FAIL.
- [ ] **Step 3:** Implement as specified. `EngineHost` is not touched.
- [ ] **Step 4:** Run `swift test --filter TimeTugEngineCTests` and `swift test`. Expected: PASS, the ten existing scenarios unchanged.
- [ ] **Step 5: Commit** — `git commit -m "C layer: remote external token source and brokered kind registration"`.

### Task 9: Engine: identity-family rule in `AccountManager`

**Files:**
- Modify: `Sources/TimeTugEngine/Accounts/AccountManager.swift` (the "already added" check in `addAccount`, around line 147)
- Test: `Tests/TimeTugEngineTests/Accounts/AccountManagerTests.swift`, fakes in `Tests/TimeTugEngineTests/Support/AccountFakes.swift`

**Interfaces:** Consumes `AccountIdentityFamily` (library). Produces a private `func sameAccount(_ existing: Connection, _ added: Connection) -> Bool`: true when `identityFamily(existing.kindID) == identityFamily(added.kindID)` and the `displayName`s are equal ignoring case, where `identityFamily(kindID)` is `(host.registry.kind(id: kindID) as? AccountIdentityFamily)?.identityFamily ?? kindID`. The message stays "\(connection.displayName) is already added." and the discard path is unchanged.

- [ ] **Step 1: Write the failing tests:** `brokeredMicrosoftIsRefusedWhenBrowserMicrosoftHasTheSameEmail`; `browserMicrosoftIsRefusedWhenBrokeredHasTheSameEmail`; `sameEmailInDifferentCaseIsRefused`; `sameEmailOnDifferentFamiliesIsAllowed` (google and microsoft, as today); `unknownKindOfAnExistingAccountFallsBackToItsKindID`; `refusedBrokeredAddLeavesStoredAccountsAndCredentialsUntouched`; `sameKindDuplicateRuleUnchanged`.
- [ ] **Step 2:** `swift test --filter AccountManagerTests`. Expected: FAIL.
- [ ] **Step 3:** Implement `sameAccount` and use it in `addAccount`.
- [ ] **Step 4:** `swift test --filter TimeTugEngineTests`. Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -m "Engine: treat Microsoft browser and brokered accounts as one identity"`.

### Task 10: Swift scenarios on recorded Graph data

**Files:**
- Modify: `Tests/TimeTugEngineCTests/ScenarioRunner.swift` (a `host.tokens` block, a step that replaces the scripted token answers, a `diagnosticsExclude` expectation), `Tests/TimeTugEngineCTests/ScenarioTests.swift` (three new scenario names)
- Create: `Conformance/Scenarios/add-account-brokered.json`, `brokered-needs-reconnect.json`, `brokered-cancel.json`; data `Conformance/Scenarios/data/graph-me.json`, `graph-calendars.json`, `graph-events-simple.json` (Graph-shaped answers; event "Design review" at 2:30 PM, account `me@example.com`)

**Interfaces:** the `host.tokens` format, shared with the C# runner (Task 11): `{ "signIn": {"status":"ok","accountID":"acct-1","accessToken":"token-1","expiresInSeconds":3600} | {"status":"blocked","reason":"adminConsentRequired"} | "never", "get": {"status":"ok","accessToken":"token-2","expiresInSeconds":3600} | {"status":"interactionRequired","reason":"signedOut"} | {"error":{"kind":"network"}} }`; a step `{ "setTokens": { ... } }` replaces the scripted answers; `expiresInSeconds` is relative to the manual clock; `{ "expect": { "diagnosticsExclude": ["token-1", "me@example.com"] } }` fails if any listed text appears in an `event.diagnostic` message since the last expectation.

Scenarios: `add-account-brokered` — config with `"externalTokens": true` and a Microsoft client id; start; `availableAccountKinds` lists `microsoft-brokered` configured; `account.add`; the events subsequence `service.token.signIn`, `service.http.send` GET `/me`, calendars, events; no `service.credentials.set`; state shows account `me@example.com` with `config.authMode == "external"` and `config.externalAccountID == "acct-1"` and the event "Design review"; `diagnosticsExclude` for `token-1`, `acct-1` and `me@example.com`. `brokered-needs-reconnect` — added as above; first `setTokens` `get: {"error":{"kind":"network"}}` and `test.advanceClock` past expiry: account status `failing` (not `authExpired`); then `system.event` `networkReturned` with `get: ok`: status `ok`; then `setTokens` `get: interactionRequired`; `test.advanceClock` past expiry; account status `authExpired` with other state intact; `setTokens` ok; `account.reconnect` with a `signIn` ok answer; status `ok` without restart. `brokered-cancel` — `signIn: "never"`; `account.add`; `account.cancel`; expects `service.token.cancelSignIn` with the same `signInID`, no account added, no error message.

- [ ] **Step 1: Write the scenarios and runner support first**; run `swift test --filter ScenarioTests`. Expected: FAIL (runner lacks `tokens`, kind not offered).
- [ ] **Step 2:** Implement the runner's `ScriptedHost` token answers (answer `service.token.*` from `host.tokens`, record them, derive expiry from the manual clock).
- [ ] **Step 3:** Run `swift test --filter ScenarioTests`. Expected: PASS including the ten existing scenarios.
- [ ] **Step 4: Commit** — `git commit -m "Scenarios: brokered add, needs-reconnect and cancel"`.

### Task 11: C# wrapper: `IExternalTokenHost` and C# scenarios

**Files:**
- Create: `dotnet/TimeTug.Engine/IExternalTokenHost.cs`
- Modify: `dotnet/TimeTug.Engine/Engine.cs` (config flag, dispatch of the three service types, host detection), `dotnet/TimeTug.Engine/Messages.cs` (wire DTOs, `EngineCapabilities.ExternalTokens`), `dotnet/TimeTug.Engine/WireJson.cs` (register the new DTOs in the source-generated context), `dotnet/TimeTug.Engine.Tests/ScenarioRunner.cs` (same `host.tokens` semantics as Task 10), `ScenarioTests.cs` (three new scenarios), `FixtureRoundTripTests.cs` (new fixtures), `EngineTests.cs`
- Test: those test files

**Interfaces (Produces, all public):**
- `interface IExternalTokenHost { ValueTask<ExternalTokenResult> GetTokenAsync(ExternalTokenRequest request, CancellationToken cancellationToken); ValueTask<ExternalSignInResult> SignInAsync(ExternalSignInRequest request, CancellationToken cancellationToken); void CancelSignIn(string signInID); }` (`CancelSignIn` is best effort and must not block or throw).
- `sealed record ExternalTokenRequest(string ConnectionID, string AccountID, string? Email, IReadOnlyList<string> Scopes, bool ForceRefresh)`; `sealed record ExternalSignInRequest(string SignInID, IReadOnlyList<string> Scopes, string? AccountID, string? Email)`.
- `sealed record ExternalTokenResult(string Status, string? AccessToken = null, DateTimeOffset? ExpiresAt = null, string? Reason = null)` and `sealed record ExternalSignInResult(string Status, string? AccountID = null, string? AccessToken = null, DateTimeOffset? ExpiresAt = null, string? Reason = null)`, each with static factories (`Ok(...)`, `InteractionRequired(reason)`, `Unavailable(reason)`; `Blocked(reason)` for sign-in), and a static class `ExternalTokenStatus` with the string constants `Ok`, `InteractionRequired`, `Unavailable`, `Blocked`.
- `EngineCapabilities.ExternalTokens { get; init; }` (an additive property).
- The wrapper uses `options.Host as IExternalTokenHost`: non-null sets `ExternalTokens = true` in the config; a host without it answers the three requests with `ServiceErrorKind.NotFound` (as for text generation). `EngineOptions` and `IEngineHost` are unchanged. An `OperationCanceledException` from the host maps to a `cancelled` reply, an `EngineServiceException` to its kind, anything else to `failed`.

- [ ] **Step 1: Write the failing tests:** `hostWithoutExternalTokenInterfaceSendsNoFlagAndAnswersNotFound`; `hostWithInterfaceSetsTheFlagAndReadyCapabilityIsTrue`; `getTokenOkIsSerializedWithMillisecondUtcExpiry` (assert the exact wire text of `expiresAt`); `interactionRequiredAndUnavailableAreSerialized`; `signInReceivesTheScopesAndOptionalAccount`; `cancelSignInIsCalledOnAccountCancelWithTheSameId`; `hostExceptionMapsToFailedAndCancellationToCancelled`; `hostExceptionMessageWithTheTokenIsNotEchoedInADiagnostic` (sentinel in the exception message; the wrapper's `wrapper` diagnostics do not repeat exception messages from this interface); the three new scenarios run through the real DLL and pass; the new golden fixtures round-trip through the C# types.
- [ ] **Step 2:** `pwsh scripts/ci/run-dotnet-tests.ps1`. Expected: FAIL.
- [ ] **Step 3:** Implement. Add the new DTOs to the `WireJson` context (a missing registration shows up as a runtime serialization error, not a compile error).
- [ ] **Step 4:** Run the C# tests on the x64 and ARM64 jobs (CI) and locally where possible; raise `scripts/ci/dotnet-test-floor.txt` to the new count if the repository requires it. Run `compat`, `compat-dotnet` and package validation. Expected: PASS; additions only.
- [ ] **Step 5: Commit** — `git commit -m "C# wrapper: IExternalTokenHost and brokered scenarios"`.

### Task 12: Review, PRs, release 1.8.0, protocol docs in `timetug`

**Files:** in `timetug` (the repository this plan lives in): `docs/engine-protocol.md` (list the three new types, the config flag and the capability), `docs/superpowers/specs/2026-10-15-phase-4-engine-c-interface-design.md` (a short amendment section).

- [ ] **Step 1:** Run `deepseek-review` on the `timetug-shared` diff (Tasks 6 to 11), verify findings, fix real defects with a failing test first.
- [ ] **Step 2:** Open the PR(s) to `main` (engine and contract; the wrapper may be the same PR). Checks green on macOS, Linux and both Windows architectures. **(owner)** merges and approves the `publish` environment; the release publishes `timetug-shared` 1.8.0 and `TimeTug.Engine` 1.8.0 on nuget.org and dispatches the bump PRs.
- [ ] **Step 3:** Open the docs PR in `timetug` for the two files above; **(owner)** merges. The engine bump PR in `timetug` carries no code change (the Mac does not set the flag); **(owner)** merges it when green.

---

## Part C: `timetug-windows`

Work in a worktree of `binary-companion/timetug-windows` off `origin/main`. Presentation tests run on any machine (`dotnet test tests/TimeTug.Presentation.Tests`); Platform and app tests, self-tests and axe run through `scripts/verify.ps1` on a Windows runner or the VM (`scripts/vm/vm-selftest.sh`).

### Task 13: Engine bump and package pins

**Files:** `Directory.Packages.props`, `src/TimeTug.Platform/TimeTug.Platform.csproj`, `src/TimeTug.App/TimeTug.App.csproj` (only if the spike's packaging recipe needs it), `tests/TimeTug.Architecture.Tests/ArchitectureTests.cs`.

- [ ] **Step 1 (owner):** Merge "Bump TimeTug.Engine to 1.8.0" (`Directory.Packages.props`); safe by the backward-compatibility rule.
- [ ] **Step 2: Write the failing architecture test** `Only_the_platform_project_references_msal` (no `Microsoft.Identity` text in the project file or any `.cs` of `TimeTug.Presentation` or `TimeTug.App`, nor in test projects other than `TimeTug.Platform.Tests`). It passes now (nothing references MSAL yet) and must keep passing after Step 3; verify it fails against a deliberately misplaced reference before removing it.
- [ ] **Step 3:** Add `PackageVersion` entries for `Microsoft.Identity.Client` and `Microsoft.Identity.Client.Broker` (and the NativeInterop package if the spike says it is separate) at the exact versions the spike chose, with a comment citing `docs/spikes/2026-11-wam-broker.md`. Add the `PackageReference` lines to `TimeTug.Platform.csproj` only. Apply the spike's `msalruntime` packaging recipe for the three flavours.
- [ ] **Step 4:** Build both architectures (`scripts/verify.ps1`). Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -m "Pin MSAL and the WAM broker; architecture rule"`.

### Task 14: Broker core in `TimeTug.Platform/Broker`

**Files:**
- Create: `src/TimeTug.Presentation/Accounts/IBrokerSignInIntent.cs` (`enum BrokerIntent { WindowsAccount, PickAccount }`; `interface IBrokerSignInIntent { void Arm(BrokerIntent intent); BrokerIntent Take(); }` where `Take` returns the armed intent and resets to `WindowsAccount`; plus a thread-safe `BrokerSignInIntent` implementation)
- Create: `src/TimeTug.Platform/Broker/IBrokerClient.cs`, `BrokerOutcome.cs`, `BrokerReason.cs`, `IBrokerParentWindow.cs`, `MsalBrokerClient.cs`, `MsalErrorMapper.cs`, `BrokeredTokenHost.cs`
- Test: `tests/TimeTug.Platform.Tests/Broker/MsalErrorMapperTests.cs`, `BrokeredTokenHostTests.cs`, `FakeBrokerClient.cs`; `tests/TimeTug.Presentation.Tests/Accounts/BrokerSignInIntentTests.cs`

**Interfaces (Produces):**
- `interface IBrokerClient { ValueTask<IReadOnlyList<BrokerAccount>> ListAccountsAsync(CancellationToken ct); ValueTask<BrokerOutcome> AcquireSilentAsync(string accountId, string? email, IReadOnlyList<string> scopes, bool forceRefresh, CancellationToken ct); ValueTask<BrokerOutcome> AcquireInteractiveAsync(BrokerIntent intent, string? accountId, string? email, IReadOnlyList<string> scopes, CancellationToken ct); }`.
- `sealed record BrokerAccount(string AccountId, string? Email)`.
- `abstract record BrokerOutcome` with sealed nested cases `Ok(string AccountId, string AccessToken, DateTimeOffset ExpiresAt)`, `UiRequired(string Reason)`, `Cancelled`, `Blocked(string Reason)`, `Unavailable(string Reason)`, `Network`, `Failed`. `static class BrokerReason` holds the eight documented code strings.
- `interface IBrokerParentWindow { nint Handle { get; } }` (implemented by the app, Task 15; refined in Task 17).
- `MsalBrokerClient : IBrokerClient`, built with the Microsoft client id: `PublicClientApplicationBuilder.Create(clientId)`, the personal-plus-work audience, `BrokerOptions(BrokerOptions.OperatingSystems.Windows)` with `ListOperatingSystemAccounts`, `WithParentActivityOrWindow` from `IBrokerParentWindow`, no token-cache file, no MSAL log callback. `BrokerIntent.WindowsAccount` uses `PublicClientApplication.OperatingSystemAccount`; `PickAccount` shows the account picker. Account matching follows the spike's S4 verdict. A static `TryCreate(...)` returns null when MSAL or `msalruntime` cannot load.
- `MsalErrorMapper.Map(Exception) -> BrokerOutcome` per the spike's S3 table. Contract, independent of the table's exact codes: `MsalUiRequiredException` becomes `UiRequired` with a documented reason (`consent`, `signedOut`, `mfa`, `policy`, `accountMissing`); a user cancel becomes `Cancelled`; consent or admin-approval service errors become `Blocked(adminConsentRequired)`; WAM missing, disabled or unsupported becomes `Unavailable(brokerUnavailable)`; transport errors become `Network`; everything else `Failed`. The log line carries the step and the MSAL error code only.
- `BrokeredTokenHost : IExternalTokenHost` over `IBrokerClient` and `IBrokerSignInIntent`: `GetTokenAsync` calls `AcquireSilentAsync` only (never interactive); `SignInAsync` takes the armed intent and calls `AcquireInteractiveAsync`; `CancelSignIn(signInID)` cancels that sign-in's linked token and ignores unknown ids. Outcome to result: `Ok` to the `Ok` result; `UiRequired` to `InteractionRequired(reason)`; `Blocked` to `Blocked(reason)`; `Unavailable` to `Unavailable(reason)`; `Network` throws `EngineServiceException(Network, ...)`; `Cancelled` throws `OperationCanceledException`; `Failed` throws `EngineServiceException(Failed, ...)`. Exception messages are codes, never Windows text.

- [ ] **Step 1: Write the failing tests:** `MsalErrorMapperTests`, one per row of the spike's table (`uiRequiredNoAccountIsUiRequiredAccountMissing`, `uiRequiredAfterPasswordChangeIsUiRequiredSignedOut`, `userCancelIsCancelled`, `consentBlockedIsBlockedAdminConsentRequired`, `brokerMissingIsUnavailableBrokerUnavailable`, `noNetworkIsNetwork`, `unknownExceptionIsFailed`) and `logLineContainsOnlyTheErrorCode` (the exception message carries a sentinel email; the recording diagnostics must not contain it). `BrokeredTokenHostTests`: `silentNeverCallsInteractive`; `silentOkMapsToken`; `silentUiRequiredMapsToInteractionRequiredWithReason`; `silentUnavailableMapsToUnavailable`; `silentNetworkThrowsNetworkServiceException`; `signInTakesTheArmedIntentAndResetsIt`; `signInDefaultsToTheWindowsAccountIntent`; `signInPickAccountIntentReachesTheBroker`; `signInOkReturnsAccountIdAndToken`; `signInBlockedMapsToBlocked`; `signInCancelledThrowsOperationCanceled`; `cancelSignInCancelsOnlyThatSignIn` (two overlapping sign-ins); `cancelSignInForUnknownIdIsIgnored`; `exceptionMessagesAreCodesNotWindowsText`; `scopesAreForwardedUnchanged`. `BrokerSignInIntentTests`: arm, take, reset.
- [ ] **Step 2:** `dotnet test tests/TimeTug.Platform.Tests --filter Broker` (Windows) and the Presentation test. Expected: FAIL.
- [ ] **Step 3:** Implement the types above. `MsalBrokerClient` itself is covered by the mapper tests plus `broker-probe` (Task 15); no unit test needs a real broker.
- [ ] **Step 4:** Re-run. Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -m "Broker core: IBrokerClient, MSAL client, error mapping, token host"`.

### Task 15: Host wiring, packaging check, probe and privacy test

**Files:**
- Create: `src/TimeTug.Platform/Broker/BrokeredEngineHost.cs`, `src/TimeTug.App/Services/BrokerParentWindow.cs` (the minimal `IBrokerParentWindow` that slice A needs to compile: the handle of the foreground TimeTug window if any, else a hidden top-level window the class creates; Task 17 refines the choice using the spike's S7 verdict), `src/TimeTug.App/SelfTest/Scenarios/BrokerProbeScenario.cs`
- Modify: `src/TimeTug.Platform/WindowsEngineHost.cs` (`Create` accepts the Microsoft client id, `IBrokerParentWindow` and `IBrokerSignInIntent` and returns `IEngineHost`: a `BrokeredEngineHost` when a client id exists and `MsalBrokerClient.TryCreate` succeeds, else the plain host), `src/TimeTug.App/Composition/AppComposition.cs` (pass the id from `startup.OAuthClients["microsoft"]` and the intent singleton), `scripts/ci/check-release-package.ps1` and `scripts/ci/tests/check-release-package.tests.ps1` (require `msalruntime` for the package's architecture; file names from the spike), `scripts/ci/selftest-scenarios.txt` (add `broker-probe`)
- Test: `tests/TimeTug.Platform.Tests/WindowsEngineHostTests.cs`, `tests/TimeTug.Platform.Tests/Broker/BrokerPrivacyTests.cs`

**Interfaces:** `BrokeredEngineHost(IEngineHost inner, IExternalTokenHost tokens) : IEngineHost, IExternalTokenHost, IDisposable`, forwarding every `IEngineHost` member to `inner` and the three token members to `tokens`. `WindowsEngineHost.Create(IUrlLauncher launcher, IAccountFormService forms, IDiagnostics diagnostics, string? microsoftClientId, IBrokerParentWindow parent, IBrokerSignInIntent intent, Func<string, IBrokerParentWindow, IBrokerClient?>? brokerFactory = null) -> IEngineHost`; `brokerFactory` is the test seam, defaulting to `MsalBrokerClient.TryCreate`, and a test passes one that returns null or a fake.

- [ ] **Step 1: Write the failing tests.** `WindowsEngineHostTests`: `createWithoutMicrosoftClientIdIsNotAnExternalTokenHost`; `createWhenTheBrokerClientCannotBeBuiltIsNotAnExternalTokenHost` (`brokerFactory` returns null); `createWithClientIdAndBrokerIsAnExternalTokenHost`; the existing every-member `IEngineHost` test still passes for the plain host. `BrokerPrivacyTests`: `sentinelTokenEmailAndAccountIdAppearInNoRollingLogEtwOrCopyDiagnostics` (run `BrokeredTokenHost` through ok, ui-required, blocked, network and failed outcomes with sentinel values, including an exception whose message embeds all three; fan diagnostics to the real `RollingFileLog` in a temp directory, the `EtwDiagnostics` test sink and `DiagnosticsReader`; none of the three sentinels appears in any of them). `check-release-package.tests.ps1`: a fixture package without `msalruntime` for its architecture fails with a message naming the file; one with it passes.
- [ ] **Step 2:** Run the Platform tests and `pwsh scripts/ci/tests/check-release-package.tests.ps1`. Expected: FAIL.
- [ ] **Step 3:** Implement the decorator, the `Create` change, the package check, and `BrokerProbeScenario`: it loads the real `MsalBrokerClient`, calls `ListAccountsAsync` (no UI), records "broker loaded", the account count or the `Unavailable` reason in the scenario log, and never fails the run on `Unavailable` (a hosted runner may have no WAM).
- [ ] **Step 4:** Run `scripts/verify.ps1`, then the self-test with `broker-probe` on the ARM64 VM (`scripts/vm/vm-selftest.sh`) and read its result; CI covers x64. Expected: PASS; the probe reports the broker loaded on the VM.
- [ ] **Step 5: Commit** — `git commit -m "Wire the broker into the engine host; package check and probe"`; open the **slice A PR** (Tasks 13 to 15), run `deepseek-review`, fix verified findings; **(owner)** merges when green.

### Task 16: Presentation: providers, welcome, flyout row

**Files:**
- Modify: `src/TimeTug.Presentation/Welcome/ProviderItem.cs` (adds `Intent` and `SecondaryText` through a second constructor; the existing one stays), `src/TimeTug.Presentation/Welcome/AccountsViewModel.cs`, `src/TimeTug.Presentation/Welcome/WelcomeViewModel.cs`, `src/TimeTug.Presentation/Welcome/ConnectedAccount.cs` (adds `IsOnThisPc`), `src/TimeTug.Presentation/Flyout/FlyoutViewModel.cs` and `FlyoutRow.cs`, `src/TimeTug.Presentation/Settings/SettingsText.cs` if it holds the pane's search catalog
- Test: `tests/TimeTug.Presentation.Tests/Welcome/WelcomeViewModelTests.cs`, `tests/TimeTug.Presentation.Tests/Settings/AccountsPaneTests.cs`, `tests/TimeTug.Presentation.Tests/Flyout/FlyoutViewModelTests.cs`, fakes in `tests/TimeTug.Presentation.Tests/Welcome/Fakes.cs`

**Interfaces:**
- Consumes: `IBrokerSignInIntent`, `BrokerIntent` (Task 14); engine state kinds `microsoft-brokered` and `microsoft`.
- Produces: `AccountsViewModel(IEngineClient, IUiDispatcher, ILocalizer, TimeProvider? clock = null)` keeps its signature and gains a settable property `IBrokerSignInIntent? BrokerIntents` (set by composition); `Task ConnectAsync(string kindId)` stays and a new `Task ConnectBrokeredAsync(BrokerIntent intent)` arms the intent and then runs the add for `microsoft-brokered`. The intent never outlives its attempt: when the attempt ends (account added, failed, declined or cancelled) the view model re-arms `BrokerIntent.WindowsAccount`, and `ReauthorizeAsync` arms `WindowsAccount` before it sends the reconnect.

Behaviour (spec, "Windows design / Presentation"): `microsoft-brokered` is ordered first and named by the string key `Provider_microsoft-brokered` ("Microsoft account on this PC"); when it is listed configured, an extra item "Another Microsoft account" (id `microsoft-brokered:pick`, the picker intent) follows it and the existing `microsoft` item is named "Microsoft (browser)" (key `Provider_microsoft-browser`); when `microsoft-brokered` is not listed, `microsoft` keeps its "Microsoft" name and the list is unchanged. The waiting text is built from the attempted kind: for a brokered attempt it is "Waiting for Windows…" whatever the engine's `waitingStyle` says. Connected rows of the brokered kind carry `IsOnThisPc` (the "On this PC" tag). A failed brokered attempt whose engine message reads as unavailable shows "Windows sign-in isn't available here" and a button "Use your browser instead" that calls `ConnectAsync("microsoft")`; a failed attempt with the admin-approval message shows the engine's text and keeps the browser button (the person may use another account). A declined or cancelled attempt (the activity ended with no account and no message) returns silently to the list with no error on any provider. Welcome: the brokered provider is pre-selected when the engine lists it configured; if the spike's S2 verdict allows naming the Windows account the item reads "Use name@example.com", otherwise "Microsoft account on this PC"; the pre-click text from Global Constraints shows under it; `ShouldShowAtStartup` is unchanged. Settings > Accounts shows the `Accounts_WithdrawConsent` text beneath the connected list whenever at least one `microsoft-brokered` account is connected (hidden otherwise). Flyout: a problem row for a `microsoft-brokered` account in `authExpired` shows "Open Accounts" (opens Settings on Accounts) instead of "Sign in again".

- [ ] **Step 1: Write the failing tests.** `AccountsPaneTests`: `brokeredProviderIsOrderedFirstAndNamedOnThisPc`; `anotherMicrosoftAccountItemFollowsItAndArmsThePickerIntent`; `windowsAccountItemArmsTheWindowsAccountIntent`; `intentIsResetWhenAnAttemptEndsWithoutReachingTheBroker`; `reconnectAfterAPickerAttemptUsesTheWindowsAccountIntent`; `browserMicrosoftIsRelabelledOnlyWhenBrokeredIsListed`; `withoutBrokeredKindTheListIsUnchanged`; `brokeredAttemptWaitingTextIsWindowsNotBrowser`; `connectedBrokeredRowShowsOnThisPcTag`; `declinedAttemptShowsNoErrorAndReturnsToTheList`; `unavailableAttemptShowsWindowsSignInIsntAvailableAndTheBrowserButton`; `browserButtonConnectsTheBrowserKind`; `adminApprovalFailureShowsEngineTextAndKeepsTheBrowserButton`; `reconnectOfABrokeredAccountSendsReconnectAndStaysBusyUntilState`; `removingABrokeredAccountSendsRemoveOnly` (the fake intent sees nothing); `withdrawConsentTextShowsOnlyWhileABrokeredAccountIsConnected`; `preClickTextShowsUnderTheBrokeredCard`. `WelcomeViewModelTests`: `brokeredCardIsPreselectedWhenConfigured`; `cardNamesTheWindowsAccountWhenTheBrokerListsOne` and `cardFallsBackToTheUnlabelledText`; `declineReturnsToStepOneSilently`; `successMovesToStepTwoWithCountAndNextMeeting`; `welcomeWithoutBrokeredKindIsUnchanged`. `FlyoutViewModelTests`: `authExpiredBrokeredRowSaysOpenAccounts`; `authExpiredBrowserRowStillSaysSignInAgain`.
- [ ] **Step 2:** `dotnet test tests/TimeTug.Presentation.Tests`. Expected: FAIL.
- [ ] **Step 3:** Implement as described; strings come through `ILocalizer` keys that Task 17 adds (the test localizer returns the English text).
- [ ] **Step 4:** Re-run the Presentation tests. Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -m "Presentation: Microsoft account on this PC"`.

### Task 17: App UI, strings, self-tests, accessibility

**Files:**
- Create: `src/TimeTug.App/SelfTest/FakeBrokerClient.cs`, `src/TimeTug.App/SelfTest/Scenarios/WelcomeBrokeredScenario.cs`, `AccountsBrokeredScenario.cs`, `BrokeredReconnectScenario.cs`, `BrokeredUnavailableScenario.cs`; data `tests/data/graph-me.json`, `graph-calendars.json`, `graph-events-simple.json`
- Modify: `src/TimeTug.App/Services/BrokerParentWindow.cs` (created in Task 15; now prefers the foreground welcome or Settings window handle, then the hidden owner window if the spike's S7 verdict says it works, then the minimal fallback), `src/TimeTug.App/Strings/en-US/Resources.resw` (all strings from Global Constraints, including `Accounts_WithdrawConsent`, plus the keys Task 16 uses), `src/TimeTug.App/Views/WelcomeWindow.xaml(.cs)`, `src/TimeTug.App/Settings/AccountsPage.xaml(.cs)`, `src/TimeTug.App/Flyout/ProblemRowView.xaml(.cs)`, `src/TimeTug.App/Composition/AppComposition.cs` (register `IBrokerSignInIntent`, set `AccountsViewModel.BrokerIntents`), `src/TimeTug.App/SelfTest/ScriptedCalendarHost.cs` (also an `IExternalTokenHost` over `FakeBrokerClient` and `BrokeredTokenHost`, with the Graph answers from `tests/data`), `scripts/ci/selftest-scenarios.txt` (one row per new scenario), `tests/TimeTug.App.A11y` (hold windows for the new states)

Scenarios (each over the real engine with the fake broker; the `Name` constants and rows in `selftest-scenarios.txt` must match, which `check-repository-contracts.py` enforces):
- `welcome-brokered`: one click on the pre-selected card, step 2 shows "Microsoft, 3 calendars, next: Design review at 2:30 PM"; second pass: the fake answers `Cancelled`, the window stays on step 1 with no error.
- `accounts-brokered`: Add Account lists "Microsoft account on this PC", "Another Microsoft account" and "Microsoft (browser)"; add through the picker intent; the "On this PC" tag shows; removing the account asks nothing of the broker (the fake records zero calls).
- `brokered-reconnect`: advance the clock, the fake answers `UiRequired`; the flyout shows the problem row with "Open Accounts"; Settings shows "Sign in again"; the fake then answers `Ok`; the account recovers without a restart.
- `brokered-unavailable`: the fake answers `Unavailable`; the card shows "Windows sign-in isn't available here" and "Use your browser instead"; pressing it starts the browser kind.

- [ ] **Step 1: Write the scenarios and the resource keys first**; run `pwsh scripts/ci/run-selftest.ps1` for each new scenario. Expected: FAIL (cards absent).
- [ ] **Step 2:** Implement the XAML and code-behind: the extra provider items and their secondary text, the "On this PC" tag, the unavailable card with the browser button, the "Open Accounts" button on the problem row, automation names for every new control, and the refined `BrokerParentWindow`.
- [ ] **Step 3:** Run the whole self-test on x64 (CI) and ARM64 (`scripts/vm/vm-selftest.sh`), then `scripts/ci/run-a11y.ps1`. Expected: PASS with screenshots for the four scenarios; axe reports no new violation (add a suppression only with a stated reason, as the existing file does).
- [ ] **Step 4: Commit** — `git commit -m "App: Microsoft account on this PC cards and self-test scenarios"`.

### Task 18: Docs, review and slice B PR

**Files:** `docs/parity.md` (row 42 moves from later to done, differs on purpose; add the Mac/Windows consent comparison from the spec's Parity section), `docs/manual-tests/windows-checklist.md` (new items 2.6 onward under "2. Real accounts": personal account through the Windows account; the picker with "Another Microsoft account"; a work account with MFA; consent declined; consent withdrawn at the provider (account.live.com/consent/Manage for personal accounts, the organization's My Apps page for work accounts) then Sign in again; account removed from Windows; a password change; no network during sign-in; a tenant that blocks user consent shows "admin approval is required"; a local-only Windows account; the broker disabled by policy; Narrator and contrast on the new cards; ARM64 VM and x64), `docs/store/capabilities.md` (no new capability; the sign-in sentence becomes "Windows account broker or browser"), `docs/development.md` (how to run `broker-probe` and the brokered scenarios), `docs/store/listing.md` if it states the sign-in method.

- [ ] **Step 1:** Write the doc changes. Each manual item gives steps, the expected result and what the agent prepared; no item asks the agent to type a password.
- [ ] **Step 2:** Run `deepseek-review` on the whole slice B diff (never send secrets; verify findings); fix real defects test-first; run `scripts/verify.ps1` and the full self-test on both architectures.
- [ ] **Step 3: Commit, push, PR** — `git commit -m "Docs: Windows account sign-in parity, checklist and Store text"`; open the slice B PR; **(owner)** merges when green. The app is released only by the owner.

---

## Part D: Verification and close

### Task 19: Live verification, tracker and program design (owner-attended)

**Files:** `docs/superpowers/plans/2026-10-09-windows-program-tracker.md`, `docs/superpowers/specs/2026-10-09-windows-program-design.md` (section 4.5 amendment), `docs/PROGRESS.md` if the repository still requires an entry.

- [ ] **Step 1 (owner):** On the ARM64 VM with the `msix-arm64` artifact of the latest `main` CI run, run checklist items 2.6 onward with the personal and the work (MFA) accounts. The agent prepares the build and the steps and records the results the owner reports; real-account steps are never automated.
- [ ] **Step 2:** Amend program design section 4.5 with the approved decisions: the second kind (not a mode flag), consent on one click, "Open Accounts" reconnect, the opt-in flag, the identity-family rule and the browser fallback section.
- [ ] **Step 3:** Update the tracker: phase 6 row to `done` with PR links and the verification date; mark the owner checklist line "Phase 6: add the WAM broker redirect URI" done with Task 0's date; add a session-log entry; record the Task 1A recommendation under "Open questions"; list any item the owner did not get to as an open owner item.
- [ ] **Step 4: Commit and PR** — `git commit -m "Tracker: phase 6 WAM sign-in done"`; **(owner)** merges.
