# Phase 5 extra: the countdown chip and the jump list — Design and Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Implementers run on **Sonnet 5.5 with reasoning effort high**; reviews use the `deepseek-review` skill; squash-merge when green.

**Goal:** In `binary-companion/timetug-windows`, add two glanceable surfaces that Windows allows third-party apps: an optional **countdown chip** (a small always-on-top window showing the next meeting and its countdown, the closest Windows has to the Mac's menu-bar text) and a **jump list** (tasks on the app's taskbar or Start entry). Both are owner-requested (2026-10-22) and are extras to slices 1 to 4: they do not change the Store packaging slice.

**Owner request:** "go ahead and do the countdown chip and jump list". The design below is the agent's call on every detail the owner did not specify; each is marked (C).

**Spec context:** `docs/superpowers/specs/2026-10-16-phase-5-windows-app-core-design.md` (presentation settings stay in the app; engine decides what and when), program design section 4 ("Text in the icon": the pinned countdown chip is the named "later option"), `docs/parity.md`, the slice 2 and 3 plans and reports.

## Spec amendment (owner, 2026-10-22)

The phase 5 spec's Decisions row "Presentation settings" says the pinned countdown chip is deferred. The owner asked for it on 2026-10-22, so it is no longer deferred: it ships as an optional presentation feature (off by default), and `docs/parity.md` records it as "differs on purpose from the Mac's menu-bar text: done". The amendment is written into the spec's row in the same pull request as this plan.

## Design

### The countdown chip (C)

- **Rule placement.** The chip's show window (the user's chosen N minutes, running, all-day excluded) is presentation: a per-user display preference applied to the engine's agenda and next-takeover state with `TimeProvider`, the same kind of display arithmetic the flyout rows and the tray digit already do. The engine still decides which meetings exist, their phases, the next takeover and the join window (the chip and the jump list read the engine's flags; they do not compute links or windows). The architecture test's rule against scheduling, rules and defaults in C# is not violated and is not waived.
- **What it shows:** the app icon, the next meeting's title (one line, truncated with an ellipsis) and a countdown: "in 12 min", "now" while it runs ("ends 10:50"), "in 1 h 5 min" beyond an hour. Text comes from the same rules as the flyout's rows (`FlyoutText`), from the engine's agenda and next-takeover state; no scheduling or date logic beyond display arithmetic against `TimeProvider` and the per-minute ticker.
- **Visibility modes** (Appearance pane, presentation setting `ChipMode`): **Off** (default, so nothing changes for existing users), **Before meetings** (shown from N minutes before the next timed meeting until it ends; N = 15 by default, choices 5, 10, 15, 30, 60), **Always** (whenever there is a next or current meeting today). When there is nothing to show the chip is hidden, never empty.
- **Placement:** a small borderless always-on-top window, draggable, position remembered per monitor in presentation settings as DIPs relative to that monitor's work-area origin (so a restore across a DPI change lands where it was dragged), validated against the current monitors, and recomputed whenever the display configuration, a monitor's DPI or the taskbar placement changes; default: just above the taskbar's notification area on the primary monitor, using the existing tray anchor. It never covers the tug (the tug is above it; the chip hides while a tug shows), never appears over exclusive full-screen apps (`SHQueryUserNotificationState` has no change event, so while the chip is visible the host re-reads `INotificationState` on every minute tick and on a 2 s `PeriodicTimer` owned by Platform, and hides it on the transition; tested), and never takes focus (spike 2026-10: `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW` alone is not enough because WinUI activates the window on a press; use `NoActivateGuard` in `TimeTug.Platform/Chip`, a thread `WH_CBT` hook refusing `HCBT_ACTIVATE` and `HCBT_SETFOCUS`; click handling through pointer events).
- **Interaction:** left click opens the flyout (the same `FlyoutHost.Toggle`); right-click opens a small menu: Join (when the next meeting has a link and is within the join window), Hide until the next meeting, Open Settings (Appearance), Test tug is not included. Drag moves it; a double-click resets the position. Esc is not meaningful (it never has focus).
- **Appearance:** follows the app theme (`ThemeService`) and the flyout backdrop choice (spike 2026-10: built-in Mica and acrylic render flat on a never-active window, so the chip uses a custom always-active acrylic `SystemBackdrop` with an explicit theme tint; solid under reduced transparency and contrast), Windows 11 rounded corners, a thin accent bar in the next meeting's calendar colour (legible rule from the colour-contrast function), height about 32 DIP, width follows the text up to 320 DIP.
- **Accessibility:** one UI Automation element named with the full text; a polite live-region announcement only at meaningful thresholds (30, 15, 5, 1 minute and "now"), never every minute; respects reduce motion (no animation); works under high contrast with system colours.
- **Not in the chip:** no meeting list, no actions beyond the menu, no sound.

### The jump list (C)

- Jump lists belong to the packaged app's taskbar button and Start entry (also shown when the person pins TimeTug), registered with `Windows.UI.StartScreen.JumpList`, independent of whether a window is open. Tasks (fixed set, localized): **Open today's meetings** (opens the flyout), **Join next meeting** (only when the engine says the next or current meeting has a join link within the join window; otherwise the item is omitted), **Test tug**, **Settings**. Items launch the app with an activation argument that `AppInstanceService` redirects to the running copy (or starts it): `--jump flyout|join-next|test-tug|settings`.
- **Privacy:** no meeting titles or links are stored in the jump list (Windows keeps jump lists on disk): item names are generic ("Join next meeting"). The list is rebuilt when the "has a join link" condition changes, never on every state update; a failure to update is logged and ignored.
- **Single-instance semantics:** a jump action while the first copy runs is delivered as an activation; while a tug shows it is ignored and logged (the tug wins), as with the second-launch rule from slice 2. In a fresh process it is held until the first engine state like any early activation.
- **Limit to state honestly:** Windows shows the jump list when the person right-clicks the TimeTug taskbar button (present while a normal window is open, or when pinned); the spike could not observe whether Start shows it, so do not promise Start. Stale items persist on disk, so save the base list at startup and on quit. The first-run welcome window's tray note will also mention pinning.

## Global Constraints

Everything in the slice 1 to 3 plans' Global Constraints holds: no scheduling, rules or defaults in C#; display arithmetic is allowed; injectable OS state; no secrets or calendar content in logs, commits or screenshots (the VM is signed into the owner's Google: scripted data only); SHA-pinned actions; DeepSeek reviews; Sonnet at high effort; squash-merge when windows-x64, windows-arm64 and architecture are green; probe dumps never committed; never use bare `git stash`.

## Review Focus

1. **Chip on a monitor that disappears or changes DPI, and on a full-screen game** — expected: moves to a valid monitor, hides over exclusive full-screen apps, never off-screen (Task 2).
2. **Chip and tug at the same time, chip and flyout open at once** — expected: the tug always wins and hides the chip; the flyout closes the chip's click handling cleanly; no focus theft anywhere (Task 2, 3).
3. **Jump list item invoked while the app is starting, while a tug shows, or with no join link** — expected: held until ready, ignored with a log entry, omitted from the list respectively (Task 4, 5).
4. **Clock step backwards or a time-zone change with the chip visible** — expected: the countdown follows the engine's refreshed state on the next tick; monotonic timing for any grace logic (Task 1, 2).
5. **Privacy** — expected: no title or link in the jump list, the chip text never written to logs (Task 5).

---

### Task 0: Spike: a no-focus tool window and the jump list API on this stack

**Files:** `docs/spikes/2026-10-chip-window-and-jumplist.md`, a throwaway SELFTEST-only scenario `spike-chip-window`.

- [ ] **Step 1:** On the VM with the packaged dev build, prove with a real HWND: a WinUI 3 window given `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW` after creation keeps those styles after it is first shown (read them back), receives pointer click, drag and right-click without being activated (`GetForegroundWindow` before and after a click is unchanged), stays topmost over a maximized window, shows rounded corners and a Mica or acrylic backdrop, and does not appear in the taskbar or Alt+Tab. Try a second approach if the first fails (setting styles in a window subclass or through `AppWindow`/`OverlappedPresenter` options) and record which worked.
- [ ] **Step 2:** Prove `Windows.UI.StartScreen.JumpList.LoadCurrentAsync` and `SaveAsync` work for the packaged app with no window open and with the app unpinned; record `JumpList.IsSupported()`, what Windows shows and where (pinned icon, Start entry, taskbar button while a window is open), and whether a user can remove task items.
- [ ] **Step 3:** Write the findings (including anything that forces a design change) into the spike document; if a design choice in this plan does not survive, amend the plan before Task 1. Commit the document only (no scenario code that reads real data).

---

### Task 1: Chip presentation model and settings

**Files:** `src/TimeTug.Presentation/Chip/{ChipViewModel.cs,ChipPlan.cs,ChipMode.cs}`, `src/TimeTug.Presentation/Settings/PresentationSettings.cs` (additive: `ChipMode`, `ChipLeadMinutes`, `ChipPosition` per monitor), `src/TimeTug.Presentation/Settings/AppearanceViewModel.cs` (new controls), `Strings/en-US/Resources.resw`, tests under `tests/TimeTug.Presentation.Tests/Chip/`.

**Interfaces:**
- Consumes: `AppState` agenda and next takeover, `FlyoutText` countdown rules, `TimeProvider`, `IMinuteTicker`, `IPresentationSettingsStore`, the colour-contrast function from the dark-calendar fix.
- Produces:

```csharp
public enum ChipMode { Off, BeforeMeetings, Always }
public sealed record ChipPlan(bool Visible, string Text, string AutomationName, string? AccentColorHex, bool CanJoin, string? Announcement);
public sealed class ChipViewModel
{
    public ChipViewModel(IEngineClient engine, IPresentationSettingsStore settings, TimeProvider time, IMinuteTicker ticker, IUiSettings ui);
    public ChipPlan Plan { get; }
    public event Action? Changed;
    public void HideUntilNextMeeting();
}
```

- [ ] **Step 1: Write the failing tests:** Off never shows; BeforeMeetings shows from N minutes before the next timed meeting through its end and not before or after (boundaries at N, N-1 s, end, end+1 s for 5, 15, 60); Always shows with a current or next meeting today, hidden with none; all-day events never drive the chip; text for upcoming, running ("now", "ends 10:50"), beyond an hour; accent colour from the meeting's calendar; `CanJoin` only with a link and within the flyout's join window; `HideUntilNextMeeting` hides until a different meeting becomes the next; announcements only at 30, 15, 5, 1 minute and now, once each per meeting; a clock step backwards or a zone change recomputes from the engine's state on the next tick and never repeats an announcement; settings changes raise `Changed` once.
- [ ] **Step 2:** Run (FAIL), implement the model, run (PASS); commit.
- [ ] **Step 3: Write the failing tests for the Appearance pane controls** (chip mode and lead-minutes choices persist and raise `Changed` once, defaults, the lead-minutes choice is disabled unless the mode is Before meetings, search catalog entries exist) before any XAML; run (FAIL), implement the controls, run (PASS).
- [ ] **Step 4: Commit** — `git commit -m "Chip: presentation model and settings"`.
- [ ] **Step 5: Privacy test:** capture the diagnostics sink while the chip view model runs through a scripted full day of states and assert that no meeting title, link or calendar name ever appears in a log line.

---

### Task 2: The chip window (three commits, reviewed as three diffs: 2a placement, 2b host and window shell, 2c styling, scenarios and accessibility)

**Files:** `src/TimeTug.Presentation/Chip/{ChipPlacement.cs,ChipHost.cs}`, `src/TimeTug.App/Chip/{ChipWindow.xaml(.cs),ChipHostWindows.cs}`, tests (`ChipPlacementTests`, `ChipHostTests`).

**Interfaces:** `IChipWindow` (Presentation, so the host is testable with a fake: `Show(PixelRect)`, `Hide()`, `Move(PixelRect)`, `SetContent(ChipPlan)`, `Announce(string)`, `Dispose()`, events `Clicked`, `MenuRequested`, `Dragged(PixelRect)`, `ResetRequested`), `IDisplayService` (monitor list and a `Changed` event covering monitor add/remove, DPI change and taskbar move; the slice 2 monitor service gains the event if it lacks one); `ChipHost` lives in Presentation and talks only to these interfaces; `ChipPlacement.Compute(saved? /* DIPs relative to the monitor's work-area origin */, monitors, taskbarAnchor, sizeInDips) → PixelRect` (pure, physical pixels; validates saved positions against current monitors, falls back to above the notification area, clamps into a work area, handles negative coordinates and DPI scale); `ChipHost` (shows or hides by `ChipPlan.Visible`, hides while a tug shows or full-screen is unavailable, never activates, closes cleanly on quit and on settings-off); `ChipWindow` (borderless, always on top, `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW`, not in the taskbar or Alt+Tab, rounded corners, backdrop per the Appearance choice and system modes, draggable by pointer, left click toggles the flyout, right-click menu with Join, Hide until next meeting, Settings, double-click resets position, accent bar, one automation element, live-region announcements from `ChipPlan.Announcement`).

- [ ] **Step 1: Write the failing tests:** placement for taskbar bottom, top, left and right, a second monitor with negative coordinates, a saved position on a monitor that no longer exists, 100%, 150% and 200% scaling, anchor unavailable; a saved position restored across a DPI change (dragged at 150%, restored at 100% and 200%) lands at the same place relative to its monitor; host behaviour with fakes (tug showing hides it, full-screen becoming unavailable while visible hides it within one poll, mode Off closes it, quit disposes, a state change updates text without reopening, a monitor removed, a DPI change or a taskbar move while visible re-places it on a valid monitor and never off-screen). The never-steals-focus assertion is NOT a fake-based test: it is made on the real HWND in the `chip-interaction` scenario (`GetForegroundWindow` unchanged and the extended styles read back after a click, a drag and a right-click).
- [ ] **Step 2:** Run (FAIL), implement, run (PASS). Self-test scenarios `chip-modes` (each mode with scripted meetings, screenshots from scripted data only, Light and Dark, high contrast), `chip-interaction` (click toggles the flyout, menu actions, drag and remembered position, tug hides it) registered in `scripts/ci/selftest-scenarios.txt`, CI steps and axe rounds. Verify on the VM and read the screenshots.
- [ ] **Step 3: Commit** — `git commit -m "The countdown chip window"`.

---

### Task 3: Compose the chip

**Files:** `src/TimeTug.App/{AppShell.cs,Tray/*}`, docs.

- [ ] **Step 1:** Composition: the chip host starts after the first state and the presentation store is loaded; the Appearance pane changes apply live; quit order closes the chip first; the tray menu gets no new row. Composition tests with fakes.
- [ ] **Step 2:** Run the whole self-test suite on both runners and the VM; fix regressions.
- [ ] **Step 3: Commit** — `git commit -m "Compose the countdown chip"`.

---

### Task 4: Jump list service

**Files:** `src/TimeTug.Platform/JumpList/{JumpListService.cs,IJumpListPlatform.cs}`, `src/TimeTug.Presentation/JumpList/{JumpListPlan.cs,JumpAction.cs}`, `src/TimeTug.Platform/Instance/*` (activation arguments), tests.

**Interfaces:** `JumpAction { Flyout, JoinNext, TestTug, Settings }` with the argument forms `--jump flyout|join-next|test-tug|settings`; `JumpListPlan.For(AppState)` (pure: the fixed tasks, `JoinNext` only when the engine's next or current meeting has a join link within the join window); `IJumpListPlatform` over `Windows.UI.StartScreen.JumpList` (`IsSupported`, `LoadCurrentAsync`, `Items`, `SaveAsync`; when not supported the service logs once and does nothing; the plan is rebuilt from scratch on every change so an item the person removed comes back only if it is part of the current plan: what Windows allows a person to remove is recorded by the Task 0 spike); `JumpListService` rebuilds only when the plan changes (never per state update), logs and ignores failures; `ActivationParser` maps launch and redirect arguments to `JumpAction`, ignoring unknown arguments.

- [ ] **Step 1: Write the failing tests:** unsupported platform logs once and does nothing; plan with and without a join link; rebuild only on plan change; a platform failure is logged and does not throw; no title or link ever appears in an item name, argument, description or log line (assert on every generated item and capture the diagnostics sink through a scripted full day of states); arguments parse for each action and unknown input is ignored; localized names come from resources.
- [ ] **Step 2:** Run (FAIL), implement, run (PASS).
- [ ] **Step 3: Commit** — `git commit -m "Jump list service"`.

---

### Task 5: Jump actions in the running app

**Files:** `src/TimeTug.Platform/Instance/AppInstanceService.cs`, `src/TimeTug.App/AppShell.cs`, `src/TimeTug.Presentation/JumpList/JumpActionHandler.cs`, tests, scenario `jump-list`.

**Interfaces:** the instance service carries an `ActivationKind` plus an optional `JumpAction` through redirect and early-activation holding; `JumpActionHandler` executes: Flyout opens the flyout, JoinNext joins the next meeting through the existing join path (launcher failure shows the copy-link state in the flyout), TestTug sends the engine's test tug, Settings opens Settings. A jump action while a tug shows is ignored and logged; a fresh process holds it until the first state; a stale JoinNext (no link any more) opens the flyout instead.

- [ ] **Step 1: Write the failing tests:** each action calls the right service once; held before ready and delivered once after; ignored while a tug shows with a log entry; stale JoinNext falls back to the flyout; rapid duplicates coalesce (monotonic timing).
- [ ] **Step 2:** Run (FAIL), implement, run (PASS). Scenario `jump-list` registers the real list through the packaged app, reads it back, asserts the items and no calendar content, exercises each action through the real activation path by raising a launch activation with the item's arguments through `AppInstance` redirection (and separately asserts the argv parser through the execution alias, which is a different path), and invokes one registered item through the shell where Windows allows it; verify on the VM, record in `docs/spikes/2026-10-jump-list.md` where Windows shows the list (taskbar button while a window is open, pinned icon, Start entry) and what could not be driven.
- [ ] **Step 3: Commit** — `git commit -m "Jump list actions"`.

---

### Task 6: Checklist, parity, DeepSeek review and close

- [ ] **Step 1:** Manual checklist items: chip in each mode over a real meeting, chip over a maximized window and a full-screen video, chip on a second monitor and after unplugging it, drag and remembered position after a restart, click and right-click menu, jump list from the pinned taskbar icon and Start, each jump action, Narrator announcements at the thresholds, high contrast; parity rows for both features (chip = differs on purpose from the Mac's menu-bar text, done, owner amendment 2026-10-22; jump list = Windows-only addition).
- [ ] **Step 2:** `deepseek-review` over the new sources with this plan; verify findings against the code; fix real ones in a follow-up PR with failing tests first.
- [ ] **Step 3:** In `timetug`: update the tracker and memory; merge on green.

---

## Self-review notes

- Covers the owner's two requests; the chip is the "pinned countdown chip" from the program design's "Text in the icon" row; the jump list is new. Neither depends on Store packaging.
- Soft spots for the implementer: how `Windows.UI.StartScreen.JumpList` behaves for a packaged WinUI app without a taskbar button (Task 5 records the probe); `WS_EX_NOACTIVATE` with WinUI 3 pointer events; Mica on a tool-style window.
