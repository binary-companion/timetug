import CalendarCore
import Foundation
import TimeTugCore
import TimeTugEngine

/// The Accounts pane's view of the engine's accounts: a mirror of `EngineState.accountStatus` whose actions are
/// sent to the engine as commands. The account lifecycle itself (add, remove, re-sign-in, the Apple Calendar switch)
/// lives in the engine's `AccountManager`.
@MainActor
final class AccountsController: ObservableObject {
    @Published private(set) var accounts: [Connection] = []
    @Published private(set) var isWorking = false
    @Published private(set) var buildFailures: [ConnectionID: String] = [:]
    @Published var errorMessage: String?

    /// The selected row of the accounts list (L2); nothing at first. Apple Calendar is its own control above the box and never selected.
    @Published var selection: ConnectionID? {
        didSet {
            // Choosing another row (or none) before the engine answers a removal cancels the "move on" that removal planned.
            if selection != removalInFlight { removalInFlight = nil }
        }
    }

    /// The account `removeSelection()` asked the engine to remove, until the engine's state drops it.
    private var removalInFlight: ConnectionID?

    /// Kind ids TimeTug supports in code but couldn't register this build — e.g. Google without an OAuth
    /// client configured. Distinct from a kind that's simply not built yet: the `+` menu lists these as disabled
    /// entries with the reason, plus a warning under the box, instead of silently leaving them out.
    let unconfiguredKindIDs: [String]

    /// What the pane shows while a sign-in runs: a password sign-in happens in the app, an OAuth one in the browser.
    @Published private(set) var waitingText = AccountsController.browserWaitingText

    /// Shows the credential sheet for `.password` kinds; the engine drives it through `SignInPrompting`.
    let credentialPrompter: CredentialPrompter

    static let browserWaitingText = "Waiting for your browser…"
    static let inAppWaitingText = "Signing in…"

    private let registry: ConnectorRegistry
    private let settings: SettingsStore
    private let send: (EngineCommand) -> Void

    init(
        registry: ConnectorRegistry, settings: SettingsStore, unconfiguredKindIDs: [String] = [],
        credentialPrompter: CredentialPrompter? = nil, send: @escaping (EngineCommand) -> Void
    ) {
        self.registry = registry
        self.settings = settings
        self.unconfiguredKindIDs = unconfiguredKindIDs
        self.credentialPrompter = credentialPrompter ?? CredentialPrompter()
        self.send = send
    }

    /// Account kinds offered by `+` (system-permission kinds such as Apple Calendar are a switch, not an account).
    /// "Other CalDAV" goes last: it is the catch-all for providers without their own entry. Read from the registry
    /// rather than the engine's state so the `+` menu is complete before the engine's first publication.
    var availableKinds: [any ConnectorKind] {
        let kinds = registry.kinds(for: .current).filter { if case .system = $0.authorization { false } else { true } }
        return kinds.filter { $0.id != "caldav" } + kinds.filter { $0.id == "caldav" }
    }

    /// The key of this account's status in `CalendarSnapshot.statuses`: every connector names its source after the
    /// connection (`Connection.sourceID`), which is what the engine's reconciler reports too.
    func statusKey(for connection: Connection) -> String { connection.sourceID }

    /// Mirrors the engine's account status.
    func apply(_ status: AccountManager.Status) {
        let previousIDs = accounts.map(\.connectionID)
        if accounts != status.accounts { accounts = status.accounts }
        reconcileSelection(previousIDs: previousIDs)
        if isWorking != status.isWorking { isWorking = status.isWorking }
        if buildFailures != status.buildFailures { buildFailures = status.buildFailures }
        if errorMessage != status.errorMessage { errorMessage = status.errorMessage }
        let text = status.waitingStyle == .inApp ? Self.inAppWaitingText : Self.browserWaitingText
        if waitingText != text { waitingText = text }
    }

    /// Keeps the selection pointing at a real row: after a requested removal the engine's state drops the row and the
    /// selection moves to the row now in its place (else the previous one, else none); a row that vanished any other way
    /// just clears it. Republishing the same accounts changes nothing, so selection survives the engine's frequent state.
    private func reconcileSelection(previousIDs: [ConnectionID]) {
        let ids = accounts.map(\.connectionID)
        if let removed = removalInFlight, !ids.contains(removed) {
            removalInFlight = nil
            if selection == removed { selection = AccountsListModel.selection(afterRemoving: removed, from: previousIDs) }
        }
        if let selection, !ids.contains(selection) { self.selection = nil }
    }

    /// Whether `-` and Delete may remove the selection now (L3, L9).
    var canRemoveSelection: Bool {
        guard !isWorking, let selection else { return false }
        return accounts.contains { $0.connectionID == selection }
    }

    /// `-` or Delete: asks the engine to remove the selected account. The row stays, selected, until the engine's state
    /// says it is gone (L3).
    func removeSelection() {
        guard canRemoveSelection, let selection else { return }
        removalInFlight = selection
        send(.removeAccount(connectionID: selection))
    }

    /// The pure model of the list, from this controller's mirrored state plus the app's source statuses and notices.
    func listModel(statuses: [String: SourceStatus], notices: [String: [SourceNotice]], eventKitEnabled: Bool) -> AccountsListModel {
        AccountsListModel(
            accounts: accounts, statuses: statuses, notices: notices, buildFailures: buildFailures,
            availableKinds: availableKinds.map { (id: $0.id, displayName: $0.displayName) },
            unconfiguredKindIDs: unconfiguredKindIDs, eventKitEnabled: eventKitEnabled, isWorking: isWorking)
    }

    /// Starts a sign-in for a new account (the pane's Cancel button calls `cancelAuthorization`).
    func beginAddAccount(kindID: String) {
        send(.addAccount(kindID: kindID))
    }

    /// Starts "Sign in again"; Cancel works during it too.
    func beginReauthorize(connectionID: ConnectionID) {
        guard !isWorking else { return }
        send(.reauthorizeAccount(connectionID: connectionID))
    }

    func cancelAuthorization() { send(.cancelAuthorization) }

    func removeAccount(connectionID: ConnectionID) async {
        send(.removeAccount(connectionID: connectionID))
    }

    /// Turning it off hides the calendars but keeps their stored selections, so turning it back on is lossless.
    func setEventKitEnabled(_ enabled: Bool) async {
        settings.eventKitEnabled = enabled
    }
}
