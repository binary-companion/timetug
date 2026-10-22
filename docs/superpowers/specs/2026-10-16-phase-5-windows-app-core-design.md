# Phase 5: the Windows app core

Status: draft for the owner's review (2026-10-16). Parent: [program design](2026-10-09-windows-program-design.md), roadmap row 5 and sections 3, 4 and 6 to 8. The program design wins where the two disagree, except for the amendments in "Decisions". Predecessors: [phase 4](2026-10-15-phase-4-engine-c-interface-design.md) (the `TimeTug.Engine` package this app consumes).

## Purpose

Build the first Windows TimeTug: a native Windows 11 app that runs the same shared engine as the Mac app, so that "what and when" is identical on both platforms, and looks and behaves like a real Windows application.

**Principle (owner):** at its core TimeTug does the same thing on every platform, and each platform must seem like a real native application. The engine decides what and when; the Windows app decides how it looks and where it lives. Settings and defaults that affect behaviour (lead time 60 seconds, snooze choices 1, 5 and 10 minutes, rules, merging, hidden calendars) come from the engine and therefore match the Mac by construction.

**Goal (owner):** feature parity with the Mac app before a real release, wherever it makes sense on Windows. Appearance is expected to differ the most.

**Anti-goal (owner):** a meeting starts and the person never saw the tug, or saw it and could not click Join. The tug must appear on time and Join must work by mouse alone. Where Windows forbids showing it (lock screen, secure prompts, exclusive full-screen apps), the app does the best it can, as the Mac does.

## What the owner will see first

The owner launches builds only when a human is needed (real-account sign-in, how it feels). Everything else is verified by CI and by commands and screenshots on the Windows 11 ARM VM (Parallels), which the agent may resume and drive.

1. **First run with no accounts: a welcome window** (decided with mockups). A normal centered window with a taskbar button, not attached to the tray, so a hidden tray icon cannot make it undiscoverable. Step 1 offers Google, Microsoft, iCloud and Other (CalDAV). Google and Microsoft sign in through the default browser and a loopback redirect; iCloud and CalDAV ask for their details in the window. Step 2, after the first account connects: what was found ("Google, 3 calendars, next: Design review at 2:30 PM"), Add another, Test tug, a one-time note that TimeTug lives in the system tray and how to pin its icon, and Done. If accounts already exist from an earlier install of the same package identity, the window never appears. A clean uninstall removes MSIX data, so that case starts empty; that is expected.
2. **The tug screen**, the first thing the app is judged on. It mirrors the Mac overlay: hero picture, large live countdown, meeting title, a details line, then Join (primary), Snooze (1, 5, 10 minutes) and Dismiss; Return, Esc and 1, 5, 0 keys once focused. Other monitors show a mirror (countdown and title, "Dismiss on your main display"). Backdrop: navy desktop acrylic, solid navy when transparency effects are off.
3. **Fallbacks, best effort:** when Windows will not hand over the keyboard, "Click anywhere to respond" (a click always works on a topmost window); when the screen cannot be shown at all (exclusive full-screen game or presentation mode), a toast with Join, Snooze and Dismiss; when a tug could not be shown (locked session, covered by a full-screen app) and the meeting is still in progress when the person returns (unlock, sign-in, leaving full-screen), the full tug screen appears with the countdown showing how late it is. After the meeting has ended nothing appears and diagnostics records "missed, meeting over". If opening the Join link fails, the app shows the link to copy instead of failing silently. The app reports `takeover.presented` with `onScreen: false` only when Windows accepted the toast. If notifications are off or Do Not Disturb holds it, the app says so in diagnostics, changes the tray icon to its attention state, and keeps the request outstanding so the full tug appears on return like any other held tug.
4. **Accessibility, as the program design requires:** Narrator announces the tug through UI Automation notification events; reduce motion (`UISettings.AnimationsEnabled`) and the transparency-effects setting are honoured; Windows contrast themes replace the navy palette; every control has an automation name and a keyboard path.

## Not in this phase

- Windows account sign-in through WAM and "On this PC" accounts (phase 6); widgets (7); on-device AI (8); Store submission, listing and winget (9). The `AGENTS.md` and package seams leave room for each.
- No change to engine behaviour or the contract. Any need found here goes back to `timetug-shared` as a backward-compatible addition (the new compatibility rule applies).
- No Mac change.

## Decisions

Owner decisions are marked (O); my calls (C) are open to change.

| Topic | Decision |
|---|---|
| Platform | (O) Windows 11 22H2 (build 22621) or later, x64 and ARM64. (O) Test machine: the Parallels Windows 11 VM; CI on GitHub's `windows-latest` and `windows-11-arm` runners. |
| Stack | Program design section 3: .NET 10, C#, WinUI 3 on the Windows App SDK, MSIX; `CommunityToolkit.Mvvm`, `CommunityToolkit.WinUI`, `Microsoft.Extensions.Hosting`, `H.NotifyIcon.WinUI`, CsWin32, xUnit with FluentAssertions. The app consumes `TimeTug.Engine` from nuget.org at an exact pinned version in `Directory.Packages.props`. |
| Repository | (C) New public repository `binary-companion/timetug-windows` with the layout of program design section 3 (`src/TimeTug.App`, `src/TimeTug.Platform`, `tests`, `packaging`, `scripts`), code index, `AGENTS.md` with the rules of section 3, MIT plus Commons Clause like the sibling repositories. The agent creates it and its CI; the owner applies the organization rulesets, environments and required checks (owner-only). |
| Slices | (C) Slice 1: repository and CI; a development MSIX from the start (Credential Locker, `LocalState`, `ApplicationData` and later the startup task all need package identity, and the program design's development builds are MSIX anyway); host services (Credential Locker, `HttpClient`, browser sign-in, credential form); welcome window and accounts; tug screen with fallbacks and late-return behaviour; minimal tray (Next, Enable Tug, Test tug, Quit); self-test. Slice 2: flyout with the day's agenda, tray states and live tooltip, single instance, global hotkey. Slice 3: Settings window and its panes in order of ease: General (with launch at login: a Settings toggle plus the ask in the welcome window's step 2), Calendars, Tug rules, About, Appearance, then the diagnostics pane, Copy diagnostics and duplicate management. Slice 4: Store packaging manifests, identity placeholders and the release-build variants (Store submission is phase 9). Each slice is runnable and merged on green. |
| Parity | (C) `docs/parity.md` in the new repository lists every Mac capability with status (done, differs on purpose, not applicable, not yet) and is the release gate for phase 9. |
| Testing without a person | (C) A self-test mode (`--selftest <scenario>`) in development and CI builds only (a compile-time define absent from release and Store builds). It runs the engine with its test configuration and manual clock against a scripted calendar and host, with faked OS state (a monitor list of two or more, lock and unlock, notification state), exercises the tug on every faked monitor, Join, Snooze, Dismiss, the click-anywhere hint, the toast fallback and the late return, and writes screenshots and a JSON result. CI runs it on both architectures; the agent runs it on the VM and reads the screenshots. |
| Engine host | (C) `TimeTug.Platform` implements the package's host interfaces: credentials in Credential Locker, HTTP through `HttpClient` (system proxy and certificate store), browser sign-in with an `HttpListener` loopback, the credential form from the engine's field descriptions (labels from the connector library, localizable by field key), diagnostics to a rolling log file plus ETW. The engine's system events (wake, clockChanged, timeZoneChanged, dayChanged, networkReturned, displayChanged) come from Win32 and WinRT notifications. Session lock and unlock are app-local state for the held-tug rule and are not sent to the engine (the contract has no kind for them, and none is needed). |
| Data | The package's `LocalState` folder holds the engine's files. The Store and a future website build have different identities and separate data (program design section 6). |
| OAuth client ids | (C) Windows uses the same Google Desktop and Microsoft app registrations as the Mac (loopback redirect). Development builds on the VM read the ids from a git-ignored local configuration file that the agent copies file to file without printing, as the Mac's local build does. Pull-request CI embeds none, so Google and Microsoft sign-in is a manual owner check in slice 1 and unconfigured kinds show as unavailable in CI builds, exactly as on the Mac. Injecting ids into merge and release builds (an environment secret) belongs to phase 9, as it did for the Mac beta. |
| Late return | (C) The engine's host contract is that every `takeoverDue` receives exactly one terminal command (`takeoverClosed`, `join`, `snooze` or `dismiss`). The app holds a request it could not show. On return it checks two things (a presentation check, not scheduling): the event is still in the latest engine `state` (a meeting deleted or moved while the screen was locked is gone from it; the engine's `takeoverWithdrawn` covers only meetings not yet emitted), and the injected `TimeProvider` says the meeting has not ended. Both true: it shows the full tug and reports `takeover.presented`. Otherwise it sends `takeover.closed` and logs "missed, meeting over" or "meeting no longer on the calendar". The engine's fire guard treats the request as outstanding until a terminal command arrives, so no second tug can start meanwhile, and the app owes that one terminal command on every path, including a withdrawal. The app's `TimeProvider` is the system clock in production and, in the self-test, a manual provider that the self-test advances together with the engine's manual clock (`test.advanceClock`), so both agree. No engine change is needed; if building it shows otherwise, the fix is an additive engine change. |
| Tug content | (C) The details line copies the Mac's: time range, calendar title and attendee count ("N people"), all carried by `takeoverDue` (the event with start, end, attendees, and `calendarTitle`). Join appears only when the request has a join link. |
| Artwork | (C) The brand artwork is all rights reserved (`artwork/LICENSE.md` in `timetug`). `timetug-windows` carries the same carve-out in its own `artwork/LICENSE.md`, keeps the source artwork there, and generates the Windows icon sizes from it. The owner, as Binary Companion LLC, may use it in the Windows app; forks may not. |
| Duplicate management | (C) In scope, in slice 3, with the same controls and places as the Mac (merge, unmerge, split off, forget corrections, and the pending-pair notices), driven by the engine's dedup commands and state. `docs/parity.md` tracks it. |
| Presentation settings | (C) Windows-only presentation preferences (tray icon style, appearance and theme options, flyout style) live in an app-side `ApplicationData.LocalSettings` store, not in the engine's `settings.json`, per the phase 3 rule that presentation stays in the front end. The Mac's menu-bar title and countdown modes map to: icon only, or icon with digits for the final ten minutes, plus the live tooltip. The pinned countdown chip was deferred here and is now in scope: the owner asked for it on 2026-10-22 (optional, off by default; plan `docs/superpowers/plans/2026-10-22-phase-5d-countdown-chip-and-jump-list.md`), together with a taskbar and Start jump list. It is recorded in `docs/parity.md` as "differs on purpose, later". |
| Backward compatibility | (O, 2026-10-16) A non-major `TimeTug.Engine` release is safe to take with no app change, so Dependabot or the bump workflow merges it when CI is green; the app is released only by the owner. |
| Models | (O) Implementation work uses Sonnet 5.5; reviews use the `deepseek-review` skill. |

## Architecture notes

- View models talk only to an `IEngine` abstraction over the package, never P/Invoke. No scheduling, dedup, rule or default logic in C#, enforced by an architecture test.
- The tug window logic is a small state machine (hidden, shown, shown-without-focus, toast, held-until-return) behind an interface so it is unit-testable without a display; monitor handling is a separate service.
- Display strings are Windows' own concern: the app owns localization resources; the engine supplies none.
- Elevation: the app never runs elevated. A tug cannot cover an elevated window's secure prompts, and this is documented, not worked around.

## Testing and CI

- xUnit tests for view models, the tug state machine, platform services (with fakes) and the architecture rules. Everything that reads OS state sits behind an injectable interface: session lock and unlock, notification state (`SHQueryUserNotificationState`), the monitor list, the transparency and animation settings, the toast service and `TimeProvider`. The self-test and unit tests fake those, because a hosted runner has one virtual display and cannot lock its session or enter presentation mode. The real OS paths are checked on the VM by the agent where possible and by the owner's manual checklist otherwise.
- Accessibility: `axe-windows` automated checks run in CI on the welcome window, the tug screen, the flyout and the settings window (program design section 7); contrast-theme and reduce-motion behaviour have unit tests on the view-model layer.
- The engine's golden fixtures and scenarios already run against the real native library in `timetug-shared`; this repository adds contract tests that the app's host implementations answer every service request kind.
- Self-test runs on `windows-latest` and `windows-11-arm` for every pull request, with screenshots attached as artifacts.
- A development MSIX is built on every pull request and merge, signed with a throwaway self-signed certificate created in the job. The owner's signing material is never in pull-request jobs (program design section 7).
- Live sign-in with real accounts is a manual check by the owner, listed in a `docs/manual-tests/windows-checklist.md` that grows with each slice.

## Risks

- **WinUI 3 plus Windows App SDK quirks on ARM64 and in CI** (UI automation needs an interactive desktop). Mitigation: the self-test renders and captures its own windows and does not depend on UI-automation drivers; a spike task at the start of slice 1 proves a window renders and is captured on both runners.
- **Foreground and focus rules.** Mitigation: mouse works regardless; the keyboard path is best effort with the click-anywhere hint; no focus-stealing tricks.
- **Multi-monitor and display changes** (docking, lid close). Mitigation: a monitor service tested with a fake display list, and the late-return behaviour covering a tug lost to a display change.
- **Credential Locker, loopback and proxy behaviour on managed PCs.** Mitigation: all HTTP through `HttpClient`; browser sign-in stays the fallback; diagnostics name the failing step.
- **A suppressed toast** (Do Not Disturb, per-app notifications off). Mitigation: report presentation only when Windows accepts the toast, tray attention state, diagnostics entry, and the held-request return behaviour.
- **Accessibility regressions** in a custom full-screen window. Mitigation: `axe-windows` in CI, Narrator and contrast checks in the manual checklist.
- **Pre-1.0 package churn.** Mitigation: exact pin plus the backward-compatibility checks in `timetug-shared`.

## Open items for the owner

These are actions, not design questions.

1. Approve this spec.
2. After the repository exists: apply the organization rulesets and environments to `timetug-windows` and add its checks as required (the agent will list them), as for the other repositories.
3. Later, for phase 9: the Partner Center account and Store identity (not needed for phase 5).
