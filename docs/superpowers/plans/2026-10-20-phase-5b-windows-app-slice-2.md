# Phase 5, slice 2: the flyout, tray states, single instance and the hotkey — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Implementers run on **Sonnet 5.5 with reasoning effort high**; escalate to Opus only for a task that failed two fix rounds. Reviews use the `deepseek-review` skill.

**Goal:** In `binary-companion/timetug-windows`, add the left-click flyout (today's agenda, problems, Join, footer), the tray's live states (tooltip and a minute-digit icon in the last ten minutes), a real single-instance guard that opens the flyout in the running copy, and the global popup hotkey (registration, storage and conflict handling; the recorder UI belongs to slice 3).

**Architecture:** Presentation gains a `FlyoutViewModel` and row models built from `AppState`; Platform gains the single-instance service, the hotkey service and the tray icon renderer; App gains `FlyoutWindow` and its placement logic. Everything that reads OS state stays behind an injectable interface (the slice 1 rule).

**Tech Stack:** as slice 1 (.NET 10, WinUI 3, Windows App SDK 2.x as pinned, CommunityToolkit.Mvvm, H.NotifyIcon.WinUI, CsWin32, xUnit + FluentAssertions, axe-windows).

**Spec:** `docs/superpowers/specs/2026-10-16-phase-5-windows-app-core-design.md` (Decisions row "Slices", "Architecture notes"); program design `docs/superpowers/specs/2026-10-09-windows-program-design.md` sections 3 and 4 ("Living in the system"). Slice 1 plan and reports: `docs/superpowers/plans/2026-10-16-phase-5a-windows-app-slice-1.md`.

## Global Constraints

- Everything in the slice 1 plan's Global Constraints still holds (no scheduling or default logic in C#, injected `TimeProvider`, no secrets in logs or commits, SHA-pinned actions, throwaway signing in CI, `SELFTEST` code only under the define, Sonnet implementers, DeepSeek reviews, squash-merge when green).
- **Display arithmetic is presentation.** Relative row text ("in 12 min") and the tray's remaining-minute digit are display formatting of engine-provided times against the injected `TimeProvider`; they are not scheduling or rules and the architecture test's timer/lead-time rule does not forbid them. What stays in the engine: which meetings exist, their phases, the next takeover and the lead time.
- **Mac is the behavioural reference.** The flyout mirrors `Apps/macOS/Sources/DropdownView.swift`: collision notice (slice 3, not here), problem rows, header (icon, weekday, summary, Settings button), day cards, empty state, "No meetings left", and the footer "Tug fires N min before". Width 360 DIP; the flyout never grows taller than 520 DIP, the list scrolls and the header stays put.
- **Mac default for the hotkey is none.** The popup shortcut is empty until the person records one (`PopupShortcut.swift`). Windows does the same: nothing is registered until a shortcut is stored; slice 3 adds the recorder. This slice delivers the service, the storage and the conflict reporting.
- Join, Settings, merge controls: Join works from a card; the Settings button is present but disabled until slice 3; duplicate merge controls and the collision notice are slice 3.
- Single instance in this slice covers one package identity. Detecting the other distribution's copy (Store versus website) and showing its collision notice has no owner yet: it is recorded as a named row in `docs/parity.md` ("cross-distribution single instance", status `not yet`, to be done in phase 9 when the website download exists) and in the tracker's phase 9 list.
- Launch at login is slice 3.
- The flyout never steals focus from a showing tug, and a tug appearing closes the flyout.

## Review Focus

1. **Flyout opened while the tug is up, and a tug firing while the flyout is open** — expected: the tug wins, the flyout closes, no second window fights for focus (Task 5, 8).
2. **Clicking the tray icon when it sits in the overflow** — expected: the flyout still opens near the icon or the overflow button, on the right monitor, never off-screen (Task 5).
3. **Second launch while the first is mid-startup or showing a tug** — expected: the first copy stays unaffected; the flyout opens only when startup has finished; no duplicate process (Task 6).
4. **Hotkey already used by another program, or the person has none stored** — expected: a clear diagnostics entry and a state the Settings slice can show; never a crash or a half-registered key (Task 7).
5. **Day list across midnight, time-zone and clock changes, and all-day events** — expected: rows and the "N meetings left" summary follow the engine's agenda (not C# date maths), and the flyout refreshes on the engine's state change (Task 1, 3).

---

### Task 1: Extend `AppState` for the flyout

**Files:** `src/TimeTug.Presentation/Engine/EngineStateModel.cs`, `EngineMapping.cs`, `tests/TimeTug.Presentation.Tests/EngineMappingTests.cs`.

**Interfaces:**
- Consumes: the `TimeTug.Engine` package's state record (read `dotnet/TimeTug.Engine/Messages.cs` in `timetug-shared` and `docs/engine-protocol.md`).
- Produces, additively (no existing member changes):

```csharp
public enum AgendaPhase { Past, Current, Upcoming }

public sealed record AgendaItem(
    string EventId, string Title, DateTimeOffset Start, DateTimeOffset End, bool IsAllDay,
    AgendaPhase Phase, string? CalendarTitle, string? CalendarColorHex,
    Uri? JoinUrl, int OtherAttendeeCount, bool IsMerged, string? Location);

public sealed record SourceProblem(string SourceId, string DisplayName, ProblemKind Kind, string? Detail, string? ConnectionId);
public enum ProblemKind { NeedsPermission, AuthExpired, Failing }

// on AppState: IReadOnlyList<AgendaItem> Agenda, IReadOnlyList<SourceProblem> Problems, TimeSpan LeadTime
```

`Phase` is the engine's agenda state (`DayAgenda.Item.State`), never recomputed in C#. `Problems` come from the engine's source statuses; `ConnectionId` is derived with the library's `<kind>-<connection>` source id rule (document that dependency in a comment and test it with a golden-fixture state).

- [ ] **Step 1: Write the failing tests** with a hand-built package state: each agenda item maps with its phase, calendar title and colour, join URL (only `http`/`https`), attendee count, merged flag; all-day events keep dates (no instants); each source status maps to a `SourceProblem` and `ok` maps to none; `LeadTime` comes from the engine settings; an unknown future field is ignored.
- [ ] **Step 2:** Run (FAIL), implement, run (PASS). Check the existing mapping tests still pass unchanged.
- [ ] **Step 3: Commit** — `git commit -m "Presentation: agenda items, problems and lead time in AppState"`.

---

### Task 2: Flyout view model and row text

**Files:** `src/TimeTug.Presentation/Flyout/{FlyoutViewModel.cs,FlyoutRow.cs,FlyoutText.cs}`, `Strings/en-US/Resources.resw` (App), `tests/TimeTug.Presentation.Tests/FlyoutViewModelTests.cs`.

**Interfaces:**
- Consumes: `AppState` (Task 1), `IEngineClient`, `TimeProvider`, `IUrlLauncher`.
- Produces:

```csharp
public sealed class FlyoutViewModel
{
    public FlyoutViewModel(IEngineClient engine, IUrlLauncher launcher, TimeProvider time, IMinuteTicker ticker);
    public string Weekday { get; }                 // "Tuesday"
    public string Summary { get; }                 // "3 meetings left" / "No meetings left" / "Nothing today", from the Mac's PopupText rules
    public IReadOnlyList<FlyoutRow> Rows { get; }  // one per AgendaItem, in order
    public IReadOnlyList<ProblemRow> Problems { get; }
    public string Footer { get; }                  // "Tug fires 1 min before"
    public bool IsEmpty { get; }  public bool NoMoreMeetings { get; }
    public ValueTask JoinAsync(string eventId);    // launcher failure sets FlyoutRow.JoinFailedUrl, never throws
    public ValueTask ReconnectAsync(string connectionId);   // for AuthExpired rows
    public event Action? Changed;                  // raised by the view model itself when `IEngineClient.State` emits or the ticker ticks; the window layer only marshals it to the UI dispatcher
}
```

`FlyoutRow` carries time text (range; "All day"; relative "in 12 min" / "now" for the current one, matching the Mac's `PopupRowModel`), title, calendar title and colour, attendee text ("5 others"), a Join flag, and a past/current/upcoming style flag. Text rules come from the Mac (`Apps/macOS/Sources/PopupText.swift`, `PopupRowModel`): read them and port exactly; all strings go through `Resources.resw`. `Summary` counts "meetings left" from the engine's agenda phases (upcoming plus current timed items), not from C# date arithmetic.

- [ ] **Step 1: Write the failing tests** (fake `IEngineClient`, `FakeTimeProvider`): weekday and summary for zero, one and many meetings left and for an all-day-only day; "No meetings left" banner after the last meeting; row text for past, current (ends in 10 min), upcoming (in 3 h), all-day, merged; Join present only with a URL; `JoinAsync` calls the launcher and, on failure, sets the row's `JoinFailedUrl` and sends nothing to the engine; problem rows for each kind with "sign in again" actions calling `ReconnectAccountAsync`; footer with 60 s lead time says "1 min"; rows refresh when `State` emits a new `AppState`; a minute-granularity timer (`PeriodicTimer`, allowed in Platform only: take it through an injected `IMinuteTicker` from slice 1) refreshes relative times.
- [ ] **Step 2:** Run (FAIL), implement, run (PASS).
- [ ] **Step 3: Commit** — `git commit -m "Presentation: flyout view model and row text"`.

---

### Task 3: Tray state and tooltip rules

**Files:** `src/TimeTug.Presentation/Tray/{TrayViewModel.cs (extend),TrayIconPlan.cs}`, `tests/TimeTug.Presentation.Tests/TrayViewModelTests.cs`.

**Interfaces:**
- Consumes: `AppState.NextTakeover`/`NextMeeting`, `TugController.NeedsAttention`, `IMinuteTicker`, `TimeProvider`.
- Produces: `TrayIconPlan(IconState State, int? Digit, string Tooltip)` where `Digit` is the remaining whole minutes (9 down to 1) only in the final ten minutes before the engine's next takeover/meeting start, else null; `Tooltip` is "Design review in 4 min", "Design review now", "No more meetings today", or "TimeTug" with an attention suffix. The ten-minute window and rounding rules are ported from the Mac's menu-bar countdown mode (read its status-item code), computed from `TimeProvider` against engine-provided times.

- [ ] **Step 1: Write the failing tests:** digit sequence at 10:00, 9:01, 5:00, 1:00 and 0:30 remaining (boundaries follow the Mac), no digit with no next meeting, attention overrides digits, all-day events never produce digits, crossing midnight and a clock change (the engine state changes; the plan recomputes on the next tick).
- [ ] **Step 2:** Run (FAIL), implement, run (PASS).
- [ ] **Step 3: Commit** — `git commit -m "Presentation: tray icon plan with digits and tooltip"`.

---

### Task 4: Tray icon digits and the live tooltip (Platform and App)

**Files:** `src/TimeTug.Platform/Tray/TrayIconRenderer.cs`, `src/TimeTug.App/Tray/TrayIconService.cs` (extend), `tests/TimeTug.Platform.Tests/TrayIconRendererTests.cs`, `tests/TimeTug.Platform.Tests/data/tray-digit-*.png` (golden images, small).

**Interfaces:** `TrayIconRenderer.Render(IconState state, int? digit, bool lightTaskbar, int sizePx) → byte[] png/ICO` drawing the digit centred on the colour icon, legible at 16, 20, 24 and 32 px, with a contrasting outline; cached per (state, digit, theme, size). The service swaps the icon and tooltip when the plan changes and follows the taskbar theme.

- [ ] **Step 1: Write the failing tests:** rendering is deterministic and independent of the machine's fonts: the digit is drawn from a bundled bitmap or vector glyph set committed with the app (not a system font), and the goldens are compared with a small per-pixel tolerance, so a different runner image cannot flip them (digits 1 to 9 at two sizes, light and dark), the cache returns the same instance for the same key, a changed theme re-renders; the renderer never throws for digit 0 or 10 (returns the plain icon).
- [ ] **Step 2:** Run (FAIL), implement with `Windows.UI.Composition`-free GDI drawing through CsWin32 or `System.Drawing` equivalents available on the pinned stack (record the choice), run (PASS); regenerate goldens only via an explicit script flag.
- [ ] **Step 3:** Wire into the existing tray service and add a self-test scenario `tray-states` that walks the plan through idle, soon (digit 9, 5, 1), attention and asserts the tooltip text and the icon hash; screenshot the notification-area crop on the VM (`vm-screenshot.sh`) for the owner (note: the VM taskbar is hidden; the scenario also renders each icon to PNG).
- [ ] **Step 4: Commit** — `git commit -m "Tray: minute digits in the icon and a live tooltip"`.

---

### Task 5: The flyout window and its placement (implemented as four commits, reviewed as four diffs: 5a placement and anchor, 5b window chrome and behaviour, 5c cards and rows, 5d self-test scenarios, screenshots and axe)

**Files:** `src/TimeTug.Presentation/Flyout/FlyoutPlacement.cs`, `src/TimeTug.App/Flyout/{FlyoutWindow.xaml(.cs),FlyoutHost.cs,EventCard.xaml(.cs),ProblemRowView.xaml(.cs)}`, `tests/TimeTug.Presentation.Tests/FlyoutPlacementTests.cs`.

**Interfaces:**
- Consumes: `FlyoutViewModel` (Task 2), `IMonitorService`, a new `ITrayAnchor` (`TryGetAnchor() → AnchorRect?` in physical pixels: first `Shell_NotifyIconGetRect` for the icon's identifier; if it fails or returns an empty rect, because the icon lives in the overflow, the rect of the notification-area overflow chevron found through UI Automation on the taskbar (`Shell_TrayWnd`) with a name or automation-id match recorded from a real VM probe; if that fails too, the corner of the taskbar's notification area nearest the clock. The probe results are written into `docs/spikes/2026-10-flyout-anchor.md` and each path has a VM test), `IUiSettings`, `TugController` state (to close the flyout on a tug).
- Produces: `FlyoutPlacement.Compute(PixelRect anchor, SizeInDips content, IReadOnlyList<MonitorInfo> monitors) → PixelRect` (pure function in physical pixels, because `AppWindow.MoveAndResize` takes pixels: it converts the DIP size (width 360, height min(content, 520), 8 DIP margin) with the DPI scale of the monitor that contains the anchor, opens above a bottom taskbar, below a top one, beside a side one, and clamps into that monitor's work area); `FlyoutHost.Toggle()`; `FlyoutWindow`.

Behaviour: borderless window, Mica or desktop acrylic backdrop (solid in the reduced-transparency and contrast modes), rounded corners (Windows 11 default), not in the taskbar or Alt+Tab, closes on deactivate and on Esc, header with app icon, weekday, summary and a disabled Settings button (a plain disabled button named "Settings", no explanatory text, until slice 3), problem rows above the header, a scrolling list of `EventCard`s (calendar colour bar, title, time, calendar name, attendee text, Join button), the empty state, "No meetings left", the footer; all text from resources; every control has an automation name; keyboard: Tab order, Enter on Join, Esc closes. A tug showing or firing closes the flyout and blocks `Toggle()` until the tug is gone.

- [ ] **Step 1: Write the failing tests, placement first, then host behaviour.** Host-behaviour tests (`FlyoutHostTests`, fakes for the window, `TugController` state and `IUiSettings`): Esc closes; deactivate closes; `Toggle()` opens then closes; `Toggle()` is refused while a tug is showing; a tug firing closes an open flyout; reduced transparency or a contrast theme selects the solid backdrop; reduce motion removes the open animation. Placement tests: taskbar bottom, top, left, right on a single monitor; a second monitor to the left with the taskbar on it (negative coordinates); anchor near a corner (clamped); an anchor on a different monitor than the primary; high DPI scaling factors; content shorter than 520; content taller (capped at 520); anchor unavailable (falls back to the bottom-right of the primary work area).
- [ ] **Step 2:** Run (FAIL), implement placement and the window, run (PASS).
- [ ] **Step 3:** Add self-test scenarios `flyout-empty`, `flyout-day` (a scripted day with past, current, upcoming, all-day and merged items), `flyout-problems` (auth expired and failing rows) and `flyout-tug-wins` (flyout open, takeover fires: the flyout closes, the tug shows, exactly one terminal command); screenshots; run the axe-windows scan on the flyout (the slice 1 a11y job extended); verify on the VM with `vm-selftest.sh`, read the screenshots, and take a real screen capture with the flyout open over a maximized window; fix visible defects. Put two key screenshots under `docs/screenshots/`.
- [ ] **Step 4: Commit** — `git commit -m "The flyout window"`.

---

### Task 6: Single instance with AppInstance

**Files:** `src/TimeTug.Platform/Instance/{AppInstanceService.cs,IInstanceActivation.cs}`, `src/TimeTug.App/App.xaml.cs`, `tests/TimeTug.Platform.Tests/AppInstanceServiceTests.cs`.

**Interfaces:** `IAppInstance` (`bool IsPrimary`, `event Action<ActivationKind> Activated`, `Task RedirectAsync(ActivationKind kind)`), `ActivationKind { Flyout }`. Implementation over the Windows App SDK `AppInstance.FindOrRegisterForKey("TimeTug.Main")`, `RedirectActivationToAsync`. It replaces the named-mutex guard from slice 1 (`SingleInstanceGuard`), keeping its guarantee that a second launch never touches the first copy's data.

Behaviour: a second launch redirects to the running copy and exits; the primary opens the flyout when it has finished starting (before that, it queues one activation and opens the flyout when startup completes); redirect while the tug is showing is ignored (the tug has priority) and logged; an unpackaged run (tests) falls back to the mutex guard.

- [ ] **Step 1: Write the failing tests** against a fake instance registry: first launch is primary; second is not primary and redirects once; activation before startup completes is queued and delivered once after; activation while a tug shows does not open the flyout; unpackaged fallback behaves like the old guard; two rapid redirects open one flyout.
- [ ] **Step 2:** Run (FAIL), implement, run (PASS). Remove the mutex path from production code but keep it as the unpackaged fallback.
- [ ] **Step 3:** Self-test scenario `second-launch` (starts the packaged app, launches it again through the alias and asserts one process, the flyout shown, and the second process's exit code); run it in CI and on the VM.
- [ ] **Step 4: Commit** — `git commit -m "Single instance with AppInstance"`.

---

### Task 7: Global hotkey service

**Files:** `src/TimeTug.Platform/Hotkey/{HotkeyService.cs,HotkeyBinding.cs,IHotkeyRegistrar.cs}`, `src/TimeTug.Presentation/Settings/IHotkeyStore.cs`, `tests/TimeTug.Platform.Tests/HotkeyServiceTests.cs` (fake store here), `tests/TimeTug.Presentation.Tests/HotkeyStateTests.cs`.

**Interfaces:** `HotkeyBinding(Modifiers, VirtualKey)` with a stable text form ("Ctrl+Alt+T") for storage; `IHotkeyStore` (declared in `src/TimeTug.Presentation/Settings/IHotkeyStore.cs`, implemented over `ApplicationData.LocalSettings` in Platform; app-side presentation setting; default: none, as on the Mac) persisting a `HotkeyState` (the binding plus the last result and when) so slice 3's Settings can show "this shortcut is inactive because another program uses it" after a restart; `HotkeyService.SetAsync(HotkeyBinding?)` → `HotkeyResult { Registered, Cleared, Conflict(OtherAppHoldsIt), Invalid(NoModifier) }`; `Pressed` event → `FlyoutHost.Toggle()`. `IHotkeyRegistrar` wraps `RegisterHotKey`/`UnregisterHotKey` on the hidden top-level window from slice 1 (`WM_HOTKEY`) so the logic is testable.

- [ ] **Step 1: Write the failing tests** with a fake registrar: nothing registered on start with no stored binding; a stored binding registers once at start; changing it unregisters the old one first; a conflict (`RegisterHotKey` fails) reports `Conflict`, is persisted in `HotkeyState` and still reported after a restart, keeps the previous binding active, writes a diagnostics entry (never the key text of other apps), and never leaves two registrations; clearing unregisters; a binding without a modifier is `Invalid`; pressing toggles the flyout once and never while a tug is showing; disposal unregisters.
- [ ] **Step 2:** Run (FAIL), implement, run (PASS). Add a SELFTEST-only scenario `hotkey` that stores a binding, injects `WM_HOTKEY` through the real window and checks the flyout opens; run it on both runners and the VM (real `RegisterHotKey` can fail on a runner without a desktop: record and accept that the scenario then asserts the conflict path).
- [ ] **Step 3: Commit** — `git commit -m "Global hotkey service"`.

---

### Task 8: Wire everything and update the tray's left click

**Files:** `src/TimeTug.App/App.xaml.cs`/`AppShell.cs`, `src/TimeTug.App/Tray/*`, `tests/TimeTug.App.Tests/*` where logic exists.

**Interfaces:** composes Tasks 1 to 7: left click → flyout when accounts exist, welcome window when none (slice 1 behaviour kept); hotkey and second-launch activation → flyout; the tray tooltip and icon follow `TrayIconPlan`; the tug closes the flyout; Quit closes the flyout first. Startup order: subscribe to `AppInstance.Activated` before the engine starts and hold at most one activation; engine up; first state; then deliver the held activation (opening the flyout) and register the hotkey.

- [ ] **Step 1: Write the failing tests** (composition-level, fakes): each trigger opens the flyout exactly once; with no accounts the left click shows the welcome window; a tug closes an open flyout; quit order (flyout, outstanding takeover, tray icon, engine).
- [ ] **Step 2:** Run (FAIL), implement, run (PASS).
- [ ] **Step 3:** Run the whole self-test suite on both runners and the VM; fix regressions in slice 1 scenarios (the `startup` and `tray` scenarios change because left click now opens the flyout).
- [ ] **Step 4: Commit** — `git commit -m "Compose the flyout, hotkey and single instance"`.

---

### Task 9: Checklist, parity, DeepSeek review and close slice 2

**Files:** `docs/manual-tests/windows-checklist.md`, `docs/parity.md`, `docs/screenshots/*`.

- [ ] **Step 1:** Add the human checks: flyout open from a tray icon in the overflow and when pinned, flyout beside a side taskbar and on a second monitor, Join from a card, auth-expired row Reconnect, the minute digit in the real tray icon in the last ten minutes, hotkey set through the dev store and conflict with another program's key, second launch while a tug shows, flyout with Narrator. Mark which parts the self-test covers.
- [ ] **Step 2:** Update `docs/parity.md` (flyout, header, rows, problems, footer, tray tooltip and digits, single instance, hotkey service = done or partly; Settings button, merge controls and hotkey recorder = slice 3).
- [ ] **Step 3:** Run the `deepseek-review` skill over the new sources with the slice spec and this plan; verify findings against the code; fix real ones in a follow-up PR.
- [ ] **Step 4:** In `timetug`: update the tracker (slice 2 built and merged; owner items) and memory; add to the phase 9 list "inject the Google and Microsoft OAuth client ids into Windows release builds from the release environment's secrets".
- [ ] **Step 5: Commit** and merge on green.

---

## Self-review notes

- Spec coverage for slice 2 (Decisions row "Slices"): flyout (2, 5), tray states and live tooltip (3, 4), single instance (6), hotkey (7). Launch at login, Settings, Appearance, duplicate management are slice 3; Store manifests slice 4.
- Known soft spots for the implementer: the exact engine state fields behind `AgendaItem` (Task 1 reads `Messages.cs` and the protocol guide); the Mac's countdown-mode boundaries for the tray digit (Task 3 reads the status-item code); how `Shell_NotifyIconGetRect` behaves for an overflow icon (Task 5 decides the fallback with a VM test).
