import TimeTugKit
import XCTest
@testable import TimeTug

/// `AppConnectors` no longer registers connector kinds; it builds the `EngineConfig` that turns them on. These tests pin
/// what the registry tests pinned: Google and Microsoft are offered only when the build has their client, iCloud,
/// CalDAV and the iCal link always, Apple Calendar through the system source.
final class AppConnectorsTests: XCTestCase {
    private let directory = URL(fileURLWithPath: "/tmp/TimeTug-config-test", isDirectory: true)
    private let google = GoogleClient(id: "i", secret: "s")
    private let microsoft = MicrosoftClient(id: "m")

    private func config(google: GoogleClient? = nil, microsoft: MicrosoftClient? = nil, textGeneration: Bool = false) -> EngineConfig {
        AppConnectors.makeConfig(dataDirectory: directory, google: google, microsoft: microsoft, textGeneration: textGeneration, timeZone: "Europe/Berlin")
    }

    func testGoogleIsConfiguredOnlyWhenTheBuildHasAClient() {
        XCTAssertNil(config().googleClient)
        XCTAssertEqual(config(google: google).googleClient, google)
    }

    func testMicrosoftIsConfiguredOnlyWhenTheBuildHasAClient() {
        XCTAssertNil(config().microsoftClient)
        XCTAssertEqual(config(microsoft: microsoft).microsoftClient, microsoft)
    }

    func testEachClientIsIndependentOfTheOther() {
        XCTAssertNil(config(google: google).microsoftClient)
        XCTAssertNil(config(microsoft: microsoft).googleClient)
        let both = config(google: google, microsoft: microsoft)
        XCTAssertEqual(both.googleClient, google)
        XCTAssertEqual(both.microsoftClient, microsoft)
    }

    func testTheFixedPartOfTheConfiguration() {
        let config = config()
        XCTAssertEqual(config.dataDirectory, directory.path)
        XCTAssertEqual(config.platform, .macos)
        XCTAssertTrue(config.systemCalendar, "Apple Calendar is always offered; the EventKit source is passed with it")
        XCTAssertFalse(config.externalTokens)
        XCTAssertEqual(config.timeZone, "Europe/Berlin")
        XCTAssertEqual(config.icalDaysBack, 3)
        XCTAssertEqual(config.icalDaysAhead, 7)
    }

    func testTextGenerationFollowsWhetherAGeneratorIsPassed() {
        XCTAssertFalse(config(textGeneration: false).textGeneration)
        XCTAssertTrue(config(textGeneration: true).textGeneration)
    }

    func testTheTimeZoneDefaultsToTheSystemZone() {
        let config = AppConnectors.makeConfig(dataDirectory: directory, google: nil, microsoft: nil, textGeneration: false)
        XCTAssertEqual(config.timeZone, TimeZone.current.identifier)
    }

    func testTheDataDirectoryIsTheAppSupportDirectory() {
        let config = AppConnectors.makeConfig(dataDirectory: AppSupportFiles.directory(), google: nil, microsoft: nil, textGeneration: false)
        XCTAssertEqual(config.dataDirectory, AppSupportFiles.directory().path)
    }

    // MARK: The engine reads the configuration the way the registry used to be built

    /// A real engine on a throwaway directory with fake host interfaces, for the kinds it offers. The system calendar is
    /// switched off here only because the test passes no EventKit source.
    private func offeredKinds(_ config: EngineConfig) async throws -> [AccountKindInfo] {
        var config = config
        config.dataDirectory = FakeEngineHost.temporaryDirectory().path
        config.systemCalendar = false
        addTeardownBlock { try? FileManager.default.removeItem(atPath: config.dataDirectory) }
        let engine = try ObservedEngine { observer in
            try Engine(config: config, host: FakeEngineHost.interfaces(), observer: observer)
        }
        defer { engine.shutdown() }
        await engine.start()
        // The engine publishes its kinds with its first state, which can arrive after `start()` returns.
        return await engine.firstPublishedState().availableAccountKinds
    }

    func testWithoutClientsGoogleAndMicrosoftAreListedAsUnconfigured() async throws {
        let kinds = try await offeredKinds(config())
        let unconfigured = kinds.filter { !$0.isConfigured }.map(\.id)
        XCTAssertEqual(Set(unconfigured), ["google", "microsoft"])
        XCTAssertEqual(Set(kinds.filter(\.isConfigured).map(\.id)), ["icloud", "caldav", "icalsub"])
    }

    func testWithClientsEveryKindIsConfigured() async throws {
        let kinds = try await offeredKinds(config(google: google, microsoft: microsoft))
        XCTAssertTrue(kinds.allSatisfy(\.isConfigured))
        XCTAssertEqual(Set(kinds.map(\.id)), ["google", "microsoft", "icloud", "caldav", "icalsub"])
    }

    func testICloudCalDAVAndTheICalLinkSignInWithTheCredentialSheet() async throws {
        let kinds = try await offeredKinds(config())
        for id in ["icloud", "caldav", "icalsub"] {
            XCTAssertEqual(kinds.first { $0.id == id }?.authorization, .password, id)
        }
        XCTAssertEqual(kinds.first { $0.id == "icloud" }?.displayName, "iCloud")
        XCTAssertEqual(kinds.first { $0.id == "caldav" }?.displayName, "Other CalDAV")
        XCTAssertEqual(kinds.first { $0.id == "icalsub" }?.displayName, "iCal link")
        XCTAssertEqual(kinds.first { $0.id == "google" }?.authorization, .oauth)
    }
}
