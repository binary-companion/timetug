# Phase 3: the `TimeTugEngine`

Status: draft for the owner's review (2026-10-15). Parent: [program design](2026-10-09-windows-program-design.md), roadmap row 3 and section 2. The program design wins where the two disagree, except for the amendments in "Decisions" below. Precedent: [phase 2](2026-10-15-phase-2-timetug-shared-design.md), whose repository, release and bump chain this phase uses.

## Purpose

Move the platform-neutral "what and when" of TimeTug out of the Mac app into a new `TimeTugEngine` module in `binary-companion/timetug-shared`, so that the C interface (phase 4) and the Windows app (phase 5) reuse it, and move the Mac app onto it with no change in behaviour.

**Principle (owner, 2026-10-15):** at its core TimeTug does the same thing on every platform, and each platform must still feel like a real native application. The engine decides *what and when*; each front end owns *how it looks and feels*. Presentation is never in the engine.

Success means: `TimeTugEngine` builds and passes its tests on macOS, Linux, Windows x64 and Windows ARM64; a conformance suite drives a real engine against fake host services and a fake clock; the Mac app runs on the engine with its existing unit tests green, the manual checklist passed and a beta cycle completed; and a `timetug-shared` release reaches `timetug` through the existing automatic bump chain.

## Not in this phase

- No `TimeTugEngineProtocol`, JSON envelope, golden fixtures, C ABI (`TimeTugEngineC`) or NuGet package (phase 4). The Swift API is designed so that phase 4 maps onto it one to one (commands as one enum, state and events as value types), but no Codable contract is published.
- No Windows code, no WAM sign-in (phase 6), no on-device AI on Windows (phase 8).
- No behaviour change in the Mac app and no new Mac feature.
- No change to Core's or Bridge's public behaviour.

## Decisions

| Topic | Decision |
|---|---|
| Migration approach | **B: build the whole engine beside the Mac code, then switch once** (owner, 2026-10-15), against option A (move one helper per pull request). Mitigation for B's risk: a conformance suite that ports today's `AppCoordinator` behaviours, and a switch pull request that is mostly deletion plus thin mirrors. |
| Concurrency | One `public actor Engine`. No main-thread assumption; no `Timer`, `RunLoop`, Combine or AppKit in the module. Timers are `Task.sleep` through the injected clock. |
| Clock | `EngineClock` protocol (`now()`, `sleep(until:)`) with a default `SystemClock` and a test fake. Hosts do not supply time in 1.0; they report system events (wake, clock change, time-zone change, network change, display change) and the engine recomputes. Core still never reads the clock. |
| Time zone and calendar | Read from the system by the engine; the host's time-zone-change event makes it re-read. |
| Settings split | The engine owns **behaviour settings**: takeover rules, lead time, skip all-day, inference on/off, the system-calendar (EventKit) switch. **Presentation preferences stay in each front end** (Mac: menu bar mode, appearance, popup card style). |
| Settings persistence | `SettingsStorage` seam; the Mac adapter keeps today's `UserDefaults` suite and keys so upgrades are invisible, and forwards widget and Control Center edits as a system event. |
| Data files | The engine owns the layout (`accounts.json`, `sync-state.json`, `takeover-ledger.json`, `dedup-state.json`) under a host-supplied directory, with today's names. |
| Text generation | New `TextGenerator` seam (`availability()`, `generate(prompt)`). Prompt building, answer parsing, the adjudicator and a prompt profile per model live in the engine. `AppleIntelligenceInference` shrinks to the Apple adapter. |
| Diagnostics | A host-supplied sink taking a `DiagnosticEvent`; the Mac maps it to OSLog with today's privacy rules (titles are never logged). |

## The module

```
timetug-shared/
  Package.swift                 # adds product TimeTugEngine (library); depends on TimeTugCore,
                                #   CalendarBridge, CalendarConnectors (Foundation only)
  Sources/TimeTugEngine/
    Engine.swift                # the actor, command handling, state and event streams
    EngineCommand.swift         # one enum of inputs
    EngineState.swift           # snapshot value type, revisioned, no display strings
    EngineEvent.swift           # takeoverDue, takeoverWithdrawn, widgetSnapshot, diagnostic
    EngineHost.swift            # the seams below, bundled
    EngineClock.swift           # protocol, SystemClock
    Accounts/                   # account lifecycle, reconcile, refresh coalescing
    Persistence/                # ledger, dedup state, settings (over the seams)
    Scheduling/                 # scheduler wiring, fire guard, launch acknowledgement, UI tick policy
    Inference/                  # PromptBuilder, answer parsing, adjudicator, TextGenerator
  Tests/TimeTugEngineTests/     # unit tests and the conformance suite
```

It imports Foundation, `TimeTugCore`, `CalendarBridge` and the connector library only, and builds on every platform `timetug-shared` supports. The architecture check gains the rule: the engine imports nothing platform-specific (no AppKit, Combine, OSLog, Network, WidgetKit).

### What moves from the Mac app

| Today (Mac app) | In the engine |
|---|---|
| `AppCoordinator` orchestration (refresh, apply, ledger bookkeeping, fire, rearm, inference resolve, dedup actions) | `Engine` |
| `AccountsController` (account lifecycle, re-sign-in, buildFailures) | `Accounts/`; the SwiftUI `ObservableObject` stays in the Mac app as a mirror |
| `SourceReconciler`, `SourceRefreshCoordinator` | `Accounts/` |
| `LedgerStore`, `DedupStateStore` | `Persistence/` |
| Behaviour part of `SettingsStore` | `Persistence/` |
| `UITickPolicy`, `LaunchAcknowledgement` | `Scheduling/` |
| `PromptBuilder` and the adjudicator wiring (`AppleIntelligenceInference`) | `Inference/` |

What stays in the Mac app: AppKit and SwiftUI UI, status item, popover, overlay, widgets and Control Center controls (the engine emits `widgetSnapshot`; the Mac writes the file and reloads timelines), Sparkle, KeyboardShortcuts, instance arbitration, the presentation settings, and the EventKit and Apple Intelligence adapters.

## The API

```swift
public actor Engine {
    public init(host: EngineHost)
    public var states: AsyncStream<EngineState> { get }   // latest value with a revision
    public var events: AsyncStream<EngineEvent> { get }
    public func start() async
    public func send(_ command: EngineCommand) async
}
```

**Commands:** start; refresh; add, remove and reconnect account; apply settings change; takeover presented (on screen or as the fallback toast) and closed; join, snooze N minutes, dismiss, test tug; merge, unmerge, separate, forget corrections; system event.

**State:** day agenda, account and source statuses, behaviour settings, inference status, next takeover. **Events:** `takeoverDue(TakeoverRequest)`, `takeoverWithdrawn`, `widgetSnapshot`, `diagnostic`. The engine produces no display strings.

The takeover fire guard keeps today's rule: a second takeover waits while one is reported visible, and the ledger and the current snapshot are re-checked before a takeover is emitted.

## Host seams

| Seam | Type | Mac supplies |
|---|---|---|
| Data directory | `EngineConfig` | Application Support folder (today's path) |
| Settings storage | new `SettingsStorage` | adapter over the app-group `UserDefaults` suite, today's keys |
| Credentials | existing `CredentialStore` | Keychain (shared group) |
| Sign-in | existing `AuthorizationInteraction`, `OAuthRedirectSession` | web-authentication sheet plus loopback |
| HTTP | existing `HTTPTransport` | `URLSession` |
| Sync state | existing `SyncStateStore` | engine's file store over the data directory |
| Connectors | existing `ConnectorRegistry` | library kinds plus EventKit |
| Text generation | new `TextGenerator` | Apple Intelligence adapter |
| Diagnostics | new sink | OSLog |
| Clock | `EngineClock` | default `SystemClock` (not supplied) |

## Error handling

- A failing source never fails the engine; it becomes a status on that source and the others keep running.
- A corrupt or unreadable state file loads as empty and emits a `diagnostic`; nothing is fatal.
- A failing `TextGenerator` call is "no verdict" and the pair stays pending. "Temporarily unavailable" keeps pairs pending without a retry loop. The bounded resolve passes (today `maxResolvePasses = 10`) stay.
- An invalid command produces a `diagnostic`, never a crash or a silent drop.

## Testing

- **Unit tests** per component with fakes (clock, in-memory storage, fake connectors, fake `TextGenerator`), run by the existing `timetug-shared` CI on macOS, Linux, Windows x64 and Windows ARM64. The Windows test count guard (`scripts/ci/count-swift-tests.py`) is updated.
- **Conformance suite:** a real engine and a scripted timeline asserting exact states and events. It ports the behaviours `AppCoordinator` covers today: launch acknowledgement, fire guard while an overlay is visible, snooze and expiry, late takeover after wake, refresh coalescing, dedup actions and persistence, ledger pruning, settings applied from outside, inference unavailable and resumed.
- **Dedup benchmark:** the fixtures and prompt building already live with `DedupBenchmark`; the model runner stays a host concern.
- **Mac:** the app's existing unit tests, `docs/manual-tests/macos-checklist.md` in full, and a beta cycle before release.

## Sequence

1. Engine module, seams and the moved components with their tests, in `timetug-shared` pull requests (the engine is not yet used by anything).
2. The `Engine` actor, state and event streams, and the conformance suite.
3. Prompt building, parsing, adjudicator and the `TextGenerator` seam.
4. Release `timetug-shared`; the bump chain opens the bump pull request in `timetug`.
5. **Switch pull request in `timetug`:** `AppCoordinator` becomes a thin host over the engine; Mac adapters (settings, text generation, diagnostics) and SwiftUI mirrors are added; the moved files and their tests are deleted; `AppleIntelligenceInference` shrinks. Full CI including the App Store build and the DMG must pass.
6. Mac beta, manual checklist, release. The owner verifies the beta and publishes.

## Risks

- **The switch pull request is large (decision B).** Mitigation: conformance suite first; the pull request is deletion plus mirrors; no logic changes inside it; the existing Mac tests must pass unmodified except for moved files.
- **Settings keys and file names drifting** would silently reset a user's state on upgrade. Mitigation: tests that load fixtures written by the current Mac app.
- **Actor reentrancy** around the awaits in refresh and resolve could reorder publications. Mitigation: revision numbers on state (as `CalendarSnapshot.revision` today) and the conformance suite.
- **Windows-only Foundation differences** (file locking, atomic write, `Task.sleep` accuracy). Mitigation: Windows jobs run the engine tests from step 1.

## Open items

None.
