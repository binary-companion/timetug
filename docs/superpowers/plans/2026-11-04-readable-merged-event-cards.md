# Readable Merged Event Cards Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this single presentation task inline. Steps use checkbox syntax for tracking.

**Goal:** Apply the approved Visible actions layout to expanded merged meeting cards.

**Architecture:** Keep EventCard's handlers and row model intact. Render its expanded list outside the
header HStack and stack member details above a separate action row.

**Tech Stack:** SwiftUI, AppKit, existing XCTest app suite and macOS visual checks.

**Spec:** `docs/superpowers/specs/2026-11-04-readable-merged-event-cards-design.md`

## Global Constraints

- App presentation only; preserve shared Core/Engine behavior and dependency pins.
- Keep popup width, existing calendar data, handlers, and all three card styles.
- Preserve complete member groups when splitting duplicate copies.

## Review Focus

- Long member titles and account/calendar labels wrap instead of truncating.
- Expanded content receives the full card width even when the header includes Join.
- Multiple identical copies retain a visible count and split together.
- Shown-member information remains accessible without crowding the title.
- Large groups scroll within the popup's existing height limit.

### Task 1: Apply and verify the expanded layout

**Files:**
- Modify: `Apps/macOS/Sources/DropdownView.swift` (EventCard body and memberRow)
- Modify: `docs/manual-tests/macos-checklist.md` (readability acceptance check)

**Interfaces:** Existing PopupRowModel/MergedMemberRow inputs; unchanged onSeparate(event, members) callback.

- [x] Run `scripts/dev/verify.sh app` as the baseline. Expected: app suite passes.
- [x] Move expanded members below the header; stack wrapping titles/details above the visible action row.
- [x] Extend the manual checklist for the five review cases above.
- [x] Run `scripts/dev/verify.sh affected`. Expected: affected app and repository checks pass.
- [x] Inspect actual rendered SwiftUI cards at the existing popup width, including long-label and duplicate fixtures.
- [x] Review the final diff and prepare the branch for review; do not merge or publish a release.

The existing VM screenshots reproduce the visual failure. This reversible layout-only change uses
existing behavior tests plus actual rendering checks; no source-text or implementation-mirroring tests
will be added. The user's approval authorizes inline execution without another plan approval round.

## Verification evidence

- Baseline app suite passed: 326 tests, one skipped, zero failures.
- Affected app, EventKit, CalendarApple, and inference checks passed. The release-tool stage
  initially needed PyYAML; rerunning it with the declared requirements in an isolated uv
  environment passed all 23 checks.
- Native SwiftUI fixtures at the existing 336-point card width passed long/short label checks;
  Glass, Frosted, and Solid were inspected in light and dark. The accessibility tree exposes
  the shown-member value and event/copy-count button labels. Spoken VoiceOver, keyboard
  traversal, and full-popup scrolling remain manual release checks.
- Independent code review reported no actionable findings.
