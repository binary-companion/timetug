# One accounts list for Mac and Windows

Status: draft for the owner's review (2026-11-02). Design only; the plan follows approval. Parents: [phase 6: WAM sign-in](2026-10-30-phase-6-wam-sign-in-design.md) (its "What the owner will see" items 1, 2 and 4 and decision D1 are amended here), [phase 5: the Windows app core](2026-10-16-phase-5-windows-app-core-design.md) (the welcome window), the [program design](2026-10-09-windows-program-design.md) sections 4 and 4.5. The owner approved the shape of this design in conversation on 2026-11-02; the "Decisions" table marks what is the owner's and what is my call.

> **Amended 2026-11-02 (second pass; owner decisions, final): no pinned row on Windows.** On Windows the pinned "This PC's Windows account" row, its switch and the "On this PC" tag are dropped; the Windows Microsoft account is added automatically, as an ordinary row, when the person presses Continue in the welcome window; every row shows its service's logo. The Mac is unchanged (its separate "Apple Calendar (this Mac)" control and switch stay). The new rules are in [Amendment A1](#amendment-a1-no-pinned-row-on-windows) below, decisions D16 to D19 in the table; the passages they replace are marked "Superseded by A1" and kept for the record. Where this spec says "pinned row" for Windows, read A1.

> **Amended 2026-11-03 (third pass; owner decision, final): the Windows account is a row in the first-run box.** On the welcome window the Windows Microsoft account no longer waits behind the Continue button as an explanation line; it is the first row of the box before Continue is pressed ("Ready to connect"), and `-` removes it. Continue still triggers the one Windows consent. The rules are in [Amendment A2](#amendment-a2-the-windows-account-is-a-row-in-the-first-run-box) below (decisions D20 to D22). A1.1's "the empty text" for step 2 and the second paragraph of A1.2 ("Offered" ... "Continue") are read with A2.

## Purpose

Make adding, seeing and removing accounts one familiar thing on both platforms: a box that lists the signed-in accounts, with `+` to add and `-` to remove the selected one. The same control sits in the Windows welcome window and in Settings > Accounts on both platforms. On Windows the first run stops pre-selecting a Microsoft card. *(Superseded by A1: the first draft started from a plain switch, "This PC's Windows account"; the final design has no switch and adds the Windows account when the person presses Continue.)* Microsoft sign-in becomes one entry in the `+` menu instead of three cards, and Google sign-in on Windows stops leaving a stranded browser tab by bringing TimeTug forward and saying so on the landing page.

**Principle (owner, kept from phase 6):** one consent per Microsoft account, asked once, with a visible user action first. Nothing is requested from Windows until the person presses Continue.

**Anti-goals:**

- A second way to do something the list already does. Every account action has one place: `+`, `-`, a row's "Sign in again", the switch.
- A silent break. A failing account is a visible row with its reason and a fix, never a missing row.
- Any trick to steal focus or close a browser tab (see D12 and the program design's no-focus-stealing rule).

## Findings that shaped this spec

Read before the decisions, because two of them correct the request's premise.

1. **The Mac has no welcome window.** `docs/PROGRESS.md` records that the Mac's first run opens Settings on the Calendars tab, and `Apps/macOS/Sources` contains no welcome or onboarding view. The welcome window is Windows-only (phase 5). This spec therefore reads "look like the Mac's welcome flow" as "look like the Mac's first-run Accounts experience": the Mac's Settings > Accounts opens with the control "Apple Calendar (this Mac)" and an Enabled switch, then the box of internet accounts. The Windows row "This PC's Windows account" with its switch is the same idea (a "this device" row, section "The shared control"). Q2 (resolved 2026-11-02): the Mac gets no welcome window, and Apple Calendar is its own control above the box, not a row inside it.
2. **The Mac's current Accounts pane is a card, not a list.** It has the Apple Calendar card, a "Connected Accounts" card with a per-row "..." menu, and an "Add an Account" tile grid (`Apps/macOS/Sources/AccountsPane.swift`). `docs/manual-tests/macos-checklist.md` lines 93 to 97 still describe a "`+ -` bar" from an older layout, so the shared control brings the Mac back to the layout its checklist already describes.
3. **Windows has already built phase 6 slice B** (timetug-windows PR 40): the welcome window pre-selects "Microsoft account on this PC", and Settings > Accounts has three Microsoft cards ("Microsoft account on this PC", "Another Microsoft account", "Microsoft (browser)"). Spike S2 (`docs/spikes/2026-11-wam-broker.md` in timetug-windows) found that the broker lists the Windows sign-in account and, on the hosted runners, nothing for a local-only Windows account. Other accounts on the PC (work or school, or added under Email & accounts) were not observed, so "the broker lists only the Windows account" is an inference that Q6 asks the owner's real-account run to settle. The local-only case, which is what "hidden" needs, is observed.
4. **The Windows landing page is a hard-coded English string** in `LoopbackAuthorization` ("You can close this tab"). It is not in `Resources.resw`, so it is not localized the way every other string is.
5. **No engine, library or protocol change is needed.** The brokered kind, the picker intent, `account.remove`, the identity-family rule and `account.reconnect` already exist. Everything below is presentation, host-local behaviour and documents.

## What the owner will see

### First run on Windows (no accounts)

1. **Step 1, "Welcome to TimeTug":** the current title and subtitle and one button, "Get started" (my call, Q1). While this screen is up TimeTug asks the broker for the account list (no token, no dialog), so step 2 is ready when it opens.
2. **Step 2, "Connect your calendars":** the shared accounts control. *(Superseded by A1 for Windows: the box has no pinned row and no switch; the bullets below describe the first draft. Under A1, Continue adds the Windows account when Windows lists one.)* Its first row, inside the box, is "This PC's Windows account" with a switch.
   - The row is shown only when the broker is available and Windows reports a signed-in Microsoft account. For a local-only Windows account, or when the broker is missing or blocked, the row is absent and the box starts with its empty text.
   - The switch is on by default. Under the row: the email when exactly one account is listed ("name@example.com"), and the line "Windows will ask you to let TimeTug read your calendars when you press Continue. TimeTug stores no password and no sign-in token."
   - Below it the (empty) list, and the `+ -` bar. `+` opens the menu: Microsoft, Google, iCloud, Other (CalDAV), iCal link (what the build can sign in to; see "The `+` menu").
   - **Continue** (accent button; the old "Skip for now" link stays). Continue with the switch on opens Windows' own consent dialog for the Windows account. Allow: step 3. If the Windows account is already connected (the person added it with `+` > Microsoft and the picker), the pinned row shows it as connected, Continue asks Windows for nothing and goes to step 3. Decline or close: nothing is added, no error, the person stays on step 2 with the switch still on.
   - Accounts added with `+` appear in the list at once and the person stays on step 2. Continue is enabled when the switch is on or the list has an account. With the switch off and an empty list it is disabled (nothing to continue to) and Skip for now is the way out.
3. **Step 3, "You're connected":** unchanged from phase 5 (what was found, Add another, Test tug, launch at login, the tray note, Done).

### Settings > Accounts, both platforms

One box of the signed-in accounts, then the `+ -` bar. On the Mac, Apple Calendar is a separate control above the box ("Apple Calendar (this Mac)" with its switch), not a row in it. Windows has no such control and no pinned row (A1; the first draft pinned "This PC's Windows account" with a switch). Under the box: the waiting row with Cancel while a sign-in runs, an error line if one failed, and (Windows, after a Windows sign-in failed or was cancelled) the "Use your browser instead" link.

- A row shows the provider glyph, the account name or email, the status in words ("Connected", "Sign in again", "Can't start this account", and so on, exactly today's text), the "On this PC" tag where it applies *(superseded by A1: no tag)*, and "Sign in again" as a button in the row when the account needs it.
- `+` adds. `-` (or the Delete key) removes the selected row after the question "Remove name?" with today's text, plus, for an "On this PC" account, how to withdraw the consent.
- *(Superseded by A1 for Windows: there is no Windows switch; a Windows-signed-in Microsoft account is removed with `-` like any row.)* The Mac switch keeps today's meaning (hide the Apple calendars, keep the choices).

### When Windows needs the person again, or cannot be used

- Reconnect: the account's row says "Sign in again" with a button; the button opens the Windows dialog for that account (unchanged behaviour). The flyout keeps saying "Open Accounts" for these accounts (phase 6, D3).
- Windows sign-in unavailable (no broker, or the host answers unavailable): the `+` menu's Microsoft entry reads "Microsoft" with the second line "Use your browser instead" and runs the browser sign-in directly. If the attempt fails after the menu offered Windows sign-in, the area under the box says "Windows sign-in isn't available here" and shows the link "Use your browser instead".
- Declining or closing the Windows dialog shows no error, but the same "Use your browser instead" link appears under the box until the next action (Q5).

### Google on Windows

The browser opens as today. When Google redirects back to TimeTug's loopback address, TimeTug asks Windows to bring the window that started the sign-in to the front, and the browser tab shows a branded page: "You're connected" and "Return to TimeTug". The tab is left open: a page cannot close a tab it did not open, and Google blocks embedded web views, so neither a script nor an in-app browser is possible. If the redirect carried an error, the page says "Sign-in didn't finish" and "Return to TimeTug and try again."

## Goals, non-goals, constraints

**Goals**

- G1 One list, one `+`, one `-`, on both platforms, in the welcome window and in Settings > Accounts.
- G2 The Windows first run asks for nothing until Continue, and shows the Windows-account choice only when it can work.
- G3 A single "Microsoft" entry; the browser route is a fallback, not a peer.
- G4 The Google landing page tells the person what to do next, in the app's language, accessibly.
- G5 The list is fully usable by keyboard and by Narrator and VoiceOver.

**Non-goals**

- No change to `calendar-connectors`, `timetug-shared`, the C interface, the wire protocol, golden fixtures or persisted data. No new engine command.
- No migration of existing accounts between kinds (D6).
- No Mac welcome window (Q2, resolved), no new providers, no change to scopes (ADR 0017 stands).
- No lossless "pause" of an account (Q3). No attempt to close the browser tab. No change to the Mac's `ASWebAuthenticationSession` sign-in.
- Not a shared UI codebase: SwiftUI and WinUI each build the control; what is shared is this contract, the strings' meaning and the test cases.

**Constraints**

- The app never steals focus: no simulated keys, no thread-input attachment (timetug-windows `AGENTS.md`). The foreground request is the ordinary activate call and may be refused by Windows (D12).
- View models stay free of OS and MSAL references (architecture tests); only `TimeTug.Platform` talks to the broker.
- Display strings live in `Resources.resw` on Windows and in the SwiftUI sources on the Mac, as today.

## Decisions

Owner decisions are marked (O); my calls (C) are open to change.

| # | Topic | Decision |
|---|---|---|
| D1 | First-run first row (O; **superseded by D16 and D17**) | "This PC's Windows account" with a switch replaces the pre-selected "Microsoft account on this PC" card. On by default when Windows reports a signed-in Microsoft account. Hidden for local-only Windows accounts and when the broker is unavailable. The switch decides whether Windows sign-in is used; nothing is requested until Continue. This keeps phase 6's approved one-click consent: the click is Continue. |
| D2 | Shared control (O) | A bordered box with a selectable list, a `+` button that opens a menu and a `-` button that removes the selected account (existing confirmation, with the consent-withdrawal text for Microsoft accounts, D18). Used in the welcome window (Windows) and in Settings > Accounts (both). *(The first draft's "The Windows-account row keeps its switch" is superseded by D16.)* |
| D3 | Device account (C, amended 2026-11-02 twice) | **Mac:** Apple Calendar (this Mac) is its own control above the box, with its on/off switch and, when Calendar access is off, "Open System Settings". The box holds only the other accounts (list, `+`, `-`, the empty text), so Apple Calendar is never a row, never selected, never removed with `-`. This is the owner's decision (Q2). **Windows:** this spec as first approved had a pinned first row "This PC's Windows account" inside the box; **superseded by D16**: Windows has no device row and no switch. |
| D4 | One Microsoft entry (O) | "Another Microsoft account" and "Microsoft (browser)" collapse into one "Microsoft" entry in the `+` menu. On Windows it uses the broker's account picker (the existing `microsoft-brokered` kind with the picker intent). The Mac already has one Microsoft entry (browser session) and is unchanged. |
| D5 | Browser as fallback (O) | The browser route is shown as "Use your browser instead" when the broker is unavailable (as the Microsoft entry's second line) and as a link on a broker error or cancel (under the box). Never a peer entry while the broker works. |
| D6 | No migration (O) | Existing browser-connected Microsoft accounts keep working and appear in the list unchanged. Moving an account between browser and Windows sign-in is remove and add. |
| D7 | Windows account identity (C; **superseded by D16: the email match now only decides whether Continue still has something to add**) | The "This PC's Windows account" row stands for the connected `microsoft-brokered` account whose email equals the email the broker lists for Windows (case-insensitive). While the pinned row is shown and that account is connected it is shown only in the pinned row, never again in the list. In every other case a connected brokered account is a normal list row with the "On this PC" tag: a different account chosen in the picker, an older account, or any account when the pinned row is hidden (listing failed, timed out or named more than one account), so a connected account never disappears. The email match applies only when the listing names exactly one account. |
| D8 | Same mailbox in the other mode (C; **superseded by D16: the engine refuses the second connection, so Continue adds nothing**) | The engine's identity-family rule already refuses a second connection for the same mailbox in either mode. If a browser-connected Microsoft account with the Windows account's email exists, the pinned row is shown with the switch off and disabled and the line "name@example.com is already connected through your browser. Remove it to use Windows sign-in." |
| D9 | Switch semantics in Settings (C; **Mac only after D16**) | On connects the Windows account at once (the person pressed something; Windows asks). Off removes it after the confirmation (with the consent-withdrawal text, as `-` does for an "On this PC" row), because the engine has no disabled state for an account and adding one is out of scope (Q3). In the welcome window the switch is only a pending choice until Continue. |
| D10 | Continue and `+` in the welcome window (C; stands, with the Continue rule of D17) | `+` adds immediately and stays on step 2; Continue is the only way to step 3 (Q4). |
| D11 | Row actions (C) | The per-row "..." menu goes away on both platforms; `-` and Delete replace it. "Sign in again" stays a button in its row. |
| D12 | Google landing and foreground (O) | On the loopback redirect Windows TimeTug requests foreground for the window that started the sign-in; the landing page says "You're connected" and "Return to TimeTug". No close attempt, no embedded browser. If Windows refuses the foreground (its foreground lock), it flashes the taskbar button, which is the standard Windows behaviour for a refused request, and the page text still says what to do. |
| D13 | Landing page (C) | Branded, accessible, localized, with two outcomes (connected, did not finish); other requests get 404 and do not end the sign-in; built from `Resources.resw` strings, no external resources (section "The landing page"). |
| D14 | No engine change (C) | Confirmed by the findings above; the plan must treat any need for one as a reason to come back to the owner. |
| D15 | Models (O) | Implementation work uses Sonnet 5.5; reviews use the `deepseek-review` skill. |
| D16 | No pinned row on Windows (O) | Windows has no pinned "This PC's Windows account" row and no switch. All Microsoft accounts, whichever way they sign in, look and behave the same as every other row. The Mac keeps its Apple Calendar control and switch above the box (a separate calendar type that is present by default). Supersedes D1, D7, D8 and the Windows halves of D3 and D9. |
| D17 | Windows account added on Continue (O) | When the person presses Continue in the welcome window and Windows lists a Microsoft account, TimeTug adds it as an ordinary Microsoft account; Windows' own consent dialog appears then (the approved one-click consent; nothing is requested before Continue). Removing it with `-` records a dismissal in the app's local settings, after which it is never added automatically again; `+` > Microsoft (whose picker lists it) adds it back. A local-only Windows account adds nothing. Details in A1. |
| D18 | No "On this PC" tag (O) | A Microsoft account that signs in through Windows has no tag. The consent-withdrawal sentence (where to remove TimeTug's access at Microsoft) is shown for every Microsoft account in the remove question and under the box, because Microsoft holds the consent for both sign-in routes (C). |
| D19 | Service logos (O) | Each row, and each `+` menu entry, shows its service's logo: the Microsoft four-square logo for Microsoft, the Google "G" for Google, the existing marks for the rest. Official, unaltered, with accessible names, correct in light, dark and high contrast. Sources and constraints in A1. |
| D20 | The Windows account is a row in the first-run box (O) | When Windows lists exactly one named Microsoft account (or, Q6, several or unnamed ones) and the person has not removed it before, the welcome window's box starts with that account as its first row: Microsoft logo, the email, "Ready to connect" and "Windows will ask you to allow TimeTug when you continue." Nothing is requested from Windows until Continue. Replaces the explanation line under the box that PR 46 added. |
| D21 | `-` removes the row without a question (C) | Selecting the row and pressing `-` (or Delete) drops it from the box at once and records the dismissal (A1.3). No question is asked: nothing is connected, nothing is forgotten, and `+` > Microsoft brings it back. |
| D22 | Status of the row follows Continue (O/C) | Ready, then "Connecting…" while Windows asks, then the connected account's own row; after a decline, close or failure the row stays with "Not connected. Choose Continue to try again." and the usual failure text under the box. Once another account is connected the row says "Not connected. Continue goes on without it." and Continue goes on without asking again (Q11). |

## Amendment A1: no pinned row on Windows

Owner decisions of 2026-11-02, final. They change Windows only. Decisions D16 to D19 in the table above point here.

### A1.1 What the person sees on Windows

- **First run.** Step 1 "Welcome to TimeTug" with Get started, as before. Step 2 "Connect your calendars" is the box with `+ -`, the empty text "No accounts yet. Choose + to add one." and Continue (and "Skip for now"). There is no switch and no "This PC's Windows account" row. Continue adds the Windows account (A1.2); the person can also add anything with `+` first.
- **Settings > Accounts.** The same box. A Microsoft account that signs in through Windows is a row like any other: name or email, "Connected" or "Sign in again" (a button in the row), `-` removes it. It looks the same as a Microsoft account connected by browser: kind name "Microsoft", no tag (D18), the Microsoft logo (D19).
- **`+` > Microsoft** (D4) is unchanged: with a working broker it opens the Windows account picker, which lists the Windows account too; without one it signs in by browser ("Use your browser instead" as the entry's second line). Settings never adds the Windows account by itself.
- **Strings gone:** "This PC's Windows account", "Use this PC's Windows account", the pinned row's description and conflict lines, "On this PC". Nothing else in the contract L1 to L10 changes except that L5 has no tag, L3 and the footnote apply to every Microsoft account (A1.4) and L6 (the Apple Calendar control) applies only to the Mac.

### A1.2 Continue adds the Windows account (D17)

While step 1 is up TimeTug asks the broker for the account list exactly as in "The pinned row on Windows" (no token, no dialog, 5 s limit), unless a dismissal is recorded (A1.3), in which case it makes no broker call at all. The listing result is mapped to one question: is there a Windows account to add?

*Offered* means all of: the broker is available and the build offers the brokered kind; the listing is `OneNamed` or `Unnamed`; no dismissal is recorded; the account is not connected already (for `OneNamed` a connected `microsoft-brokered` account with the listed email, compared case-insensitively; for `Unnamed` any connected `microsoft-brokered` account); and, for `OneNamed`, no browser-connected Microsoft account has that email (the engine's identity-family rule would refuse the second connection, so there is nothing to add).

| State of step 2 | Continue |
|---|---|
| Listing still pending (even when the list has an account) | disabled; the answer arrives within 5 s at most (a late or failed listing counts as not offered), so Continue never goes on before the Windows offer is known |
| Offered | enabled. Pressing it arms the Windows-account intent and adds the brokered kind: Windows' consent dialog appears (the first and only request to Windows). Allow: the new row appears and the window goes to step 3. Decline or close: nothing is added, no error words, the person stays on step 2 and the link "Use your browser instead" shows (Q5). Fail: nothing is added, the usual failure text with the engine's detail shows under the box (L8) with the same link, and the person stays on step 2; pressing Continue again asks again when the list is empty, and goes on to step 3 without asking when the list has an account |
| Not offered, list has an account | enabled; goes to step 3, no broker call |
| Not offered, list empty (a local-only Windows account, an unavailable listing, or a recorded dismissal) | disabled; "Skip for now" is the way out; `+` works |

Accounts added with `+` stay on step 2 (D10). When the list already has an account and the Windows account is offered, Continue still asks Windows (the owner's rule is "adds the Windows account when the person continues"); declining then lets the next Continue go on. Nothing is requested from Windows before the first press of Continue; the listing is the only broker call before it.

### A1.3 Remembering the removal

The engine has no place for a host-local flag (D14), so the dismissal is one boolean in the app's local settings (`ApplicationData.LocalSettings`, key `Accounts.WindowsAccountDismissed`), read and written through an interface in the presentation layer. It holds no account data.

- Set when the person confirms the removal of a `microsoft-brokered` account that can be the Windows account: the listing is `OneNamed` with that account's email, or `Unnamed`, or unavailable. Not set when the listing is `None` (nothing is the Windows account) or names a different email (a picker-added account).
- While set, Continue never adds the Windows account automatically and step 1 makes no listing call.
- It is never cleared by the app. `+` > Microsoft still adds the Windows account (the picker lists it); a later removal sets the flag again. Declining or closing the Windows dialog does not set it (Q10).

### A1.4 Consent withdrawal without the tag (D18)

The remove question's second paragraph and the note under the box ("To stop TimeTug reading a Microsoft account's calendars, remove its access at account.live.com/consent/Manage (personal accounts) or on your organization's My Apps page (work accounts).") apply to every Microsoft account, of either sign-in kind, because Microsoft holds the consent in both cases. Row accessibility names lose ", On this PC".

### A1.5 Service logos (D19)

Every row and every `+` menu entry shows its service's mark in a small white tile (rounded square, the mark inset with clear space, a 1 px light-grey outline baked into the SVG; built: an SVG cannot follow the theme, so a high-contrast theme shows the same tile, which already gives the mark its contrast). The mark is always the unmodified full-colour vendor mark: both vendors forbid recolouring it, so a high-contrast theme changes the outline, not the mark. The mark repeats what the row's text already says ("Microsoft", "Google"), so it adds no information that colour alone carries.

| Service | Mark | Source | Constraints we follow |
|---|---|---|---|
| Microsoft (both sign-in kinds) | The four-square logo: red #F25022, green #7FBA00, blue #00A4EF, yellow #FFB900, squares of equal size with a gap of one eighth of a square | Microsoft identity platform, "Sign in with Microsoft branding guidelines" (the downloadable Microsoft logo, `ms-symbollockup_mssymbol_19.svg`: 19 by 19, four 9 by 9 squares, 1 gap) | Do not alter the logo; light and dark backgrounds allowed; the tile is white so one asset serves every theme |
| Google | The four-colour "G" | Google Identity, "Sign in with Google branding guidelines" (the standard G of the pre-approved buttons) | The standard-colour G on a white background; no monochrome version; do not change its size ratio or colours or draw our own G. Google's page speaks of sign-in buttons; using the G beside an account and on the `+` entry is the nearest allowed use (Q12) |
| iCloud, CalDAV, iCal link | Segoe Fluent Icons glyphs (cloud, calendar, link) as today | Windows system font | Not brand marks, so no brand constraints. The Mac draws its own equivalents; unchanged |

Accessible names: the mark is an image named "Microsoft logo" or "Google logo" (resource key `Accounts_LogoAutomation`, "{0} logo"); in a menu entry the entry's own text names it and the mark is decorative. Each row's name is still "Provider, name, status". The assets live in `src/TimeTug.App/Assets/Providers/` of `timetug-windows` with a README that records source, date and the constraints above, and `docs/third-party.md` there lists them as third-party marks used under the vendors' guidelines (not covered by the repository's licence).

### A1.6 Effects on the rest of this spec

- **Accessibility.** The pinned row's switch name and description go; Tab order is the list, `+`, `-`, then the controls under the box. Everything else stands.
- **What changes where, `timetug-windows`.** `DeviceRowModel`, the pinned row of `AccountsListBox`, `DeviceRowIsPending`, the conflict and description strings and the `ConnectedAccount` tag go; `AccountsViewModel` gains the offer rule and the dismissal (an `IWindowsAccountDismissalStore` implemented over local settings); `WelcomeViewModel`'s Continue follows A1.2; `ProviderLogo` and the vector assets arrive. `timetug` (the Mac): documents only.
- **Cross-platform documents.** `docs/parity.md` rows 37, 41, 42, 43 and the "pinned device row" row are rewritten (the Windows account is an ordinary row; row 41's counterpart note goes); ADR 0021 says the pinned device row is Mac-only and records the Windows rules; the program design's section 4.5 and the phase 5 and phase 6 notes point to A1; the Mac checklist needs no change (the Mac does not change).
- **Test strategy.** The device-row cases become the offer and Continue cases of A1.2 (offered for `OneNamed` and `Unnamed`, not for `None`, `Unavailable`, a dismissal, a connected account or a browser account with the same email; Continue asks Windows once; decline stays; a second Continue with an account goes on; no broker call but the listing before Continue; none at all when dismissed), the dismissal cases of A1.3 (set for the matching, unnamed and unavailable cases, not for none or a different email; survives a restart through the store; `+` still adds), and the logo cases (mark per kind, accessible names, tile colours per theme, no mark recoloured). The owner-attended items 1 to 4 and 6 change: item 1 has no pinned row (Continue shows the real dialog and the row appears), item 2 decline stays with the link, item 3 a local-only account leaves Continue disabled and `+` > Microsoft opens the picker, item 4 skips the switch (add Google with `+`, Continue still offers Windows' dialog; declining and Continue again goes on), item 6 has no switch (`-` on the Windows row, then relaunch with no accounts: Continue does not add it again, and `+` > Microsoft adds it back).
- **Open questions.** Q6 now only affects whether Continue can name nothing special (the offer treats one and several listed accounts alike); Q9 is moot (no tags).

## Amendment A2: the Windows account is a row in the first-run box

Owner decision of 2026-11-03, final, from the first real run of the A1 build (screenshot: an empty box reading "No accounts yet. Choose + to add one." with, under it, the line PR 46 added: "Continue connects the Microsoft account you sign in to Windows with (name). Windows asks you to allow TimeTug."). The owner's reading: a line that tells the person to press a button is not the interface; the account should be *in the box*. Windows first-run window only; Settings > Accounts and the Mac do not change. Decisions D20 to D22 in the table point here.

### A2.1 What the person sees

- **Step 2 "Connect your calendars".** When the Windows account is *offered* (A1.2: the broker is available and the build offers the brokered kind; the listing is `OneNamed` or `Unnamed`; no dismissal is recorded; the account is not connected already and no browser-connected Microsoft account holds the same email) the box shows it as its **first row**, already, before anything is pressed:
  - the Microsoft logo (A1.5, "Microsoft logo");
  - the name: the account's email when Windows names exactly one account; for `Unnamed` (several listed accounts, or one without an email; Q6 default) "The account you sign in to Windows with";
  - the status "Ready to connect" and, as a second line, "Windows will ask you to allow TimeTug when you continue.";
  - no "Sign in again" button (it is not an account yet).
- The empty text "No accounts yet. Choose + to add one." shows only when the box has no rows: a local-only Windows account, an unavailable listing, a recorded dismissal, or after the row was removed. The line under the box (the A1-era "Continue connects ..." and "Windows didn't connect ..." notes) is **removed**. The line "Google and Microsoft open your browser to sign in." stays.
- The row is an ordinary selectable row: Tab reaches the list, arrows select, `-` and Delete act on it, Narrator reads "Microsoft, me@example.com, Ready to connect. Windows will ask you to allow TimeTug when you continue." and "Remove me@example.com" on the minus button.
- **Listing still pending** when step 2 opens: the row is not there yet; it appears in place when the answer arrives (no focus move; Narrator is told through the list's live region as for any row), and Continue stays disabled until the answer is known (A1.2). A listing that fails or times out (5 s) offers nothing and shows no row.
- **Skip for now** adds nothing and records nothing (the row was never an account).

### A2.2 Continue

Continue behaves as in A1.2 and is the only thing that asks Windows for anything (the listing stays the one earlier call):

| Moment | The row |
|---|---|
| Before Continue, and while another sign-in (Google, iCloud, a picker) runs | "Ready to connect" with its second line |
| Continue pressed, Windows' dialog open ("Waiting for Windows…" under the box, Cancel) | "Connecting…", no second line; `-` and `+` are disabled (L9) |
| Allowed | the connected account's own row takes the row's place ("Connected" or "Connecting…" while the engine reads the calendars); the window goes to step 3 |
| Declined, closed, cancelled or failed | the row stays: "Not connected. Choose Continue to try again." (warning colour **and** a warning mark and the words, never colour alone); the failure text, if any, and "Use your browser instead" appear under the box exactly as in A1.2; Continue asks Windows again |
| The same, once another account is connected (added with `+`) | "Not connected. Continue goes on without it."; Continue goes on to step 3 without asking (the next press after the single decline, Q11); the person may still select the row and remove it |

A connected row can also arrive through `+` > Microsoft: choosing the Windows account in the picker replaces the offered row by the connected one; choosing a different account leaves the offered row first and adds the new row below it. Accounts added with `+` always appear below the offered row, which stays first.

### A2.3 Removing the row (`-`, Delete)

Select the row and press `-` (or Delete in the list): the row is dropped from the box **at once, with no question** (D21), the dismissal of A1.3 is recorded (the same rule and the same flag as removing a connected Windows account), selection and focus move as after any removal (L2: the row now in its place, else the previous one, else `+`), and the screen reader announces "<name> removed". `+` > Microsoft still adds the account (its picker lists it). With the box then empty, Continue is disabled and Skip for now is the way out. `-` is disabled while Windows is being asked (L9). Where nothing can persist the flag (no store, or a store that cannot write) the row still goes for the rest of that window's life.

### A2.4 What does not change

The engine, the library, the broker host and the intents (the Windows-account intent is armed by Continue exactly as before); the listing rule and the 5 s limit; the dismissal flag and its key; the approved one-click consent; Settings > Accounts (it gives no Windows account source, so it never shows the row); the Mac. Contract items: L1 (rows in the engine's order) reads "the offered row first, then the engine's order"; L3's question is not asked for the offered row (A2.3); L7 (empty text) as above.

### A2.5 Test strategy (amends "Test strategy")

View-model tests: the row exists before Continue for `OneNamed` and `Unnamed` (name, logo, status, hint, automation name), not for `None`, `Unavailable` or a dismissal; it appears in place after a late listing; it is selectable; Continue sets "Connecting…" and the connected account replaces it; a decline, a failure and a cancel each give "Not connected. Choose Continue to try again."; with another account connected the status reads "Continue goes on without it." and Continue goes on without a broker call; `+` accounts appear below it; the picker with the Windows email replaces it and with another email leaves it; a browser account with the same email leaves no row; `-` drops it with no question, records one dismissal, moves selection and focus, is disabled while busy and works without a store; Skip records nothing; only the listing is called before Continue. Self-tests (`welcome-brokered`, `welcome-dismissed`, `welcome-local-only`, and the welcome round of `a11y-hold`): the row is in the box with its logo, its automation name and the Selection and SelectionItem patterns; after a closed dialog its status says so; `-` on it drops it with no dialog and the next first-run window makes no listing call. Owner-attended: windows-checklist 2.17 to 2.20 are rewritten for the row.

## The shared control

### Parts

```
+--------------------------------------------------+
| (o) This PC's Windows account            [ on  ] |   pinned device row (optional)
|     name@example.com                              |
|     Windows will ask you ... press Continue.      |
|--------------------------------------------------|
| [G] you@gmail.com                                 |   list rows (selectable)
|     Connected                                     |
| [M] work@contoso.com  On this PC  [Sign in again] |
|     Sign in again                                 |
+--------------------------------------------------+
| [ + v ] [ - ]                                     |   bar
```

Under the box, in this order, each shown only when it applies: the waiting row (progress, text, Cancel), the error line, the browser fallback link, the configuration warning ("This build is missing configuration for some account types..."), the consent-withdrawal footnote (Windows, when any Microsoft account is connected, D18; today's text).

### Behaviour contract (both platforms)

Numbered so the parity document, the plans and the tests can cite them.

- **L1 Order.** Rows are in the engine's order. The box holds nothing else on either platform (the Mac's Apple Calendar control is outside it; Windows has no device row, A1).
- **L2 Selection.** At most one list row is selected. Nothing is selected when the control first appears. The Mac's Apple Calendar control is not part of the selection. After the selected row is removed, selection moves to the row now in its place, or the previous one, or none; focus follows (Accessibility).
- **L3 `-`.** Disabled when nothing is selected or while a sign-in runs. Its accessible name is "Remove" plus the selected account's name. Pressing it (or Delete while the list has focus) asks "Remove name?" with the body "Its calendars will no longer appear and their Tug and visibility choices are forgotten." For a Microsoft account (either sign-in kind, D18) the body adds the withdrawal text ("To stop TimeTug reading a Microsoft account's calendars, remove its access at account.live.com/consent/Manage (personal accounts) or on your organization's My Apps page (work accounts)."). Confirm sends the engine's remove; the row leaves when the engine's state says so, not before.
- **L4 `+`.** Disabled while a sign-in runs. Opens the menu (below). Choosing an entry starts that sign-in; the waiting row appears; Cancel works as today.
- **L5 Row content.** Provider mark, name (the account's display name or email), status text (today's words), no tag for how the account signs in (the "On this PC" tag of the first draft is gone, D18), the unreadable-recurrence notice marker where it applies. A row that needs the person (expired sign-in, or "Can't start this account") shows "Sign in again" as a button in the row and the status in the warning colour; the warning is never colour alone.
- **L6 Apple Calendar control (the Mac only).** A separate control above the box, with the title "Apple Calendar (this Mac)", the status words, the switch and "Open System Settings" (calendar access off, shown only while the switch is on); it is one VoiceOver group named "Apple Calendar" whose switch reads "Use Apple Calendar". Windows has none (A1; the first draft's pinned "This PC's Windows account" row is gone).
- **L7 Empty.** No list rows: the box shows one line in the list area, "No accounts yet. Choose + to add one." The Mac's Apple Calendar control, which is outside the box, is unaffected. The line is not a button.
- **L8 Failure placement.** A sign-in failure appears under the box, not as a row, because no account exists yet. A failed account that exists is a row with "Sign in again". An engine message that no provider explains is shown once under the box.
- **L9 Busy.** While any sign-in runs: `+`, `-`, the switch and Sign in again are disabled; the waiting row shows progress and Cancel.
- **L10 Stable updates.** The engine publishes often; the control updates in place and rebuilds rows only when a row's content changed, so keyboard focus and selection survive (the Windows page already works this way).

### The `+` menu

Entries, in this order, for the kinds the build offers:

1. **Microsoft.** Windows with a working broker: runs the account picker (D4); no second line. Windows with no usable broker and a Microsoft client id: second line "Use your browser instead", runs the browser sign-in. Mac: the existing browser session. Disabled with "isn't set up in this build" when neither route is configured.
2. **Google.**
3. The remaining kinds in today's order: iCloud, iCal link, Other (CalDAV) last.
4. Mac only: a separator and a "Coming soon" group with Fastmail, Todoist, Zoom and Webex disabled, as the tiles are today. Windows omits them (parity ledger, unchanged).

A kind the build cannot sign in to is a disabled entry with the reason, plus the existing configuration warning under the box. Entries are never removed from the menu while busy; `+` itself is disabled instead.

### Microsoft on Windows: the states

| Situation | Menu entry | Under the box |
|---|---|---|
| Broker works | "Microsoft" (picker) | nothing |
| Broker not offered (no client id, broker did not load, policy) but browser configured | "Microsoft" + "Use your browser instead" (browser sign-in) | nothing |
| Neither configured | "Microsoft" disabled, "isn't set up in this build" | configuration warning |
| Picker or Windows-account dialog closed, no account added | unchanged | the link "Use your browser instead", no error words |
| Host answered unavailable during sign-in | unchanged | "Windows sign-in isn't available here" and the link |
| Sign-in failed (admin approval needed, other) | unchanged | the usual failure text with the engine's detail, and the link |

The link starts the browser sign-in (kind `microsoft`). It disappears when any sign-in starts or succeeds, or when the pane is closed.

### The pinned row on Windows

> **Superseded by A1 (D16).** Kept as the record of the first draft. Windows has no pinned row; the broker listing below now decides only whether Continue has a Windows account to add (A1.1).

Visibility and default state come from one question asked of the broker (`ListAccountsAsync`, no token, no dialog): which accounts does Windows list?

| Broker listing | Row | Switch in the welcome window |
|---|---|---|
| Broker not offered, or the listing fails or times out | hidden | n/a |
| Zero accounts (local-only Windows account) | hidden | n/a |
| Exactly one account with an `@` in its user name | shown, names the email | on |
| One or more accounts otherwise (not seen in the spike; Q6) | shown without an email | on |

The listing started on step 1 normally finishes before step 2 opens (first call about 1.6 s, later about 0.1 s in the spike). If it has not, step 2 opens with the row absent and Continue disabled, and the row appears in place when the answer arrives without taking focus; Narrator hears it through a polite live region. A listing that never answers within 5 s counts as a failure (the row stays hidden, a diagnostics line records the step and no account data).

In Settings the switch shows the truth from the engine's state (D7): on when that account is connected, off otherwise. Turning it on from Settings runs the same sign-in Continue runs; its failure goes under the box.

## Windows and Mac differences

| Aspect | Mac | Windows |
|---|---|---|
| Where | Settings > Accounts only (no welcome window, Q2) | Welcome window step 2 and Settings > Accounts |
| Device account | Apple Calendar (this Mac): its own control above the box, switch hides calendars and keeps the choices; "Open System Settings" when access is off | None (D16). The Windows Microsoft account is an ordinary row, added on Continue at first run (D17) |
| Control | SwiftUI `List` in a bordered box with a bottom bar of `+` (a `Menu`) and `-` | WinUI `ListView` in a bordered box with a bar of `+` (a button with a `MenuFlyout`) and `-` |
| Remove question | `confirmationDialog` (as today) | `ContentDialog` (as today) |
| Remove key | Delete (`onDeleteCommand`) | Delete |
| Microsoft entry | Browser session (`ASWebAuthenticationSession`) | Broker picker; browser as fallback |
| Google | `ASWebAuthenticationSession`, closes its own sheet | Default browser and loopback; TimeTug comes forward, landing page says to return |
| "On this PC" tag | none | none (D18) |
| Coming-soon entries | disabled group in the menu | omitted |
| Row and menu icons | Drawn marks (`ProviderIcon`: a four-colour "G", four squares) on a white tile; unchanged | The vendors' logos as vector assets on a white tile (D19, A1.5) |
| Strings | SwiftUI sources, as today | `Resources.resw`, as today |

## Accessibility

Requirements apply to both platforms; the mechanisms differ.

**Keyboard (Windows).** Tab reaches, in order: the pinned row's switch, the list (one tab stop; arrow keys move the selection), the `+` button, the `-` button, then the controls under the box. Enter, Space or Alt+Down on `+` opens the menu; arrows move, Enter chooses, Esc closes and focus returns to `+`. Delete on the list, or Enter on `-`, opens the remove question; the dialog's default button is Cancel, not Remove. A row's "Sign in again" is reachable with Tab when its row is selected and is a button with its own name. After a removal focus lands on the next row, else the previous, else `+`. Nothing the engine publishes moves focus. Esc does not close the Settings window (existing rule) and does not remove anything.

**Keyboard (Mac).** With Full Keyboard Access: Tab to the Apple Calendar switch (and "Open System Settings" when shown), then to the list, arrows to select, Delete asks to remove, Tab to `+` (Space opens the menu) and `-`. The remove dialog's default is Cancel.

**Narrator (Windows).** The list is named "Connected accounts" (existing string). A row's name is "Provider, name, status" and nothing more (A1: the first draft's ", On this PC" suffix and the pinned row's switch are gone). `+` is "Add account" (with "has a menu"); `-` is "Remove name" when a row is selected and "Remove account" (dimmed) otherwise. Changes announce through live regions: "Waiting for Windows..." or "Waiting for your browser..." when a sign-in starts (polite); the error line when it fails (assertive, as the cards' errors are now); "name removed" after removal; the pinned row appearing late.

**VoiceOver (Mac).** Apple Calendar is one group named "Apple Calendar" containing its switch ("Use Apple Calendar") and, when shown, "Open System Settings" (hint: opens the Calendars privacy settings in System Settings). Rows are one accessibility element each, reading provider, name, status, with custom actions "Sign in again" and "Remove". `+` is "Add account", `-` is "Remove account", with the selected account's name in its hint. The `List` exposes selection state. Removal and sign-in outcomes are announced with accessibility announcements.

**Visual.** Selection, focus rings, error and warning states use system colours and glyphs plus text, so Windows contrast themes and the Mac's Increase Contrast work; the warning is never colour alone (L5). No animation beyond the system's; reduced motion is respected. Targets are the platform's standard control sizes. Text wraps and the control reflows at 200 percent text size.

**Automated checks.** Windows: axe-windows on the welcome window and the Accounts pane (existing rounds) plus assertions in the self-tests that each new control has an automation name and the list and item patterns. Mac: unit tests on the model that produces the labels; VoiceOver itself is a manual check.

## The landing page (Windows)

Served by `LoopbackAuthorization` for the redirect request. Replaces `ClosePage`.

- **Outcomes** (decided from the redirect request's query string; nothing from it is echoed):
  - A `code` and no `error`: title "You're connected", body "Return to TimeTug." The page cannot know whether the later token exchange succeeds; if it fails, TimeTug shows its usual failure and the person has met one sentence that was too optimistic, not lost data (Q8).
  - An `error` parameter: title "Sign-in didn't finish", body "Return to TimeTug and try again."
  - Any other request (no `code` and no `error`, including a bare `GET /` and the favicon): 404, empty, and the listener keeps waiting. Today the first non-favicon request ends the sign-in, so a stray local request could burn it; this change makes the capture require `code` or `error` (the engine still validates the `state` value as before).
- **Content:** the TimeTug name and mark (an inline SVG element, so the page makes no request at all), an `h1` with the title, one paragraph, nothing else. No script, and no button that claims to close the tab (an honest page does not offer one).
- **Accessibility:** `lang` set from the app's UI language, `dir` for right-to-left languages, a `main` landmark, a meaningful `title` ("TimeTug"), light and dark colours through `prefers-color-scheme`, `prefers-contrast` and forced-colours support, contrast of at least 4.5:1 for text, responsive with a `viewport` meta, no auto-refresh, no motion.
- **Security:** every string HTML-encoded; response headers `Cache-Control: no-store`, `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`. The page is served only by the loopback listener that already exists.
- **Localization:** strings are `Resources.resw` keys, resolved at request time through the `ILocalizer` the app already injects (keys `Landing_PageTitle`, `Landing_ConnectedTitle`, `Landing_ConnectedBody`, `Landing_FailedTitle`, `Landing_FailedBody`, each with a translator comment). A test fails when a `Landing_*` key is missing from the resource file, as the existing resource-completeness tests do for other keys.
- **Mac:** nothing. `ASWebAuthenticationSession` closes its own sheet. The Mac's optional browser route (`oauth.useBrowser.v1`) keeps the connector library's "You're signed in" page; not changed here.

### Bringing TimeTug forward

When the loopback listener has captured the redirect, `TimeTug.Platform` raises one call on a small interface owned by the presentation layer ("a sign-in came back"), and the app implements it by restoring (if minimized) and activating the window that started the sign-in: the welcome window, or the Settings window. Rules:

- Best effort. It uses the ordinary activation call and nothing else (no simulated keys, no thread-input attachment). If Windows refuses, the taskbar button flashes; the landing page and the waiting row ("Waiting for your browser...") already say what to do.
- Only a window that exists and started this sign-in. With no TimeTug window visible (for example a sign-in begun from a flyout problem row), nothing is shown or raised.
- Not for a cancelled or failed sign-in, and never for the broker path (the Windows dialog is already modal over the app).
- Spike S-FG (small, owner-attended on the VM and one other PC): does the request succeed or flash, with Edge, Chrome and Firefox as the default browser, and with TimeTug minimized or behind other windows? The outcome is recorded in `docs/spikes/` of timetug-windows and decides only Q7; the design stands either way.

## What changes where

### `timetug` (the Mac app and the documents)

- `Apps/macOS/Sources/AccountsPane.swift`: replace the connected-accounts card, the provider tile grid and the per-row menu with the shared control (extract it as `AccountsListBox`, a view over a small model so a welcome case can reuse it later); make the Apple Calendar card its own control above the box (`AppleCalendarRow`), not a row in it; keep the waiting row, error text, configuration warning, diagnostics section and the credential sheet presenter; the placeholder providers move into the menu's disabled group.
- `Apps/macOS/Sources/AccountsController.swift`: add the selection (`ConnectionID?`), the ordered menu entries (Microsoft, Google, the rest, CalDAV last), `canRemoveSelection`, and removal by selection. A pure model (`AccountsListModel`: rows, labels, menu entries, remove-question text) holds everything that can be unit-tested without a view.
- Tests (Swift Testing): menu order and disabled reasons, selection after removal, `-` disabled states, the remove question text, row labels and accessibility labels, the Apple Calendar control's states (off, on, access off, its VoiceOver group, switch label and hint) and that it is never a row; `AccountsControllerTests` updated.
- `docs/manual-tests/macos-checklist.md`: lines 93 to 97 reviewed against the new layout, new items from "Test strategy".
- `docs/decisions/0021-one-accounts-list.md` (the decision and its rationale, written at plan time) and its row in the ADR index.
- Amendments, as short dated notes: the phase 6 spec (its items 1, 2 and 4 and D1 point here), the program design sections 4 ("Calendars and sign-in") and 4.5 (first run, Accounts pane, browser fallback), the phase 5 spec's first-run paragraph; `docs/PROGRESS.md` and the tracker rows.
- Not touched: `Packages/*`, `AppConnectors.swift`, the `project.yml` pins, anything in Core or the engine.

### `timetug-windows`

> **A1 supersedes the pinned-row parts of this list** (the pinned row model, the pending switch, `PreselectBrokered` aside): A1.6 lists the Windows changes that stand. The slices W1 to W3 as built are history; the redesign is slice W4 in the plan (Part F).

- `TimeTug.Platform`: `LoopbackAuthorization` builds its response from a new `SignInLandingPage` (the two outcomes, the stray-request rule, encoding, headers, `lang`); one call raised on capture for the foreground request; `BrokerWindowsAccountSource` returns the listing's shape (none, one named, one or more unnamed) instead of only an email. No MSAL type leaves the Platform project.
- `TimeTug.Presentation`: `AccountsViewModel` gains the pinned row model (visibility, name, email, switch state, status, the "already connected through your browser" case), the `+` menu entries with their states, the selected account and the `-` and Delete commands, the browser fallback link state, and the Continue rule; `WelcomeViewModel` gains the intro step, `ContinueCommand`, the pending switch, and no longer advances on `Connected`; `PreselectBrokered` and the three Microsoft cards go away (`ProviderItem` remains as the menu entry model); the picker and Windows-account intents stay.
- `TimeTug.App`: one `AccountsListBox` user control (a `ListView`, the bar with a `MenuFlyout`, the pinned row) used by `WelcomeWindow.xaml` and `AccountsPage.xaml`; the welcome window gets the intro step and Continue; the `AccountCard` and `ProviderCard` code in `AccountsPage.xaml.cs` is deleted; the activation implementation for the returning sign-in.
- `Strings/en-US/Resources.resw`: add `Accounts_DeviceRow*`, `Accounts_AddAutomation`, `Accounts_ListEmpty`, `Welcome_Continue`, `Welcome_GetStarted`, `Landing_*`; reword `Accounts_Empty`; remove `Provider_microsoft-brokered-pick`, `-named` and `Provider_microsoft-browser` when nothing references them.
- Tests: see "Test strategy".
- Documents: `docs/parity.md` (below), `docs/manual-tests/windows-checklist.md` (sections 1.1, 2.1, 2.6, 2.7, 2.9 and the accessibility entry), a spike note for S-FG.

### Not changed

`calendar-connectors`, `timetug-shared` (and so the `TimeTug.Engine` package), the C interface, the wire protocol, golden fixtures, persisted account files, Entra and Google registrations, the Store capability declarations (`docs/store/capabilities.md`), and the Mac's sign-in code.

## Cross-platform documents

There is no separate behaviour-contract file today; the contract is the program design's section 4 table, the parity ledger and the phase specs. This change keeps it that way and adds one reference.

- **This spec** holds the list's behaviour contract (L1 to L10); the plans and tests cite those numbers.
- **`docs/parity.md` (timetug-windows):** row 37 (Accounts list, add, remove, sign in again) says the cards are replaced by the box with `+ -` and Delete; row 41 (Apple Calendar switch) stays "not applicable" but names the Windows-account row as its counterpart; row 42 (WAM) is rewritten for "This PC's Windows account", the single Microsoft entry and the fallback; row 43 (consent at first run) now says "one click on Continue"; row 44 (Soon tiles) now says omitted from the menu; row 39 (Google and Microsoft browser sign-in with loopback) gains the foreground request and the landing page; row 61 (first-run experience) describes the three steps and notes that the Mac has no welcome window. One new row: "Accounts list: `+`, `-`, Delete, selection, pinned device row", done on both.
- **Program design, section 4 "Calendars and sign-in":** the "Sign-in window" row notes the foreground request and landing page. **Section 4.5:** "First run" describes the switch and Continue instead of an automatic dialog; "Accounts pane" describes the single Microsoft entry; "Browser fallback" says "Use your browser instead" appears when the broker is unavailable or after a broker error or cancel (the program design's "Sign in with a browser instead" menu item is replaced).
- **Phase 6 spec:** a dated amendment at the top says items 1, 2 and 4 of "What the owner will see" and D1 are superseded by this spec; the library, engine and broker designs are unchanged.
- **`docs/engine-protocol.md`:** no change (stated here so nobody looks).
- **ADR 0021** records: one accounts list on both platforms, the pinned device row, switch semantics, the browser as fallback, and the landing-page decision with the reasons a tab cannot be closed.

## Test strategy

**Windows, automated (CI and the VM, no person)**

- View-model tests (`TimeTug.Presentation.Tests`, scripted `IEngineClient`): pinned row visibility for each listing outcome; default switch state; Continue enabled and disabled rules; Continue with the switch on arms the Windows-account intent and adds the brokered kind; decline stays on step 2 with the switch on; `+` in the welcome window adds without leaving step 2; the switch off with accounts continues without any broker call; D7 matching (case-insensitive, an unrelated brokered account stays a list row) and D8 (the browser-connected same mailbox); menu entries for each row of "Microsoft on Windows: the states"; the fallback link appears after cancel, failure and unavailable and disappears on the next action; selection after removal; `-` and Delete only when allowed and only when idle; the Settings switch connects and removes; no broker call happens before Continue (a fake broker records every call; the listing is the only allowed one).
- Platform tests: `SignInLandingPage` for each outcome, a stray request (no `code`, no `error`) answered 404 without ending the sign-in, HTML encoding of hostile query strings (nothing echoed), headers, `lang` and `dir`, no external URL in the output; resource-completeness for `Landing_*`; `LoopbackAuthorization` raises the foreground call exactly once per captured redirect and not for favicon or cancel; `BrokerWindowsAccountSource` for none, one named, one unnamed, many, throw and timeout.
- Architecture tests: unchanged rules (no MSAL outside Platform; view models free of OS types) stay green.
- Self-tests (real engine, scripted broker, recorded Graph answers, both architectures, screenshots): `welcome` and `welcome-brokered` rewritten for the three steps; `accounts-brokered`, `brokered-reconnect`, `brokered-unavailable` rewritten for the list; new `accounts-list` (selection, `+` menu entries, `-`, Delete, focus after removal, empty state, busy state, error and fallback placement) and `welcome-local-only` (listing empty: no pinned row, empty text). Each asserts automation names and runs axe.
- The existing privacy test (sentinel values never reach the log, ETW or Copy diagnostics) runs over the new flows; the listing and the landing page add no account data to any of them.

**Mac, automated**

- Swift Testing for `AccountsListModel` and `AccountsController` (cases above). `scripts/dev/verify.sh affected` and `verify.sh app` pass. There is no UI-test target today; this change does not add one.

**Owner-attended (cannot be automated; the agent prepares builds, steps and expected text, the owner presses and approves, and nobody types a credential on the owner's behalf)**

Windows, on the ARM64 VM, and x64 where a second PC exists:

1. First run on a PC signed in with a Microsoft account: step 2 shows the pinned row with the right email, switch on; Continue opens the real consent dialog; Allow reaches step 3.
2. Same, but decline and close the dialog: stays on step 2, no error, the link "Use your browser instead" is there and works.
3. A local-only Windows account (a second Windows user): no pinned row, empty text, `+` > Microsoft opens the account picker.
4. Switch off, add Google with `+`, Continue: step 3, no Windows dialog appeared.
5. Google in a real browser (Edge, Chrome, Firefox): TimeTug comes forward or its taskbar button flashes; the tab shows the branded page in light, dark and a contrast theme; the page reads correctly at 200 percent zoom and with Narrator in browse mode. Spike S-FG notes.
6. Settings > Accounts: switch off removes with the question and the withdrawal text; switch on reconnects; `-` and Delete on a Google account; Sign in again after revoking consent at the provider; a browser-connected Microsoft account with the Windows account's email shows the D8 line.
7. Keyboard only, then Narrator: the whole welcome flow and the Accounts pane, including `+` menu, `-`, Delete, focus after removal and the live-region announcements.
8. The broker disabled or missing (a build without the client id): the Microsoft entry reads "Use your browser instead" and signs in by browser.

Mac, on a Mac with the Google client: the new box in light and dark; `+` menu order; Google sign-in still uses the system sheet; `-` and Delete with the question; the Apple Calendar control above the box, its switch off and on keeping the calendar choices; access denied shows "Open System Settings"; VoiceOver reads rows, `+`, `-`, and the removal announcement; Full Keyboard Access reaches everything.

## Release order and slices

No library or engine release is involved, so the bump chain does not move. The Mac and Windows work are independent and can ship in either order; each app is released only by the owner.

1. **This spec** (documents only), reviewed and merged by the owner. Then one plan per repository, written in `timetug` under `docs/superpowers/plans/` (the Windows plans live here too, as for phases 5 and 6).
2. **Windows W1: landing page and foreground request** (`timetug-windows`). Self-contained, no list UI change, shippable alone; also fixes the stranded-tab problem for Google today. Includes the S-FG spike notes.
3. **Windows W2: Presentation.** *(Built as written, then reshaped by A1 in slice W4.)* Pinned row, menu, selection, welcome steps and Continue, fallback link, with view-model tests. W2 only adds members and rules; it changes no behaviour the shipped window relies on, so the existing advance on `Connected`, `PreselectBrokered` and the card properties stay until W3 replaces the window's XAML and removes them in the same pull request. W2 is therefore not user-visible.
4. **Windows W3: App.** `AccountsListBox`, the welcome window and the Accounts pane switched over, strings, self-tests, axe, parity rows, checklist.
5. **Mac M1** (`timetug`): the box in Settings > Accounts, model and tests, checklist, ADR. Independent of W1 to W3.
6. **Documents** (amendments to the program design and phase specs, tracker, `docs/PROGRESS.md`) land with the slice that makes each statement true; the parity rows with W3.

Each slice merges on green CI. A slice that passes CI but cannot be seen working (W2) says so in its pull request.

## Risks

- **Foreground is refused by Windows.** Expected in some cases; the design never depends on it. The page text and the waiting row carry the instruction; S-FG measures how often.
- **The listing differs from the spike** (multiple accounts, work accounts, slow first call). Mitigated by the table in "The pinned row on Windows" and the 5 s limit; Q6 asks the owner's run to settle it.
- **A removal-based switch loses an account's Tug and visibility choices** when the person toggles the Windows switch off and on. The confirmation says so (today's text). Q3 offers an engine "pause" as a future change.
- **List-item focus is fiddly in WinUI** (a button inside a selectable row, live updates). Mitigation: update in place (L10), self-test focus assertions, a Narrator check; fallback is to show "Sign in again" for the selected row in a strip under the box if a nested button proves unreachable.
- **Mac layout churn.** The Accounts pane changes shape. Apple Calendar stays a separate control above the box (Q2, resolved), so the only moves are the cards, tiles and per-row menus into the box.
- **The landing page claims success early** (Q8). Accepted, with the "did not finish" outcome for explicit errors.
- **Two apps, one description.** Divergence is caught by the shared numbered contract in the parity ledger and a test per rule on each side.

## Open questions for the owner

Each has my default, used if you do not answer.

- **Q1 Step count.** The request says step 2 starts with the Windows-account row, and today's Windows flow has two screens (connect, connected). Default: add a short step 1 ("Welcome to TimeTug", Get started), so the connect screen is step 2 and the broker listing runs while step 1 is up. Alternative: keep two screens and put the welcome text above the box.
- **Q2 Mac scope. Resolved by the owner, 2026-11-02.** The Mac has no welcome window. Apple Calendar is its own control above the box, with its on/off switch (and "Open System Settings" when access is off); the box holds only the other accounts (list, `+`, `-`, the empty text "No accounts yet. Choose + to add one."). The earlier default put Apple Calendar inside the box as a pinned first row (shipped in #164 and replaced by this decision); the Mac first-run window stays a separate project. Windows has no Apple Calendar and, by A1, no pinned row either.
- **Q3 Windows switch off (moot after A1: no Windows switch).** Default: removes the account after the question (the engine has no disabled state). Alternative: a lossless "pause" like the Mac's Apple Calendar switch, which needs an additive engine change and a new release of `timetug-shared`.
- **Q4 `+` in the welcome window.** Default: adds the account and stays on step 2 until Continue. Alternative: advance to step 3 as soon as the first account connects (today's behaviour), skipping Continue for that case.
- **Q5 Decline note.** Default: after the Windows dialog is closed with no account, show the "Use your browser instead" link with no error words. Alternative: show nothing at all (phase 6's silent decline) and keep the link only after failures.
- **Q6 More than one listed account.** Default: show the pinned row without an email, switch on. Alternative: hide the row and let the picker handle it. Settled by the owner's real-account run (work account, second account).
- **Q7 A reliable "bring me back" link.** If S-FG shows Windows often refuses the foreground, default: accept it. Alternative: an "Open TimeTug" link on the landing page that activates the packaged app through a registered `timetug:` protocol (a person's click is allowed to bring an app forward). It needs a manifest protocol declaration and a Store capability review, so it is not in this design.
- **Q8 "You're connected" wording.** Default: shown whenever the redirect carries a code. Alternative: hold the response until the engine's token exchange finishes, which adds a wait inside the loopback listener and a longer-lived connection.
- **Q9 Telling kinds apart.** Browser-connected and Windows-connected Microsoft accounts both read "Microsoft" in the list, and only the latter has the "On this PC" tag (D6 says browser rows are unchanged). Default: no extra tag. Alternative: a small "Browser" tag, so the person knows what remove-and-add would change.
- **Q10 Remembering a decline (A1.3).** Default: only a removal is remembered; closing the Windows dialog is not, so the next Continue asks again (with an empty list). Alternative: also remember a decline.
- **Q11 Other accounts first (A1.2).** Default: Continue offers the Windows account even when the person added another account with `+`, because the rule is that Continue adds it; one decline lets the next Continue go on. Alternative: offer it only when the list is empty.
- **Q12 The Google "G" on an account row (A1.5).** Google's guidelines describe sign-in buttons. Default: use the unmodified standard G on a white tile for the Google row and menu entry. Alternative: a generic account glyph for Google.

## Actions for the owner

1. Approve this spec, or answer the open questions that matter.
2. After approval, the plans and slices above follow; merging each pull request and releasing either app stays yours.
3. Be available for the owner-attended checks in "Test strategy", in particular the real-account listing (Q6), the S-FG browser runs and the Narrator and VoiceOver passes.
