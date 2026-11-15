import TimeTugKit
import XCTest
@testable import TimeTug

/// The kinds a Mac build with a Google client but no Microsoft client offers, in the engine's order: Apple Calendar is
/// a system kind (a switch, never an account), Microsoft is unconfigured, "Other CalDAV" sits before the iCal link.
private let engineKinds: [AccountKindInfo] = [
    AccountKindInfo(id: "eventkit", displayName: "Apple Calendar", authorization: .system, isConfigured: true),
    AccountKindInfo(id: "caldav", displayName: "Other CalDAV", authorization: .password, isConfigured: true),
    AccountKindInfo(id: "google", displayName: "Google", authorization: .oauth, isConfigured: true),
    AccountKindInfo(id: "microsoft", displayName: "Microsoft", authorization: .oauth, isConfigured: false),
    AccountKindInfo(id: "icalsub", displayName: "iCal link", authorization: .password, isConfigured: true),
]

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

    private func makeController(kinds: [AccountKindInfo] = engineKinds) -> AccountsController {
        let controller = AccountsController(settings: settings, send: { [unowned self] in sent.append($0) })
        controller.apply(kinds: kinds)
        return controller
    }

    private var sentDescriptions: [String] { sent.map { String(describing: $0) } }

    func testMirrorsTheEnginesAccountStatus() {
        let controller = makeController()
        let account = Connection(kindId: "google", connectionId: "1", displayName: "a@x.test", config: [:])
        var status = AccountStatus.empty
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
        XCTAssertEqual(makeController().availableKinds.map(\.id), ["google", "icalsub", "caldav"])
    }

    func testAppleCalendarIsASwitchNotAnAccountKind() {
        let controller = makeController()
        XCTAssertFalse(controller.availableKinds.map(\.id).contains("eventkit"))
        XCTAssertFalse(controller.unconfiguredKindIDs.contains("eventkit"))
    }

    func testUnconfiguredKindsAreKeptForTheDimmedTiles() {
        XCTAssertEqual(makeController().unconfiguredKindIDs, ["microsoft"])
        XCTAssertFalse(makeController().availableKinds.map(\.id).contains("microsoft"))
        let none = makeController(kinds: engineKinds.map {
            var kind = $0
            if kind.id == "google" { kind.isConfigured = false }
            return kind
        })
        XCTAssertEqual(none.unconfiguredKindIDs, ["google", "microsoft"])
    }

    func testTheKindsFollowTheEngineState() {
        let controller = makeController(kinds: [])
        XCTAssertTrue(controller.availableKinds.isEmpty)
        controller.apply(kinds: engineKinds)
        XCTAssertEqual(controller.availableKinds.count, 3)
    }

    func testAStatusIsKeyedByTheConnectionsSourceID() {
        let account = Connection(kindId: "caldav", connectionId: "p1", displayName: "me", config: [:])
        XCTAssertEqual(makeController().statusKey(for: account), "caldav-p1")
    }

    func testActionsAreSentToTheEngine() async {
        let controller = makeController()
        controller.beginAddAccount(kindID: "google")
        controller.beginReauthorize(connectionID: "1")
        controller.cancelAuthorization()
        await controller.removeAccount(connectionID: "1")
        XCTAssertEqual(sentDescriptions, [
            String(describing: EngineCommand.addAccount(kindId: "google")),
            String(describing: EngineCommand.reauthorizeAccount(connectionId: "1")),
            String(describing: EngineCommand.cancelAuthorization),
            String(describing: EngineCommand.removeAccount(connectionId: "1")),
        ])
    }

    func testSignInAgainIsNotSentWhileASignInRuns() {
        let controller = makeController()
        var status = AccountStatus.empty
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

    private func status(_ accounts: [Connection], isWorking: Bool = false) -> AccountStatus {
        var status = AccountStatus.empty
        status.accounts = accounts
        status.isWorking = isWorking
        return status
    }

    private let a1 = Connection(kindId: "google", connectionId: "a1", displayName: "one@x.test", config: [:])
    private let a2 = Connection(kindId: "google", connectionId: "a2", displayName: "two@x.test", config: [:])
    private let a3 = Connection(kindId: "google", connectionId: "a3", displayName: "three@x.test", config: [:])

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
        XCTAssertEqual(sentDescriptions, [String(describing: EngineCommand.removeAccount(connectionId: "a2"))])
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
        let controller = makeController()
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
            String(describing: EngineCommand.addAccount(kindId: "caldav")),
            String(describing: EngineCommand.reauthorizeAccount(connectionId: "a1")),
        ])
    }

    /// A real engine (fake host interfaces, no network) signs in through the Mac's credential sheet: a link the feed
    /// server rejects reopens the sheet with the kind's own error and what was typed; a good one adds the account.
    func testAnICalLinkSignInThroughTheEngineUsesTheCredentialSheet() async throws {
        let http = FakeFeedTransport()
        http.serve(feed: "", status: 404)
        let prompter = CredentialPrompter()
        var config = AppConnectors.makeConfig(
            dataDirectory: FakeEngineHost.temporaryDirectory(), google: nil, microsoft: nil, textGeneration: false)
        config.systemCalendar = false
        addTeardownBlock { try? FileManager.default.removeItem(atPath: config.dataDirectory) }
        let host = FakeEngineHost.interfaces(
            authorization: FakeAuthorization(prompt: { fields in try await prompter.prompt(fields) }),
            signIn: prompter, http: http)
        let engine = try ObservedEngine { observer in try Engine(config: config, host: host, observer: observer) }
        addTeardownBlock { engine.shutdown() }
        let controller = AccountsController(settings: settings, credentialPrompter: prompter, send: { command in
            Task { await engine.send(command) }
        })
        let states = engine.states
        let mirror = Task { @MainActor in
            for await state in states { controller.apply(state.accountStatus) }
        }
        defer { mirror.cancel() }
        await engine.start()
        controller.apply(kinds: await engine.firstPublishedState().availableAccountKinds)
        XCTAssertTrue(controller.availableKinds.contains { $0.id == "icalsub" })

        controller.beginAddAccount(kindID: "icalsub")
        try await waitUntil { prompter.request != nil }
        XCTAssertEqual(prompter.request?.title, "iCal link account")
        XCTAssertEqual(prompter.request?.fields.map(\.key), ["link"])
        XCTAssertNil(prompter.request?.error)
        XCTAssertEqual(controller.waitingText, "Signing in…")
        prompter.submit(["link": "https://feeds.example.com/team.ics"])
        try await waitUntil { prompter.request?.error != nil }
        XCTAssertEqual(prompter.request?.error, "iCal link was not accepted.")
        XCTAssertEqual(prompter.request?.values, [:], "the link is a secret field: never prefilled")
        http.serve(feed: FakeFeedTransport.emptyFeed)
        prompter.submit(["link": "https://feeds.example.com/team.ics"])
        try await waitUntil { controller.accounts.count == 1 && !controller.isWorking }
        XCTAssertEqual(controller.accounts.map(\.displayName), ["feeds.example.com"])
        XCTAssertEqual(controller.accounts.first?.kindID, "icalsub")
        XCTAssertNil(controller.errorMessage)
        XCTAssertNil(prompter.request)
    }
}
