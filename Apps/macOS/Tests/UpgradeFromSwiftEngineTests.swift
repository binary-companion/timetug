import TimeTugKit
import XCTest
@testable import TimeTug

/// Review Focus 1: a user upgrading from the last Swift release keeps everything. A data directory in the 1.x file
/// formats (`Fixtures/legacy-data`, copies of the libraries' own fixtures) is opened by the real engine, built through
/// the app's own factory, with fake host interfaces and no network, Keychain or calendar store.
final class UpgradeFromSwiftEngineTests: XCTestCase {
    private static let fixtureDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("Fixtures/legacy-data", isDirectory: true)
    private static let dataFiles = ["accounts.json", "sync-state.json", "takeover-ledger.json", "dedup-state.json"]

    private static func state(of engine: ObservedEngine, matching condition: @escaping @Sendable (EngineState) -> Bool) async throws -> EngineState {
        try await withThrowingTaskGroup(of: EngineState?.self) { group in
            group.addTask {
                for await state in engine.states where condition(state) { return state }
                return nil
            }
            group.addTask { try await Task.sleep(for: .seconds(15)); return nil }
            defer { group.cancelAll() }
            let first = try await group.next()
            return try XCTUnwrap(first ?? nil, "no state matched within 15 s; last: \(engine.currentState().accounts.count) accounts")
        }
    }

    private func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    private func json(_ url: URL) throws -> Any { try JSONSerialization.jsonObject(with: read(url)) }

    func testTheEngineReadsAnExistingDataDirectoryInPlace() async throws {
        // The data directory: a copy of the fixture's data files.
        let directory = FakeEngineHost.temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        for name in Self.dataFiles {
            try FileManager.default.copyItem(
                at: Self.fixtureDirectory.appendingPathComponent(name), to: directory.appendingPathComponent(name))
        }
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(before, Self.dataFiles.sorted())

        // UserDefaults as the last release left it: the takeover JSON under today's key.
        let suiteName = "TimeTugTests-upgrade-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let takeoverJSON = try read(Self.fixtureDirectory.appendingPathComponent("userdefaults-takeoverSettings.v1.json"))
        defaults.set(takeoverJSON, forKey: UserDefaultsSettingsStorage.takeoverKey)
        defaults.set(false, forKey: UserDefaultsSettingsStorage.inferenceKey)
        defaults.set(false, forKey: UserDefaultsSettingsStorage.eventKitKey)
        let storage = UserDefaultsSettingsStorage(defaults: defaults, shared: SharedSettings(defaults: defaults))

        // The engine, through the app's own factory, with both OAuth clients present.
        var config = AppConnectors.makeConfig(
            dataDirectory: directory, google: GoogleClient(id: "test-id", secret: "test-secret"),
            microsoft: MicrosoftClient(id: "test-id"), textGeneration: false, timeZone: "Europe/Berlin")
        config.systemCalendar = false
        let interfaces = EngineHostInterfaces(
            credentials: FakeCredentialStore(), authorization: FakeAuthorization(), signIn: FakeSignIn(),
            settings: storage, http: FakeFeedTransport())
        let engine = try ObservedEngine { observer in try Engine(config: config, host: interfaces, observer: observer) }
        var isShutDown = false
        defer { if !isShutDown { engine.shutdown() } }
        await engine.start()
        // The engine loads its files after `start` returns and publishes the result as a state.
        let state = try await Self.state(of: engine, matching: { !$0.accounts.isEmpty })

        // Accounts: every kind, with its display name.
        let accounts = Dictionary(uniqueKeysWithValues: state.accounts.map { ($0.kindId, $0.displayName) })
        XCTAssertEqual(state.accounts.count, 5)
        XCTAssertEqual(accounts, [
            "google": "alice@example.com", "microsoft": "Carol@Contoso.com", "icloud": "alice@icloud.com",
            "caldav": "bob@caldav.fastmail.com", "icalsub": "Team offsites",
        ])
        XCTAssertEqual(Set(state.accounts.map(\.connectionId)), [
            "0B9C1A7E-6A55-4F0B-9E43-5C1F7D2A9B10", "5D2E8F4A-1B3C-4D6E-8F90-A1B2C3D4E5F6",
            "9A8B7C6D-5E4F-4A3B-2C1D-0E9F8A7B6C5D", "1F2E3D4C-5B6A-4798-8A9B-0C1D2E3F4A5B",
            "C0FFEE00-1234-4567-89AB-CDEF01234567",
        ])
        XCTAssertEqual(state.accounts.first { $0.kindId == "icalsub" }?.config["host"], "calendar.example.org")
        XCTAssertTrue(state.availableAccountKinds.allSatisfy(\.isConfigured))

        // Behaviour settings: the fixture's legacy takeover JSON ("disabled", "skipSoloEvents", leadTime 120).
        XCTAssertEqual(state.settings, storage.load())
        XCTAssertFalse(state.settings.takeover.enabled)
        XCTAssertTrue(state.settings.takeover.requireOtherAttendees)
        XCTAssertEqual(state.settings.takeover.leadTime, 120)
        XCTAssertFalse(state.settings.inferenceEnabled)
        XCTAssertFalse(state.settings.systemCalendarEnabled)

        // The takeover ledger: the fixture's four keys.
        XCTAssertEqual(state.ledger.keyCount, 4)

        // One settings change and one dismiss.
        await engine.applySettings { $0.takeover.leadTime = 300 }
        await engine.send(.dismiss(eventId: "s/a/1800000000"))
        engine.shutdown()
        isShutDown = true
        let saved = try JSONDecoder().decode(TakeoverSettings.self, from: try XCTUnwrap(defaults.data(forKey: UserDefaultsSettingsStorage.takeoverKey)))
        XCTAssertEqual(saved.leadTime, 300)

        // Nothing was removed and every original file still parses.
        let after = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        for name in Self.dataFiles {
            XCTAssertTrue(after.contains(name), "\(name) was removed")
            XCTAssertNoThrow(try json(directory.appendingPathComponent(name)), "\(name) no longer parses")
        }

        // The accounts are untouched, the ledger keeps its four keys, and the dedup lesson survives.
        XCTAssertEqual(try read(directory.appendingPathComponent("accounts.json")),
                       try read(Self.fixtureDirectory.appendingPathComponent("accounts.json")))
        let ledger = try XCTUnwrap(json(directory.appendingPathComponent("takeover-ledger.json")) as? [String: Any])
        XCTAssertGreaterThanOrEqual((ledger["records"] as? [String: Any])?.count ?? 0, 4)
        let dedup = try XCTUnwrap(json(directory.appendingPathComponent("dedup-state.json")) as? [String: Any])
        let lessons = ((dedup["lessons"] as? [String: Any])?["lessons"] as? [[String: Any]]) ?? []
        XCTAssertEqual(lessons.count, 1)
        XCTAssertEqual(lessons.first?["titleA"] as? String, "sample a")
        XCTAssertEqual(lessons.first?["titleB"] as? String, "sample b")
    }
}
