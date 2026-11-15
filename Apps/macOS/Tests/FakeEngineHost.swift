import Foundation
import TimeTugKit

/// Fake host interfaces for tests that run a real engine (no network, no Keychain, no calendar store): an in-memory
/// credential store, a settings store, an HTTP transport that serves one iCalendar feed for every address, and an
/// authorization that answers the credential prompt with a link. Tests never touch real accounts.
final class FakeCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: [String: String]] = [:]
    func secrets(connectionId: String) async throws -> [String: String]? { lock.withLock { store[connectionId] } }
    func setSecrets(secrets: [String: String], connectionId: String) async throws { lock.withLock { store[connectionId] = secrets } }
    func removeSecrets(connectionId: String) async throws { lock.withLock { store[connectionId] = nil } }
    func credentialSnapshot(connectionId: String) async throws -> CredentialSnapshot? {
        lock.withLock { store[connectionId] }.map { CredentialSnapshot(secrets: $0, revision: UUID()) }
    }
    func updateRefreshToken(token: String, connectionId: String, expectedRevision: UUID) async throws -> Bool { false }
}

final class FakeSettingsStorage: SettingsStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: EngineSettings
    init(_ settings: EngineSettings = EngineSettings(takeover: TakeoverSettings(), inferenceEnabled: false, systemCalendarEnabled: false)) {
        stored = settings
    }
    func load() -> EngineSettings { lock.withLock { stored } }
    func save(settings: EngineSettings) { lock.withLock { stored = settings } }
}

/// Serves `feed` (an iCalendar document) with status 200 for every request, or `status` when it is not 200.
final class FakeFeedTransport: HttpTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var feedText: String
    private var statusCode: Int64 = 200
    init(feed: String = FakeFeedTransport.emptyFeed) { feedText = feed }
    static let emptyFeed = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\nEND:VCALENDAR\r\n"
    func serve(feed: String, status: Int64 = 200) { lock.withLock { feedText = feed; statusCode = status } }
    func send(request: HttpRequest) async throws -> HttpResponse {
        let (body, status) = lock.withLock { (feedText, statusCode) }
        return HttpResponse(status: status, headers: ["content-type": "text/calendar"], body: Data(body.utf8))
    }
}

/// An authorization that never opens a browser; the credential prompt goes to `prompt`.
final class FakeAuthorization: AuthorizationInteraction, @unchecked Sendable {
    typealias Prompt = @Sendable ([CredentialField]) async throws -> [String: String]
    private let prompt: Prompt
    init(prompt: @escaping Prompt = { _ in throw HostError.Cancelled }) { self.prompt = prompt }
    func beginOauthRedirect() async throws -> OAuthRedirectHandle { throw HostError.Denied }
    func promptCredentials(fields: [CredentialField]) async throws -> [String: String] { try await prompt(fields) }
}

final class FakeSignIn: SignInPrompting, @unchecked Sendable {
    func prepare(title: String, help: CredentialHelp?, values: [String: String], error: String?) async {}
    func lastNonSecretValues() async -> [String: String]? { nil }
}

enum FakeEngineHost {
    static func interfaces(
        authorization: FakeAuthorization = FakeAuthorization(), signIn: any SignInPrompting = FakeSignIn(),
        settings: FakeSettingsStorage = FakeSettingsStorage(), http: FakeFeedTransport = FakeFeedTransport(),
        credentials: FakeCredentialStore = FakeCredentialStore()
    ) -> EngineHostInterfaces {
        EngineHostInterfaces(credentials: credentials, authorization: authorization, signIn: signIn, settings: settings, http: http)
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("timetug-app-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
