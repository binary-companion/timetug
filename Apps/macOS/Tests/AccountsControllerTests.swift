import CalendarCore
import TimeTugCore
import TimeTugEngine
import XCTest
@testable import TimeTug

private struct PrompterInteraction: AuthorizationInteraction {
    let prompter: CredentialPrompter
    func beginOAuthRedirect() async throws -> any OAuthRedirectSession { throw CalendarCore.SourceError.invalidResponse("unused") }
    func promptCredentials(_ fields: [CredentialField]) async throws -> [String: String] { try await prompter.prompt(fields) }
}

/// A source that never has calendars or events, for accounts the engine builds in these tests.
private struct EmptyLibrarySource: CalendarCore.CalendarSource {
    let id: String
    var displayName: String { "Empty" }
    var capabilities: SourceCapabilities { SourceCapabilities() }
    func calendars() async throws -> [CalendarDescriptor] { [] }
    func events(in interval: DateInterval) async throws -> [CalendarCore.CalendarEvent] { [] }
    func changes() -> AsyncStream<CalendarChange> { AsyncStream { $0.finish() } }
}

/// A `.password` kind like "Other CalDAV": it prompts, then accepts only `goodPassword`.
private final class PasswordKind: ConnectorKind, CredentialPromptHelp, @unchecked Sendable {
    let id = "caldav"
    let displayName = "Other CalDAV"
    let supportedPlatforms = Platform.macOS
    let fields = [
        CredentialField(key: "serverURL", label: "Server address"), CredentialField(key: "username", label: "User name"),
        CredentialField(key: "password", label: "Password", isSecret: true),
    ]
    var authorization: AuthorizationMethod { .password(fields: fields) }
    let credentialHelp: CredentialHelp? = CredentialHelp(text: "Use the address your provider gives you.")
    let goodPassword = "right"

    func authorize(using interaction: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection {
        let values = try await interaction.promptCredentials(fields)
        guard values["password"] == goodPassword else { throw CalendarCore.SourceError.authExpired }
        return Connection(kindID: id, connectionID: "p1", displayName: values["username"] ?? "",
                          config: ["serverURL": values["serverURL"] ?? "", "username": values["username"] ?? ""])
    }
    func reauthorize(_ connection: Connection, using interaction: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection {
        connection
    }
    func makeSource(for connection: Connection, credentials: any CredentialStore, syncState: any SyncStateStore) throws -> any CalendarCore.CalendarSource {
        EmptyLibrarySource(id: connection.sourceID)
    }
}

private final class OAuthKind: ConnectorKind, @unchecked Sendable {
    let id = "google"
    let displayName = "Google"
    let supportedPlatforms = Platform.macOS
    let authorization = AuthorizationMethod.oauth
    func authorize(using interaction: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection {
        throw CalendarCore.SourceError.authExpired
    }
    func reauthorize(_ connection: Connection, using interaction: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection {
        connection
    }
    func makeSource(for connection: Connection, credentials: any CredentialStore, syncState: any SyncStateStore) throws -> any CalendarCore.CalendarSource {
        EmptyLibrarySource(id: connection.sourceID)
    }
}

/// The Accounts pane's mirror of the engine. The account lifecycle itself is tested with the engine in
/// `timetug-shared`; the last test drives a real engine through the Mac credential sheet.
@MainActor
final class AccountsControllerTests: XCTestCase {
    private var settings: SettingsStore!
    private var sent: [EngineCommand] = []

    override func setUp() async throws {
        let suite = "AccountsControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        settings = SettingsStore(defaults: defaults)
        sent = []
    }

    private func makeController(unconfigured: [String] = []) -> AccountsController {
        var registry = ConnectorRegistry()
        registry.register(PasswordKind())
        registry.register(OAuthKind())
        return AccountsController(registry: registry, settings: settings, unconfiguredKindIDs: unconfigured,
                                  send: { [unowned self] in sent.append($0) })
    }

    private var sentDescriptions: [String] { sent.map { String(describing: $0) } }

    func testMirrorsTheEnginesAccountStatus() {
        let controller = makeController()
        let account = Connection(kindID: "google", connectionID: "1", displayName: "a@x.test", config: [:])
        var status = AccountManager.Status.empty
        status.accounts = [account]
        status.isWorking = true
        status.buildFailures = ["1": "broken"]
        status.errorMessage = "Sign-in was not completed."
        status.waitingStyle = .inApp
        controller.apply(status)
        XCTAssertEqual(controller.accounts, [account])
        XCTAssertTrue(controller.isWorking)
        XCTAssertEqual(controller.buildFailures, ["1": "broken"])
        XCTAssertEqual(controller.errorMessage, "Sign-in was not completed.")
        XCTAssertEqual(controller.waitingText, "Signing in…")

        controller.apply(.empty)
        XCTAssertEqual(controller.accounts, [])
        XCTAssertFalse(controller.isWorking)
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(controller.waitingText, "Waiting for your browser…")
    }

    func testOtherCalDAVIsOfferedLast() {
        XCTAssertEqual(makeController().availableKinds.map(\.id), ["google", "caldav"])
    }

    func testUnconfiguredKindsAreKeptForTheDimmedTiles() {
        XCTAssertEqual(makeController(unconfigured: ["google", "microsoft"]).unconfiguredKindIDs, ["google", "microsoft"])
    }

    func testAStatusIsKeyedByTheConnectionsSourceID() {
        let account = Connection(kindID: "caldav", connectionID: "p1", displayName: "me", config: [:])
        XCTAssertEqual(makeController().statusKey(for: account), "caldav-p1")
    }

    func testActionsAreSentToTheEngine() async {
        let controller = makeController()
        controller.beginAddAccount(kindID: "google")
        controller.beginReauthorize(connectionID: "1")
        controller.cancelAuthorization()
        await controller.removeAccount(connectionID: "1")
        XCTAssertEqual(sentDescriptions, [
            String(describing: EngineCommand.addAccount(kindID: "google")),
            String(describing: EngineCommand.reauthorizeAccount(connectionID: "1")),
            String(describing: EngineCommand.cancelAuthorization),
            String(describing: EngineCommand.removeAccount(connectionID: "1")),
        ])
    }

    func testSignInAgainIsNotSentWhileASignInRuns() {
        let controller = makeController()
        var status = AccountManager.Status.empty
        status.isWorking = true
        controller.apply(status)
        controller.beginReauthorize(connectionID: "1")
        XCTAssertTrue(sent.isEmpty)
    }

    func testTheAppleCalendarSwitchIsABehaviourSetting() async {
        let controller = makeController()
        await controller.setEventKitEnabled(false)
        XCTAssertFalse(settings.eventKitEnabled)
        XCTAssertFalse(settings.storage.load().systemCalendarEnabled)
    }

    // MARK: Selection and removal (the one accounts list)

    private func status(_ accounts: [Connection], isWorking: Bool = false) -> AccountManager.Status {
        var status = AccountManager.Status.empty
        status.accounts = accounts
        status.isWorking = isWorking
        return status
    }

    private let a1 = Connection(kindID: "google", connectionID: "a1", displayName: "one@x.test", config: [:])
    private let a2 = Connection(kindID: "google", connectionID: "a2", displayName: "two@x.test", config: [:])
    private let a3 = Connection(kindID: "google", connectionID: "a3", displayName: "three@x.test", config: [:])

    func testNothingIsSelectedInitially() {
        let controller = makeController()
        controller.apply(status([a1, a2]))
        XCTAssertNil(controller.selection)
        XCTAssertFalse(controller.canRemoveSelection)
    }

    func testRemoveSelectionSendsRemoveAccountForTheSelectedID() {
        let controller = makeController()
        controller.apply(status([a1, a2]))
        controller.selection = "a2"
        XCTAssertTrue(controller.canRemoveSelection)
        controller.removeSelection()
        XCTAssertEqual(sentDescriptions, [String(describing: EngineCommand.removeAccount(connectionID: "a2"))])
        XCTAssertEqual(controller.selection, "a2", "the row stays selected until the engine drops it")
    }

    func testRemoveSelectionDoesNothingWithoutASelection() {
        let controller = makeController()
        controller.apply(status([a1]))
        controller.removeSelection()
        XCTAssertTrue(sent.isEmpty)
    }

    func testRemoveSelectionIsIgnoredWhileWorking() {
        let controller = makeController()
        controller.apply(status([a1], isWorking: true))
        controller.selection = "a1"
        XCTAssertFalse(controller.canRemoveSelection)
        controller.removeSelection()
        XCTAssertTrue(sent.isEmpty)
    }

    func testRemoveSelectionIgnoresASelectionThatIsNotAnAccount() {
        let controller = makeController()
        controller.apply(status([a1]))
        controller.selection = "eventkit"
        controller.removeSelection()
        XCTAssertTrue(sent.isEmpty)
    }

    func testSelectionMovesToTheNextAccountOnlyAfterTheEngineDropsTheAccount() {
        let controller = makeController()
        controller.apply(status([a1, a2, a3]))
        controller.selection = "a1"
        controller.removeSelection()
        controller.apply(status([a1, a2, a3]))            // the engine republishes before it has removed anything
        controller.apply(status([a1, a2, a3], isWorking: false))
        XCTAssertEqual(controller.selection, "a1")
        controller.apply(status([a2, a3]))
        XCTAssertEqual(controller.selection, "a2")
    }

    func testRemovingTheLastAccountSelectsThePreviousThenNothing() {
        let controller = makeController()
        controller.apply(status([a1, a2]))
        controller.selection = "a2"
        controller.removeSelection()
        controller.apply(status([a1]))
        XCTAssertEqual(controller.selection, "a1")
        controller.removeSelection()
        controller.apply(status([]))
        XCTAssertNil(controller.selection)
    }

    func testARefusedRemovalKeepsTheSelectionAndTheRow() {
        let controller = makeController()
        controller.apply(status([a1, a2]))
        controller.selection = "a1"
        controller.removeSelection()
        var refused = status([a1, a2])
        refused.errorMessage = "Couldn't remove it."
        controller.apply(refused)
        XCTAssertEqual(controller.selection, "a1")
        XCTAssertEqual(controller.accounts, [a1, a2])
        XCTAssertEqual(controller.errorMessage, "Couldn't remove it.")
    }

    func testChoosingAnotherRowBeforeTheEngineAnswersLeavesThatChoiceAlone() {
        let controller = makeController()
        controller.apply(status([a1, a2, a3]))
        controller.selection = "a1"
        controller.removeSelection()
        controller.selection = "a3"
        controller.apply(status([a2, a3]))
        XCTAssertEqual(controller.selection, "a3")
    }

    func testSelectionIsClearedWhenItsAccountVanishes() {
        let controller = makeController()
        controller.apply(status([a1, a2]))
        controller.selection = "a2"
        controller.apply(status([a1]))                    // vanished without a removeSelection
        XCTAssertNil(controller.selection)
    }

    func testPublishingTheSameStatusKeepsTheSelection() {
        let controller = makeController()
        controller.apply(status([a1, a2]))
        controller.selection = "a2"
        for _ in 0..<10 { controller.apply(status([a1, a2])) }
        XCTAssertEqual(controller.selection, "a2")
        XCTAssertEqual(controller.accounts, [a1, a2])
    }

    func testTheListModelMirrorsTheControllersState() {
        let controller = makeController(unconfigured: ["microsoft"])
        controller.apply(status([a1], isWorking: true))
        let model = controller.listModel(statuses: ["google-a1": .ok], notices: [:], eventKitEnabled: false)
        XCTAssertEqual(model.rows.map(\.id), ["a1"])
        XCTAssertFalse(model.isAddEnabled)
        XCTAssertFalse(model.appleCalendar.isOn)
        XCTAssertEqual(model.menuEntries.first?.id, "microsoft")
        XCTAssertEqual(model.menuEntries.first?.isEnabled, false)
    }

    func testExistingBeginAddAndReauthorizeStillSendTheirCommands() {
        let controller = makeController()
        controller.beginAddAccount(kindID: "caldav")
        controller.beginReauthorize(connectionID: "a1")
        XCTAssertEqual(sentDescriptions, [
            String(describing: EngineCommand.addAccount(kindID: "caldav")),
            String(describing: EngineCommand.reauthorizeAccount(connectionID: "a1")),
        ])
    }

    /// A real engine signs in through the Mac's credential sheet: a rejected password reopens the sheet with the
    /// kind's own error and what was typed (never the password); the right one adds the account.
    func testAPasswordSignInThroughTheEngineUsesTheCredentialSheet() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AccountsControllerTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let prompter = CredentialPrompter()
        var registry = ConnectorRegistry()
        registry.register(PasswordKind())
        let engine = Engine(host: EngineHost(
            dataDirectory: directory, settings: InMemorySettingsStorage(EngineSettings(systemCalendarEnabled: false)),
            credentials: InMemoryCredentialStore(), interaction: PrompterInteraction(prompter: prompter),
            signIn: prompter.signIn, registry: registry))
        await engine.send(.start)
        let controller = AccountsController(
            registry: registry, settings: settings, credentialPrompter: prompter,
            send: { command in Task { await engine.send(command) } })
        let states = await engine.states
        let mirror = Task { @MainActor in for await state in states { controller.apply(state.accountStatus) } }
        defer { mirror.cancel() }

        controller.beginAddAccount(kindID: "caldav")
        try await waitUntil { prompter.request != nil }
        XCTAssertEqual(prompter.request?.title, "Other CalDAV account")
        XCTAssertEqual(controller.waitingText, "Signing in…")
        prompter.submit(["serverURL": "https://dav.example.test", "username": "me", "password": "wrong"])
        try await waitUntil { prompter.request?.error != nil }
        XCTAssertEqual(prompter.request?.error, "User name or password was not accepted.")
        XCTAssertEqual(prompter.request?.values, ["serverURL": "https://dav.example.test", "username": "me"])
        prompter.submit(["serverURL": "https://dav.example.test", "username": "me", "password": "right"])
        try await waitUntil { controller.accounts.count == 1 && !controller.isWorking }
        XCTAssertEqual(controller.accounts.first?.displayName, "me")
        XCTAssertNil(controller.errorMessage)
        await engine.send(.stop)
    }
}
