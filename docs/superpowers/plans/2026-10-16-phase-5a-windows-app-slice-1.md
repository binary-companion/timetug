# Phase 5, slice 1: the Windows app skeleton, accounts and the tug screen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Implementers run on **Sonnet 5.5**; escalate to Opus only for a task that failed two fix rounds.

**Goal:** Create `binary-companion/timetug-windows` and deliver slice 1 of the Windows app: a packaged WinUI 3 app that runs the shared engine, shows the first-run welcome window and accounts, takes over the screen with the tug (with its fallbacks and late-return rule), has a minimal tray, and proves all of it with a CI self-test on both Windows architectures.

**Architecture:** Three projects. `TimeTug.Presentation` (plain `net10.0`, runs on any runner): view models, the tug state machine and every interface to OS state. `TimeTug.Platform` (`net10.0-windows`): the engine host services and the OS-state implementations. `TimeTug.App` (WinUI 3, packaged MSIX): views, tray, window management, `--selftest`. The app consumes `TimeTug.Engine` from nuget.org at an exact pinned version.

**Tech Stack:** .NET 10, C#, WinUI 3 on the Windows App SDK (latest stable at execution time, pinned in `Directory.Packages.props`), MSIX, `CommunityToolkit.Mvvm`, `CommunityToolkit.WinUI`, `H.NotifyIcon.WinUI`, `Microsoft.Windows.CsWin32`, xUnit + FluentAssertions, `axe-windows`.

**Spec:** `docs/superpowers/specs/2026-10-16-phase-5-windows-app-core-design.md`. Parent: `docs/superpowers/specs/2026-10-09-windows-program-design.md` (sections 3, 4, 6, 7, 8). Engine contract: `docs/engine-protocol.md` and `docs/superpowers/specs/2026-10-15-phase-4-engine-c-interface-design.md`.

**Later slices** (2 flyout and tray states, 3 Settings and parity panes, 4 Store packaging) each get their own plan after this one lands, because what slice 1 teaches about WinUI, MSIX and the runners decides their details.

## Global Constraints

- Windows 11 22H2 (build 22621) or later, x64 and ARM64. Target framework `net10.0-windows10.0.22621.0` for Windows projects.
- Repository `binary-companion/timetug-windows`, public, MIT plus Commons Clause (holder Binary Companion LLC), default branch `main`, `.gitattributes` with `* text=auto eol=lf`. Brand artwork all rights reserved in `artwork/LICENSE.md`.
- No scheduling, dedup, rule or default logic in C#. View models talk only to `IEngineClient` (this repository's abstraction), never to P/Invoke. An architecture test enforces both.
- The app never runs elevated. No focus-stealing tricks (no simulated key presses, no thread-input attachment).
- All HTTP goes through `HttpClient`. Secrets only in Credential Locker. Never log event titles or calendar content.
- Every OS read sits behind an injectable interface: session lock and unlock, notification state, monitor list, transparency and animation settings, toast service, `TimeProvider`.
- Self-test and the `--selftest` switch exist only when the compile-time define `SELFTEST` is set (development and CI builds), never in release or Store builds.
- Pin third-party GitHub Actions by commit SHA (look it up with `gh api`, never guess). Pull-request jobs get none of the owner's signing material; the development MSIX uses a throwaway self-signed certificate created in the job.
- OAuth client ids come from a git-ignored local file (VM builds) and are never printed or committed; CI embeds none.
- Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Squash-merge when all checks pass. The owner applies rulesets, environments and required checks (owner-only).
- Reviews use the `deepseek-review` skill; never send secrets; verify findings against the repository.
- Display strings: the app owns its localization resources (`Strings/en-US/Resources.resw`); the engine supplies none.

## Review Focus

1. **Join must work by mouse alone while the tug has no keyboard focus** — expected: clicking Join opens the link; a failed open shows the link to copy (Task 8, 9).
2. **A tug held while locked, then the meeting is deleted before unlock** — expected: no tug; `takeover.closed` is sent; diagnostics says "no longer on the calendar" (Task 9).
3. **Two monitors, one unplugged while the tug is showing** — expected: the tug stays on the remaining monitor with controls; no crash (Task 7, 8).
4. **Transparency effects off, contrast theme on, reduce motion on** — expected: solid navy or system contrast colours, no animation (Task 8).
5. **Credential Locker or loopback blocked on a managed PC** — expected: a clear failure in the accounts UI and a diagnostics entry naming the step; other accounts keep working (Task 5, 6).

---

## File Structure

```
.gitattributes  .gitignore  .editorconfig  global.json  nuget.config
Directory.Build.props  Directory.Packages.props  TimeTug.sln
LICENSE  README.md  AGENTS.md  CODEOWNERS
artwork/LICENSE.md  artwork/…                       copied from timetug, plus generated icon sizes
docs/parity.md  docs/manual-tests/windows-checklist.md
scripts/verify.ps1  scripts/ci/…  scripts/vm/…        logic lives in scripts, not workflow YAML
.github/workflows/ci.yml  .github/pull_request_template.md
src/TimeTug.Presentation/   Engine/ Tug/ Welcome/ Accounts/ Diagnostics/ Abstractions/
src/TimeTug.Platform/       Credentials/ Http/ Auth/ OsState/ Diagnostics/
src/TimeTug.App/            App.xaml(.cs) Package.appxmanifest Views/ Tray/ Tug/ SelfTest/ Strings/
tests/TimeTug.Presentation.Tests/  tests/TimeTug.Platform.Tests/  tests/TimeTug.Architecture.Tests/
```

---

### Task 1: Create the repository and the solution skeleton

**Files:** everything in the tree above except `src/*/` feature folders; create `TimeTug.sln`, the three source projects and three test projects with one passing placeholder test each.

**Interfaces:** none yet.

- [ ] **Step 1:** Create the repository: `gh repo create binary-companion/timetug-windows --public --description "TimeTug for Windows" --license mit` is not enough for the Commons Clause, so create it empty with `gh repo create binary-companion/timetug-windows --public`, then clone it. Copy `LICENSE` text and the Commons Clause wording from `binary-companion/timetug-shared` (read its `LICENSE`; holder Binary Companion LLC) and `.gitattributes`, `.editorconfig` where applicable.
- [ ] **Step 2:** Add `global.json` pinning the .NET 10 SDK; `nuget.config` with only nuget.org; `Directory.Build.props` (nullable on, warnings as errors, analysers on, `LangVersion` latest, `ContinuousIntegrationBuild` in CI); `Directory.Packages.props` with central package management and **exact** versions of every package (look up the current stable versions of Windows App SDK, `CommunityToolkit.Mvvm`, `CommunityToolkit.WinUI.*`, `H.NotifyIcon.WinUI`, `Microsoft.Windows.CsWin32`, xUnit, FluentAssertions, `TimeTug.Engine`, `Axe.Windows` with `dotnet package search` and record them in the ledger).
- [ ] **Step 3:** Create the six projects and `TimeTug.sln`. `TimeTug.Presentation` is `net10.0`; `TimeTug.Platform` and `TimeTug.App` are `net10.0-windows10.0.22621.0`; the App project is a packaged WinUI 3 app (single-project MSIX) with `<Platforms>x64;ARM64</Platforms>` and a `SELFTEST` define in the `Debug` and `CI` configurations only. Each test project has one placeholder test that passes.
- [ ] **Step 4:** Write `AGENTS.md` (the rules of program design section 3 "Rules", the Global Constraints above, the backward-compatibility policy: a non-major `TimeTug.Engine` bump is merged when CI is green and requires no app change), `README.md`, `CODEOWNERS` (`@darkarena1`, as the other repositories), `artwork/LICENSE.md` (copy `timetug`'s wording, adapted to this repository's paths), `.github/pull_request_template.md`, `docs/parity.md` (a table seeded from the Mac app's capabilities: one row each for every pane and feature of `Apps/macOS/Sources`, status `not yet`), and `docs/manual-tests/windows-checklist.md` (empty headings: first run, accounts, tug screen, tray).
- [ ] **Step 5:** `dotnet build TimeTug.sln -c Debug -p:Platform=x64` and `dotnet test` on the VM or any Windows machine pass. Run them on the VM through `prlctl exec` (see Task 12 for the helper; until then run them by hand and record the command).
- [ ] **Step 6:** Commit and push `main`.

---

### Task 2: CI skeleton and the architecture test

**Files:** `.github/workflows/ci.yml`, `scripts/verify.ps1`, `scripts/ci/*`, `tests/TimeTug.Architecture.Tests/ArchitectureTests.cs`.

**Interfaces:** produces CI jobs named `windows-x64`, `windows-arm64`, `architecture`, which later become required checks.

- [ ] **Step 1: Write the failing architecture tests**

```csharp
public class ArchitectureTests
{
    private static readonly string Root = FindRepositoryRoot();

    [Fact]
    public void Presentation_has_no_windows_or_native_dependencies()
    {
        var project = File.ReadAllText(Path.Combine(Root, "src/TimeTug.Presentation/TimeTug.Presentation.csproj"));
        project.Should().NotContain("windows");
        project.Should().NotContain("WindowsAppSDK");
    }

    [Fact]
    public void Only_the_platform_project_may_use_pinvoke_or_the_native_engine()
    {
        foreach (var file in SourceFiles("src/TimeTug.Presentation").Concat(SourceFiles("src/TimeTug.App")))
        {
            var text = File.ReadAllText(file);
            text.Should().NotContain("DllImport", file);
            text.Should().NotContain("LibraryImport", file);
            text.Should().NotContain("TimeTug.Engine.NativeMethods", file);
        }
    }

    [Fact]
    public void No_scheduling_or_default_logic_in_csharp()
    {
        // The engine owns lead time, snooze choices and rules. Forbid their literals and timers in app code.
        foreach (var file in SourceFiles("src"))
        {
            var text = File.ReadAllText(file);
            text.Should().NotContain("new DispatcherTimer", $"{file}: timers that schedule takeovers belong in the engine");
            text.Should().NotMatchRegex(@"\bleadTime\s*=\s*\d", file);
        }
    }

    [Fact]
    public void Selftest_code_is_compiled_only_under_the_SELFTEST_define()
    {
        foreach (var file in SourceFiles("src/TimeTug.App/SelfTest"))
            File.ReadAllText(file).Should().StartWith("#if SELFTEST", file);
    }
}
```

- [ ] **Step 2: Run to verify failure.** `dotnet test tests/TimeTug.Architecture.Tests` → FAIL until `FindRepositoryRoot` and `SourceFiles` exist; write them (walk up to the folder containing `TimeTug.sln`; enumerate `*.cs` and `*.xaml.cs`, skipping `obj` and `bin`).
- [ ] **Step 3:** `scripts/verify.ps1` runs restore, build (x64 and ARM64 as the machine allows), tests and the architecture tests; the workflow only calls it. `ci.yml`: jobs `windows-x64` on `windows-latest` and `windows-arm64` on `windows-11-arm` (setup-dotnet pinned by SHA, `dotnet` 10), job `architecture` on `ubuntu-latest` running the architecture tests plus a repository-contracts script that checks `LICENSE`, `.gitattributes` and workflow action pins (copy and adapt `timetug-shared`'s `scripts/ci/check-repository-contracts.py` and its tests).
- [ ] **Step 4:** Run `scripts/verify.ps1` locally, push a branch, open a PR, get all three jobs green. Merge.
- [ ] **Step 5: Commit** — `git commit -m "CI skeleton and architecture tests"`.

---

### Task 3: Spike: a packaged WinUI window renders and is captured on both runners

**Files:** `src/TimeTug.App/App.xaml(.cs)`, `src/TimeTug.App/MainWindow` (temporary), `src/TimeTug.App/SelfTest/SelfTestRunner.cs`, `scripts/ci/build-msix.ps1`, CI job additions.

**Interfaces:**
- Produces: `ScreenCapture.Window(IntPtr hwnd, string path)` (PNG via `PrintWindow`/`Windows.Graphics.Capture`, whichever works on the runners), and `SelfTestRunner.Run(string scenario)` returning a JSON result file. This task proves the approach before any feature depends on it.

- [ ] **Step 1: Write the failing test** — a CI job step (not xUnit): after building the MSIX, run `TimeTug.App.exe --selftest hello` and assert `selftest-result.json` has `"ok": true` and a non-blank `hello.png` (more than one distinct colour; check with a small script).
- [ ] **Step 2:** Run it: fails (no app).
- [ ] **Step 3:** Implement a window that shows the text "TimeTug", the self-test entry point (`#if SELFTEST`; the development manifest declares an app execution alias `timetug-dev.exe` through `uap5:ExecutionAlias` so the switch can be passed while keeping package identity, which launching the `.exe` from the package folder would lose), the capture helper, and `scripts/ci/build-msix.ps1` (create a throwaway self-signed certificate in the job, build the packaged app for the architecture, sign, install the certificate to the runner's trusted store, install the package, return the launch command). Windows hosted runners are interactive enough for WinUI; if a runner cannot render the window, fall back to `RenderTargetBitmap` of the XAML root and record the finding.
- [ ] **Step 4:** The step passes on `windows-latest` and `windows-11-arm`; attach screenshots as artifacts; also run it on the VM through the Task 12 helper (until then by hand).
- [ ] **Step 5: Commit** — `git commit -m "Spike: packaged WinUI window renders and is captured on both runners"`. Write the findings (what worked, what each runner needs) into `docs/spikes/2026-10-spike-winui-ci.md`. If the spike fails on a runner, stop and report: the later tasks depend on it.

---

### Task 4: Presentation layer: the engine client and the application state

**Files:** `src/TimeTug.Presentation/Engine/{IEngineClient.cs,EngineClient.cs,EngineStateModel.cs}`, `Abstractions/{ITimeProvider usage,IDiagnostics.cs,ISessionState.cs,IMonitorService.cs,INotificationState.cs,IToastService.cs,IUrlLauncher.cs,IUiDispatcher.cs}`, `tests/TimeTug.Presentation.Tests/EngineClientTests.cs`.

**Interfaces:**
- Consumes: the `TimeTug.Engine` package types (`IEngine`, `EngineState`, `EngineEvent`, `EngineCommand`).
- Produces:

```csharp
namespace TimeTug.Presentation.Engine;

public interface IEngineClient
{
    IObservable<AppState> State { get; }           // latest-wins, replayed to new subscribers
    IObservable<TakeoverRequest> TakeoversDue { get; }
    IObservable<string> TakeoversWithdrawn { get; } // event ids
    ValueTask StartAsync();
    ValueTask AddAccountAsync(string kindId);
    ValueTask RemoveAccountAsync(string connectionId);
    ValueTask ReconnectAccountAsync(string connectionId);
    ValueTask CancelAuthorizationAsync();
    ValueTask TakeoverPresentedAsync(string eventId, bool onScreen);
    ValueTask TakeoverClosedAsync(string eventId);
    ValueTask JoinAsync(string eventId);
    ValueTask SnoozeAsync(string eventId, TimeSpan duration);
    ValueTask DismissAsync(string eventId);
    ValueTask TestTugAsync(string title, string calendarTitle);
    ValueTask SetEnabledAsync(bool enabled);        // the Enable Tug switch (engine settings patch)
    ValueTask SystemEventAsync(SystemEventKind kind, string? timeZone = null);
}
```

`AppState` is the Presentation-side projection of the engine state: accounts (id, kind, display name, status, calendar count), available account kinds (id, display name, configured), `Events` (event id, title, start, end, has-join-link; the held-tug rule and the tray read them), `NextMeeting` (title, start, has-join-link) and `NextTakeover` (event id, fire time, taken straight from the engine's `nextTakeover`, never computed in C#), `TakeoverVisible`, `Enabled`. `EngineClient` wraps `IEngine`, converts its `IAsyncEnumerable`s to observables, and never interprets rules.

- [ ] **Step 1: Write the failing tests** using a fake `IEngine` (an in-memory implementation of the package's interface that the test drives): a `state` message updates `State`; `AddAccountAsync("google")` sends `account.add` with that kind; `TakeoverPresentedAsync(id, false)` sends `takeover.presented` with `onScreen:false`; a second subscriber to `State` gets the latest state immediately; `SetEnabledAsync(false)` sends a `settings.apply` patch with only the enabled field.
- [ ] **Step 2:** Run (FAIL), implement (`EngineClient` over the package's `IEngine.SendAsync`), run (PASS).
- [ ] **Step 3: Commit** — `git commit -m "Presentation: engine client and app state"`.

---

### Task 5: Platform services: credentials, HTTP, browser sign-in, forms, diagnostics

**Files:** `src/TimeTug.Platform/Credentials/CredentialLockerStore.cs`, `Http/HttpClientTransport.cs`, `Auth/{LoopbackAuthorization.cs,SystemBrowserLauncher.cs,CredentialFormPrompter.cs}`, `Diagnostics/{RollingFileLog.cs,EtwDiagnostics.cs}`, `src/TimeTug.Platform/EngineHost.cs` (the `IEngineHost` implementation), `tests/TimeTug.Platform.Tests/*`.

**Interfaces:**
- Consumes: `IEngineHost`, `ICredentialStore`, `IHttpTransport`, `IAuthorizationInteraction`, `EngineServiceException`, `ServiceErrorKind` from `TimeTug.Engine`.
- Produces: `public sealed class WindowsEngineHost : IEngineHost` and the pieces above. A small interface `IPasswordVault` (`Retrieve`, `Add`, `Remove`) wraps `Windows.Security.Credentials.PasswordVault` so the store is testable.

Behaviour to implement and test:
- `CredentialLockerStore`: one vault resource `TimeTug`, user name = connection id, password = a JSON object of the secrets plus a `revision` GUID (stored inside the JSON). `UpdateRefreshTokenAsync` compares revision and writes atomically behind one `SemaphoreSlim`; returns false on mismatch without writing. Missing connection → `null`, never an exception.
- `HttpClientTransport`: one shared `HttpClient` (system proxy and certificate store, no cookies, no cache); 4xx and 5xx returned as results; `HttpRequestException`, timeouts and DNS failures become `EngineServiceException(ServiceErrorKind.Network, …)`; request bodies and headers passed through; never logs URLs with query strings.
- `LoopbackAuthorization`: `BeginRedirectAsync` finds a free port (bind a `TcpListener` to `127.0.0.1:0`, read the port, release it) and starts an `HttpListener` on that explicit `http://127.0.0.1:<port>/` prefix (`HttpListener` cannot bind port 0), retrying up to 5 times when the port is taken in between, returns the session id and `http://127.0.0.1:<port>/`; `AuthorizeAsync` opens the URL with the default browser through `IUrlLauncher`, waits for the redirect request, answers it with a small "You can close this tab" page, returns the full redirect URL, and honours cancellation (`ServiceErrorKind.Cancelled`); `CloseRedirectAsync` stops the listener; a second `AuthorizeAsync` for a closed session throws `NotFound`.
- `CredentialFormPrompter`: implements all of `IAuthorizationInteraction` that is not the browser flow: `PrepareSignInAsync` and `PromptCredentialsAsync` go to `IAccountFormService` (implemented by the App's dialog in Task 6), `LastNonSecretValuesAsync` returns the non-secret values of the last submitted form (secret fields are never kept; null when none was submitted), and "user cancelled" maps to `ServiceErrorKind.Cancelled`.
- Diagnostics: `RollingFileLog` writes under `ApplicationData.Current.LocalFolder\logs`, rolling at 1 MB, keeping five files, never writing event titles (the engine already omits them; the log adds timestamp and category); `EtwDiagnostics` is an `EventSource` named `BinaryCompanion-TimeTug`.

- [ ] **Step 1: Write the failing tests**, for example:

```csharp
[Fact]
public async Task Refresh_token_update_with_a_stale_revision_writes_nothing()
{
    var vault = new FakePasswordVault();
    var store = new CredentialLockerStore(vault);
    await store.SetAsync("c1", new Dictionary<string, string> { ["refresh_token"] = "old" }, default);
    var snapshot = (await store.SnapshotAsync("c1", default))!;
    (await store.UpdateRefreshTokenAsync("c1", "new", "not-the-revision", default)).Should().BeFalse();
    (await store.GetAsync("c1", default))!["refresh_token"].Should().Be("old");
    (await store.UpdateRefreshTokenAsync("c1", "new", snapshot.Revision, default)).Should().BeTrue();
}

[Fact]
public async Task A_connection_refused_becomes_a_network_error()
{
    var transport = new HttpClientTransport(new HttpClient(new ThrowingHandler(new HttpRequestException("refused"))));
    var act = async () => await transport.SendAsync(new EngineHttpRequest("GET", "https://example.test/", new Dictionary<string, string>(), null), default);
    (await act.Should().ThrowAsync<EngineServiceException>()).Which.Kind.Should().Be(ServiceErrorKind.Network);
}

[Fact]
public async Task Loopback_returns_the_redirect_url_and_answers_the_browser()
{
    var launcher = new FakeLauncher(onOpen: url => FakeBrowser.FollowRedirect(url, "?code=abc&state=xyz"));
    var auth = new LoopbackAuthorization(launcher);
    var session = await auth.BeginRedirectAsync(default);
    var redirect = await auth.AuthorizeAsync(session.SessionID, "https://accounts.example.test/auth", default);
    redirect.Should().StartWith(session.RedirectURI).And.Contain("code=abc");
    await auth.CloseRedirectAsync(session.SessionID, default);
}
```

  Also: 20 parallel `UpdateRefreshTokenAsync` calls with the same expected revision let exactly one succeed; every member of `IEngineHost` is non-null on `WindowsEngineHost` and answers (a reflection test over the interface, plus one request per kind taken from the package's golden fixtures where the fixtures are shipped in the package); the form prompter returns non-secret values only; cancellation cancels the wait; the listener port is released on close; the vault never receives the secrets in plain text outside the JSON blob; the file log rolls at the size limit and never writes more than five files.
- [ ] **Step 2:** Run (FAIL), implement, run (PASS), on x64 and ARM64 runners via CI and on the VM.
- [ ] **Step 3: Commit** in three commits so they review separately: `Platform: credential locker and HTTP`, `Platform: loopback sign-in, form prompter and the engine host`, `Platform: diagnostics`.

---

### Task 6: Welcome window and accounts

**Files:** `src/TimeTug.Presentation/Welcome/{WelcomeViewModel.cs,AccountsViewModel.cs}`, `src/TimeTug.App/Views/{WelcomeWindow.xaml(.cs),CredentialFormDialog.xaml(.cs)}`, `src/TimeTug.App/Strings/en-US/Resources.resw`, `tests/TimeTug.Presentation.Tests/WelcomeViewModelTests.cs`.

**Interfaces:**
- Consumes: `IEngineClient`, `AppState` (Task 4), `IAccountFormService` (Task 5).
- Produces: `WelcomeViewModel` with `Step` (`Connect`, `Connected`), `Providers` (from `AppState.AvailableKinds`, unconfigured ones shown disabled with the reason), `ConnectAsync(kindId)`, `AddAnotherAsync()`, `TestTugAsync()`, `Done()`, and `ShouldShowAtStartup(AppState)` (true only when there are zero accounts after the engine's first `state`).

Behaviour (spec, "What the owner will see first" item 1): step 1 lists Google, Microsoft, iCloud, Other (CalDAV) in engine order, with a "Skip for now" link; Google and Microsoft show "opens your browser"; a failed sign-in shows the error beside that provider and keeps the window; step 2 shows each connected account ("Google · you@example.com · 3 calendars"), the next meeting, Add another, Test tug, the one-time tray note, Done. The window never appears when `State` already has accounts. A `Cancel` during browser sign-in sends `account.cancel`. The credential form dialog is built from the engine's field descriptions and localizes labels by field key with the English label as fallback.

- [ ] **Step 1: Write the failing tests** (fake `IEngineClient`): no accounts → `ShouldShowAtStartup` true; one account → false; `ConnectAsync("google")` calls `AddAccountAsync("google")`, and when state then contains one account the step becomes `Connected`; a failed connect (state with an account status of `failing` or an engine diagnostic for that kind) keeps step `Connect` and sets `Error` for that provider; unconfigured kind is disabled; `TestTugAsync` calls the engine's test tug with a sample title.
- [ ] **Step 2:** Run (FAIL), implement view models and views (Mica window, `NavigationView` not used; plain page), run (PASS).
- [ ] **Step 3:** Add the welcome window to the self-test (Task 11) as scenario `welcome`; capture screenshots of both steps.
- [ ] **Step 4: Commit** — `git commit -m "Welcome window and accounts"`.

---

### Task 7: The tug state machine and OS-state services

**Files:** `src/TimeTug.Presentation/Tug/{TugController.cs,TugState.cs,TugPlan.cs}`, `Abstractions/*` already created, `src/TimeTug.Platform/OsState/{SessionState.cs,NotificationState.cs,MonitorService.cs,UiSettings.cs,ToastService.cs,UrlLauncher.cs}`, `tests/TimeTug.Presentation.Tests/TugControllerTests.cs`.

**Interfaces:**
- Consumes: `IEngineClient`, `ISessionState` (`IsLocked`, `Locked`/`Unlocked` events), `INotificationState` (`CanShowFullScreen` false for exclusive full-screen or presentation mode, `ToastsAllowed`, and a `FullScreenEnded` event: `SHQueryUserNotificationState` has no notification, so the Platform implementation polls it with a `PeriodicTimer` every 5 seconds only while a request is held), `IMonitorService` (`Monitors`, `Changed`, `Primary`), `IToastService` (`ShowAsync(TakeoverRequest) → bool accepted`), `TimeProvider`, `IUrlLauncher`, `IUiDispatcher`.
- Produces:

```csharp
public enum TugState { Hidden, Shown, ShownWithoutFocus, Toast, HeldUntilReturn }

public sealed class TugController
{
    public TugState State { get; }
    public TakeoverRequest? Current { get; }
    public event Action<TugPlan>? PlanChanged;   // what the window layer should draw
    public ValueTask OnTakeoverDueAsync(TakeoverRequest request);
    public ValueTask OnTakeoverWithdrawnAsync(string eventId);
    public ValueTask OnEngineStateAsync(AppState state);
    public ValueTask JoinAsync();          // Join; a launcher failure produces TugPlan.JoinFailed(url)
    public ValueTask SnoozeAsync(TimeSpan duration);
    public ValueTask DismissAsync();
    public ValueTask OnSessionUnlockedAsync();
    public ValueTask OnMonitorsChangedAsync();
}
```

`TugPlan` carries: the request, per-monitor roles (`Primary`, `Mirror`), `ShowClickToRespond`, `JoinFailedUrl`, and the mode (`FullScreen`, `Toast`, `None`). The controller never uses the OS clock directly (only `TimeProvider`) and never schedules: it reacts to engine events.

Rules (each is a test):
1. `takeoverDue` with the session unlocked and full-screen allowed → `Shown` (or `ShownWithoutFocus` when the platform reports it cannot take focus), plan has every monitor, primary with controls, others mirror; reports `takeover.presented(onScreen:true)`.
2. Full-screen not allowed and toasts accepted → `Toast`, reports `presented(onScreen:false)`; toast refused → `HeldUntilReturn`, tray attention flag set, diagnostics entry, and **no** `presented` report.
3. Session locked → `HeldUntilReturn`.
4. `OnSessionUnlockedAsync` (and the full-screen-ended signal) with a held request: if the event is still in the latest `AppState` events and `TimeProvider.GetUtcNow() < request.End` → show the full tug (late: the plan carries `LateBy`), report presented; if the event is gone or ended → `takeover.closed` and a diagnostics entry ("missed, meeting over" or "no longer on the calendar"), state `Hidden`.
5. `takeoverWithdrawn` for the current request that is not yet held or shown → ignore; for a held request whose event is gone → treated as rule 4's "gone" branch at return time (no command until then, the contract still owes exactly one).
6. Join: launcher success → `engine.Join`; launcher failure → plan `JoinFailed(url)`, request stays, no engine command; Snooze/Dismiss send the engine command and set `Hidden`; exactly one terminal command per request on every path (a property test over random event sequences asserts "never more than one terminal command per request, and exactly one once the request has left Shown, Toast and HeldUntilReturn"; quitting the app with an outstanding request sends `takeover.closed` first).
7. Monitors changing while shown rebuilds the plan keeping the primary controls on the new primary monitor.

- [ ] **Step 1: Write the failing tests** for each rule with fakes and a manual `TimeProvider` (`Microsoft.Extensions.Time.Testing.FakeTimeProvider`), plus the property test (FsCheck or a seeded random loop of 500 sequences).
- [ ] **Step 2:** Run (FAIL), implement, run (PASS).
- [ ] **Step 3:** Implement the Platform services: `SessionState` (`WTSRegisterSessionNotification`, `WM_WTSSESSION_CHANGE` through a message-only window), `NotificationState` (`SHQueryUserNotificationState` via CsWin32; exclusive full-screen, presentation mode → full-screen not allowed; busy/quiet-time → toast risk flagged), `MonitorService` (`EnumDisplayMonitors`, `WM_DISPLAYCHANGE`), `UiSettings` behind `IUiSettings` (`UISettings.AnimationsEnabled`, transparency effects, high contrast, and the taskbar theme `SystemUsesLightTheme` that the tray icon follows), `ToastService` (`AppNotificationManager`, returns whether Windows accepted it; Join, Snooze, Dismiss buttons mapped to controller calls), `UrlLauncher` (`Launcher.LaunchUriAsync`; only `http`/`https`/known conferencing schemes allowed; failure returns false). Each has an interface in Presentation and a thin test with a fake where logic exists.
- [ ] **Step 4:** Add `SystemEventsBridge` in Platform: it sends the engine's system events from OS notifications through `IEngineClient.SystemEventAsync`: power resume (`PowerModeChanged`) → `wake`; `WM_TIMECHANGE` → `clockChanged`; a time-zone change (`TimeZoneInfo` change, `WM_SETTINGCHANGE` for the time zone) → `timeZoneChanged` with the IANA id (convert the Windows id with `TimeZoneInfo.TryConvertWindowsIdToIanaId`); local midnight (one timer to the next midnight, rearmed after each firing, as Windows has no day-change notification; this is a notification substitute, not takeover scheduling) → `dayChanged`; `NetworkChange.NetworkAvailabilityChanged` to available → `networkReturned`; `WM_DISPLAYCHANGE` → `displayChanged` and `IMonitorService.Changed`. The session-change window is a hidden message-only window created through CsWin32 (`WTSRegisterSessionNotification` needs an `HWND`, and the WinUI windows come and go). Test with fakes: each source raises exactly one engine system event; unlock is app-local and sends none; the architecture test's timer rule allows timers only under `src/TimeTug.Platform`.
- [ ] **Step 5: Commit** — commit the controller and the OS-state services as two commits (`Tug state machine`, `OS-state services and system events`) so they review separately.

---

### Task 8: The tug window

**Files:** `src/TimeTug.App/Tug/{TugWindowHost.cs,PrimaryTugWindow.xaml(.cs),MirrorTugWindow.xaml(.cs),TugBackdrop.cs}`, `src/TimeTug.Presentation/Tug/TugViewModel.cs`, `tests/TimeTug.Presentation.Tests/TugViewModelTests.cs`, `src/TimeTug.App/Assets/hero.png` (copied from the artwork).

**Interfaces:**
- Consumes: `TugPlan` (Task 7), `UiSettings`.
- Produces: `TugWindowHost` (subscribes to `TugController.PlanChanged`, creates one borderless topmost window per monitor sized to the monitor, primary with controls and mirrors without, destroys them on `Hidden`).

Behaviour (spec items 2 and 4): hero picture, large live countdown (updated once a second from `TimeProvider`; after the start it reads "Started 2:10 ago" style via the same text rules as the Mac's `TakeoverCountdown`, written as view-model text with resources), title (two lines max), details line `"{start}–{end} · {calendar} · {N} people"` (Mac's `TakeoverText.details`), Join only when the request has a link, Snooze menu with the request's `SnoozeOptions`, Dismiss; Return joins (or dismisses when no link), Esc dismisses, 1, 5, 0 snooze when offered; hints line; a "Click anywhere to respond" banner when `ShowClickToRespond`, and the first click on any part of the window takes focus; backdrop: desktop acrylic with navy tint, solid navy when transparency effects are off, system contrast colours in a contrast theme; no animation when `AnimationsEnabled` is false; Narrator announcement through a UI Automation notification event when the tug appears; every control has an `AutomationProperties.Name`; mirrors say "Dismiss on your main display".

- [ ] **Step 1: Write the failing view-model tests**: countdown text before and after start (using `FakeTimeProvider`), details line with and without calendar title and attendees, hints list only applicable keys, keyboard routing (`1` snoozes 60 s only when 60 s is in `SnoozeOptions`), reduced-motion flag disables the animation flag, contrast mode selects the high-contrast palette, spoken announcement text.
- [ ] **Step 2:** Run (FAIL), implement the view model, the windows and the host, run (PASS).
- [ ] **Step 3:** Verify on the VM (Task 12 helper): trigger `--selftest tug-basic`, read the screenshots of primary and mirror windows; fix visible defects. Check the window really covers the monitor including the taskbar area and sits above normal windows and borderless full-screen apps.
- [ ] **Step 4: Commit** — `git commit -m "The tug window"`.

---

### Task 9: Hold, toast and late return, wired end to end

**Files:** `src/TimeTug.App/App.xaml.cs` (composition root), `src/TimeTug.Presentation/Tug/TugController.cs` (already), `tests/TimeTug.Presentation.Tests/LateReturnTests.cs`.

**Interfaces:** consumes everything from Tasks 4 to 8; produces the composed running app: engine started with `WindowsEngineHost`, `TugController` fed by `EngineClient`, `TugWindowHost` drawing plans, toast actions routed to the controller, a startup flow that opens the welcome window when `ShouldShowAtStartup`.

- [ ] **Step 1: Write the failing integration-style tests** (Presentation level, fake engine): locked at fire time → held → unlock 10 minutes into a 30-minute meeting → plan is full-screen with `LateBy` 10 minutes and exactly one `takeover.presented`; unlock after the meeting ended → one `takeover.closed`, no plan; meeting deleted while locked (state no longer contains it) → one `takeover.closed`; toast refused → held plus attention flag, then shown on return; Join with a failing launcher → `JoinFailedUrl` plan, then Dismiss sends exactly one terminal command.
- [ ] **Step 2:** Run (FAIL), implement the composition root (`Microsoft.Extensions.Hosting` generic host, DI registrations with interfaces), run (PASS).
- [ ] **Step 3: Commit** — `git commit -m "Compose the app: hold, toast and late return"`.

---

### Task 10: Minimal tray

**Files:** `src/TimeTug.App/Tray/{TrayIconService.cs,TrayMenu.cs}`, `src/TimeTug.Presentation/Tray/TrayViewModel.cs`, icons under `src/TimeTug.App/Assets/Tray/` generated from the artwork (light, dark, colour states; `scripts/ci/make-icons.ps1` produces 16, 20, 24, 32 px at 100 to 200 percent), `tests/TimeTug.Presentation.Tests/TrayViewModelTests.cs`.

**Interfaces:** consumes `AppState`, `IEngineClient`; produces `TrayViewModel` with `NextText` (information only: "Next: Design review · 2:30 PM", or "Join Design review" once a link is near, taken from the engine's next-takeover state, not computed), `Enabled` (toggles `SetEnabledAsync`), `TestTug`, `Settings` (disabled placeholder until slice 3), `Quit`, `IconState` (`Idle`, `Soon`, `Attention`: attention when a tug is held or a toast was refused, `Soon` straight from the engine's next-takeover state).

- [ ] **Step 1: Write the failing tests**: menu has at most six rows in the grouped order of the program design; `Enabled` round-trips through the engine setting; `Quit` calls the application shutdown once; icon state follows the controller's attention flag and the engine's next takeover; the tray icon follows the taskbar theme (`SystemUsesLightTheme`), not the app theme.
- [ ] **Step 2:** Run (FAIL), implement with `H.NotifyIcon.WinUI`, run (PASS). Left-click opens the welcome window when there are no accounts (a stand-in until slice 2's flyout).
- [ ] **Step 3: Commit** — `git commit -m "Minimal tray"`.

---

### Task 11: Self-test scenarios, screenshots and accessibility checks in CI

**Files:** `src/TimeTug.App/SelfTest/{SelfTestRunner.cs,Scenarios/*.cs,FakeOsState.cs,ScriptedCalendarHost.cs}` (all under `#if SELFTEST`), `scripts/ci/run-selftest.ps1`, `.github/workflows/ci.yml` additions, `tests/TimeTug.App.A11y/` (axe-windows run).

**Interfaces:** consumes the composed app. Scenarios, each producing `result.json` and numbered PNGs: `welcome` (both steps, account added through a scripted provider), `tug-basic` (two faked monitors; primary with controls, mirror; Join, Snooze 5, Dismiss each as a separate run; one terminal command each), `tug-no-focus` ("Click anywhere to respond", then the click), `tug-toast` (full-screen not allowed → toast), `tug-late-return` (lock, advance both clocks 10 minutes, unlock), `tug-meeting-gone`, `tug-join-fails`, `tug-contrast-and-motion`.

- [ ] **Step 1:** Write the scenario runner so each scenario is a short C# script over the fakes (fake `ISessionState`, `INotificationState`, `IMonitorService`, `UiSettings`, `IToastService`, `IUrlLauncher`, and a `ScriptedCalendarHost` whose HTTP answers come from files under `tests/data/` — the smallest Google events response and token response, as in `timetug-shared`'s scenarios). The engine runs with `testing: true`; the self-test advances the engine clock with `test.advanceClock` and its own `FakeTimeProvider` by the same amount.
- [ ] **Step 2: Write the failing CI step**: `scripts/ci/run-selftest.ps1` runs every scenario against the installed dev MSIX and fails on any `"ok": false`, any scenario missing a result, or any blank screenshot.
- [ ] **Step 3:** Run (FAIL), implement, run (PASS) on both architectures and on the VM. Upload screenshots as artifacts.
- [ ] **Step 4:** Add the `axe-windows` job: run the accessibility scan against the welcome window and the tug window while the self-test holds them open (a scenario `a11y-hold` pauses until the scanner finishes), fail on any error-level rule, and write the report as an artifact.
- [ ] **Step 5: Commit** — `git commit -m "Self-test scenarios, screenshots and axe-windows in CI"`.

---

### Task 12: VM workflow and the first manual checklist

**Files:** `scripts/vm/{vm-up.sh,vm-run.sh,vm-install.ps1,vm-screenshot.sh}`, `docs/manual-tests/windows-checklist.md`, `docs/development.md`.

**Interfaces:** produces the helpers the agent uses to drive the Parallels Windows 11 VM from the Mac: `vm-up.sh` resumes the VM if suspended (`prlctl resume`), waits for Parallels Tools; `vm-run.sh <command>` runs a command in the VM (`prlctl exec`); `vm-install.ps1` installs the development MSIX and its throwaway certificate; `vm-screenshot.sh <path>` captures the VM screen (`prlctl capture`). `docs/development.md` documents Developer Mode needs (SwiftPM is not involved here), where local OAuth ids go (`%LOCALAPPDATA%\TimeTug\dev-oauth.json`, git-ignored; copy file to file, never print), and how to run the self-test locally.

- [ ] **Step 1:** Write and run each helper on the VM; record exact commands and any prerequisite (Parallels Tools, shared folder or `prlctl exec` file copy for the MSIX) in `docs/development.md`. Failing first: running `vm-run.sh "echo ok"` with the VM suspended starts it and returns `ok`.
- [ ] **Step 2:** `windows-checklist.md` lists the human checks of slice 1, each with an exact action and expected result: real Google sign-in, real Microsoft sign-in, iCloud with an app-specific password, an account already present (the window does not appear), the tug on a real second monitor if available, Join opening the real conference link, Test tug, the tray icon in the notification area and in the overflow, Narrator reading the tug, high contrast, transparency off.
- [ ] **Step 3: Commit** — `git commit -m "VM helpers and the first manual checklist"`.

---

### Task 13: Development MSIX in CI, review and close of slice 1

**Files:** `.github/workflows/ci.yml` (MSIX job and artifact), `docs/parity.md` (status updates), `docs/superpowers/` notes in `timetug`.

- [ ] **Step 1:** CI builds the development MSIX for x64 and ARM64 on every PR and merge, signed with the job's throwaway certificate, uploaded as an artifact with its public certificate and `vm-install.ps1`. Verify the artifact installs and passes the self-test on the VM.
- [ ] **Step 2:** Run the `deepseek-review` skill over the whole repository diff (presentation and platform sources plus the spec), verify findings against the code, fix real ones.
- [ ] **Step 3:** Update `docs/parity.md` for what slice 1 delivered; list in a message to the owner, with direct links, what only the owner can do: apply the organization rulesets and environments to `timetug-windows` (<https://github.com/organizations/binary-companion/settings/rules>), add the CI jobs as required checks bound to GitHub Actions (<https://github.com/binary-companion/timetug-windows/settings/rules>), and run `docs/manual-tests/windows-checklist.md` with real accounts on the VM.
- [ ] **Step 4:** In `timetug`: update the tracker (phase 5 slice 1 built and merged; owner items) and the memory; open and merge that PR when green.
- [ ] **Step 5: Commit** — `git commit -m "Close slice 1"`.

---

## Self-review notes

- Spec coverage: first-run welcome and accounts (6), tug screen and fallbacks (7, 8, 9), tray (10), host services (5), self-test and CI (3, 11, 13), accessibility (8, 11), VM workflow (12), repository and licence (1, 2), anti-goal and Join by mouse (7, 8), late return and withdrawn rule (7, 9), OAuth ids handling (Global Constraints, 12), package identity first (3, 13). Not in slice 1 by design: flyout, hotkey, single instance, launch at login, Settings panes, duplicate management, Store manifests.
- Known soft spots for the implementer: the exact names in `TimeTug.Engine`'s `EngineState` and message records must be read from the package (`docs/engine-protocol.md`, `dotnet/TimeTug.Engine/Messages.cs`) before writing `AppState`; Task 3 decides whether `PrintWindow`, `Windows.Graphics.Capture` or `RenderTargetBitmap` is the capture method on the runners.
