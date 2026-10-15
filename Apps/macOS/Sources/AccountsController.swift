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

    /// Kind ids TimeTug supports in code but couldn't register this build — e.g. Google without an OAuth
    /// client configured. Distinct from a kind that's simply not built yet: the Accounts pane shows these
    /// with their real icon, dimmed, plus a warning, instead of silently leaving them out.
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
    /// rather than the engine's state so the grid is complete before the engine's first publication.
    var availableKinds: [any ConnectorKind] {
        let kinds = registry.kinds(for: .current).filter { if case .system = $0.authorization { false } else { true } }
        return kinds.filter { $0.id != "caldav" } + kinds.filter { $0.id == "caldav" }
    }

    /// The key of this account's status in `CalendarSnapshot.statuses`: every connector names its source after the
    /// connection (`Connection.sourceID`), which is what the engine's reconciler reports too.
    func statusKey(for connection: Connection) -> String { connection.sourceID }

    /// Mirrors the engine's account status.
    func apply(_ status: AccountManager.Status) {
        if accounts != status.accounts { accounts = status.accounts }
        if isWorking != status.isWorking { isWorking = status.isWorking }
        if buildFailures != status.buildFailures { buildFailures = status.buildFailures }
        if errorMessage != status.errorMessage { errorMessage = status.errorMessage }
        let text = status.waitingStyle == .inApp ? Self.inAppWaitingText : Self.browserWaitingText
        if waitingText != text { waitingText = text }
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
