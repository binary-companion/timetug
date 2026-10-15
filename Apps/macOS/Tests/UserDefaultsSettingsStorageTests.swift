import TimeTugCore
import TimeTugEngine
import XCTest
@testable import TimeTug

/// The engine's settings storage must read and write exactly what the Mac app's `SettingsStore` always did, so an
/// upgrade keeps every setting and a Control Center toggle still wins.
@MainActor
final class UserDefaultsSettingsStorageTests: XCTestCase {
    private func freshDefaults() -> KeyRecordingDefaults {
        let name = "TimeTugTests-\(UUID().uuidString)"
        let defaults = KeyRecordingDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func storage(_ defaults: UserDefaults) -> UserDefaultsSettingsStorage {
        UserDefaultsSettingsStorage(defaults: defaults, shared: SharedSettings(defaults: defaults))
    }

    func testAnEmptySuiteLoadsTheDefaults() {
        XCTAssertEqual(storage(freshDefaults()).load(),
                       EngineSettings(takeover: TakeoverSettings(), inferenceEnabled: false, systemCalendarEnabled: true))
    }

    /// A suite as the current Mac app leaves it: the takeover JSON, the legacy keys and the shared booleans.
    func testASuiteWrittenByTheCurrentAppLoadsTheSameValues() {
        let defaults = freshDefaults()
        defaults.set(Data(#"""
        {"leadTime":300,"takeoverCalendarKeys":["eventkit\/work","google-1\/primary"],"hiddenCalendarKeys":["eventkit\/spam"],
         "requireConferenceLink":true,"requireOtherAttendees":false,"skipAllDayEvents":true,"enabled":true}
        """#.utf8), forKey: "takeoverSettings.v1")
        defaults.set(false, forKey: "dedupInference.v1")
        defaults.set(false, forKey: "eventKitEnabled.v1")
        defaults.set(false, forKey: "shared.skipAllDay")
        defaults.set(false, forKey: "shared.enableTug")
        defaults.set(true, forKey: "shared.useIntelligence")

        let loaded = storage(defaults).load()
        var expected = TakeoverSettings()
        expected.leadTime = 300
        expected.takeoverCalendarKeys = ["eventkit/work", "google-1/primary"]
        expected.hiddenCalendarKeys = ["eventkit/spam"]
        expected.requireConferenceLink = true
        expected.skipAllDayEvents = false   // the shared suite wins over the JSON
        expected.enabled = false
        XCTAssertEqual(loaded, EngineSettings(takeover: expected, inferenceEnabled: true, systemCalendarEnabled: false))
    }

    func testTheLegacyInferenceKeyIsUsedOnlyWithoutASharedValue() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "dedupInference.v1")
        XCTAssertTrue(storage(defaults).load().inferenceEnabled)
        defaults.set(false, forKey: "shared.useIntelligence")
        XCTAssertFalse(storage(defaults).load().inferenceEnabled)
    }

    func testASavedDisabledFlagFromAnOlderVersionTurnsTugOff() {
        let defaults = freshDefaults()
        defaults.set(Data(#"{"disabled":true,"skipSoloEvents":true}"#.utf8), forKey: "takeoverSettings.v1")
        let loaded = storage(defaults).load()
        XCTAssertFalse(loaded.takeover.enabled)
        XCTAssertTrue(loaded.takeover.requireOtherAttendees)
    }

    func testSaveWritesTheKeysThatChangedAndRoundTrips() {
        let defaults = freshDefaults()
        let storage = storage(defaults)
        var settings = storage.load()
        settings.takeover.leadTime = 120
        settings.takeover.enabled = false
        settings.inferenceEnabled = true
        settings.systemCalendarEnabled = false
        defaults.isRecording = true
        storage.save(settings)
        XCTAssertEqual(Set(defaults.recorded), [
            "takeoverSettings.v1", "dedupInference.v1", "eventKitEnabled.v1", "shared.enableTug", "shared.useIntelligence",
        ])
        XCTAssertEqual(self.storage(defaults).load(), settings)
    }

    func testAnUnrelatedEditDoesNotOverwriteAPendingExternalToggle() {
        let defaults = freshDefaults()
        let storage = storage(defaults)
        var settings = storage.load()
        defaults.set(false, forKey: "shared.enableTug")
        defaults.set(false, forKey: "shared.skipAllDay")
        defaults.set(true, forKey: "shared.useIntelligence")
        settings.takeover.leadTime = 300
        defaults.isRecording = true
        storage.save(settings)
        XCTAssertEqual(defaults.recorded, ["takeoverSettings.v1"])
        let reloaded = storage.load()
        XCTAssertFalse(reloaded.takeover.enabled)
        XCTAssertFalse(reloaded.takeover.skipAllDayEvents)
        XCTAssertTrue(reloaded.inferenceEnabled)
        XCTAssertEqual(reloaded.takeover.leadTime, 300)
    }

    func testSavingTheLoadedValueWritesNothing() {
        let defaults = freshDefaults()
        let storage = storage(defaults)
        let settings = storage.load()
        defaults.isRecording = true
        storage.save(settings)
        XCTAssertEqual(defaults.recorded, [])
    }

    func testSeedingWritesTheSharedSuite() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "dedupInference.v1")
        let storage = storage(defaults)
        storage.seedSharedSuite(from: storage.load())
        XCTAssertEqual(defaults.object(forKey: "shared.useIntelligence") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "shared.skipAllDay") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "shared.enableTug") as? Bool, true)
    }
}

/// Records the keys written after `isRecording` is switched on.
private final class KeyRecordingDefaults: UserDefaults {
    var isRecording = false
    var recorded: [String] = []

    override func set(_ value: Any?, forKey defaultName: String) {
        if isRecording { recorded.append(defaultName) }
        super.set(value, forKey: defaultName)
    }
    override func set(_ value: Bool, forKey defaultName: String) {
        if isRecording { recorded.append(defaultName) }
        super.set(value, forKey: defaultName)
    }
    override func removeObject(forKey defaultName: String) {
        if isRecording { recorded.append(defaultName) }
        super.removeObject(forKey: defaultName)
    }
}
