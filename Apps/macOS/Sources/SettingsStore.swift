import Foundation
import TimeTugCore
import TimeTugEngine

enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case iconOnly, nextMeeting, countdown

    var title: String {
        switch self {
        case .iconOnly: "Icon only"
        case .nextMeeting: "Next meeting"
        case .countdown: "Countdown only"
        }
    }
}

/// The Mac app's settings. Presentation preferences (menu bar mode, appearance, popup card style) live here; the
/// behaviour settings (takeover rules, inference, the Apple Calendar switch) belong to the engine and are mirrored
/// here for the views. Both are stored in UserDefaults under the keys the app has always used.
///
/// Once `AppCoordinator` attaches the engine (`sendBehaviourChange`, `requestExternalReload`), a behaviour edit is
/// sent to the engine, which saves it through the shared `UserDefaultsSettingsStorage`, and the engine's state flows
/// back through `applyEngineSettings`. Detached (tests, before launch finishes), edits are saved directly.
@MainActor
final class SettingsStore: ObservableObject {
    /// One edit of a behaviour setting, for the engine.
    enum BehaviourChange {
        case takeover(TakeoverSettings)
        case inference(Bool)
        case systemCalendar(Bool)
    }

    private static let modeKey = "menuBarMode.v1"
    private static let appearanceKey = "appearanceMode.v1"
    private static let cardStyleKey = "popupCardStyle.v1"
    private let defaults: UserDefaults
    let shared: SharedSettings
    /// The engine's settings storage over the same suite; the coordinator hands it to the engine.
    let storage: UserDefaultsSettingsStorage
    /// True while values that came from outside (the suite or the engine) are assigned; they are not sent back.
    private var isApplyingSharedValues = false

    /// Set by the coordinator: behaviour edits go to the engine instead of being saved here.
    var sendBehaviourChange: ((BehaviourChange) -> Void)?
    /// Set by the coordinator: `reloadFromShared()` asks the engine to re-read the storage.
    var requestExternalReload: (() -> Void)?

    @Published var takeover: TakeoverSettings {
        didSet { behaviourDidChange(.takeover(takeover)) }
    }
    @Published var menuBarMode: MenuBarDisplayMode {
        didSet { defaults.set(menuBarMode.rawValue, forKey: Self.modeKey) }
    }
    @Published var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Self.appearanceKey) }
    }
    @Published var popupCardStyle: PopupCardStyle {
        didSet { defaults.set(popupCardStyle.rawValue, forKey: Self.cardStyleKey) }
    }
    @Published var eventKitEnabled: Bool {
        didSet { behaviourDidChange(.systemCalendar(eventKitEnabled)) }
    }
    @Published var inferenceEnabled: Bool {
        didSet { behaviourDidChange(.inference(inferenceEnabled)) }
    }

    init(defaults: UserDefaults = .standard, shared: SharedSettings? = nil) {
        self.defaults = defaults
        let shared = shared ?? SharedSettings(defaults: defaults)
        self.shared = shared
        let storage = UserDefaultsSettingsStorage(defaults: defaults, shared: shared)
        self.storage = storage
        let loaded = storage.load()
        self.takeover = loaded.takeover
        self.menuBarMode = defaults.string(forKey: Self.modeKey)
            .flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .iconOnly
        self.appearanceMode = defaults.string(forKey: Self.appearanceKey)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .auto
        self.popupCardStyle = defaults.string(forKey: Self.cardStyleKey)
            .flatMap(PopupCardStyle.init(rawValue:))
            .flatMap { PopupCardStyle.available.contains($0) ? $0 : nil } ?? PopupCardStyle.defaultStyle
        self.inferenceEnabled = loaded.inferenceEnabled
        self.eventKitEnabled = loaded.systemCalendarEnabled
        // One-time migration: seed the suite so widgets and controls see current values.
        storage.seedSharedSuite(from: loaded)
    }

    /// The behaviour settings as this store currently shows them.
    var behaviour: EngineSettings {
        EngineSettings(takeover: takeover, inferenceEnabled: inferenceEnabled, systemCalendarEnabled: eventKitEnabled)
    }

    /// Applies values a Control Center toggle wrote to the shared suite while the app was running. With the engine
    /// attached, the engine re-reads the storage and its state updates this store.
    func reloadFromShared() {
        if let requestExternalReload { return requestExternalReload() }
        applyExternal(storage.load())
    }

    /// Mirrors the engine's behaviour settings without sending them back.
    func applyEngineSettings(_ settings: EngineSettings) {
        applyExternal(settings)
    }

    private func applyExternal(_ settings: EngineSettings) {
        isApplyingSharedValues = true
        defer { isApplyingSharedValues = false }
        if settings.takeover != takeover { takeover = settings.takeover }
        if settings.inferenceEnabled != inferenceEnabled { inferenceEnabled = settings.inferenceEnabled }
        if settings.systemCalendarEnabled != eventKitEnabled { eventKitEnabled = settings.systemCalendarEnabled }
    }

    private func behaviourDidChange(_ change: BehaviourChange) {
        guard !isApplyingSharedValues else { return }
        if let sendBehaviourChange { sendBehaviourChange(change) } else { storage.save(behaviour) }
    }
}
