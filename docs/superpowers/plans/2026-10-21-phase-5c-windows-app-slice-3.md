# Phase 5, slice 3: Settings, launch at login, Appearance and duplicate management — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Implementers run on **Sonnet 5.5 with reasoning effort high**; escalate to Opus only for a task that failed two fix rounds. Reviews use the `deepseek-review` skill.

**Goal:** In `binary-companion/timetug-windows`, add the Settings window with every pane the Mac has that makes sense on Windows (General, Appearance, Accounts, Calendars, Tug Rules), launch at login, the hotkey recorder, the Windows Appearance preferences, settings search, diagnostics (Copy and Clear), and duplicate-merge management in the flyout, so the Windows app reaches feature parity with the Mac app apart from the items the parity table marks as differing on purpose or later.

**Architecture:** Presentation gains one view model per pane over `AppState` and an `ISettingsClient` for engine settings patches; Platform gains the startup-task service, the presentation-settings store (`ApplicationData.LocalSettings`) and the diagnostics reader; App gains `SettingsWindow` with a navigation view, the five pane pages and the merge controls on flyout cards. Behaviour settings (lead time, requirements, hidden and tug calendars, skip all-day, inference switch, Enable Tug) live in the engine; presentation settings (theme, tray icon style, flyout backdrop, hotkey, launch at login) live in the app.

**Tech Stack:** as slices 1 and 2 (.NET 10, WinUI 3, Windows App SDK as pinned, CommunityToolkit.Mvvm and `CommunityToolkit.WinUI` `SettingsCard`/`SettingsExpander`, CsWin32, xUnit + FluentAssertions, axe-windows).

**Spec:** `docs/superpowers/specs/2026-10-16-phase-5-windows-app-core-design.md` (Decisions rows "Slices", "Duplicate management", "Presentation settings", "Parity"). Program design `docs/superpowers/specs/2026-10-09-windows-program-design.md` sections 3 and 4. Slice 1 and 2 plans in `docs/superpowers/plans/`. Mac reference: `Apps/macOS/Sources/` (`SettingsView.swift`, `SettingsNavigation.swift`, `SettingsSearch.swift`, `GeneralPane.swift`, `AppearancePane.swift`, `AccountsPane.swift`, `CalendarsPane.swift`, `TugRulesPane.swift`, `AboutView.swift`, `MergeBadge.swift`, `EventCard` views, `AppDiagnostics.swift`).

## Global Constraints

- Everything in the slice 1 and 2 plans' Global Constraints still holds (no scheduling, rules or defaults in C#; display arithmetic against `TimeProvider` is allowed; injectable OS state; no secrets or calendar content in logs, commits or screenshots; SHA-pinned actions; Sonnet implementers at high effort; DeepSeek reviews; squash-merge when green; probe dumps and screenshots from the VM must never contain real calendar text).
- **Mac is the behavioural reference** for what each pane offers, its order and its text; Windows presentation (NavigationView, SettingsCard, Mica) is native. Differences on purpose are recorded in `docs/parity.md`.
- **Engine owns behaviour.** Tug Rules, Calendars and the inference switch edit the engine's settings through `settings.apply` patches (the engine persists them); the app never keeps its own copy of those values.
- **Differences on purpose** (record in `docs/parity.md`): no Apple Calendar row (EventKit is Mac-only); no Sparkle updates (Store updates; dev builds show the version and a note); "Open System Settings" links become `ms-settings:` links where an equivalent exists; the Mac's menu-bar text modes map to Windows tray icon styles (icon only, icon with minute digit in the last ten minutes; no title text in the tray); WAM accounts are phase 6.
- On-device duplicate inference: the engine reports its inference status. On Windows 1.0 no text generator is registered, so the switch shows the engine's status text ("not available on this PC") and is disabled and off while the engine says unavailable; nothing is persisted from a disabled switch, and the engine's stored value is left untouched until phase 8 makes it available.
- Launch at login: Windows cannot enable a startup task silently; the app asks on the welcome window's step 2 and offers a Settings toggle; a user or policy disabling it in Windows Settings is shown as such with a link to `ms-settings:startupapps`.
- The Settings window is single-instance within the app: opening it again focuses the existing one. A tug showing does not close it, but the tug is always on top.
- The Cross-distribution collision notice stays "not yet" (phase 9); the Mac's `CollisionNotice` has no Windows counterpart in this slice.

## Review Focus

1. **Settings applied while the engine is busy or a settings patch races a state update** — expected: the control shows the engine's last published value, a failed or rejected patch reverts the control with a message, never a silent mismatch (Task 1, 3, 4).
2. **Lead time, requirements and calendar toggles changed while a tug is outstanding or about to fire** — expected: the engine alone decides; the UI never recomputes what fires; the Test tug button works with Enable Tug off (Task 3).
3. **Launch at login disabled by the user or by policy** — expected: the toggle reflects the real state, explains the cause with a working link, never claims enabled when it is not (Task 6).
4. **Removing an account or forgetting learned corrections** — expected: a confirmation naming what is lost, then the engine's state drives the list; removing the last account shows the welcome state; no orphaned credentials (Task 5 for accounts, Task 4 for learned corrections).
5. **Merge, unmerge and separate on a stale card** — expected: the controls act on event ids resolved by the engine; an id that vanished shows a short message and refreshes, never throws (Task 8).

---

### Task 1: Settings plumbing: engine settings in `AppState`, patches and presentation settings

**Files:** `src/TimeTug.Presentation/Engine/{EngineStateModel.cs,EngineClient.cs,IEngineClient.cs}`, `src/TimeTug.Presentation/Settings/{ISettingsClient.cs,SettingsClient.cs,PresentationSettings.cs,IPresentationSettingsStore.cs}`, `src/TimeTug.Platform/Settings/LocalSettingsPresentationStore.cs`, tests in `tests/TimeTug.Presentation.Tests/Settings/` and `tests/TimeTug.Platform.Tests/Settings/`.

**Interfaces:**
- Consumes: the engine package's settings and state records (`Messages.cs`, `docs/engine-protocol.md`), `IEngineClient.SetEnabledAsync` from slice 1 (the `settings.apply` patch path).
- Produces (additive):

```csharp
public sealed record EngineSettingsView(
    bool Enabled, TimeSpan LeadTime, bool RequireConferenceLink, bool RequireOtherAttendees,
    bool SkipAllDayEvents, bool InferenceEnabled, IReadOnlySet<string> HiddenCalendarKeys,
    IReadOnlySet<string> TugCalendarKeys /* whatever the engine's takeover settings call the allow-list */);
public enum CalendarOrigin { Account, System, Other }
public sealed record CalendarGroup(string AccountName, string SourceId, string KindId, CalendarOrigin Origin, string? Subtitle, bool ShowsGroupName, IReadOnlyList<CalendarEntry> Calendars);
public sealed record CalendarEntry(string Key, string Title, string? ColorHex, bool IsShown, bool Tugs, string? Kind, bool IsSubscribed, bool IsSystem);
// the sectioning rules (origin, subtitles, which groups show their names) are ported from the Mac's `CalendarSections.make(...)` and live in one place with tests
public enum InferenceAvailability { Disabled, NoEngine, Unavailable, NotOnDevice, Active }
// AppState gains: EngineSettingsView Settings, IReadOnlyList<CalendarGroup> CalendarGroups, InferenceAvailability Inference, string? InferenceReason

public interface ISettingsClient
{
    ValueTask<SettingsResult> ApplyAsync(Func<EngineSettingsPatch, EngineSettingsPatch> edit);   // one atomic settings.apply patch
    ValueTask ForgetLearnedCorrectionsAsync();                                                    // dedup.forget
}
public sealed record PresentationSettings(AppTheme Theme, TrayIconStyle TrayStyle, FlyoutBackdrop Backdrop, WindowGeometry? SettingsWindow);
public sealed record WindowGeometry(int X, int Y, int Width, int Height);   // physical pixels; validated against the current monitors on restore (off-screen geometry is discarded)
// IPresentationSettingsStore: Load(), Save(), event Changed — presentation-only values. The hotkey has its own store (slice 2). Launch at login has NO app-side store: Windows is the source of truth (`StartupTask.GetAsync(...).State`), read every time.
```

Read the engine's real takeover-settings field names and the calendar allow/deny semantics (`hiddenCalendarKeys` and the tug allow-list; Mac `TakeoverSettings`, `TakeoverPolicy`) before naming anything; mirror them, and put the mapping in one place. `SettingsResult` is `Applied` or `Rejected(reason)`; a rejection or timeout leaves the view model on the engine's last state.

- [ ] **Step 1: Write the failing tests:** each engine setting maps from a package state (use the golden fixtures); an unknown extra field is ignored; `ApplyAsync` sends exactly one `settings.apply` with only the edited fields; two rapid edits do not lose the first; a rejected patch returns `Rejected` and sends nothing else; the presentation store round-trips every field with defaults on a fresh install and on a corrupt value; `Changed` fires once per save.
- [ ] **Step 2:** Run (FAIL), implement, run (PASS).
- [ ] **Step 3: Commit** — `git commit -m "Settings plumbing: engine settings view, patches and presentation store"`.

---

### Task 2: The Settings window shell, navigation and search

**Files:** `src/TimeTug.Presentation/Settings/{SettingsShellViewModel.cs,SettingsPane.cs,SettingsSearch.cs,SettingsText.cs}`, `src/TimeTug.App/Settings/{SettingsWindow.xaml(.cs),SettingsHost.cs}`, resources, `tests/TimeTug.Presentation.Tests/Settings/SettingsShellTests.cs`.

**Interfaces:** `SettingsPane { General, Appearance, Accounts, Calendars, TugRules }` (Mac order and titles) and `GeneralDestination { About, SoftwareUpdate }` with a drill-down path and a back button as on the Mac (`generalPath`), so About and the update card are reachable and `Open(pane, highlightId, destination?)` can select them; `SettingsShellViewModel` (selected pane, search text, results, `Open(SettingsPane?, string? highlightId)`); `SettingsSearch.Catalog` ported from the Mac's `SettingsSearch.swift` (every control's id, title, keywords, pane; plus one entry per calendar, using a prefix as on the Mac) **without** the Mac's three Software Update entries (Sparkle has no Windows counterpart; recorded in `docs/parity.md`) and with Windows-only entries added where Windows differs; the matching rule is the Mac's exactly: case- and diacritic-insensitive (folded) substring match, results are title matches first and then keyword matches, catalog order within each group, no results for an empty query; `SettingsHost.Show(pane?, highlight?)` single-instance.

Behaviour: a normal window with Mica, a `NavigationView` (left, five panes with icons), an "AutoSuggestBox" search that jumps to the pane and highlights the control for about 1.5 s (respecting reduce motion), remembered size and position (presentation setting), Esc does not close it, closes with the window button; the tray's "Settings…" row and the flyout's gear button (both disabled placeholders until now) open it; an open request from the hotkey recorder or the welcome window opens the right pane. All text from `Resources.resw`, every control has an automation name.

- [ ] **Step 1: Write the failing tests:** pane order and titles equal the Mac's; search finds a control by title and by keyword, folds case and diacritics ("cafe" finds a calendar "Café Sync"), returns title matches before keyword matches in catalog order, includes calendar entries from `AppState`, returns nothing for an empty query, never offers a Software Update entry; `Open(pane, id)` selects the pane and sets the highlight once; a second `SettingsHost.Show` focuses instead of opening another window (fake window factory); tray and flyout gear call `Show`.
- [ ] **Step 2:** Run (FAIL), implement the shell with empty pane pages, run (PASS).
- [ ] **Step 3:** Self-test scenario `settings-shell` (opens each pane, screenshots, axe scan); register in `scripts/ci/selftest-scenarios.txt` and CI.
- [ ] **Step 4: Commit** — `git commit -m "Settings window shell, navigation and search"`.

---

### Task 3: Tug Rules pane

**Files:** `src/TimeTug.Presentation/Settings/TugRulesViewModel.cs`, `src/TimeTug.App/Settings/TugRulesPage.xaml(.cs)`, `tests/TimeTug.Presentation.Tests/Settings/TugRulesViewModelTests.cs`.

**Interfaces:** consumes `ISettingsClient`, `IEngineClient.TestTugAsync`. Sections as on the Mac: Timing (lead time picker with the Mac's choices; read them from `TugRulesPane.swift` and the engine's allowed range), Requirements (require a video link, require other attendees), Test (Test tug button, shows the engine's sample tug), and the "Enable Tug" switch at the top, plus the rest of the Mac pane: the hero block (bolt icon, "Tug" headline, subtitle "Pulls your attention to meetings before they start." when on and the Mac's "off" text adapted for Windows when off, without the Mac-only widget wording), the caption under the lead-time picker ("How long before a meeting starts TimeTug tugs you."), and the two conditional warnings when a requirement is on ("Meetings without a link won't tug you." / "Meetings without other attendees won't tug you." as on the Mac), each with its own search id. The lead-time choices and their text come from one list in Presentation; the value sent is seconds.

- [ ] **Step 1: Write the failing tests:** each control reflects `AppState.Settings`; changing it sends one patch with only that field; Test tug sends the engine's test command with a sample title and works when Enable Tug is off; a rejected patch reverts the control and exposes a message; the lead-time list equals the Mac's; each warning appears exactly when its requirement is on; the hero text follows Enable Tug. Also add to `tests/TimeTug.Presentation.Tests/Flyout/FlyoutViewModelTests.cs` (this task owns the test; the footer itself is slice 2's `PopupText.tugFooter` port): the flyout footer ("Tugs you N min before") updates when `AppState.Settings.LeadTime` changes.
- [ ] **Step 2:** Run (FAIL), implement, run (PASS); self-test scenario `settings-tugrules` (screenshots, change a value through the real `EngineClient` with the testing engine and assert the state echoes it).
- [ ] **Step 3: Commit** — `git commit -m "Tug Rules pane"`.

---

### Task 4: Calendars pane

**Files:** `src/TimeTug.Presentation/Settings/CalendarsViewModel.cs`, `src/TimeTug.App/Settings/CalendarsPage.xaml(.cs)`, tests.

**Interfaces:** consumes `AppState.CalendarGroups`, `ISettingsClient`. As on the Mac: per account group, an "All" tug toggle, per calendar a "show in list" toggle and a "Tug" toggle, collapsible groups, the Mac's subscribed/system calendars section where it applies, Options (skip all-day events; find duplicates with on-device intelligence, showing the engine's status text and disabled when unavailable), and a "Forget learned corrections" button with confirmation. The rest of the Mac pane is ported too: the intro line ("Choose which calendars are allowed to tug you away from your work."), the "Tug calendars" column header, section subtitles and provider icons from the sectioning model, the empty state ("No calendars found..." wording adapted to Windows: no system-settings text, "add an account in Accounts" with a link that opens the Accounts pane), a hidden calendar's Tug switch is disabled and dimmed, and the system/subscribed disclosure with its count and badge text.

- [ ] **Step 1: Write the failing tests:** groups and entries map from state; "All" sets or clears every calendar's tug key of that group in one patch; toggling a calendar's visibility updates `HiddenCalendarKeys` only; hidden calendars never tug (display only: the engine decides; assert the patch content, not behaviour); skip all-day and inference toggles patch one field; inference unavailable disables the switch and shows the status text; forget-corrections asks for confirmation (view model exposes `ConfirmForget` then `ForgetLearnedCorrectionsAsync`); a calendar that disappears from state disappears from the list; with no calendars at all the empty state shows; a calendar hidden from the list has its Tug switch disabled; section order, subtitles and icons equal the Mac's for an account, a subscribed feed and an Other source.
- [ ] **Step 2:** Run (FAIL), implement, run (PASS); scenario `settings-calendars`.
- [ ] **Step 3: Commit** — `git commit -m "Calendars pane"`.

---

### Task 5: Accounts pane and diagnostics

**Files:** `src/TimeTug.Presentation/Settings/{AccountsViewModel.cs (extend slice 1's),DiagnosticsViewModel.cs}`, `src/TimeTug.Platform/Diagnostics/DiagnosticsReader.cs`, `src/TimeTug.App/Settings/AccountsPage.xaml(.cs)`, tests.

**Interfaces:** reuses slice 1's account flows (`AddAccountAsync`, credential form dialog, browser sign-in, `ReconnectAccountAsync`, `RemoveAccountAsync`, `CancelAuthorizationAsync`). Sections as on the Mac: Connected Accounts (name, kind icon, status text from the engine's status with "Sign in again" and "Remove account" in a menu; Remove asks for confirmation: "Its calendars will no longer appear and their Tug and visibility choices are forgotten."), Add an Account (available kinds from the engine, unconfigured ones disabled with the reason), the Mac's intro ("Choose where TimeTug reads your calendars from.") and empty row ("No internet accounts yet. Add one below."), the build-failure status ("Can't start this account") with "Sign in again" shown only when the status is auth-expired or a build failure exists (not for a healthy account), a notice when kinds are unavailable in this build, (the Mac's "Soon" placeholder tiles for future providers are omitted on Windows and recorded as such in `docs/parity.md`), a waiting state with Cancel during sign-in, and Diagnostics (Copy diagnostics and Clear over the rolling log, with the Mac's text "A short log of recent calendar activity to share when reporting a problem. It contains no feed links or event titles."). `DiagnosticsReader` reads the rolling log files, redacts nothing it should not contain (assert no URLs with query strings and no event titles), and copies as text through the clipboard service interface.

- [ ] **Step 1: Write the failing tests:** account rows and status texts for each status; remove confirmation flow and the engine call; removing the last account yields the "no accounts" state; add-account buttons disabled when unconfigured with the reason; sign-in failure message beside the provider; Cancel sends `account.cancel`; diagnostics copy returns the last N lines and never a line containing `?` followed by `code=`, `token`, or an event title (feed it a log with such content and assert it was never written by the app's own logger, and that the reader drops it as a safety net); Clear empties the log.
- [ ] **Step 2:** Run (FAIL), implement, run (PASS); scenario `settings-accounts` (scripted accounts with each status).
- [ ] **Step 3: Commit** — `git commit -m "Accounts pane and diagnostics"`.

---

### Task 6: General pane: launch at login, hotkey recorder, About (implemented as three commits, reviewed as three diffs: 6a launch at login and the welcome checkbox, 6b hotkey recorder, 6c About and the update card)

**Files:** `src/TimeTug.Presentation/Settings/{GeneralViewModel.cs,LaunchAtLoginViewModel.cs,HotkeyRecorderViewModel.cs}`, `src/TimeTug.Platform/Startup/StartupTaskService.cs`, `src/TimeTug.App/Settings/{GeneralPage.xaml(.cs),HotkeyRecorder.xaml(.cs),AboutPage.xaml(.cs)}`, the welcome window's step 2, `Package.appxmanifest` (startup task extension), tests.

**Interfaces:**
- `IStartupTaskService`: `GetStateAsync() → StartupState { Enabled, Disabled, DisabledByUser, DisabledByPolicy, EnabledByPolicy }`, `RequestEnableAsync()`, `DisableAsync()` over `Windows.ApplicationModel.StartupTask` (task id declared in the manifest). `LaunchAtLoginViewModel` shows the real state, explains `DisabledByUser`/`DisabledByPolicy` with a link to `ms-settings:startupapps`, and never reports enabled when the OS says otherwise.
- The welcome window's step 2 gains the "Start TimeTug when I sign in" checkbox (off until the person ticks it; a tick calls `RequestEnableAsync`).
- `HotkeyRecorderViewModel` over `HotkeyService` (slice 2): records a chord from key events (requires a modifier; Esc cancels; Backspace or a clear button clears), suspends the current registration while the recorder has focus (`HotkeyService.SuspendForRecording()`/`Resume()`, so pressing the chord already registered reaches the recorder instead of firing `WM_HOTKEY`) and restores it on cancel or after a commit, shows the result (`Registered`, `Conflict` with the persisted `HotkeyState` after a restart, `Invalid`), text "Press a shortcut to show or hide the popup from anywhere. Click ✕ to clear it." from the Mac.
- General also has: "Show today's meetings" label for the shortcut row (Mac text), the About page (app icon, name, version from the package identity, copyright, a link to the website and licences; the Mac's "Other copy installed" section is phase 9), and a Software Update card that says updates come from the Microsoft Store (hidden in dev builds, which show the build's commit).

- [ ] **Step 1: Write the failing tests:** every `StartupState` maps to the correct toggle state and text; enabling when the OS refuses leaves the toggle off and explains; while recording the current registration is suspended and always restored (also on cancel and on failure); recorder accepts Ctrl+Alt+T (including when it is the chord already registered), rejects a bare key, ignores modifier-only presses until a key arrives, cancels on Esc, shows the conflict message for a `Conflict` result and still shows it after the store is reloaded; clearing unregisters; the welcome checkbox starts unchecked and a tick requests enabling; About shows the package version.
- [ ] **Step 2:** Run (FAIL), implement, run (PASS); scenarios `settings-general` and update `hotkey`; on the VM check the real startup task: read it through the app's own `StartupTask` call in the `settings-general` scenario (it writes the state to `result.json`) and cross-check in Task Manager's Startup tab or the package's startup-task registry key; do not reboot the VM.
- [ ] **Step 3: Commit** — `git commit -m "General pane: launch at login, hotkey recorder, About"`.

---

### Task 7: Appearance pane and applying presentation settings

**Files:** `src/TimeTug.Presentation/Settings/AppearanceViewModel.cs`, `src/TimeTug.App/Settings/AppearancePage.xaml(.cs)`, `src/TimeTug.App/Theming/ThemeService.cs`, changes in the tray controller and flyout, tests.

**Interfaces:** presentation preferences (not engine settings): **Theme** (Use system, Light, Dark; applies to the Settings window, the flyout and the welcome window; the tug stays navy), **Tray icon style** (icon only, or icon with minute digit in the last ten minutes: maps the Mac's menu-bar text modes), **Flyout backdrop** (Mica/Acrylic, Solid), each with a live preview card like the Mac's popup-card preview; the reduced-transparency and high-contrast system modes override the backdrop choice and the pane says so. `ThemeService` applies the theme to open windows immediately and on start, by setting `RequestedTheme` on each window's root element and re-setting the `SystemBackdrop` theme and the `AppWindow` title-bar caption and button colours explicitly, because WinUI does not retheme a loaded element's backdrop or caption through `RequestedTheme` alone (verify on the VM with the Settings window open while switching, and record what had to be recreated); the tray controller and `FlyoutHost` read `IPresentationSettingsStore.Changed`.

- [ ] **Step 1: Write the failing tests:** defaults; each choice persists and raises `Changed` once; the tray plan omits the digit when the style is icon only (digit rendering and the per-minute tick already exist from slice 2: `TrayIconRenderer` and the minute ticker; this task only feeds the style into `TrayIconPlan` and re-plans on `Changed`); the flyout backdrop resolves to solid under reduced transparency or contrast regardless of the choice; theme resolution (system follows `IUiSettings`); corrupt stored values fall back to defaults.
- [ ] **Step 2:** Run (FAIL), implement, run (PASS); scenario `settings-appearance` (each theme and backdrop; screenshots of the flyout under Light and Dark).
- [ ] **Step 3: Commit** — `git commit -m "Appearance pane and presentation settings"`.

---

### Task 8: Duplicate management in the flyout

**Files:** `src/TimeTug.Presentation/Engine/EngineStateModel.cs` (merge info), `src/TimeTug.Presentation/Flyout/{MergeInfo.cs,FlyoutRow.cs (extend),FlyoutViewModel.cs (extend)}`, `src/TimeTug.App/Flyout/{EventCard.xaml(.cs) (extend),MergeBadge.xaml(.cs),MergeFlyout.xaml(.cs)}`, tests.

**Interfaces:** `AppState` gains, additively, each agenda item's merge data (members with ids, calendar names and times, provenance: rule, inference with engine name, or confirmed by the user) and the engine's pending candidate pairs per event; the flyout view model exposes `UnmergeAsync(eventId)`, `SeparateAsync(eventId, memberIds)` and `MergeAsync(eventId, otherEventId)` calling `dedup.unmerge`, `dedup.separate` and `dedup.merge` (ids only; the wire contract resolves them); `FlyoutRow` carries `MergeInfo?` and `Candidates`. UI as on the Mac (`MergeBadge.swift`, `EventCard` merge menu): a badge on merged cards showing the provenance and the member calendars, a menu with "Not the same meeting" (opens a submenu listing the card's member meetings by calendar name and time; picking one separates that member), "Unmerge" and, on cards with candidates, "Merge with…" listing them; a confirm-free action with an undo-free refresh (the engine republishes).

- [ ] **Step 1: Write the failing tests:** badge text per provenance; members and candidates map from a package state fixture with a merged event and a pending pair; each action sends the right command with ids only; an action on an event id that vanished (state changed) shows a short message and refreshes, never throws; the engine's rejection diagnostic is surfaced as the same message.
- [ ] **Step 2:** Run (FAIL), implement, run (PASS); scenario `flyout-merge` (a merged item, a candidate pair, each action through the testing engine; screenshots; axe scan of the menu).
- [ ] **Step 3: Commit** — `git commit -m "Duplicate management in the flyout"`.

---

### Task 9: Wiring, checklist, parity, DeepSeek review and close slice 3

**Files:** `src/TimeTug.App/{AppShell.cs,Tray/*,Flyout/*}`, `docs/manual-tests/windows-checklist.md`, `docs/parity.md`, `docs/development.md`.

- [ ] **Step 1:** Compose: tray "Settings…" and the flyout gear open `SettingsHost`; the welcome window's "Add another" and the flyout's problem rows deep-link to the Accounts pane; Quit closes the Settings window first; the presentation store feeds the tray, flyout and theme at start; startup order unchanged otherwise. Composition tests with fakes (each entry point opens Settings on the right pane once).
- [ ] **Step 2:** Run the whole self-test suite on both runners and the VM; fix regressions; read every new screenshot (scripted data only, no real calendar text); real end-to-end check on the VM with the packaged app: open Settings from the real tray icon message, change lead time and see the flyout footer change, record a hotkey, toggle launch at login and read the real startup task state, switch theme; say honestly what could not be driven.
- [ ] **Step 3:** Checklist: add human checks for each pane (real account removal and re-add, real Google calendar visibility toggles, launch at login after a real sign-out and sign-in, a hotkey that another program holds, theme switch with the app running, merge actions on a real duplicate meeting, Narrator through Settings, high contrast through Settings). Parity: mark every Mac pane and control done, differs on purpose, or later (WAM = phase 6, widgets = 7, AI = 8, Store updates and cross-distribution notice = 9).
- [ ] **Step 4:** Run the `deepseek-review` skill over the new sources with this plan; verify findings against the code; fix real ones in a follow-up PR with failing tests first.
- [ ] **Step 5:** In `timetug`: update the tracker (slice 3 built and merged; owner checks with direct links) and memory; plan slice 4 (Store packaging) next.
- [ ] **Step 6: Commit** and merge on green.

---

## Self-review notes

- Parity coverage against the Mac panes: General (About, update note, launch at login, shortcut), Appearance (menu-bar text mapped to tray style, popup cards mapped to flyout backdrop, light/dark/auto), Accounts (connected accounts, add, remove, reauthorize, diagnostics; Apple Calendar not applicable), Calendars (tug and visibility per calendar, skip all-day, inference, forget corrections), Tug Rules (lead time, requirements, test, enable), settings search, merge management. Collision notice and Sparkle are deliberate differences.
- Known soft spots for the implementer: the engine's exact calendar allow/deny setting names (Task 1 reads the package and the Mac `TakeoverSettings`); `StartupTask` behaviour in an unpackaged test run and on the VM (Task 6); how `NavigationView` panes host `SettingsCard`/`SettingsExpander` under the pinned Windows App SDK 2.x with `CommunityToolkit.WinUI` 8.2 (slice 1 flagged this as untested: check on first use and record the finding).
