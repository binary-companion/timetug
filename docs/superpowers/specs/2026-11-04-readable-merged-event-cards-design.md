# Readable merged event cards

Approved design: the **Visible actions** variant of the in-chat mockup, approved by Scott on 2026-11-04.

## Intent

Expanded merged events must expose their titles, calendar names, times, and Split off actions without
squeezing the text into the meeting header's narrow title column. This also makes the real app usable
for the planned App Store preview.

## Design

- Keep the current meeting header, disclosure, join action, card styles, and merge behavior.
- Put the expanded list beneath the entire header, across the card's content width, with quiet dividers.
- Each member has a full-width, wrapping title, followed by wrapping calendar/time details.
- Put a visible Split off button on a separate trailing action row. Keep duplicate-copy counts visible.
- Preserve the shown-member distinction for VoiceOver without the cramped visible `shown` label.
- Continue sending the original event and that row's full members collection to the existing handler.
- Support long titles, calendar/account labels, light/dark appearance, Solid/Frosted/Glass cards, and
  keyboard/VoiceOver use. Do not increase the popup width or change calendar data or dependency pins.

## Approaches

**Visible actions (selected):** actions below the details keep the text readable and make splitting
discoverable. Costs a little vertical space; the existing popup scroll limit handles larger groups.

**Quiet menus (not selected):** per-member overflow menus save height but hide the action.

## Scope

This is app presentation only. No changes to shared Core/Engine, merge rules, Apple Intelligence,
calendar writes, releases, or the installed VM app. The mockup's Undo split control was an interactive
preview aid, not part of the selected production change.
