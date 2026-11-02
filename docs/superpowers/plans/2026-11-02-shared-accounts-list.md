# One accounts list for Mac and Windows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Tasks marked **(owner)** are for the owner; agents never do them.

**Goal:** The same accounts control on both platforms: a box listing the signed-in accounts with `+` to add and `-` to remove the selected one, in Settings > Accounts on the Mac and Windows and in the Windows welcome window, with a pinned "this device" row, a single "Microsoft" entry on Windows, and a Google landing page that brings TimeTug forward.

**Architecture:** No library, engine, protocol or persisted-data change (spec D14). Windows work is three slices in `timetug-windows`: W1 the loopback landing page and foreground request, W2 the Presentation model (additive, not user-visible), W3 the WinUI `AccountsListBox`, the welcome and Accounts pages switched over, self-tests and parity rows. The Mac work (M1) is one slice in `timetug`: a pure `AccountsListModel`, selection and removal in `AccountsController`, and a SwiftUI box that replaces the cards. Each side builds its own control; what they share is the numbered behaviour contract L1 to L10 in the spec.

**Tech Stack:** .NET 10, WinUI 3, CommunityToolkit.Mvvm, `System.Net.HttpListener`, axe-windows, the in-app self-test runner (Windows); Swift 6, SwiftUI, XCTest, XcodeGen (Mac).

> **Amended 2026-11-02 (second pass):** Windows slice W4 (Part F below) replaces the pinned "This PC's Windows account" row, its switch and the "On this PC" tag with an ordinary row added on Continue, and adds service logos. W2 and W3 as written above are history; the Mac slice M1 is unchanged. Source of truth: spec Amendment A1 and decisions D16 to D19.

**Spec:** `docs/superpowers/specs/2026-11-02-shared-accounts-list-design.md` (approved; PR 161; amended by A1). Parents: `docs/superpowers/specs/2026-10-30-phase-6-wam-sign-in-design.md` (items 1, 2, 4 and D1 are amended by the spec), `docs/superpowers/specs/2026-10-16-phase-5-windows-app-core-design.md`, `docs/superpowers/specs/2026-10-09-windows-program-design.md` sections 4 and 4.5. Style reference: `docs/superpowers/plans/2026-11-01-phase-6-wam-sign-in.md`.

**Owner decisions (approved; the owner accepted the defaults for all nine open questions):** Q1 a short step 1 "Welcome to TimeTug" with "Get started"; Q2 no Mac welcome window, the Apple Calendar row moves into the box as the pinned row; Q3 *(moot after A1: no Windows switch)*; Q4 `+` in the welcome window adds and stays on step 2, Continue is the only way to step 3; Q5 after the Windows dialog is closed with no account the link "Use your browser instead" shows with no error words; Q6 *(reshaped by A1.2: one or several listed accounts are treated alike, "offered"; the real-account run still settles what Windows lists)*; Q7 if the foreground request is often refused, accept it (no `timetug:` protocol); Q8 "You're connected" shows whenever the redirect carries a code; Q9 no extra "Browser" tag. D1 to D15 in the spec stand.

## Merge order and who does what

| Order | Repository | What | Who merges / publishes |
|---|---|---|---|
| 0 | `timetug` | This plan and the tracker row | merged by the agent on green (standing authorization for plan PRs) |
| 1 | `timetug-windows` | W1 (Tasks 1 to 3), shippable alone; `timetug` docs PR D1 (Task 3) | owner merges |
| 2 | `timetug-windows` | W2 (Tasks 4 to 9): not user-visible, says so in its PR | owner merges |
| 3 | `timetug-windows` | W3 (Tasks 10 to 13); `timetug` docs PR D2 (Task 13) | owner merges |
| 4 | `timetug` | M1 (Tasks 14 to 17), independent of 1 to 3 and may merge before or between them | owner merges |
| 5 | both | Owner-attended checks and the tracker close (Task 18) | **(owner)** for the real-account and screen-reader steps |

W2 may be prepared while W1 waits, and W3 while W2 waits, but a slice cannot merge before the one it builds on. M1 and the Windows slices share no code. Squash-merge every PR when its checks are green (`gh pr merge --squash`). No library or engine release is involved, so the bump chain does not move; each app is released only by the owner. If any task seems to need an engine, library, protocol or fixture change, stop: that is spec D14 and goes back to the owner.

## Owner-only steps (flagged in the tasks)

- Task 3 Step 4: spike S-FG, the foreground request with Edge, Chrome and Firefox on the VM and one other PC (the owner runs the Google sign-in; nobody types a credential for the owner).
- Tasks 3, 9, 13 and 17: merging the PRs.
- Task 18: every owner-attended item in the spec's "Test strategy" (Windows 1 to 8, the Mac pass), the real-account listing that settles Q6, and the Narrator and VoiceOver passes.

## Global Constraints

- No change to `calendar-connectors`, `timetug-shared` or `TimeTug.Engine`, the C interface, the wire protocol, golden fixtures, persisted account files, Entra and Google registrations, `docs/store/capabilities.md`, or the Mac's sign-in code (spec "Not changed"). `docs/engine-protocol.md` does not change.
- Principle: one consent per Microsoft account, asked once, with a visible user action first. Nothing is requested from Windows until the person presses Continue; the account listing (no token, no dialog) is the only broker call allowed before it.
- No focus stealing: no simulated keys, no thread-input attachment (timetug-windows `AGENTS.md`). The foreground request is the ordinary activate call and may be refused. No attempt to close the browser tab, no embedded browser.
- View models stay free of OS and MSAL types; only `TimeTug.Platform` talks to the broker (architecture tests stay green). Strings live in `Resources.resw` on Windows and in the SwiftUI sources on the Mac.
- Behaviour contract L1 to L10 (spec "The shared control") is the acceptance list on both platforms; each task cites the numbers it implements. The accessibility names below are exact.
- *(Amended by A1: the Windows pinned-row strings "This PC's Windows account", its description, the D8 conflict line, the switch name and "On this PC" no longer exist; the withdrawal text applies to every Microsoft account. Part F lists what replaces them. The list below is the first draft's and still holds for everything else.)*
- Exact strings: "No accounts yet. Choose + to add one."; "Use your browser instead"; "Windows sign-in isn't available here"; "Remove name?" with the body "Its calendars will no longer appear and their Tug and visibility choices are forgotten." (plus, for a Microsoft account, the existing `Accounts_WithdrawConsent` text); "Welcome to TimeTug" with the button "Get started"; "Connect your calendars" with "Continue" and "Skip for now"; Narrator: list "Connected accounts", `+` "Add account", `-` "Remove name" (a row selected) or "Remove account" (nothing selected); live regions "Waiting for Windows..." / "Waiting for your browser..." (polite), the error line (assertive), "name removed".
- Landing page (spec D13): outcomes "You're connected" / "Return to TimeTug." and "Sign-in didn't finish" / "Return to TimeTug and try again."; page title "TimeTug"; keys `Landing_PageTitle`, `Landing_ConnectedTitle`, `Landing_ConnectedBody`, `Landing_FailedTitle`, `Landing_FailedBody`, each with a translator comment; headers `Cache-Control: no-store`, `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`; no script, no external URL, no query-string text echoed.
- The broker listing limit is 5 s (first call about 1.6 s and later about 0.1 s in the spike).
- Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR bodies end `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Implementation work uses Sonnet 5.5 (D15); each PR gets a `deepseek-review` pass (never send secrets; verify every Critical or Important finding against the repository before acting).
- Real-account and screen-reader steps cannot be automated: the agent prepares the build, steps and expected text; the owner presses and approves.

## Decisions this plan makes (small; flagged for the owner's read)

These fill gaps the spec leaves; each is local and reversible.

1. **Test framework on the Mac is XCTest**, not Swift Testing as the spec says: all 42 test files in `Apps/macOS/Tests` use XCTest and mixing frameworks buys nothing.
2. **W2 is additive through a flag.** `WelcomeViewModel` gets `bool ListFlow { get; init; }` (default false). With it true the window starts on a new `WelcomeStep.Intro`, does not advance on `Connected`, and uses the pinned row and the Continue rule; with it false nothing changes. W3 sets it by construction and deletes the flag with the old behaviour. Likewise `AccountsViewModel` gains new members (`DeviceRow`, `MenuEntries`, `ListAccounts`, selection) beside the cards' members; W3 deletes the card members (`Providers`, `PreselectBrokered`, `OffersBrowserFallback` and its text properties, `IWindowsAccountSource.GetEmailAsync`, the three `Provider_microsoft-*` strings).
3. **The listing shape** is `WindowsAccountListing(WindowsListingKind Kind, string? Email)` with kinds `Unavailable` (broker not offered, throw or the 5 s timeout), `None`, `OneNamed`, `Unnamed`. The 5 s limit and its diagnostics line live in `BrokerWindowsAccountSource`, which takes an optional `TimeProvider`.
4. **"The window that started the sign-in"** is the most recently *active* registered TimeTug window: the person pressed `+` or Continue in it, so it was the active one. `BrokerParentWindow` gains `Touch(handle)`, called from the welcome and Settings windows' `Activated` handlers, which moves a registered handle to the end of its list. The requester never uses the hidden fallback window; with none open it does nothing. (Passing the originating handle through the engine host would need plumbing across the engine seam for no visible gain.)
5. **The foreground call is raised for every captured redirect**, including the `error` one, because that page also tells the person to return. It is not raised for the favicon, a stray request, a cancelled wait or the broker path. The spec's "not for a failed sign-in" is read as a failure before any redirect (the spec's own test strategy says "once per captured redirect"). If the owner prefers the other reading, gating the notifier on `Connected` is a one-line change and one test.
6. **Landing language** comes from `CultureInfo.CurrentUICulture` (tag for `lang`, `TextInfo.IsRightToLeft` for `dir`); `ILocalizer` has no language property.
7. **The `Landing_*` keys and the keys W2's view models consume are added to `Resources.resw` with the code that reads them**, not all in W3, so no slice reads a missing string. XAML-only keys (`Accounts_AddAutomation` and the like) arrive with W3.
8. **`AccountsListBox` lives in `src/TimeTug.App/Controls/`** (a new folder).
9. **ADR 0021 is written with M1**, not with this plan: its "Verified by" column needs the tests that exist then. The dated amendments to the older specs land with the slice that makes each statement true (D1 with W1, D2 with W3), as the spec's release order says.
10. **`settings-accounts` and `a11y-hold`** self-tests are adapted in W3 as well as the five the spec names, because they touch the cards being deleted.

## Review Focus

The inputs and failure modes the spec implies that no happy-path test would exercise, most likely first. Each line names the tasks whose tests pin it.

- **A stray or hostile request on the loopback port** (a bare `GET /`, a port scanner, a request with an unrelated or 100 KB query, the favicon) while a Google sign-in is waiting: the sign-in is not burned and the listener keeps waiting; only a request carrying a non-empty `code` or `error` ends the wait (the engine still validates `state`, as today). Whatever such a request carries (`code=<script>`, `error=` with HTML) is never echoed into the page. Tasks 1 and 2.
- **The broker listing is late, absent, throws, names two accounts, or names an account that differs only in case from a connected one**: the pinned row is hidden (a connected brokered account still shows as an ordinary row and never disappears), appears later without taking focus, Continue stays disabled while the answer is pending, and no broker call other than the listing happens before Continue. Tasks 4, 5 and 8.
- **Decline, close or fail the Windows dialog at Continue, or add an account with `+` first**: nothing is added, no error words, the person stays on step 2 with the switch still on and the "Use your browser instead" link visible; with the Windows account already connected Continue asks Windows for nothing; the switch off with an empty list leaves Continue disabled and Skip for now as the way out. Tasks 6 and 8.
- **Removing while the engine keeps publishing**: the selected row removed by another path, Delete with nothing selected, `-` during a sign-in, a removal the engine refuses; the row leaves only when the engine's state says so, selection and focus land on the next row, else the previous, else `+`, and unrelated updates never move keyboard focus. Tasks 7, 11, 15 and 16.
- **Windows refuses the foreground, no TimeTug window is open, or TimeTug is minimized**: no crash, a minimized window is restored, a missing window does nothing, and the sign-in still completes. Tasks 2 and 3.

---

## Part A: `timetug-windows`, slice W1 (landing page and foreground request)

Work in a worktree of `binary-companion/timetug-windows` off `origin/main` (not on this machine: clone it). Platform and App tests, self-tests and axe run through `scripts/verify.ps1` on a Windows runner or the ARM64 VM (`scripts/vm/vm-selftest.sh`); Presentation tests run anywhere (`dotnet test tests/TimeTug.Presentation.Tests`). CI jobs `windows-x64`, `windows-arm64` and `architecture` must be green.

### Task 1: `SignInLandingPage`

**Files:**
- Create: `src/TimeTug.Platform/Auth/SignInLandingPage.cs`
- Test: `tests/TimeTug.Platform.Tests/Auth/SignInLandingPageTests.cs`

**Interfaces (Produces):**
- `enum LandingOutcome { Connected, DidNotFinish, NotARedirect }`.
- `sealed record LandingText(string PageTitle, string ConnectedTitle, string ConnectedBody, string FailedTitle, string FailedBody, string LanguageTag, bool RightToLeft)` with `static LandingText From(ILocalizer text, CultureInfo culture)` (reads the five `Landing_*` keys) and `static LandingText English` (the exact English strings, used when no localizer is given).
- `static class SignInLandingPage`: `LandingOutcome Classify(string rawUrl)`; `string Render(LandingOutcome outcome, LandingText text)` (never called with `NotARedirect`, which throws `ArgumentOutOfRangeException`); `IReadOnlyDictionary<string,string> Headers` (the four headers in Global Constraints).
- `Classify`: the query string is parsed; a non-empty `error` value wins; else a non-empty `code` value is `Connected`; anything else, including `code=` and no query, is `NotARedirect`. Only presence and non-emptiness are read; no value is returned.

- [ ] **Step 1: Write the failing tests:** `codeOnlyIsConnected`; `errorOnlyIsDidNotFinish`; `errorWinsOverCode`; `emptyCodeIsNotARedirect`; `bareRootAndFaviconAreNotARedirect`; `unrelatedQueryIsNotARedirect` (`/?state=x`); `renderConnectedHasTitleBodyLangAndMain` (`<html lang="en">`, one `<h1>You're connected</h1>`, `<p>Return to TimeTug.</p>`, a `<main>` landmark, `<title>TimeTug</title>`, the viewport meta); `renderDidNotFinishHasTheFailedStrings`; `renderSetsDirRtlForArabic` (`LanguageTag: "ar"`, `RightToLeft: true` gives `dir="rtl"`); `renderEncodesEveryStringAsHtml` (strings `"<script>alert(1)</script>&\""` come out encoded, no `<script`); `outputEchoesNothingFromTheQuery` (classify then render for `/?code=<img src=x onerror=1>&state=abc`: output contains neither `onerror` nor `abc`); `outputHasNoScriptNoExternalUrlAndNoFormOrButton` (no `<script`, `<button`, `<form`, `<link`, `<img`, and no `http://` or `https://` other than an SVG namespace if one is used); `outputHasLightDarkContrastAndForcedColorsRules` (`prefers-color-scheme`, `prefers-contrast`, `forced-colors`); `headersAreExactlyTheFourFromTheSpec`; `contrastOfPageColoursIsAtLeastFourPointFive` (parse the `:root` colour pairs for light and dark and compute the WCAG ratio); `englishTextMatchesTheSpecStrings`; `fromLocalizerReadsTheFiveKeys` (a fake `ILocalizer` returning `key + "!"`).
- [ ] **Step 2:** `dotnet test tests/TimeTug.Platform.Tests --filter SignInLandingPage` (Windows). Expected: FAIL (types missing).
- [ ] **Step 3: Implement** in `SignInLandingPage.cs`: one inline-CSS HTML document, every string through `System.Net.WebUtility.HtmlEncode`; the TimeTug mark as an inline `<svg role="img" aria-label="TimeTug">`; colours as CSS custom properties with `@media (prefers-color-scheme: dark)`, `(prefers-contrast: more)` and `(forced-colors: active)` (system colours); no script, no animation, no meta refresh.
- [ ] **Step 4:** Re-run. Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -m "Platform: branded sign-in landing page"`.

### Task 2: Loopback integration, foreground request, strings

**Files:**
- Create: `src/TimeTug.Presentation/Abstractions/ISignInReturnNotifier.cs`, `src/TimeTug.App/Services/SignInForegroundRequester.cs`
- Modify: `src/TimeTug.Platform/Auth/LoopbackAuthorization.cs` (delete `ClosePage`; use the landing page and the notifier), `src/TimeTug.Platform/WindowsEngineHost.cs` (pass the localizer and notifier through `Create`'s optional trailing parameters), `src/TimeTug.App/Composition/AppComposition.cs` (build the requester over the `BrokerParentWindow` registry), `src/TimeTug.App/Services/BrokerParentWindow.cs` (add `nint? OpenWindowHandle`: the most recently active registered window, null when none, never the fallback; add `Touch(nint handle)`, called from the `Activated` handlers of the code that already calls `Register`), `src/TimeTug.App/Strings/en-US/Resources.resw` (the five `Landing_*` keys with `<comment>` translator notes)
- Test: `tests/TimeTug.Platform.Tests/Auth/LoopbackAuthorizationTests.cs`, the App test project's resource-completeness test (extend it to `Landing_*`), `tests/TimeTug.Architecture.Tests/ArchitectureTests.cs`

**Interfaces:**
- Consumes: Task 1.
- Produces: `interface ISignInReturnNotifier { void SignInReturned(); }` (Presentation; must not throw and must not block). `LoopbackAuthorization(IUrlLauncher launcher, IDiagnostics? diagnostics = null, ILocalizer? localizer = null, ISignInReturnNotifier? notifier = null)`. `SignInForegroundRequester(BrokerParentWindow windows) : ISignInReturnNotifier`: when `OpenWindowHandle` is non-null it restores the window with `ShowWindow(SW_RESTORE)` only if `IsIconic`, then calls `SetForegroundWindow`; a refusal records a diagnostics line with the step name only.
- Behaviour in `AuthorizeAsync`: `Classify(rawUrl)`; `NotARedirect` answers 404 with an empty body and the headers and keeps waiting; `Connected` or `DidNotFinish` answers 200 with the rendered page, raises the notifier exactly once and returns the redirect URL as today. The favicon rule is subsumed.

- [ ] **Step 1: Write the failing tests** (a real `HttpClient` against the listener, a recording notifier, a fake launcher that opens no browser): `redirectWithCodeAnswers200BrandedPageAndRaisesNotifierOnce`; `redirectWithErrorAnswers200DidNotFinishAndRaisesNotifierOnce`; `bareGetAnswers404AndTheSignInKeepsWaiting` (a real redirect afterwards still completes with the right URL); `faviconAnswers404AndDoesNotRaiseNotifier`; `hostileQueryIsNotEchoed` (`code=<script>` and a 100 KB query: status 200, no `<script` in the body, completes); `strayRequestsDoNotEndTheWait` (ten stray requests, then a redirect); `cancelRaisesNoNotifier`; `notifierThrowingDoesNotBreakTheSignIn`; `responseCarriesTheFourHeaders`; `languageComesFromTheCurrentUiCulture` (`ar` gives `dir="rtl"`). App side with a fake `IForegroundWindowApi`: `requesterDoesNothingWithNoOpenWindow` (zero calls); `requesterRestoresAMinimizedWindowThenActivates`; `requesterNeverUsesTheHiddenFallbackWindow`; `touchingAnOlderWindowMakesItTheOneRaised` (two registered windows, the first touched: the first is restored); `requesterSurvivesARefusedForegroundCall` (API returns false, no exception). Resource completeness: `everyLandingKeyExistsInResw`. Architecture: `foregroundRequesterUsesNoSimulatedInput` (the file contains none of `AttachThreadInput`, `keybd_event`, `SendInput`, `SendKeys`).
- [ ] **Step 2:** Run the Platform and App tests. Expected: FAIL.
- [ ] **Step 3: Implement** as above. Win32 calls go through a small internal `IForegroundWindowApi` so the requester is testable; the production implementation is P/Invoke in the same file.
- [ ] **Step 4:** `scripts/verify.ps1`. Expected: PASS on x64 and ARM64.
- [ ] **Step 5: Commit** — `git commit -m "Sign-in: landing page, stray-request rule and foreground request"`.

### Task 3: W1 documents, spike S-FG, PR

**Files:** in `timetug-windows`: `docs/manual-tests/windows-checklist.md` (landing page and foreground items appended under "2. Real accounts" so numbers do not move), `docs/spikes/2026-11-foreground-on-signin-return.md` (S-FG findings), `docs/parity.md` (row 39 gains the foreground request and landing page). In `timetug` (docs PR D1): `docs/superpowers/specs/2026-10-09-windows-program-design.md` section 4, the "Sign-in window" row notes the foreground request and landing page.

- [ ] **Step 1:** Write the checklist items (steps, expected text, light, dark and contrast themes, 200 percent zoom, Narrator in browse mode) and the parity row text.
- [ ] **Step 2:** Run `deepseek-review` on the W1 diff with the spec's "The landing page" and "Bringing TimeTug forward" as context. Targeted questions: the stray-request loop, the headers, encoding, and the notifier's exactly-once rule. Verify findings; fix real defects test-first.
- [ ] **Step 3: Commit, push, PR** — `git commit -m "Docs: landing page checks and parity"`; open the W1 PR to `main` (checks green on both architectures); its description says it also fixes the stranded tab for Google today. Open docs PR D1 in `timetug`. **(owner)** merges.
- [ ] **Step 4 (owner):** Spike S-FG on the VM and one other PC using the PR's `msix-arm64` or `msix-x64` artifact: Google sign-in with Edge, Chrome and Firefox as the default browser, with TimeTug in front, behind other windows and minimized; record per case whether TimeTug came forward or the taskbar button flashed. The agent writes the findings document (no email, id or token); it decides only Q7 (default: accept). If the owner is not available, merge W1 without the document and add it in a docs-only PR; W2 does not wait for it.

---

## Part B: `timetug-windows`, slice W2 (Presentation, not user-visible)

### Task 4: The listing shape in the Platform

**Files:**
- Modify: `src/TimeTug.Presentation/Accounts/IWindowsAccountSource.cs` (add `WindowsListingKind`, `WindowsAccountListing`, `ValueTask<WindowsAccountListing> GetListingAsync(CancellationToken)`; `GetEmailAsync` stays until W3), `src/TimeTug.Platform/Broker/BrokerWindowsAccountSource.cs`
- Test: `tests/TimeTug.Platform.Tests/Broker/BrokerWindowsAccountSourceTests.cs`

**Interfaces (Produces):** `enum WindowsListingKind { Unavailable, None, OneNamed, Unnamed }`; `sealed record WindowsAccountListing(WindowsListingKind Kind, string? Email = null)`; `BrokerWindowsAccountSource(IBrokerClient broker, IDiagnostics? diagnostics = null, TimeProvider? clock = null)` (the one-argument form keeps working). Mapping (spec table): zero accounts is `None`; exactly one account with an `@` in its user name is `OneNamed` with that email; any other non-empty listing (one without `@`, or several) is `Unnamed`; a throw, an unavailable broker or no answer within 5 s on `clock` is `Unavailable`, with a diagnostics line carrying the step name and no account data.

- [ ] **Step 1: Write the failing tests** (`FakeBrokerClient`): `zeroAccountsIsNone`; `oneNamedAccountIsOneNamedWithItsEmail`; `oneAccountWithoutAtIsUnnamed`; `twoAccountsAreUnnamed`; `throwIsUnavailable`; `noAnswerWithinFiveSecondsIsUnavailable` (manual `TimeProvider`, advance 5 s); `answerAtFourSecondsIsUsed`; `timeoutRecordsADiagnosticsLineWithoutAccountData` (a sentinel email in a throwing exception must not appear in the recording diagnostics); `callerCancellationPropagates`; `getEmailAsyncStillWorks`.
- [ ] **Step 2:** `dotnet test tests/TimeTug.Platform.Tests --filter BrokerWindowsAccountSource`. Expected: FAIL.
- [ ] **Step 3:** Implement `GetListingAsync` (a linked cancellation with the 5 s timeout from `clock`); keep `GetEmailAsync` as a projection of it.
- [ ] **Step 4:** Re-run. Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -m "Platform: broker listing shape with a five second limit"`.

### Task 5: The pinned device row (D1, D3, D7, D8, D9; L1, L6)

**Files:**
- Create: `src/TimeTug.Presentation/Accounts/DeviceRowModel.cs`
- Modify: `src/TimeTug.Presentation/Welcome/AccountsViewModel.cs`, `src/TimeTug.Presentation/Welcome/ConnectedAccount.cs` (adds `string? Email`, used for D7), `src/TimeTug.App/Strings/en-US/Resources.resw` (Decision 7)
- Test: `tests/TimeTug.Presentation.Tests/Accounts/DeviceRowTests.cs`, fakes in `tests/TimeTug.Presentation.Tests/Welcome/Fakes.cs`

**Interfaces (Produces):**
- `DeviceRowModel : ObservableObject` with `bool IsVisible`, `string Title`, `string? Email`, `string Description` (the pre-click line, the D8 line, or empty), `bool IsOn`, `bool IsSwitchEnabled`, `bool NeedsSignIn`, `string StatusText`, `string SwitchAutomationName`, `IAsyncRelayCommand SignInAgainCommand`, `Task SetOnAsync(bool on)`.
- On `AccountsViewModel`: `DeviceRowModel DeviceRow { get; }`; `bool DeviceRowIsPending { get; set; }` (true in the welcome window, where the switch is only a pending choice; false in Settings, where on runs `ConnectBrokeredAsync(BrokerIntent.WindowsAccount)` and off asks the removal question through `BeginRemove` with the withdrawal text); `ObservableCollection<ConnectedAccount> ListAccounts` (the connected accounts without the one the pinned row stands for); `RefreshWindowsAccountAsync()` now sets the row from `IWindowsAccountSource.GetListingAsync`.
- Rules: the row is visible for `OneNamed` and `Unnamed`, hidden otherwise (spec table); `IsOn` defaults true in pending mode. D7: while the row is visible and the listing is `OneNamed`, the connected `microsoft-brokered` account whose email equals the listed email (case-insensitive) is shown only in the pinned row; in every other case (another account, `Unnamed`, row hidden, listing failed) a connected brokered account is an ordinary `ListAccounts` row with `IsOnThisPc`. D8: a connected `microsoft` (browser) account with the listed email makes the row visible with the switch off and disabled and the D8 line. In Settings mode `IsOn` mirrors whether the pinned account is connected.

- [ ] **Step 1: Write the failing tests:** `listingNoneHidesTheRow`; `listingUnavailableHidesTheRow`; `oneNamedShowsTheEmailAndDefaultsOn`; `unnamedShowsTheRowWithoutAnEmailAndOn` (Q6); `settingsModeSwitchShowsTheEnginesTruth`; `connectedBrokeredAccountWithTheListedEmailShowsOnlyInTheRow` (also `Me@Example.com` against `me@example.com`); `connectedBrokeredAccountWithAnotherEmailStaysAListRow`; `connectedBrokeredAccountWhenTheRowIsHiddenStaysAListRow` (never disappears); `connectedBrokeredAccountWhenListingIsUnnamedStaysAListRow`; `browserAccountWithTheSameEmailDisablesTheRowAndShowsTheD8Line`; `pendingModeSwitchOffMakesNoBrokerCall`; `settingsSwitchOnArmsWindowsAccountAndConnects`; `settingsSwitchOffAsksTheRemovalQuestionWithWithdrawalText`; `removalConfirmedSendsRemoveOnly`; `rowShowsSignInAgainWhenThePinnedAccountNeedsIt` (reconnect arms `WindowsAccount`); `onlyTheListingIsCalledOnTheBrokerBeforeConnect` (the fake broker records every call).
- [ ] **Step 2:** `dotnet test tests/TimeTug.Presentation.Tests --filter DeviceRow`. Expected: FAIL.
- [ ] **Step 3:** Implement. New keys `Accounts_DeviceRowTitle`, `Accounts_DeviceRowDescription`, `Accounts_DeviceRowBrowserConflict`, `Accounts_DeviceRowSwitch` go into `Resources.resw` here.
- [ ] **Step 4:** Re-run the Presentation tests. Expected: PASS, no existing test edited.
- [ ] **Step 5: Commit** — `git commit -m "Presentation: pinned Windows account row"`.

### Task 6: The `+` menu, Microsoft states, fallback link (D4, D5; L4)

**Files:**
- Modify: `src/TimeTug.Presentation/Welcome/AccountsViewModel.cs` (build `MenuEntries` in `RebuildProviders`)
- Test: `tests/TimeTug.Presentation.Tests/Accounts/AddMenuTests.cs`

**Interfaces (Produces):** `ObservableCollection<ProviderItem> MenuEntries` in the spec's order (Microsoft, Google, then iCloud, iCal link, Other (CalDAV) last; a kind the build cannot sign in to is a disabled entry with the reason in `Hint`; the second line is `Hint`); `bool IsAddEnabled`; `bool ShowBrowserFallbackLink`; `string? FallbackMessage`; `IAsyncRelayCommand BrowserFallbackCommand` (on the view model, under the box, not on a card). The Microsoft entry: broker offered gives `Id == BrokeredKinds.PickItem`, name "Microsoft", empty `Hint`; broker not offered but the browser kind configured gives `Id == BrokeredKinds.Browser` and `Hint` "Use your browser instead"; neither configured gives a disabled entry whose `Hint` comes from `ProviderUnavailable`. `+` is disabled while a sign-in runs; entries are never removed while busy.
- Fallback rules (spec table "Microsoft on Windows: the states"): the link appears after the Windows dialog closed with no account (no message, Q5), after a failure (the usual failure text with the engine's detail), and after the host answered unavailable (`FallbackMessage` "Windows sign-in isn't available here"); it starts the `microsoft` kind; it disappears when any sign-in starts or succeeds.

- [ ] **Step 1: Write the failing tests:** `menuOrderIsMicrosoftGoogleThenTheRestWithCaldavLast`; `microsoftEntryUsesThePickerWhenTheBrokerIsOffered`; `microsoftEntryOffersTheBrowserWhenTheBrokerIsNot` (second line, runs `microsoft`); `microsoftEntryDisabledWhenNeitherIsConfigured`; `unconfiguredKindsAreDisabledEntriesWithAReason`; `addIsDisabledWhileASignInRunsAndEntriesRemain`; `closingTheWindowsDialogShowsTheLinkAndNoErrorWords`; `unavailableAnswerShowsTheMessageAndTheLink`; `failureShowsTheEnginesDetailAndTheLink`; `linkStartsTheBrowserKind`; `linkDisappearsWhenAnySignInStartsOrSucceeds`; `linkNeverShowsWhileTheBrokerWorksAndNothingFailed`; `pickerEntryArmsThePickerIntentAndResetsIt`.
- [ ] **Step 2:** `dotnet test tests/TimeTug.Presentation.Tests --filter AddMenu`. Expected: FAIL.
- [ ] **Step 3:** Implement by reusing `ConnectAsync`, `ConnectBrokeredAsync` and the existing failure classification (`ExplainBrokeredFailure`).
- [ ] **Step 4:** Re-run. Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -m "Presentation: add menu with one Microsoft entry and the browser fallback"`.

### Task 7: Selection, remove, empty and busy rules (L1 to L3, L5, L7 to L10)

**Files:**
- Modify: `src/TimeTug.Presentation/Welcome/AccountsViewModel.cs`
- Test: `tests/TimeTug.Presentation.Tests/Accounts/AccountsSelectionTests.cs`

**Interfaces (Produces):** `string? SelectedAccountId { get; set; }`; `bool CanRemoveSelected`; `string RemoveSelectedAutomationName` ("Remove name" or "Remove account"); `IRelayCommand RemoveSelectedCommand` (also bound to Delete: begins the existing removal question for the selected account); `string EmptyText` with `bool ShowEmptyText` (no `ListAccounts`); `event EventHandler<FocusTarget> FocusRequested` where `FocusTarget` is `record FocusTarget(FocusKind Kind, string? AccountId)` with kinds `Row` and `AddButton`, raised only after a confirmed removal. `ListAccounts` keeps the engine's order (L1) and is updated in place: unchanged rows are not recreated (L10).
- Rules: nothing is selected at first (L2); `CanRemoveSelected` is false when nothing is selected or a sign-in runs (L3, L9); after the engine's state drops the removed row, selection moves to the row now in its place, else the previous, else none, and `FocusRequested` names it, else `AddButton`; a selection whose row vanished by any other cause is cleared with no focus request; the question keeps today's text plus the withdrawal text for an `IsOnThisPc` row.

- [ ] **Step 1: Write the failing tests:** `nothingIsSelectedAtFirst`; `removeIsDisabledWithNothingSelected`; `removeIsDisabledWhileASignInRuns`; `removeNameReflectsTheSelectedRow`; `deleteWithNothingSelectedDoesNothing`; `removeQuestionHasTodaysTextAndWithdrawalOnlyForOnThisPc`; `rowLeavesOnlyWhenTheEnginesStateSaysSo` (confirm, no state change: the row is still listed); `afterRemovalSelectionMovesToTheNextRow`; `afterRemovingTheLastRowSelectionMovesToThePrevious`; `afterRemovingTheOnlyRowFocusGoesToAdd`; `aVanishedSelectionIsClearedWithoutFocusRequest`; `enginePublicationsKeepRowInstancesAndSelection` (publish ten identical states: no collection change events, `SelectedAccountId` unchanged, no `FocusRequested`); `aChangedRowIsRebuiltInPlaceOnly`; `emptyTextShowsOnlyWithNoListRowsAndThePinnedRowStays`; `anErrorLineIsNotARowAndAFailedAccountIsARowWithSignInAgain`; `engineRefusalOfRemovalKeepsTheRowAndShowsTheMessage`; `lateListingShowsThePinnedRowWithoutRaisingFocusRequested`.
- [ ] **Step 2:** `dotnet test tests/TimeTug.Presentation.Tests --filter AccountsSelection`. Expected: FAIL.
- [ ] **Step 3:** Implement; reuse `BeginRemove` and `ConfirmRemoveAsync` for the question; compare `ConnectedAccount` records for the in-place update.
- [ ] **Step 4:** Re-run. Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -m "Presentation: selection, remove and empty rules for the accounts list"`.

### Task 8: The welcome flow (Q1, Q4, Q5; D1, D9, D10)

**Files:**
- Modify: `src/TimeTug.Presentation/Welcome/WelcomeViewModel.cs`, `Resources.resw` (`Welcome_GetStarted`, `Welcome_Continue`)
- Test: `tests/TimeTug.Presentation.Tests/Welcome/WelcomeListFlowTests.cs`

**Interfaces (Produces):** `WelcomeStep` gains `Intro`; `bool ListFlow { get; init; }` (Decision 2). With it true: the first step is `Intro`; `GetStartedCommand` moves to `Connect`; `Accounts.RefreshWindowsAccountAsync()` starts when the view model is created (it runs while step 1 is up); `IAsyncRelayCommand ContinueCommand`; `bool CanContinue`; `bool IsIntroStep`; `Accounts.DeviceRowIsPending` is true; `Accounts.Connected` no longer moves the step.
- Rules: `CanContinue` is true when not busy and (the pinned row is visible with its switch on, or `ListAccounts` has an account); false while the listing is pending with an empty list, with the switch off and an empty list, and while a sign-in runs. `ContinueCommand` with the switch on and the Windows account not connected arms `WindowsAccount` and connects it (Windows asks): success goes to `Connected`; decline, close or failure stays on `Connect` with the switch still on and the fallback link shown; with the Windows account already connected, or the switch off and an account in the list, it goes to `Connected` and makes no broker call. `+` entries add and stay. Step 3 is unchanged. `SkipCommand` still cancels and closes.

- [ ] **Step 1: Write the failing tests:** `listFlowStartsOnTheIntroStep`; `getStartedMovesToConnectAndTheListingStartedOnConstruction` (the fake source is called once, before Get started); `continueIsDisabledWhileTheListingIsPending`; `continueIsDisabledWithTheSwitchOffAndNoAccount`; `continueWithTheSwitchOnConnectsTheWindowsAccountAndGoesToConnected`; `declineStaysOnConnectWithTheSwitchOnNoErrorAndTheLink`; `failureStaysOnConnectAndShowsTheEngineText`; `continueWithTheWindowsAccountAlreadyConnectedMakesNoBrokerCall`; `continueWithTheSwitchOffAndAGoogleAccountMakesNoBrokerCall` (the fake broker records only the listing); `plusAddsAnAccountAndStaysOnConnect`; `plusThenContinueWithTheSwitchOnStillAsksWindows`; `noBrokerCallOtherThanTheListingBeforeContinue`; `localOnlyWindowsAccountHidesTheRowAndDisablesContinueAndSkipCloses`; `lateListingEnablesContinueWithoutChangingTheStep`; `withoutListFlowTheOldBehaviourIsUnchanged` (the existing `WelcomeViewModelTests` pass untouched).
- [ ] **Step 2:** `dotnet test tests/TimeTug.Presentation.Tests --filter WelcomeListFlow`. Expected: FAIL.
- [ ] **Step 3:** Implement behind `ListFlow`.
- [ ] **Step 4:** Re-run all Presentation tests. Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -m "Presentation: welcome intro step and Continue rule"`.

### Task 9: W2 review and PR

- [ ] **Step 1:** Run `deepseek-review` on the W2 diff (whole changed files plus the spec's "The shared control", "The pinned row on Windows" and D7 to D10 as context). Targeted questions: trace D7 for `Me@Example.com` against `me@example.com` with the row hidden; trace Continue when the listing answers after the switch is toggled; trace selection when the engine publishes a state that drops the selected row while a sign-in runs. Verify findings; fix real defects test-first.
- [ ] **Step 2:** `scripts/verify.ps1` on both architectures. Expected: PASS; `check-repository-contracts.py` and the architecture tests unchanged.
- [ ] **Step 3: Commit, push, PR** — open the W2 PR; its description says it is **not user-visible** (new members and rules behind `ListFlow`; nothing the shipped window relies on changes). **(owner)** merges when green.

---

## Part C: `timetug-windows`, slice W3 (App, strings, self-tests, parity)

### Task 10: `AccountsListBox`

**Files:**
- Create: `src/TimeTug.App/Controls/AccountsListBox.xaml`, `AccountsListBox.xaml.cs`
- Modify: `src/TimeTug.App/Strings/en-US/Resources.resw` (XAML-only keys: `Accounts_AddAutomation`, `Accounts_ListEmpty`, the list and bar automation names; reword `Accounts_Empty` if still referenced), `tests/TimeTug.App.A11y/suppressions.json` (only with a stated reason, as the file does)
- Test: the self-tests in Task 12 (WinUI controls need the packaged app)

**Interfaces:** a user control with a dependency property `Accounts` (an `AccountsViewModel`). Top to bottom: the pinned row (glyph, title, email, description or conflict line, a `ToggleSwitch` named by `SwitchAutomationName`, "Sign in again" when `NeedsSignIn`); a `ListView` named "Connected accounts" (single selection bound to `ListAccounts` and `SelectedAccountId`, item automation name "Provider, name, status, On this PC", a "Sign in again" button inside the row reachable by Tab when the row is selected); the empty text (not a button); the bar: `+` (a button with a `MenuFlyout` of `MenuEntries`, automation name "Add account", disabled when `IsAddEnabled` is false) and `-` (bound to `RemoveSelectedCommand`, named from `RemoveSelectedAutomationName`). Delete on the list runs `RemoveSelectedCommand`. Esc closes the menu and returns focus to `+`, does not close the Settings window and removes nothing. The remove dialog is a `ContentDialog` with `DefaultButton="Close"` (Cancel). Only `FocusRequested` moves focus.

- [ ] **Step 1:** Write the control against L1 to L10 and the spec's "Accessibility / Keyboard (Windows)" and "Narrator": live regions through `AutomationProperties.LiveSetting` (polite for the waiting row and the late pinned row, assertive for the error line) and `RaiseNotificationEvent` for "name removed". Rows update in place from collection changes (L10). If a button nested in a selectable row proves unreachable by keyboard, fall back to the spec's strip under the box for the selected row's "Sign in again" (spec Risks) and say so in the PR.
- [ ] **Step 2:** Add the resource keys with translator comments; `scripts/verify.ps1` (build). Expected: PASS.
- [ ] **Step 3: Commit** — `git commit -m "App: AccountsListBox control"`.

### Task 11: Switch the welcome window and the Accounts page; delete the cards

**Files:**
- Modify: `src/TimeTug.App/Views/WelcomeWindow.xaml(.cs)` (three steps: intro with "Get started"; the control with Continue and the "Skip for now" link; the unchanged connected step; the window still registers its handle), `src/TimeTug.App/Settings/AccountsPage.xaml(.cs)` (the control with `DeviceRowIsPending` false; under the box in the spec's order: waiting row with Cancel, error line, browser fallback link and message, configuration warning, consent-withdrawal footnote; delete `AccountCard` and `ProviderCard` code), `src/TimeTug.App/Services/WelcomeWindowFactory.cs` and `AppComposition.cs` (construct `WelcomeViewModel` with `ListFlow`, then remove the flag), `src/TimeTug.Presentation/Welcome/AccountsViewModel.cs`, `WelcomeViewModel.cs`, `ProviderItem.cs`, `src/TimeTug.Presentation/Accounts/IWindowsAccountSource.cs`, `src/TimeTug.Platform/Broker/BrokerWindowsAccountSource.cs` (delete the Decision 2 members and the old behaviour), `Resources.resw` (remove `Provider_microsoft-brokered-pick`, `-named`, `Provider_microsoft-browser` and any other key nothing references)
- Test: Presentation tests that described only a card are deleted or ported in the same commit; `tests/TimeTug.Platform.Tests/Broker/BrokerWindowsAccountSourceTests.cs` (delete `getEmailAsyncStillWorks`); `tests/TimeTug.Architecture.Tests`

- [ ] **Step 1:** Port `WelcomeBrokeredTests`, `AccountsBrokeredTests` and `AccountsPaneTests` to the new members (keep every case that still describes behaviour; delete cases that describe only a card). Run `dotnet test tests/TimeTug.Presentation.Tests`. Expected: FAIL until the old members go and the new ones are the only path.
- [ ] **Step 2:** Make the XAML and code-behind changes; delete the dead members; confirm with `git grep` that nothing references `PreselectBrokered`, `OffersBrowserFallback`, `GetEmailAsync`, `AccountCard`, `ProviderCard` or the removed keys.
- [ ] **Step 3:** `scripts/verify.ps1`. Expected: PASS (view models free of OS types, no MSAL outside Platform).
- [ ] **Step 4: Commit** — `git commit -m "App: welcome window and Accounts page use the accounts list"`.

### Task 12: Self-tests and accessibility

**Files:**
- Modify: `src/TimeTug.App/SelfTest/Scenarios/WelcomeScenario.cs`, `WelcomeBrokeredScenario.cs`, `AccountsBrokeredScenario.cs`, `BrokeredReconnectScenario.cs`, `BrokeredUnavailableScenario.cs`, `SettingsAccountsScenario.cs`, `A11yHoldScenario.cs`, `src/TimeTug.App/SelfTest/FakeBrokerClient.cs` (listing answers for none, one and two accounts), `scripts/ci/selftest-scenarios.txt`, `tests/TimeTug.App.A11y/Program.cs`
- Create: `src/TimeTug.App/SelfTest/Scenarios/AccountsListScenario.cs` (Name `accounts-list`), `WelcomeLocalOnlyScenario.cs` (Name `welcome-local-only`)

Scenarios (each over the real engine with the scripted broker and recorded Graph answers, on both architectures, with screenshots; the `Name` constants and rows in `selftest-scenarios.txt` must match, which `check-repository-contracts.py` enforces; each asserts every new control has an automation name and the list and item patterns):
- `welcome`, `welcome-brokered`: three steps; pinned row with the listed email and the switch on; Continue with the fake answering the dialog; second pass: the fake answers `Cancelled`, the window stays on step 2, no error, the link shows; third pass: Google added with `+`, switch off, Continue goes to step 3 and the fake records zero dialog calls.
- `welcome-local-only`: listing empty; no pinned row; the empty text; Continue disabled; `+` > Microsoft opens the picker intent.
- `accounts-list`: selection, `+` menu entries and order, `-`, Delete, focus after removal (next row, previous, `+`), empty state, busy state (`+`, `-` and the switch disabled), error and fallback placement, the D8 line, the late pinned row.
- `accounts-brokered`, `brokered-reconnect`, `brokered-unavailable`: the single Microsoft entry, the "On this PC" tag, "Sign in again" as a row button, the flyout row still says "Open Accounts", the unavailable entry reads "Microsoft" with "Use your browser instead" and runs the browser kind, removing asks nothing of the broker.

- [ ] **Step 1: Write the scenarios first**; run `pwsh scripts/ci/run-selftest.ps1` for each. Expected: FAIL until the rewrites are complete.
- [ ] **Step 2:** Complete the scenarios and update the rows (screenshot minimums, timeouts, the two new names). Run the whole self-test on x64 (CI) and ARM64 (`scripts/vm/vm-selftest.sh`), then `scripts/ci/run-a11y.ps1`. Expected: PASS with screenshots; axe reports no new violation; the existing privacy test (sentinels never reach the log, ETW or Copy diagnostics) passes over the new flows.
- [ ] **Step 3: Commit** — `git commit -m "Self-tests: accounts list scenarios and axe"`.

### Task 13: Documents, review, W3 PR, docs PR D2

**Files:** in `timetug-windows`: `docs/parity.md` (rows 37, 39, 41, 42, 43, 44 and 61 as the spec's "Cross-platform documents" lists them, and one new row "Accounts list: `+`, `-`, Delete, selection, pinned device row", done on both), `docs/manual-tests/windows-checklist.md` (sections 1.1, 2.1, 2.6, 2.7, 2.9 and the accessibility entry rewritten for the list; the spec's owner-attended items 1 to 8 as numbered steps with expected text), `docs/development.md` (the new scenarios). In `timetug` (docs PR D2): the phase 6 spec (a dated amendment at the top: items 1, 2, 4 of "What the owner will see" and D1 are superseded), the program design section 4.5 ("First run", "Accounts pane", "Browser fallback"), the phase 5 spec's first-run paragraph.

- [ ] **Step 1:** Write the documents; each manual item gives steps, the expected text and what the agent prepared; none asks the agent to type a password.
- [ ] **Step 2:** Run `deepseek-review` on the W3 diff (whole files plus the spec's "Accessibility" and L1 to L10). Targeted questions: Delete and focus after removal; the live-region announcements; whether any removed member is still referenced. Verify findings; fix real defects test-first; run `scripts/verify.ps1` and the full self-test on both architectures.
- [ ] **Step 3: Commit, push, PRs** — `git commit -m "Docs: accounts list parity and checklist"`; open the W3 PR and docs PR D2. **(owner)** merges when green.

---

## Part D: `timetug` (Mac), slice M1

Work in a worktree off `origin/master`. Tests: `scripts/dev/verify.sh affected` and `scripts/dev/verify.sh app` (see `docs/development.md` for XcodeGen). New files under `Apps/macOS/Sources` and `Tests` are picked up by `project.yml`'s source globs; do not touch `Packages/*`, `AppConnectors.swift` or the `project.yml` pins.

### Task 14: `AccountsListModel`

**Files:**
- Create: `Apps/macOS/Sources/AccountsListModel.swift`
- Test: `Apps/macOS/Tests/AccountsListModelTests.swift`

**Interfaces (Produces):** `struct AccountsListModel` built from the accounts (`[Connection]`), statuses (`[String: SourceStatus]`), notices (`[String: [SourceNotice]]`), build failures (`[ConnectionID: String]`), available kinds (`[(id: String, displayName: String)]`), `unconfiguredKindIDs`, `eventKitEnabled` and `isWorking`, with:
- `rows: [Row]` (id, kindID, name, `statusText` from `AccountStatusText.make`, `needsAttention`, `canSignInAgain`, `noticeText` from `AccountNoticeText.make`, `accessibilityLabel` "Provider, name, status");
- `pinned: PinnedRow` (title "Apple Calendar (this Mac)", `statusText` ("Off" when disabled, else the status words), `showsOpenSystemSettings`, `isOn`, `accessibilityLabel` "Use Apple Calendar");
- `menuEntries: [MenuEntry]` (id, title, `isEnabled`, `disabledReason`, `isPlaceholder`);
- `emptyText` ("No accounts yet. Choose + to add one."), `isAddEnabled`, `isSwitchEnabled` and `canSignInAgain(for:)` (all false while `isWorking`, L4 and L9), `isRemoveEnabled(selection:)`, `removeQuestion(for:) -> (title: String, body: String)`, `selectionAfterRemoving(_ id: ConnectionID) -> ConnectionID?` (next, else previous, else nil), `removeLabel(for:)` ("Remove account" with the name as the hint).
- Menu order: Microsoft, Google, the rest in today's order with Other (CalDAV) last; unconfigured kinds as disabled entries "isn't set up in this build"; then the four placeholders (Fastmail, Todoist, Zoom, Webex) disabled with "Coming soon".

- [ ] **Step 1: Write the failing tests:** `menuOrderPutsMicrosoftAndGoogleFirstAndCaldavLast`; `placeholdersAreDisabledAndComingSoon`; `unconfiguredKindIsADisabledEntryWithAReason`; `emptyTextWhenNoAccountsAndPinnedRowStays`; `rowsKeepTheEnginesOrder`; `needsAttentionRowOffersSignInAgain` (also for a build failure: "Can't start this account"); `rowAccessibilityLabelReadsProviderNameStatus`; `noticeMarkerCarriesItsText`; `removeIsDisabledWithNoSelectionAndWhileWorking`; `addSwitchAndSignInAgainAreDisabledWhileWorking`; `removeQuestionTextMatchesToday`; `selectionAfterRemovingMovesToNextThenPreviousThenNil`; `pinnedRowStatesOffOnAndAccessOff` ("Open System Settings" only while enabled and access is off); `pinnedRowIsNeverASelectableRow`.
- [ ] **Step 2:** `scripts/dev/verify.sh affected`. Expected: FAIL (type missing).
- [ ] **Step 3:** Implement as a value type with no AppKit or SwiftUI import.
- [ ] **Step 4:** Re-run. Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -m "App: AccountsListModel for the one accounts list"`.

### Task 15: `AccountsController` selection and removal

**Files:**
- Modify: `Apps/macOS/Sources/AccountsController.swift`
- Test: `Apps/macOS/Tests/AccountsControllerTests.swift` (existing cases pass unchanged)

**Interfaces (Produces):** `@Published var selection: ConnectionID?`; `func listModel(statuses:notices:eventKitEnabled:) -> AccountsListModel`; `var canRemoveSelection: Bool`; `func removeSelection()` (sends `.removeAccount` for the selection, keeps it until `apply(_:)` drops the account, then applies `selectionAfterRemoving`); `availableKinds` unchanged. `apply(_:)` clears a selection whose account vanished for any other cause.

- [ ] **Step 1: Write the failing tests:** `nothingIsSelectedInitially`; `removeSelectionSendsRemoveAccountForTheSelectedID`; `removeSelectionDoesNothingWithoutASelection`; `removeSelectionIsIgnoredWhileWorking`; `selectionMovesToTheNextAccountOnlyAfterTheEngineDropsTheAccount`; `selectionIsClearedWhenItsAccountVanishes`; `publishingTheSameStatusKeepsTheSelection`; `existingBeginAddAndReauthorizeStillSendTheirCommands`.
- [ ] **Step 2:** Run the app tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Re-run. Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -m "App: selection and removal in AccountsController"`.

### Task 16: The SwiftUI box in `AccountsPane`

**Files:**
- Create: `Apps/macOS/Sources/AccountsListBox.swift`
- Modify: `Apps/macOS/Sources/AccountsPane.swift`

**Interfaces:** `AccountsListBox` is a view over `AccountsListModel`, a selection binding and closures (`signInAgain`, `add`, `remove`, `setEnabled`, `openSystemSettings`): a bordered box with the pinned row (not selectable, switch labelled "Use Apple Calendar", disabled while a sign-in runs), a `List(selection:)` of rows (one accessibility element each, with custom actions "Sign in again" and "Remove"), the empty text, and a bottom bar with `+` (a `Menu`, label "Add account", disabled when `isAddEnabled` is false, entries from the model, placeholders in a separator-delimited disabled group) and `-` (label "Remove account", the selected name in its hint). `onDeleteCommand` asks the question through the existing `confirmationDialog` (default Cancel). `AccountsPane` keeps the waiting row with Cancel, the error line, the configuration warning, the diagnostics section and the credential sheet presenter; the Apple Calendar card, the provider grid, the `placeholderProviders` array and the per-row "..." menu are removed. Removal and sign-in outcomes post `NSAccessibility` announcements (`.announcementRequested`).

- [ ] **Step 1:** Write the view against the model. Run `scripts/dev/verify.sh app`. Expected: PASS (there is no UI-test target and none is added).
- [ ] **Step 2:** Exercise it in a debug build (see the `configuring-local-app-builds` skill for signing and the Google client); where that is not possible, say so in the PR and leave the pass to Task 18. Check light and dark, the `+` menu order, `-` and Delete with the question, the Apple Calendar switch off and on, and the access-denied row.
- [ ] **Step 3: Commit** — `git commit -m "App: Settings > Accounts uses the one accounts list"`.

### Task 17: Mac documents, review, M1 PR

**Files:** `docs/decisions/0021-one-accounts-list.md` and its row in `docs/decisions/README.md` (status Current, verified by "App tests, manual checklist"), `docs/manual-tests/macos-checklist.md` (lines 93 to 97 reviewed against the new layout; new items from the spec's Mac pass: the box in light and dark, `+` menu order, Google still uses the system sheet, `-` and Delete with the question, the Apple Calendar switch keeps the calendar choices, "Open System Settings" when access is denied, VoiceOver reads rows, `+`, `-` and the removal announcement, Full Keyboard Access reaches everything), `docs/PROGRESS.md` (one dated note).

ADR 0021 records: one accounts list on both platforms, the pinned device row, the switch semantics (Mac hides and keeps the choices; Windows connects and removes), the browser as fallback, D6 no migration, and the landing-page decision with the reasons a tab cannot be closed (a page cannot close a tab it did not open; Google blocks embedded web views). It states that the engine, library and protocol did not change.

- [ ] **Step 1:** Write the documents.
- [ ] **Step 2:** Run `deepseek-review` on the M1 diff (whole changed files plus the spec's L1 to L10 and "Accessibility / VoiceOver"). Targeted questions: selection after removal when the engine republishes between the command and the state; `onDeleteCommand` with nothing selected; whether any removed view is still referenced. Verify findings; fix real defects test-first; `scripts/dev/verify.sh affected` and `app` pass.
- [ ] **Step 3: Commit, push, PR** — `git commit -m "Docs: ADR 0021 and Mac checklist for the one accounts list"`; PR to `master` titled "One accounts list on the Mac". **(owner)** merges when green.

---

## Part E: Verification and close

### Task 18: Owner-attended checks, tracker, close (owner-attended)

**Files:** `docs/superpowers/plans/2026-10-09-windows-program-tracker.md`, `docs/PROGRESS.md` if required.

- [ ] **Step 1 (owner):** Windows, on the ARM64 VM with the `msix-arm64` artifact of the latest `main` CI run (and x64 where a second PC exists): the spec's owner-attended items 1 to 8, including the real-account listing that settles Q6 (a work account, a second account) and the Narrator pass (keyboard-only welcome flow, `+` menu, `-`, Delete, focus after removal, live-region announcements). Mac: the spec's Mac pass with VoiceOver and Full Keyboard Access. The agent prepares the builds and records what the owner reports; real-account steps are never automated.
- [ ] **Step 2:** Update the tracker: the "6A" row to `done` with PR links and the verification date; record the Q6 and S-FG outcomes; list any item the owner did not get to as an open owner item; add a session-log line.
- [ ] **Step 3: Commit and PR** — `git commit -m "Tracker: shared accounts list done"`; **(owner)** merges.

---

## Part F: `timetug-windows`, slice W4 (no pinned row, Windows account added on Continue, logos)

Owner decisions of 2026-11-02 (spec Amendment A1, D16 to D19). Windows only; the Mac does not change. Work test-first: write the tests of each task, run them and see them fail, then implement. Implementers use Sonnet 5.5 (D15). Merge order: the `timetug` documents PR (this amendment) first, then W4 as two PRs in `timetug-windows`: W4a (Presentation and Platform: Tasks 19 to 21, not user-visible until W4b) and W4b (App, self-tests, logos, documents: Tasks 22 to 25). Squash-merge each on green CI (`windows-x64`, `windows-arm64`, `architecture`), after a `deepseek-review` pass whose verified findings are fixed test-first.

### Task 19: The dismissal store (A1.3)

**Files:** Create `src/TimeTug.Presentation/Accounts/IWindowsAccountDismissalStore.cs`, `src/TimeTug.Platform/Settings/LocalSettingsWindowsAccountDismissalStore.cs`. Test: `tests/TimeTug.Platform.Tests/Settings/LocalSettingsWindowsAccountDismissalStoreTests.cs`.

**Interfaces (Produces):** `interface IWindowsAccountDismissalStore { bool IsDismissed { get; } void Dismiss(); }`; the local-settings implementation over an `IDictionary<string, object>` with key `Accounts.WindowsAccountDismissed`, never throwing (an unreadable container reads as not dismissed, an unwritable one drops the write; both log a diagnostics line with no account data), `ForCurrentPackage` like `LocalSettingsHotkeyStore`.

- [ ] Step 1: failing tests: `defaultsToNotDismissed`; `dismissThenReadBack`; `survivesANewInstanceOverTheSameValues`; `unreadableContainerReadsAsNotDismissed`; `unwritableContainerLogsAndDoesNotThrow`; `aWrongTypedValueReadsAsNotDismissed`. Step 2: run, expect FAIL. Step 3: implement. Step 4: PASS. Step 5: commit.

### Task 20: Remove the pinned row; the offer rule (A1.1, A1.2)

**Files:** Modify `src/TimeTug.Presentation/Welcome/AccountsViewModel.cs`, `ConnectedAccount.cs`; delete `src/TimeTug.Presentation/Accounts/DeviceRowModel.cs`; tests in `tests/TimeTug.Presentation.Tests/Accounts/` (`DeviceRowTests` becomes `WindowsAccountOfferTests`) and `Settings/AccountsBrokeredTests.cs`.

**Interfaces (Produces):** on `AccountsViewModel`: `IWindowsAccountDismissalStore? Dismissals { get; set; }`; `bool WindowsAccountOffered` (A1.2 "offered"); `bool ListingPending`; `ListAccounts` is now every connected account (no pinned exclusion); `ConnectedAccount` loses `IsOnThisPc` and `TagText` and the ", On this PC" automation suffix; `ShowWithdrawConsent` and `RemovalWithdrawText` are true for any Microsoft account (`microsoft` or `microsoft-brokered`). `RefreshWindowsAccountAsync` makes no broker call when the store says dismissed. Confirming the removal of a `microsoft-brokered` account calls `Dismissals.Dismiss()` under the A1.3 rule.

- [ ] Step 1: failing tests: `oneNamedListingIsOffered`; `unnamedListingIsOffered`; `noneAndUnavailableAreNotOffered`; `dismissedIsNotOfferedAndMakesNoBrokerCall`; `connectedBrokeredAccountWithTheListedEmailIsNotOffered` (also `Me@Example.com` against `me@example.com`); `unnamedListingWithAnyConnectedBrokeredAccountIsNotOffered`; `aDifferentBrokeredAccountDoesNotStopTheOffer`; `browserAccountWithTheSameEmailIsNotOffered`; `windowsAccountRowIsAnOrdinaryMicrosoftRow` (kind name "Microsoft", no tag, automation name without "On this PC", every account in `ListAccounts`); `withdrawalTextAppliesToAnyMicrosoftAccountAndNotToGoogle`; `removingTheMatchingBrokeredAccountDismisses`; `removingAnUnnamedOrUnavailableListedBrokeredAccountDismisses`; `removingWhenListingIsNoneOrNamesAnotherEmailDoesNotDismiss`; `removingAGoogleOrBrowserAccountNeverDismisses`; `cancellingTheRemovalDoesNotDismiss`; `aRefusedRemovalDoesNotDismiss`; `plusMicrosoftStillAddsAfterADismissal`. Step 2: FAIL. Step 3: implement; delete the device-row members and strings (`Accounts_DeviceRow*`, `Accounts_OnThisPc`, `Provider_microsoft-brokered-hint` if unused). Step 4: all Presentation tests PASS. Step 5: commit.

### Task 21: Continue adds the Windows account (A1.2)

**Files:** Modify `src/TimeTug.Presentation/Welcome/WelcomeViewModel.cs`; tests `tests/TimeTug.Presentation.Tests/Welcome/WelcomeListFlowTests.cs` (rewritten for the new rule), `WelcomeViewModelTests.cs` as needed.

**Rules:** `CanContinue` = connect step, not busy, the listing not pending, and (list has an account, or the Windows account is offered). `ContinueAsync`: offered and (list empty or no decline yet this window) arms `WindowsAccount` and adds the brokered kind; success goes to `Connected`; decline, close or failure stays with the link shown and records the decline for this window; otherwise goes to `Connected` and makes no broker call.

- [ ] Step 1: failing tests: `continueIsDisabledWhileTheListingIsPending` (empty list and with an account added by `+`); `continueWithAnOfferedWindowsAccountAsksWindowsOnceAndGoesOn`; `theNewRowIsAnOrdinaryMicrosoftRow`; `declineStaysOnConnectWithNoErrorAndTheLink`; `declineThenContinueWithAnEmptyListAsksAgain`; `declineThenContinueWithAnAccountGoesOnWithoutAsking`; `failureStaysAndShowsTheEngineText`; `localOnlyWindowsAccountLeavesContinueDisabledWithAnEmptyList`; `dismissedWindowsAccountLeavesContinueDisabledAndMakesNoBrokerCall`; `continueWithAGoogleAccountAndAnOfferedWindowsAccountStillAsks` (Q11); `plusAddsAndStaysOnConnect`; `noBrokerCallOtherThanTheListingBeforeContinue`; `lateListingEnablesContinueWithoutChangingTheStep`; `skipClosesWithoutAnyBrokerCall`. Step 2: FAIL. Step 3: implement. Step 4: PASS. Step 5: commit; open W4a (not user-visible; says so).

### Task 22: Service logos (A1.5)

**Files:** Create `src/TimeTug.App/Assets/Providers/microsoft.svg`, `google.svg`, `README.md` (source, retrieval date, constraints), `src/TimeTug.App/Controls/ProviderLogo.xaml(.cs)`; modify `src/TimeTug.App/Settings/ProviderGlyphs.cs`, `AccountsListBox.xaml(.cs)` (row and menu entries), `Resources.resw` (`Accounts_LogoAutomation`), `docs/third-party.md`, `tests/TimeTug.Architecture.Tests` (every asset listed in the README exists; no other asset is referenced by `ProviderLogo`).

**Behaviour:** `ProviderLogo` takes a kind id and shows the vendor mark for `microsoft`, `microsoft-brokered`, `microsoft-brokered:pick` and `google`, and the Segoe glyph otherwise, on a 28 px white tile with the A1.5 outline per theme; the mark's colours never change. Row logo: an `Image` named "{Provider} logo"; menu entry logo: decorative.

- [ ] Step 1: failing self-test assertions (Task 24) and pure tests: `microsoftKindsAllMapToTheMicrosoftMark`; `googleMapsToTheGoogleMark`; `otherKindsKeepTheirGlyphs`; `logoNameIsProviderLogo`. Step 2 to 4: red, implement, green. Step 5: commit.

### Task 23: Switch the control and the welcome window

**Files:** Modify `AccountsListBox.xaml(.cs)` (delete the device panel, divider and handlers), `WelcomeWindow.xaml(.cs)`, `AccountsPage.xaml(.cs)`, `AppComposition.cs` and `WelcomeWindowFactory.cs` (pass the dismissal store), `Resources.resw` (delete the removed keys; reword `Welcome_*` only if a string mentioned the switch).

- [ ] Steps: `git grep` shows nothing references `DeviceRow`, `IsOnThisPc`, `TagText`, `Accounts_DeviceRow`, `Accounts_OnThisPc`; `scripts/verify.ps1` PASS. Commit.

### Task 24: Self-tests and accessibility

Rewrite, test-first (run red against the old behaviour first): `welcome` and `welcome-brokered` (Get started, Continue shows the scripted Windows dialog, the new row is an ordinary Microsoft row with the Microsoft logo, step 3; a second pass declines and stays with the link; a third adds Google first, Continue still asks, decline then Continue goes on); `welcome-local-only` (no Windows account: empty text, Continue disabled, `+` > Microsoft opens the picker intent); `accounts-list` (no device row; logos per row with their names; selection, `-`, Delete, focus, empty and busy states); `accounts-brokered`, `brokered-reconnect`, `brokered-unavailable` (no tag; Microsoft row with "Sign in again"); `settings-accounts`, `a11y-hold`; new `welcome-dismissed` (a recorded dismissal: no listing call, Continue disabled with an empty list; removing the Windows account in Settings records it and a relaunch does not add it again) with a row in `scripts/ci/selftest-scenarios.txt`. Each asserts automation names, the list and item patterns and the logos' names, and runs axe in light, dark and a high-contrast theme for the Accounts pane.

- [ ] Run each scenario on the ARM64 VM (`scripts/vm/vm-selftest.sh`) red, then green; `scripts/ci/run-a11y.ps1`; commit.

### Task 25: Documents, review, W4b PR, `timetug` docs

`timetug-windows`: `docs/parity.md` (rows 37, 41, 42, 43, 61 and the accounts-list row), `docs/manual-tests/windows-checklist.md` (sections 2.17 to 2.20 rewritten for A1.6; logo checks in light, dark and high contrast), `docs/development.md` (new scenario), `docs/third-party.md`. `timetug`: ADR 0021, program design 4.5, the phase 5 and 6 notes and the tracker row were amended with the spec (the docs PR); add the final session-log line when W4 merges. Run `deepseek-review` on the W4a and W4b diffs; verify; fix test-first; merge both on green CI.
