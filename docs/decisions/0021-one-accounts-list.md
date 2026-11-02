# 0021: One accounts list on both platforms

Status: accepted, 2026-11-02; amended 2026-11-02 (Mac: Apple Calendar is its own control above the box, spec Q2 and D3) and again 2026-11-02 (Windows: no pinned row, the Windows account is added on Continue, service logos; see "Amendment"). Spec: [one accounts list for Mac and Windows](../superpowers/specs/2026-11-02-shared-accounts-list-design.md) (D1 to D19, A1 and L1 to L10). Plan: [shared accounts list](../superpowers/plans/2026-11-02-shared-accounts-list.md).

## Context
The Mac's Settings > Accounts was a stack of cards (Apple Calendar, a "Connected Accounts" card with a per-row "..." menu, an "Add an Account" tile grid). Windows had its own three Microsoft cards and a welcome window that pre-selected one. Adding, seeing and removing accounts looked different on each platform, and the Mac checklist still described a `+ -` bar from an older layout.

## Decision
- **One control on both platforms**: a bordered box with a selectable list of the signed-in accounts and a bar with `+` (a menu of what can be added) and `-` (remove the selected account; Delete does the same). The box holds accounts only. Each platform builds it natively (SwiftUI `AccountsListBox` over the pure `AccountsListModel`; WinUI on Windows). What they share is the numbered behaviour contract L1 to L10 in the spec, the strings' meaning and the test cases, not code.
- **Apple Calendar is its own control above the box** (the owner's decision on spec Q2, which replaced the first default of a pinned row inside the box that shipped in #164). On the Mac it is "Apple Calendar (this Mac)" with its on/off switch and, when Calendar access is off, "Open System Settings"; it is a separate bordered row and one VoiceOver group named "Apple Calendar", never a row of the list, never selected, never removed with `-`. The box then has the list, `+`, `-` and the empty text "No accounts yet. Choose + to add one." Windows has no Apple Calendar and no pinned row either (see "Amendment").
- **The switch is a Mac thing.** The Mac switch hides the Apple calendars and keeps their Tug and visibility choices (as before), and shows "Open System Settings" when Calendar access is off. Windows has no switch: the first draft's "This PC's Windows account" switch, which removed the account when turned off because the engine has no disabled state, was dropped (see "Amendment").
- **One Microsoft entry.** The `+` menu lists Microsoft, Google, then iCloud, iCal link and Other (CalDAV) last. On Windows the browser route is a fallback ("Use your browser instead"), not a peer entry. The Mac already has one Microsoft entry (a browser session) and is unchanged. Mac only: Fastmail, Todoist, Zoom and Webex sit disabled under a "Coming soon" heading, as the tiles were.
- **Removal is asked, then confirmed by the engine.** `-` and Delete ask "Remove name?" with today's text (Cancel is the default). The row leaves, and selection moves to the row now in its place (else the previous one, else none), only when the engine's state says the account is gone; a refused removal leaves the row. While a sign-in runs `+`, `-`, the switch and "Sign in again" are disabled.
- **D6, no migration.** Existing accounts keep working and appear in the list unchanged; moving an account between sign-in modes is remove and add.
- **Landing page (Windows, D12 and D13).** After Google redirects back to TimeTug's loopback address, TimeTug asks Windows to bring the window that started the sign-in forward, and the browser tab shows a branded "You're connected" page that says to return to TimeTug. The tab is left open: a page cannot close a tab it did not open, and Google blocks embedded web views, so neither a script nor an in-app browser is possible. The Mac needs nothing: `ASWebAuthenticationSession` closes its own sheet.
- **No engine, library or protocol change** (D14). `Packages/*`, `AppConnectors.swift`, the dependency pins, the wire protocol and persisted account files are untouched; this is presentation, host-local behaviour and documents.

## Amendment (2026-11-02, second pass; owner decisions, final)

Spec Amendment A1 and decisions D16 to D19 change Windows only:

- **No pinned row on Windows.** (The Mac no longer has one either: its Apple Calendar control sits above the box.) A Microsoft account that signs in through Windows is an ordinary row, like every other. No switch, no "This PC's Windows account" strings, no "On this PC" tag.
- **Added on Continue.** In the welcome window, Continue adds the Windows account when Windows lists one (Windows' own consent dialog is the one-click consent; nothing is requested before Continue). Removing it with `-` records a dismissal in the app's local settings (a boolean, no account data), so it is never added automatically again; `+` > Microsoft (whose picker lists it) adds it back. A local-only Windows account adds nothing. This is host-local behaviour; the engine, library and protocol are unchanged (D14).
- **Service logos.** Rows and `+` entries show the vendor mark (Microsoft four squares, Google "G") unmodified on a white tile, with accessible names; sources and constraints are in the spec (A1.5) and in `timetug-windows` `src/TimeTug.App/Assets/Providers/README.md`. The Mac keeps its drawn marks (`ProviderIcon`), which differs on purpose and is not changed here.
- The consent-withdrawal sentence now applies to every Microsoft account in the remove question and under the box.

## Consequences
- The Mac and Windows differ on purpose in three ways: the Mac has the separate Apple Calendar control with its switch and Windows has no such control or pinned row; the Windows account is added automatically at first run (the Mac asks EventKit for access at launch); the icons are drawn on the Mac and vendor assets on Windows.
- The Mac's Accounts pane changes shape: the connected-accounts card, the tile grid and the per-row menus become one box, and the Apple Calendar card stays a separate control above it.
- The Mac model and controller rules are unit-tested without a view; VoiceOver, Full Keyboard Access and the real sign-ins stay on the [manual checklist](../manual-tests/macos-checklist.md).
- Windows slices W1 to W3 are in `timetug-windows`; they and this Mac slice (M1) are independent and merge in any order.

## Verified by
| Rule | Test |
|---|---|
| Menu order, disabled reasons, "Coming soon" group (`+`) | `AccountsListModelTests.testMenuOrderPutsMicrosoftAndGoogleFirstAndCaldavLast`, `testPlaceholdersAreDisabledAndComingSoon`, `testUnconfiguredKindIsADisabledEntryWithAReason` |
| Rows in the engine's order, status words, "Sign in again" (L1, L5) | `testRowsKeepTheEnginesOrder`, `testNeedsAttentionRowOffersSignInAgain`, `testABuildFailureShowsCantStartAndOffersSignInAgain` |
| Empty text; the box holds accounts only (L7) | `testEmptyTextWhenNoAccountsAndTheBoxHoldsNothingElse`, `testAppleCalendarOnAndOffDoNotChangeTheBox`, `testAppleCalendarIsNeverARowOfTheBox` |
| The Apple Calendar control: off, on, access off, "Open System Settings" only while on (L6) | `testAppleCalendarControlStatesOffOnAndAccessOff`, `AccountsControllerTests.testTheListModelMirrorsTheControllersState` |
| The Apple Calendar control's VoiceOver group, switch label and hint | `testAppleCalendarControlVoiceOverText` |
| `-`, Delete, `+` and the switch disabled while busy (L3, L4, L9) | `testRemoveIsDisabledWithNoSelectionAndWhileWorking`, `testAddSwitchAndSignInAgainAreDisabledWhileWorking`, `testTheSwitchIsDisabledOnlyWhileASignInRuns`, `testEntriesStayInTheMenuWhileBusyAndPlusIsDisabledInstead` |
| The remove question and accessibility text | `testRemoveQuestionTextMatchesToday`, `testRemoveLabelIsRemoveAccountWithTheNameInTheHint`, `testRowAccessibilityLabelReadsProviderNameStatus`, `testAnnouncementNamesAnAddedOrRemovedAccount` |
| Selection after removal, only once the engine drops the account (L2, L3) | `AccountsListModelTests.testSelectionAfterRemovingMovesToNextThenPreviousThenNil`, `AccountsControllerTests.testSelectionMovesToTheNextAccountOnlyAfterTheEngineDropsTheAccount`, `testRemovingTheLastAccountSelectsThePreviousThenNothing`, `testARefusedRemovalKeepsTheSelectionAndTheRow` |
| Selection survives the engine's frequent state (L10) | `AccountsControllerTests.testPublishingTheSameStatusKeepsTheSelection`, `testSelectionIsClearedWhenItsAccountVanishes`, `testChoosingAnotherRowBeforeTheEngineAnswersLeavesThatChoiceAlone` |
| Removal commands | `AccountsControllerTests.testRemoveSelectionSendsRemoveAccountForTheSelectedID`, `testRemoveSelectionDoesNothingWithoutASelection`, `testRemoveSelectionIsIgnoredWhileWorking` |
| The drawn box, VoiceOver, Full Keyboard Access, real sign-ins | [manual checklist](../manual-tests/macos-checklist.md), "One accounts list" |
