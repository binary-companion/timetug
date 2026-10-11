# Architecture

This is the current module map. The [2026-09-18 core design](superpowers/specs/2026-09-18-timetug-core-design.md) records original rationale; later ADRs and code supersede changed details.

## Modules
- `Packages/TimeTugCore`: pure Swift; depends only on `CalendarCore`. `TimeTugCalendarEvent` model (wraps the library `CalendarEvent`, adds merge and display state), `CalendarSource` protocol, `CalendarStore`
  (merge/dedupe/last-good), duplicate rules, resolver, lessons and the adjudicator interface (ADR 0009), `TakeoverPolicy`, `TakeoverLedger` + `Scheduler`,
  `DayAgenda`, `TakeoverRequest`, `TakeoverSettings` (including `enabled`), `WidgetSnapshot` and `WidgetTimeline` (widget data and entry dates, ADR 0010). Note: `additionalCalendarKeys` tracks when a meeting
  appears on multiple opted-in calendars so takeover opt-in on any calendar counts.
- `Packages/EventKitSource`: Apple Calendar adapter. Only place EventKit is imported.
- `Packages/CalendarConnectors`: portable calendar connector library (ADR 0012), no external dependencies. Products: `CalendarCore` (model, `AllDay`, `ConferenceDetector`, `JoinURLPolicy`, file-backed connection and sync-state stores, optional write API), `CalendarOAuth` (PKCE and refresh), `GoogleCalendar`, `MicrosoftCalendar`, `ICalendar`, `CalDAVCalendar` (including iCloud), `ICalSubscription` and `CalendarTestSupport`. The app supplies OAuth configuration and credentials (see [operations](development/runbooks/operations.md)). Microsoft sign-in requests read-only scopes under [ADR 0017](decisions/0017-microsoft-read-only-scopes.md); the library's write implementation remains available for a host that grants wider scopes.
- `Packages/CalendarBridge`: minimal glue. `EventMapper` wraps library events (drops cancelled, adds calendar info); `ConnectedSource` adapts a library source to Core and translates errors and changes.
- `Packages/CalendarApple`: Keychain credential store, loopback OAuth and `CryptoKitSHA256` for the library.
- `Packages/AppleIntelligenceInference`: Apple on-device model adapter for duplicate detection (macOS 26+, compile-guarded). Only place with Foundation Models imports.
- `Apps/macOS`: menu bar item, popover, overlay windows, settings, wiring (`AppCoordinator`). XcodeGen builds direct and App Store distributions from one specification; they share an App Group but use separate build directories. The App Store target excludes Sparkle.
- `Apps/macOS/Widgets`: WidgetKit extension (Next Up, Today, macOS 26 controls) that reads the app-written snapshot from the App Group; `Apps/macOS/Shared` holds the code compiled into both targets (ADR 0010).
  The optional global popup shortcut uses the KeyboardShortcuts package (ADR 0005), app layer only.

## Dependencies

`TimeTugCore -> CalendarCore`; `CalendarBridge -> TimeTugCore + CalendarCore`; `EventKitSource -> CalendarCore`; `CalendarApple -> CalendarCore + CalendarOAuth`. The inference package depends on TimeTugCore and the connector package. Inside CalendarConnectors: `CalendarOAuth`, `ICalendar` and `CalendarTestSupport` depend on `CalendarCore`; Google and Microsoft each depend on `CalendarCore + CalendarOAuth`; CalDAV and iCal subscriptions each depend on `CalendarCore + ICalendar`. The app composes these packages. Keep this map aligned with the package manifests and `scripts/ci/check-architecture.sh`.

## Flow
EventKit, Google, Microsoft, CalDAV and iCal subscriptions -> `CalendarBridge.ConnectedSource` -> `CalendarStore.refresh` (fetch window) -> `CalendarSnapshot` -> `Scheduler.next` -> one timer
-> `TakeoverRequest` -> `OverlayController`. `DayAgenda.make` feeds the popover and the status title.
App -> `WidgetSnapshot` -> group container (`agenda-snapshot.json`) -> widget timelines. Control Center intents write shared settings and post a Darwin notification; the app re-reads them.

## Adding a calendar source
Implement the library's `CalendarSource` and `ConnectorKind` in `Packages/CalendarConnectors` (except Apple Calendar, which uses `EventKitSource`). Use `CalendarCore` models and errors; add `WritableCalendarSource` only for supported writes. Map the source through `CalendarBridge.ConnectedSource` and register its connector kind in `Apps/macOS/Sources/AppConnectors.swift`. The app supplies credentials, OAuth interaction and source configuration UI. Never import UI frameworks into the connector library or leak provider types into Core. A new package also needs its allowed dependencies and import rules in `scripts/ci/check-architecture.sh`, which fails until it has them.

## Adding a platform front end
Depend on `TimeTugCore` only. Decide for yourself whether a status bar exists and what it shows, how
the takeover looks, and where settings live.
