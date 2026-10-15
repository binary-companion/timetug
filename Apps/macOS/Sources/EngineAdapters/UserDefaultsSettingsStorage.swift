import Foundation
import TimeTugCore
import TimeTugEngine

/// The engine's behaviour settings over the keys the Mac app has always used, so an upgrade changes nothing:
/// `takeoverSettings.v1` (JSON), `dedupInference.v1`, `eventKitEnabled.v1`, and the shared-suite booleans that
/// Control Center toggles also edit. The shared booleans win over the stored JSON and the legacy inference key.
///
/// One instance serves the engine and `SettingsStore`. It remembers the last value it loaded or saved, so `save`
/// writes only the keys whose value changed: an unrelated edit must not overwrite a pending external toggle.
final class UserDefaultsSettingsStorage: SettingsStorage, @unchecked Sendable {
    static let takeoverKey = "takeoverSettings.v1"
    static let inferenceKey = "dedupInference.v1"
    static let eventKitKey = "eventKitEnabled.v1"

    private let defaults: UserDefaults
    let shared: SharedSettings
    private let lock = NSLock()
    private var lastKnown: EngineSettings?

    init(defaults: UserDefaults, shared: SharedSettings) {
        self.defaults = defaults
        self.shared = shared
    }

    func load() -> EngineSettings {
        var takeover = defaults.data(forKey: Self.takeoverKey)
            .flatMap { try? JSONDecoder().decode(TakeoverSettings.self, from: $0) } ?? TakeoverSettings()
        if let skip = shared.bool(.skipAllDay) { takeover.skipAllDayEvents = skip }
        if let enabled = shared.bool(.enableTug) { takeover.enabled = enabled }
        let loaded = EngineSettings(
            takeover: takeover,
            inferenceEnabled: shared.bool(.useIntelligence) ?? defaults.bool(forKey: Self.inferenceKey),
            systemCalendarEnabled: defaults.object(forKey: Self.eventKitKey) as? Bool ?? true)
        lock.withLock { lastKnown = loaded }
        return loaded
    }

    func save(_ settings: EngineSettings) {
        let previous: EngineSettings? = lock.withLock {
            defer { lastKnown = settings }
            return lastKnown
        }
        if previous?.takeover != settings.takeover, let data = try? JSONEncoder().encode(settings.takeover) {
            defaults.set(data, forKey: Self.takeoverKey)
        }
        if previous?.inferenceEnabled != settings.inferenceEnabled {
            defaults.set(settings.inferenceEnabled, forKey: Self.inferenceKey)
            shared.set(settings.inferenceEnabled, for: .useIntelligence)
        }
        if previous?.systemCalendarEnabled != settings.systemCalendarEnabled {
            defaults.set(settings.systemCalendarEnabled, forKey: Self.eventKitKey)
        }
        if previous?.takeover.skipAllDayEvents != settings.takeover.skipAllDayEvents {
            shared.set(settings.takeover.skipAllDayEvents, for: .skipAllDay)
        }
        if previous?.takeover.enabled != settings.takeover.enabled {
            shared.set(settings.takeover.enabled, for: .enableTug)
        }
    }

    /// The one-time migration `SettingsStore` has always run at launch: seed the suite so widgets and controls see
    /// the current values.
    func seedSharedSuite(from settings: EngineSettings) {
        shared.set(settings.takeover.skipAllDayEvents, for: .skipAllDay)
        shared.set(settings.takeover.enabled, for: .enableTug)
        shared.set(settings.inferenceEnabled, for: .useIntelligence)
    }
}
