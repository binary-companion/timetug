import CalendarCore
import TimeTugCore

/// Everything the one accounts list shows and decides that can be tested without a view (spec L1 to L10).
/// A value built from the engine's mirrored state; the SwiftUI box (`AccountsListBox`) only draws it.
struct AccountsListModel {
    /// One signed-in account (L5).
    struct Row: Equatable, Identifiable {
        let id: ConnectionID
        let kindID: String
        /// The account's display name or email.
        let name: String
        let providerName: String
        let statusText: String
        /// Expired sign-in, or an account the engine could not start: the status is drawn in the warning colour.
        let needsAttention: Bool
        /// Whether the row shows a "Sign in again" button. Whether it is enabled now is `canSignInAgain(for:)`.
        let canSignInAgain: Bool
        let noticeText: String?
        /// "Provider, name, status", plus the notice when there is one, because a row is one accessibility element.
        let accessibilityLabel: String
    }

    /// The pinned device row (D3, L6): Apple Calendar, with its switch. Not selectable, never removed with `-`.
    struct PinnedRow: Equatable {
        let title: String
        let statusText: String
        let showsOpenSystemSettings: Bool
        let isOn: Bool
        let accessibilityLabel: String
    }

    /// One entry of the `+` menu.
    struct MenuEntry: Equatable, Identifiable {
        let id: String
        let title: String
        let isEnabled: Bool
        let disabledReason: String?
        let isPlaceholder: Bool
    }

    static let emptyReason = "No accounts yet. Choose + to add one."
    static let notSetUpReason = "isn't set up in this build"
    static let comingSoonReason = "Coming soon"
    static let removeBody = "Its calendars will no longer appear and their Tug and visibility choices are forgotten."

    /// Providers on the roadmap but not yet wired to a real `ConnectorKind`: shown disabled so people know they are coming.
    static let placeholderNames = ["Fastmail", "Todoist", "Zoom", "Webex"]

    let rows: [Row]
    let pinned: PinnedRow
    let menuEntries: [MenuEntry]
    private let isWorking: Bool

    init(
        accounts: [Connection], statuses: [String: SourceStatus], notices: [String: [SourceNotice]],
        buildFailures: [ConnectionID: String], availableKinds: [(id: String, displayName: String)],
        unconfiguredKindIDs: [String], eventKitEnabled: Bool, isWorking: Bool
    ) {
        self.isWorking = isWorking
        let providerNames = Dictionary(availableKinds.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        rows = accounts.map { account in
            let status = statuses[account.sourceID]
            let failed = buildFailures[account.connectionID] != nil
            let needsAttention = status == .authExpired || failed
            let statusText = failed ? "Can't start this account" : AccountStatusText.make(status)
            let noticeText = AccountNoticeText.make(notices[account.sourceID])
            let provider = providerNames[account.kindID] ?? ProviderIcon.displayName(forKindID: account.kindID)
            var label = "\(provider), \(account.displayName), \(statusText)"
            if let noticeText { label += ", \(noticeText)" }
            return Row(
                id: account.connectionID, kindID: account.kindID, name: account.displayName, providerName: provider,
                statusText: statusText, needsAttention: needsAttention, canSignInAgain: needsAttention,
                noticeText: noticeText, accessibilityLabel: label)
        }

        let eventKitStatus = statuses["eventkit"]
        pinned = PinnedRow(
            title: "\(SettingsText.appleCalendar) (this Mac)",
            statusText: eventKitEnabled ? AccountStatusText.make(eventKitStatus) : "Off",
            showsOpenSystemSettings: eventKitEnabled && eventKitStatus == .needsPermission,
            isOn: eventKitEnabled,
            accessibilityLabel: "Use \(SettingsText.appleCalendar)")

        // Microsoft and Google first, the rest in the registry's order (kinds this build cannot sign in to after the
        // ones it can), Other (CalDAV) last as the catch-all. Unconfigured kinds stay in the menu, disabled.
        let configured = availableKinds.map { (id: $0.id, title: $0.displayName, reason: String?.none) }
        let unconfigured = unconfiguredKindIDs.map {
            (id: $0, title: ProviderIcon.displayName(forKindID: $0), reason: String?.some(Self.notSetUpReason))
        }
        func rank(_ id: String) -> Int {
            switch id {
            case "microsoft": 0
            case "google": 1
            case "caldav": 3
            default: 2
            }
        }
        let ordered = (configured + unconfigured).enumerated()
            .sorted { (rank($0.element.id), $0.offset) < (rank($1.element.id), $1.offset) }
            .map(\.element)
        menuEntries = ordered.map {
            MenuEntry(id: $0.id, title: $0.title, isEnabled: $0.reason == nil, disabledReason: $0.reason, isPlaceholder: false)
        } + Self.placeholderNames.map {
            MenuEntry(id: "placeholder-\($0.lowercased())", title: $0, isEnabled: false,
                      disabledReason: Self.comingSoonReason, isPlaceholder: true)
        }
    }

    // MARK: Empty and busy rules (L4, L7, L9)

    var emptyText: String { Self.emptyReason }
    var showsEmptyText: Bool { rows.isEmpty }
    var isAddEnabled: Bool { !isWorking }
    var isSwitchEnabled: Bool { !isWorking }

    /// Whether the row's "Sign in again" button can be pressed now: only for a row that shows it, and not while a sign-in runs.
    func canSignInAgain(for id: ConnectionID) -> Bool {
        !isWorking && (rows.first { $0.id == id }?.canSignInAgain ?? false)
    }

    // MARK: Removal (L2, L3)

    /// `-` and Delete: something real is selected and no sign-in runs. A selection that is not a row counts as none.
    func isRemoveEnabled(selection: ConnectionID?) -> Bool {
        guard !isWorking, let selection else { return false }
        return rows.contains { $0.id == selection }
    }

    func removeQuestion(for id: ConnectionID) -> (title: String, body: String) {
        let name = rows.first { $0.id == id }?.name ?? "this account"
        return ("Remove \(name)?", Self.removeBody)
    }

    /// The `-` button's accessibility text: "Remove account", with the selected account's name in the hint.
    func removeLabel(for selection: ConnectionID?) -> (label: String, hint: String?) {
        let name = selection.flatMap { id in rows.first { $0.id == id }?.name }
        return ("Remove account", name.map { "Removes \($0)" })
    }

    /// Where the selection goes when `id` leaves: the row now in its place, else the previous one, else none.
    func selectionAfterRemoving(_ id: ConnectionID) -> ConnectionID? {
        Self.selection(afterRemoving: id, from: rows.map(\.id))
    }

    static func selection(afterRemoving id: ConnectionID, from ids: [ConnectionID]) -> ConnectionID? {
        guard let index = ids.firstIndex(of: id) else { return nil }
        let remaining = ids.filter { $0 != id }
        if index < remaining.count { return remaining[index] }
        return remaining.last
    }

    // MARK: VoiceOver

    /// The sentence to announce when the engine's accounts changed: which account was added or removed, if one was.
    static func announcement(from old: [Connection], to new: [Connection]) -> String? {
        let oldIDs = Set(old.map(\.connectionID)), newIDs = Set(new.map(\.connectionID))
        if let removed = old.first(where: { !newIDs.contains($0.connectionID) }) { return "\(removed.displayName) removed" }
        if let added = new.first(where: { !oldIDs.contains($0.connectionID) }) { return "\(added.displayName) added" }
        return nil
    }
}
