# Mac migration map for the Rust engine

This is Task 1 of the phase 6 plan (`docs/superpowers/plans/2026-11-10-rust-phase-6-mac-cutover.md`). It lists every file of the Mac app and its local packages that imports a Swift shared library, the library symbols each file uses, how each symbol is provided by `TimeTugKit`, and which plan task changes the file.

## Method

- The 88 files come from `grep -rlE '^import (TimeTugEngine|TimeTugCore|CalendarBridge|CalendarCore|GoogleCalendar|MicrosoftCalendar|CalDAVCalendar|ICalSubscription|ICalendar|CalendarOAuth)' --include='*.swift' Apps Packages`: 51 sources and 37 tests.
- Classified against `binary-companion/timetug-shared` branch `v2` at commit `7743b05` (`docs/bindings.md`, `docs/bindings-surface.txt`, the generated Swift and the hand-written layer under `swift/TimeTugKit`). Branch `main` has no `docs/bindings.md` yet, so `v2` was used. No `TimeTugKit` release exists at this commit; the newest tag is `2.0.0-alpha.1`, which predates the bindings. Step 3 of the plan ("the version that has them all") is open until the missing items below are released.
- The old behaviour was read from `timetug-shared` branch `1.x` and `calendar-connectors` branch `1.x`.
- **Fallback:** the app cannot be built here (signing, OAuth ids), so Serena could not list references. Symbols were found by text search: the names in `docs/bindings-surface.txt` plus member names read from the old sources and searched in the 88 files. A symbol used only through type inference (for example `item.state == .past`) is not listed. Task 5 and 6 compile errors will find any that were missed; add them to this table when they do.
- Generic words (`State`, `Status`, `Value`) matched SwiftUI and local names and were dropped by hand.

## Classes

| Class | Meaning |
|---|---|
| same | The type exists in `TimeTugKit` with the same name. Argument labels that end in `ID` or `URL` become `Id` or `Url` (`eventID:` is `eventId:`); the shim restores the computed properties only. |
| renamed (shim alias) | `Names.swift` has a typealias, so the old spelling compiles. |
| renamed | Different name or shape; the file changes. |
| exposed as function | The helper is a free function (`detectConferences`, `joinUrlIsAllowed`, `allDayDates`, ...). |
| replaced by config | `EngineConfig` carries the setting; the host builds no connector kind. |
| not exposed | The engine keeps it. Unused after the change, or replaced as the row says. |
| moves into app | Task 7: widgets do not link the engine. |
| replaced by summary field | `EngineState.nextTakeover` and `takeoverVisible`. |
| missing | See the list below. |

## Counts

Symbols found in the 88 files, by class: same 58 (`TakeoverLedger` is a read-only mirror), renamed (shim alias) 5, renamed 8, exposed as function 6, replaced by config 10, not exposed 13, moves into app 5, missing 2 types (`DiagnosticEvent`, `DiagnosticLevel`: delivery, see M10). In addition 13 groups of members and initialisers (M1 to M13) are missing from types that otherwise exist. Total: 107 symbols.

## Missing

Each item needs a change in `timetug-shared` (a pull request and a release) before the task that uses it. "Shim" means Swift in `swift/TimeTugKit/Sources/TimeTugKit` with a test; "function" means a new exported function in `timetug-engine-ffi` with the same behaviour as the Rust method, so a rule stays in one place.

| # | Missing | Used by | Proposed fix |
|---|---|---|---|
| M1 | `TimeTugCalendarEvent` accessors: `id`, `title`, `start`, `end`, `isAllDay`, `timeZone`, `location`, `notes`, `url`, `calendarID`, `calendarKey`, `contentKey`, `shownStart`, `conferenceURL`, `allCalendarKeys`, `Identifiable`, and `init(event:sourceID:)`. The generated struct has only `event`, `sourceId` and the merge fields. | popup, overlay, dropdown, formatting, tests | Shim. The formulas are the Rust ones: `id` is `sourceId/eventId/<start seconds>`, `calendarKey` is `sourceId/calendarId`, `contentKey` is `lowercased title\|start\|end`, `shownStart` is `displayStart ?? start`. A shim test compares them with values produced by the engine. `init(event:sourceID:)` mirrors 1.x defaults (`otherAttendeeCount`, `responseStatus`, `conferences` derived from the event). |
| M2 | `CalendarInfo.key`, `.id`, `static key(sourceID:calendarID:)`, and an initialiser with defaults (`colorHex`, `accountName`, `kind: .standard`, `service`, `provider`). | calendar lists, settings search, popup, tests | Shim. `key` is `sourceId/calendarId` (Rust `CalendarInfo::key`). |
| M3 | `TakeoverSettings`: `init()` with the 1.x defaults (60 s lead time, `skipAllDayEvents` true, `enabled` true), `Codable` with the 1.x lenient decoder (the app reads this JSON from UserDefaults), `isShownInList(_:)`, `setTakeover(_:forCalendar:)`, `setTakeover(_:forCalendars:)`, `setShownInList(_:forCalendar:)`. | CalendarsPane, SettingsStore, UserDefaultsSettingsStorage, tests | Shim for the mutators (ported from `TakeoverSettings.swift` 1.x; Rust has `is_shown_in_list` and friends in `timetug-core`). For `Codable` and `init()`: shim with a fixture test that decodes a JSON blob written by the last Swift release. Task 8 depends on this one. |
| M4 | `Connection.sourceID` (`"\(kindID)-\(connectionID)"`) and `Connection.init(kindID:connectionID:displayName:)` with default `config`. | AccountsController, AccountsListModel, tests | Shim. |
| M5 | Write checks the EventKit adapter calls: `EventDraft.usedFields`, `EventPatch.touchedFields`, `EventDraft.validate()`, `EventTiming.validate()`, `RecurrenceRule.validate()` (all throw `WriteError`). `requireWritable` needs the field sets. | EventKitSource+Write, EventKit write tests | Functions: `event_draft_used_fields`, `event_patch_touched_fields`, `validate_event_draft`, `validate_event_timing`, `validate_recurrence_rule`. They exist in `calendar-core` (`write/event_draft.rs`) and are not exported. Also note `requireWritable` throws `FfiError`, not `WriteError`; the adapter's catch changes. |
| M6 | `CalendarService` and `CalendarProvider` static values: `.eventKit`, `.google`, `.microsoft`, `.calDAV`, `.iCalSubscription`; `.iCloud`, `.local`, `.subscription`, and `RawRepresentable`. The generated types are plain structs with `rawValue`. | EventKitSource, EventKitMapping, tests | Shim (raw strings `eventkit`, `google`, `microsoft`, `caldav`, `icalsub`; `icloud`, `local`, `subscription`, as in `Model.swift` 1.x). |
| M7 | Nested names `RecurrenceRule.Weekday`, `.Frequency`, `.WeekdayOccurrence`, and `WeekdayOccurrence.init(_:ordinal:)`. (`RecurrenceRule.End` is aliased.) | EventKitMapping, EventKitWriteMapping | Shim typealiases in `Names.swift`; the initialiser in a shim. |
| M8 | Convenience initialisers with defaults. The generated ones need every field: `CalendarEvent(eventID:calendarID:title:start:end:timeZone:isAllDay:...)`, `CalendarDescriptor(id:title:service:...)`, `CalendarPermissions(canViewDetails:canEdit:)`, `SourceCapabilities(canWrite:providedFields:...)`, `Reminder(trigger:type:)` (the field is now `kind`), `Attendee(...)`, `ConferenceInfo(url:provider:)` (origin defaults). | EventKitSource, EventKitMapping, tests | Shim `Initializers.swift`, defaults as in 1.x `Model.swift`; one test per initialiser. |
| M9 | `Scheduler.next(events:settings:ledger:now:)` and ledger queries, used by `MenuBarIconState.resolve`. `nextTakeover` is the replacement, but it is `nil` while a takeover is on screen (`docs/bindings.md`), and `TakeoverLedger` is a read-only count. With `Scheduler` the icon stayed color during the takeover. | MenuBarIconState, its tests, EngineModelMirror | Decision for Task 6. Preferred: `timetug-shared` adds a summary field `nextPendingStart` (start of the next event that qualifies, ignoring whether a takeover is outstanding), so the icon rule is `nextPendingStart - now <= 10 min`. Fallback with no shared change: icon is `.soon` when `takeoverVisible` or when `nextTakeover.event.start - now <= 10 min`. Check that the fallback matches the old icon during snooze. |
| M10 | Delivery of connector diagnostics. Connectors report structured `DiagnosticEvent`s with private fields; `DiagnosticSink.log` takes only `EngineDiagnostic` (level, category, message). The mirrors `DiagnosticEvent` and `DiagnosticLevel` exist but no host interface receives them. I found no path in `timetug-engine` or `timetug-engine-ffi` that forwards them. The app's "Copy Diagnostics" (ring buffer, private-field redaction, OSLog privacy split) would lose iCal and sign-in events. The `DiagnosticLog` protocol and its `FanOut`, `RingBuffer` and `Null` implementations are in `CalendarCore` and are not exposed. | AppDiagnostics, OSLogDiagnosticLog, AppConnectors, tests | `timetug-shared`: add a method `record(event: DiagnosticEvent)` to `DiagnosticSink` and forward connector events through it, keeping the private flag. App: port `RingBufferDiagnosticLog`, `FanOutDiagnosticLog` and the redaction renderer into `AppDiagnostics` (Task 5). If the owner decides connector events may be dropped, record it as a behaviour change in the ADR. |
| M11 | `DayAgenda.make(events:settings:now:calendar:)` and `DayAgenda.empty`. | two test files only | No shared change: tests build `DayAgenda` values with a test helper (`DayAgendaItem` has a memberwise initialiser). |
| M12 | `JoinURLPolicy.isAllowed` in the widget extension, which must not link the engine. | NextUpWidget, TodayWidget | No shared change: Task 7 adds a copy of the policy (scheme allow-list) to `Apps/macOS/Shared`, with a parity test over a list of URLs against `joinUrlIsAllowed` in the app test target. The plan's Task 7 does not list it; add it. |
| M13 | `ConferenceDetector.provider(of:)` (a URL to a `ConferenceProvider`). `detectConferences` also takes a new first argument `structured`. | PopupLogicTests, EventKitSource | Tests: construct the provider directly. `EventKitSource`: pass `structured: []`. No shared change. |

Not missing, but checked: `EngineState.availableAccountKinds` is filled when the engine is created (`Engine::new`), so the `+` menu does not need the registry (to confirm in the Task 5 test); `AccountKindInfo.isConfigured` replaces `unconfiguredKindIDs`. `PatchMerge.apply` stays in the EventKit adapter (about ten lines; `patchMergeConflicts` does the comparison). `DuplicateRules` and `WidgetTimeline` are not used by the app outside the widgets.

## Plan notes from this pass

- `AccountsController` and its tests are in Task 6, but Task 5 changes `AppCoordinator`, which builds the controller from the registry. Change both together in Task 5.
- Argument labels in enum payloads change (`.join(eventID:)` is `.join(eventId:)`; `.takeoverClosed`, `.snooze`, `.dismiss`, `.addAccount`, `.removeAccount`, `.reauthorizeAccount`, `MergeProvenance.inference(engineId:...)`). The UniFFI error enums have upper-camel cases (`.Source`, `.Denied`).
- `Engine` is the generated class; the app uses the shim `ObservedEngine` for `states`, `events`, `send` and `applySettings { }`.
- `AccountsControllerTests` builds an engine around fake connector kinds and sources. Fake kinds cannot be injected any more. Rewrite it with a fake `HttpTransport` and fake host interfaces, or test the controller against a protocol (Task 5 or 6).
- The live smoke tests in `Packages/CalendarApple/Tests` and `CryptoKitSHA256*` are deleted in Task 3, as planned.

## Per-file map

"Missing" in the class column means the file uses one of the items M1 to M13 (listed in the Missing column).

| File | Symbols | Class | Missing | Task |
|---|---|---|---|---|
| `Apps/macOS/Shared/WidgetSnapshotStore.swift` | WidgetSnapshot | moves into app | - | 7 |
| `Apps/macOS/Sources/AccountNoticeText.swift` | SourceNotice | same | - | 6 |
| `Apps/macOS/Sources/AccountStatusText.swift` | SourceStatus | same | - | 6 |
| `Apps/macOS/Sources/AccountsController.swift` | Connection, ConnectionID, ConnectorKind, ConnectorRegistry, EngineCommand, EngineState, SignInPrompting, SourceNotice, SourceStatus, AccountManager.Status | missing, renamed, renamed (shim alias), replaced by config, same | M4 | 6 (with 5: its constructor takes the registry) |
| `Apps/macOS/Sources/AccountsListBox.swift` | ConnectionID | renamed (shim alias) | - | 6 |
| `Apps/macOS/Sources/AccountsListModel.swift` | Connection, ConnectionID, ConnectorKind, SourceNotice, SourceStatus | missing, renamed (shim alias), replaced by config, same | M4 | 6 |
| `Apps/macOS/Sources/AccountsPane.swift` | ConnectionID | renamed (shim alias) | - | 6 |
| `Apps/macOS/Sources/AppConnectors.swift` | CalDAVConnectorKind, ConnectorRegistry, DiagnosticLog, GoogleConnectorKind, GoogleOAuthConfig, ICalSubscriptionKind, ICloudConnectorKind, MicrosoftConnectorKind, MicrosoftOAuthConfig, NullDiagnosticLog, RetentionWindow | missing, not exposed, replaced by config | M10 | 5 |
| `Apps/macOS/Sources/AppCoordinator.swift` | ConnectedSource, CredentialStore, Engine, EngineCommand, EngineEvent, EngineHost, EngineSettings, EngineState, InferenceStatus, MergedMember, SystemEvent, TakeoverRequest, TimeTugCalendarEvent, WidgetEvent, WidgetSnapshot | missing, moves into app, not exposed, renamed, same | M1 | 5 |
| `Apps/macOS/Sources/AppCredentials.swift` | CredentialStore | renamed | - | 5 |
| `Apps/macOS/Sources/AppDiagnostics.swift` | DiagnosticLog, FanOutDiagnosticLog, RingBufferDiagnosticLog | missing, not exposed | M10 | 5 |
| `Apps/macOS/Sources/AppModel.swift` | CalendarInfo, DayAgenda, InferenceStatus, SourceNotice, SourceStatus, TimeTugCalendarEvent | missing, same | M2 | 6 |
| `Apps/macOS/Sources/CalendarGrouping.swift` | CalendarInfo | missing, same | M2 | 6 |
| `Apps/macOS/Sources/CalendarSections.swift` | CalendarInfo, Connection | missing, same | M2 | 6 |
| `Apps/macOS/Sources/CalendarsPane.swift` | CalendarInfo | missing, same | M2, M3 | 6 |
| `Apps/macOS/Sources/CredentialPrompter.swift` | CredentialField, CredentialHelp, EngineHost, SignInPrompting | renamed, same | - | 5 |
| `Apps/macOS/Sources/CredentialSheet.swift` | CredentialField | same | - | 6 |
| `Apps/macOS/Sources/DropdownView.swift` | MergedMember, SourceStatus, TimeTugCalendarEvent | missing, same | M1, M2 | 6 |
| `Apps/macOS/Sources/EngineAdapters/EngineCommandQueue.swift` | EngineCommand | same | - | 5 |
| `Apps/macOS/Sources/EngineAdapters/EngineModelMirror.swift` | EngineState | same | - | 5 |
| `Apps/macOS/Sources/EngineAdapters/OSLogEngineDiagnostics.swift` | EngineDiagnostic, EngineDiagnosticSink, EngineHost, Level | renamed, renamed (shim alias), same | - | 5 |
| `Apps/macOS/Sources/EngineAdapters/UserDefaultsSettingsStorage.swift` | EngineSettings, SettingsStorage, TakeoverSettings | missing, renamed, same | M3 | 5 |
| `Apps/macOS/Sources/GoogleOAuthSettings.swift` | GoogleOAuthConfig | replaced by config | - | 5 |
| `Apps/macOS/Sources/InferenceAvailability.swift` | InferenceStatus | same | - | 6 |
| `Apps/macOS/Sources/InferenceStatusText.swift` | InferenceStatus | same | - | 6 |
| `Apps/macOS/Sources/MenuBarIconState.swift` | Scheduler, TakeoverLedger, TakeoverSettings, TimeTugCalendarEvent | missing, not exposed, replaced by summary field, same, same (read-only mirror) | M9 | 6 |
| `Apps/macOS/Sources/MergeBadge.swift` | MergeProvenance | same | - | 6 |
| `Apps/macOS/Sources/MicrosoftOAuthSettings.swift` | MicrosoftOAuthConfig | replaced by config | - | 5 |
| `Apps/macOS/Sources/OSLogDiagnosticLog.swift` | DiagnosticEvent, DiagnosticLevel, DiagnosticLog | missing, not exposed | M10 | 5 |
| `Apps/macOS/Sources/OverlayController.swift` | TakeoverRequest | missing, same | M1 | 6 |
| `Apps/macOS/Sources/OverlayView.swift` | TakeoverRequest, TimeTugCalendarEvent | missing, same | M1 | 6 |
| `Apps/macOS/Sources/PopupRowModel.swift` | CalendarInfo, DayAgenda, MergedMember, TimeTugCalendarEvent | missing, same | M1, M2 | 6 |
| `Apps/macOS/Sources/SafeJoin.swift` | JoinURLPolicy | exposed as function | - | 6 |
| `Apps/macOS/Sources/SettingsSearch.swift` | CalendarInfo | missing, same | M2 | 6 |
| `Apps/macOS/Sources/SettingsStore.swift` | EngineSettings, TakeoverSettings | missing, same | M3 | 6 |
| `Apps/macOS/Sources/TimeFormatting.swift` | TimeTugCalendarEvent | missing, same | M1 | 6 |
| `Apps/macOS/Tests/AccountNoticeTextTests.swift` | SourceNotice | same | - | 6 |
| `Apps/macOS/Tests/AccountStatusTextTests.swift` | none by name (uses the module through inference) | same | - | 6 |
| `Apps/macOS/Tests/AccountsControllerTests.swift` | AccountManager, AuthorizationInteraction, AuthorizationMethod, CalendarChange, CalendarDescriptor, CalendarEvent, CalendarSource, Connection, ConnectorKind, ConnectorRegistry, CredentialField, CredentialHelp, CredentialStore, Engine, EngineCommand, EngineHost, EngineSettings, OAuthRedirectSession, Platform, SourceCapabilities, SourceError, SyncStateStore | missing, not exposed, renamed, replaced by config, same | M4 | 6 (with 5: its constructor takes the registry) |
| `Apps/macOS/Tests/AccountsListModelTests.swift` | Connection, ConnectionID, SourceNotice, SourceStatus | missing, renamed (shim alias), same | M4 | 6 |
| `Apps/macOS/Tests/AppConnectorsTests.swift` | GoogleOAuthConfig, MicrosoftOAuthConfig | replaced by config | - | 5 |
| `Apps/macOS/Tests/AppCredentialsTests.swift` | none by name (uses the module through inference) | same | - | 5 |
| `Apps/macOS/Tests/AppDiagnosticsTests.swift` | DiagnosticEvent | missing | M10 | 5 |
| `Apps/macOS/Tests/CalendarGroupingTests.swift` | CalendarInfo | missing, same | M2 | 6 |
| `Apps/macOS/Tests/CalendarSectionsTests.swift` | CalendarInfo, CalendarKind, Connection | missing, same | M2, M4 | 6 |
| `Apps/macOS/Tests/CredentialPrompterTests.swift` | CredentialField, CredentialHelp | same | - | 5 |
| `Apps/macOS/Tests/EngineCommandQueueTests.swift` | EngineCommand | same | - | 5 |
| `Apps/macOS/Tests/EngineModelMirrorTests.swift` | CalendarEvent, CalendarInfo, DayAgenda, EngineState, TimeTugCalendarEvent | missing, same | M1, M11, M2 | 5 |
| `Apps/macOS/Tests/InferenceAvailabilityTests.swift` | InferenceStatus | same | - | 6 |
| `Apps/macOS/Tests/InferenceStatusTextTests.swift` | EngineInfo, InferenceStatus | same | - | 6 |
| `Apps/macOS/Tests/MenuBarIconStateTests.swift` | CalendarEvent, CalendarInfo, ResponseStatus, TakeoverLedger, TakeoverSettings, TimeTugCalendarEvent | missing, replaced by summary field, same, same (read-only mirror) | M1, M2, M3, M9 | 6 |
| `Apps/macOS/Tests/MergeBadgeTests.swift` | none by name (uses the module through inference) | same | - | 6 |
| `Apps/macOS/Tests/OSLogEngineDiagnosticsTests.swift` | EngineDiagnostic, Level | renamed (shim alias), same | - | 5 |
| `Apps/macOS/Tests/PopupLogicTests.swift` | CalendarEvent, CalendarInfo, ConferenceDetector, DayAgenda, MergeProvenance, MergedMember, TakeoverSettings, TimeTugCalendarEvent | exposed as function, missing, same | M1, M11, M13, M2, M3, M8 | 6 |
| `Apps/macOS/Tests/SettingsSearchTests.swift` | CalendarInfo | missing, same | M2 | 6 |
| `Apps/macOS/Tests/SettingsStoreTests.swift` | TakeoverSettings | missing, same | M3 | 6 |
| `Apps/macOS/Tests/SharedInfraTests.swift` | WidgetEvent, WidgetSnapshot | moves into app | - | 7 |
| `Apps/macOS/Tests/TakeoverEditTests.swift` | TakeoverSettings | missing, same | M3 | 6 |
| `Apps/macOS/Tests/TakeoverTextTests.swift` | CalendarEvent, TimeTugCalendarEvent | missing, same | M1 | 6 |
| `Apps/macOS/Tests/TimeFormattingTests.swift` | CalendarEvent, TimeTugCalendarEvent | missing, same | M1 | 6 |
| `Apps/macOS/Tests/UserDefaultsSettingsStorageTests.swift` | EngineSettings, TakeoverSettings | missing, same | M3 | 5 |
| `Apps/macOS/Widgets/AgendaProvider.swift` | WidgetEvent, WidgetSnapshot, WidgetTimeline | moves into app | - | 7 |
| `Apps/macOS/Widgets/NextUpWidget.swift` | JoinURLPolicy, NextUp, WidgetEvent, WidgetTimeline | exposed as function, missing, moves into app | M12 | 7 |
| `Apps/macOS/Widgets/TodayWidget.swift` | JoinURLPolicy, TodayRow, WidgetTimeline | exposed as function, missing, moves into app | M12 | 7 |
| `Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/AppleIntelligence.swift` | EngineInfo, TextGenerator | same | - | 4 |
| `Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/AppleTextGenerator.swift` | TextGenerator, TextGeneratorAvailability | same | - | 4 |
| `Packages/AppleIntelligenceInference/Tests/AppleIntelligenceInferenceTests/AppleTextGeneratorTests.swift` | TextGeneratorAvailability | same | - | 4 |
| `Packages/CalendarApple/Sources/CalendarApple/CryptoKitSHA256.swift` | SHA256Hashing | not exposed | - | 3 |
| `Packages/CalendarApple/Sources/CalendarApple/KeychainCredentialStore.swift` | ConnectionID, CredentialSnapshot, CredentialStore | renamed, renamed (shim alias), same | - | 3 |
| `Packages/CalendarApple/Sources/CalendarApple/LoopbackAuthorizationInteraction.swift` | AuthorizationInteraction, CredentialField, OAuthRedirectSession | renamed, same | - | 3 |
| `Packages/CalendarApple/Sources/CalendarApple/MigratingCredentialStore.swift` | ConnectionID, CredentialSnapshot, CredentialStore | renamed, renamed (shim alias), same | - | 3 |
| `Packages/CalendarApple/Tests/CalendarAppleTests/CryptoKitSHA256Tests.swift` | SHA256Hashing (tests the deleted adapter) | not exposed | - | 3 |
| `Packages/CalendarApple/Tests/CalendarAppleTests/GoogleLiveWriteSmokeTests.swift` | CalendarEvent, CalendarSource, EventDraft, EventPatch, EventRef, EventTiming, GoogleConnectorKind, GoogleOAuthConfig, RecurrenceRule, RecurrenceScope, WritableCalendarSource, WriteError | not exposed, replaced by config, same | - | 3 |
| `Packages/CalendarApple/Tests/CalendarAppleTests/KeychainCredentialStoreTests.swift` | CredentialStore | renamed | - | 3 |
| `Packages/CalendarApple/Tests/CalendarAppleTests/LoopbackTests.swift` | CredentialField, OAuthRedirectSession | renamed, same | - | 3 |
| `Packages/CalendarApple/Tests/CalendarAppleTests/MicrosoftLiveWriteSmokeTests.swift` | CalendarEvent, CalendarSource, EventDraft, EventPatch, EventRef, EventTiming, MicrosoftConnectorKind, MicrosoftOAuthConfig, RecurrenceRule, WritableCalendarSource | not exposed, replaced by config, same | - | 3 |
| `Packages/CalendarApple/Tests/CalendarAppleTests/MigratingCredentialStoreTests.swift` | ConnectionID, CredentialSnapshot, CredentialStore | renamed, renamed (shim alias), same | - | 3 |
| `Packages/EventKitSource/Sources/EventKitSource/EventKitConnectorKind.swift` | AuthorizationInteraction, AuthorizationMethod, CalendarSource, Connection, ConnectorKind, CredentialStore, Platform, SourceError, SyncStateStore | not exposed, renamed, replaced by config, same | - | 4 |
| `Packages/EventKitSource/Sources/EventKitSource/EventKitMapping.swift` | AttendeeRole, Availability, CalendarKind, CalendarProvider, End, EventStatus, Frequency, Participation, RecurrenceRule, Reminder, ReminderTrigger, ReminderType, ResponseStatus, SeriesInfo, StructuredLocation, UIDScope, Weekday, WeekdayOccurrence | missing, renamed (shim alias), same | M6, M7, M8 | 4 |
| `Packages/EventKitSource/Sources/EventKitSource/EventKitSource+Series.swift` | CalendarSeries, RecurrenceSet, SeriesSource, SourceError | not exposed, same | - | 4 |
| `Packages/EventKitSource/Sources/EventKitSource/EventKitSource+Write.swift` | Attempt, Availability, CalendarEvent, EventDraft, EventPatch, EventRef, EventTiming, NotifyPolicy, PatchMerge, RecurrenceScope, ResponseStatus, WritableCalendarSource, WriteError, WriteValidation | exposed as function, missing, not exposed, same | M5 | 4 |
| `Packages/EventKitSource/Sources/EventKitSource/EventKitSource.swift` | Attendee, CalendarChange, CalendarDescriptor, CalendarEvent, CalendarPermissions, CalendarSource, CalendarUserAddress, ConferenceDetector, Connection, RecurrenceScope, SourceCapabilities, SourceError | exposed as function, missing, not exposed, same | M6, M8 | 4 |
| `Packages/EventKitSource/Sources/EventKitSource/EventKitWriteMapping.swift` | AllDay, EventRef, EventTiming, Frequency, NotifyPolicy, RecurrenceRule, RecurrenceScope, Reminder, Weekday, WriteError | exposed as function, missing, same | M7, M8 | 4 |
| `Packages/EventKitSource/Tests/EventKitSourceTests/EventKitConnectorKindTests.swift` | EventKitConnectorKind (deleted or reduced in Task 4) | replaced by config | - | 4 |
| `Packages/EventKitSource/Tests/EventKitSourceTests/EventKitLiveWriteTests.swift` | CalendarEvent, EventDraft, EventPatch, EventRef, EventTiming, RecurrenceRule, WriteError | missing, same | M5 | 4 |
| `Packages/EventKitSource/Tests/EventKitSourceTests/EventKitMappingTests.swift` | Availability, CalendarEvent, CalendarProvider, EventRef, EventTiming, RecurrenceRule, Reminder, StructuredLocation | missing, same | M6, M7, M8 | 4 |
| `Packages/EventKitSource/Tests/EventKitSourceTests/EventKitWriteMappingTests.swift` | EventTiming, RecurrenceRule, Reminder, StructuredLocation, WriteError | missing, same | M5, M7, M8 | 4 |
| `Packages/EventKitSource/Tests/EventKitSourceTests/EventKitWriteTests.swift` | CalendarSource, EventDraft, EventPatch, EventRef, EventTiming, RecurrenceRule, RecurrenceScope, Reminder, WritableCalendarSource, WriteError | missing, not exposed, same | M5 | 4 |
