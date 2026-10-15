import Foundation
import TimeTugCore
import TimeTugEngine

/// Copies an `EngineState` into what the Mac views render. Each value is assigned only when it changed, so a
/// countdown tick (a new state with the same agenda) does not redraw the popup or the Settings window.
@MainActor
enum EngineModelMirror {
    static func apply(_ state: EngineState, to model: AppModel) {
        assign(state.agenda, to: \.agenda, of: model)
        assign(state.calendars, to: \.calendars, of: model)
        assign(state.statuses, to: \.statuses, of: model)
        assign(state.notices, to: \.notices, of: model)
        assign(state.sourceNames, to: \.sourceNames, of: model)
        assign(state.candidates, to: \.candidates, of: model)
        assign(state.inferenceStatus, to: \.inferenceStatus, of: model)
        assign(state.settings.takeover.leadTime, to: \.leadTime, of: model)
    }

    /// The text next to the menu bar icon for `state` at `now`.
    static func statusTitle(_ state: EngineState, mode: MenuBarDisplayMode, now: Date) -> String? {
        TimeFormatting.statusTitle(mode: mode, next: state.agenda.next, now: now)
    }

    /// The menu bar icon for `state` at `now`.
    static func iconState(_ state: EngineState, now: Date) -> MenuBarIconState {
        MenuBarIconState.resolve(events: state.events, settings: state.settings.takeover, ledger: state.ledger, now: now)
    }

    private static func assign<Value: Equatable>(
        _ value: Value, to keyPath: ReferenceWritableKeyPath<AppModel, Value>, of model: AppModel
    ) {
        if model[keyPath: keyPath] != value { model[keyPath: keyPath] = value }
    }
}
