import CalendarCore
import TimeTugCore
import XCTest
@testable import TimeTug

/// The one accounts list's pure model (spec L1 to L10, "Accessibility / VoiceOver"). No view is involved.
final class AccountsListModelTests: XCTestCase {
    private let google = Connection(kindID: "google", connectionID: "g1", displayName: "me@gmail.test", config: [:])
    private let microsoft = Connection(kindID: "microsoft", connectionID: "m1", displayName: "work@contoso.test", config: [:])
    private let feed = Connection(kindID: "icalsub", connectionID: "f1", displayName: "Holidays", config: [:])

    private let allKinds: [(id: String, displayName: String)] = [
        ("icloud", "iCloud"), ("google", "Google"), ("icalsub", "iCal link"), ("caldav", "Other CalDAV"),
    ]

    private func make(
        accounts: [Connection] = [], statuses: [String: SourceStatus] = [:], notices: [String: [SourceNotice]] = [:],
        buildFailures: [ConnectionID: String] = [:], kinds: [(id: String, displayName: String)]? = nil,
        unconfigured: [String] = [], eventKitEnabled: Bool = true, isWorking: Bool = false
    ) -> AccountsListModel {
        AccountsListModel(
            accounts: accounts, statuses: statuses, notices: notices, buildFailures: buildFailures,
            availableKinds: kinds ?? allKinds, unconfiguredKindIDs: unconfigured,
            eventKitEnabled: eventKitEnabled, isWorking: isWorking)
    }

    // MARK: Menu (the `+` entries)

    func testMenuOrderPutsMicrosoftAndGoogleFirstAndCaldavLast() {
        let model = make(kinds: allKinds + [("microsoft", "Microsoft")])
        XCTAssertEqual(model.menuEntries.filter { !$0.isPlaceholder }.map(\.id),
                       ["microsoft", "google", "icloud", "icalsub", "caldav"])
    }

    func testAnUnconfiguredMicrosoftStillSitsFirst() {
        let model = make(unconfigured: ["microsoft"])
        XCTAssertEqual(model.menuEntries.filter { !$0.isPlaceholder }.map(\.id).first, "microsoft")
    }

    func testPlaceholdersAreDisabledAndComingSoon() {
        let placeholders = make().menuEntries.filter(\.isPlaceholder)
        XCTAssertEqual(placeholders.map(\.title), ["Fastmail", "Todoist", "Zoom", "Webex"])
        XCTAssertTrue(placeholders.allSatisfy { !$0.isEnabled && $0.disabledReason == "Coming soon" })
    }

    func testPlaceholdersComeAfterEveryRealEntry() {
        let flags = make().menuEntries.map(\.isPlaceholder)
        let firstPlaceholder = flags.firstIndex(of: true)!
        XCTAssertTrue(flags[firstPlaceholder...].allSatisfy { $0 })
    }

    func testUnconfiguredKindIsADisabledEntryWithAReason() throws {
        let model = make(unconfigured: ["microsoft"])
        let entry = try XCTUnwrap(model.menuEntries.first { $0.id == "microsoft" })
        XCTAssertEqual(entry.title, "Microsoft")
        XCTAssertFalse(entry.isEnabled)
        XCTAssertEqual(entry.disabledReason, "isn't set up in this build")
        XCTAssertFalse(entry.isPlaceholder)
    }

    func testConfiguredKindsAreEnabledWithNoReason() {
        let real = make().menuEntries.filter { !$0.isPlaceholder }
        XCTAssertTrue(real.allSatisfy { $0.isEnabled && $0.disabledReason == nil })
        XCTAssertEqual(real.first { $0.id == "caldav" }?.title, "Other CalDAV")
    }

    func testEntriesStayInTheMenuWhileBusyAndPlusIsDisabledInstead() {
        let idle = make()
        let busy = make(isWorking: true)
        XCTAssertEqual(busy.menuEntries, idle.menuEntries)
        XCTAssertTrue(idle.isAddEnabled)
        XCTAssertFalse(busy.isAddEnabled)
    }

    // MARK: Rows

    func testEmptyTextWhenNoAccountsAndPinnedRowStays() {
        let model = make(accounts: [])
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertTrue(model.showsEmptyText)
        XCTAssertEqual(model.emptyText, "No accounts yet. Choose + to add one.")
        XCTAssertEqual(model.pinned.title, "Apple Calendar (this Mac)")
        XCTAssertFalse(make(accounts: [google]).showsEmptyText)
    }

    func testRowsKeepTheEnginesOrder() {
        let model = make(accounts: [microsoft, google, feed])
        XCTAssertEqual(model.rows.map(\.id), ["m1", "g1", "f1"])
        XCTAssertEqual(model.rows.map(\.name), ["work@contoso.test", "me@gmail.test", "Holidays"])
    }

    func testRowStatusWordsAreTodaysWords() {
        let model = make(accounts: [google, microsoft, feed], statuses: [
            "google-g1": .ok, "microsoft-m1": .authExpired, "icalsub-f1": .failing("x"),
        ])
        XCTAssertEqual(model.rows.map(\.statusText), ["Connected", "Sign in again", "Can't reach this calendar right now"])
    }

    func testAnAccountWithNoStatusYetReadsConnecting() {
        XCTAssertEqual(make(accounts: [google]).rows.first?.statusText, "Connecting…")
    }

    func testNeedsAttentionRowOffersSignInAgain() {
        let model = make(accounts: [google, microsoft], statuses: ["google-g1": .ok, "microsoft-m1": .authExpired])
        XCTAssertFalse(model.rows[0].needsAttention)
        XCTAssertFalse(model.rows[0].canSignInAgain)
        XCTAssertTrue(model.rows[1].needsAttention)
        XCTAssertTrue(model.rows[1].canSignInAgain)
    }

    func testABuildFailureShowsCantStartAndOffersSignInAgain() {
        let model = make(accounts: [google], statuses: ["google-g1": .ok], buildFailures: ["g1": "broken"])
        XCTAssertEqual(model.rows[0].statusText, "Can't start this account")
        XCTAssertTrue(model.rows[0].needsAttention)
        XCTAssertTrue(model.rows[0].canSignInAgain)
    }

    func testRowAccessibilityLabelReadsProviderNameStatus() {
        let model = make(accounts: [google, feed], statuses: ["google-g1": .ok, "icalsub-f1": .ok])
        XCTAssertEqual(model.rows[0].accessibilityLabel, "Google, me@gmail.test, Connected")
        XCTAssertEqual(model.rows[1].accessibilityLabel, "iCal link, Holidays, Connected")
    }

    func testAKindNoLongerRegisteredStillGetsAProviderName() {
        let orphan = Connection(kindID: "microsoft", connectionID: "m9", displayName: "x@y.test", config: [:])
        let model = make(accounts: [orphan], statuses: ["microsoft-m9": .ok])
        XCTAssertEqual(model.rows[0].accessibilityLabel, "Microsoft, x@y.test, Connected")
    }

    func testNoticeMarkerCarriesItsText() throws {
        let notice = SourceNotice(kind: .unreadableRecurrence, count: 2)
        let model = make(accounts: [feed], statuses: ["icalsub-f1": .ok], notices: ["icalsub-f1": [notice]])
        let text = try XCTUnwrap(model.rows[0].noticeText)
        XCTAssertEqual(text, AccountNoticeText.make([notice]))
        XCTAssertTrue(model.rows[0].accessibilityLabel.hasSuffix(text))
        XCTAssertNil(make(accounts: [feed]).rows[0].noticeText)
    }

    // MARK: Busy and removal rules

    func testRemoveIsDisabledWithNoSelectionAndWhileWorking() {
        let idle = make(accounts: [google])
        XCTAssertFalse(idle.isRemoveEnabled(selection: nil))
        XCTAssertTrue(idle.isRemoveEnabled(selection: "g1"))
        XCTAssertFalse(idle.isRemoveEnabled(selection: "gone"), "a selection that is not a row is nothing selected")
        XCTAssertFalse(make(accounts: [google], isWorking: true).isRemoveEnabled(selection: "g1"))
    }

    func testAddSwitchAndSignInAgainAreDisabledWhileWorking() {
        let expired = make(accounts: [google], statuses: ["google-g1": .authExpired])
        XCTAssertTrue(expired.isAddEnabled)
        XCTAssertTrue(expired.isSwitchEnabled)
        XCTAssertTrue(expired.canSignInAgain(for: "g1"))
        let busy = make(accounts: [google], statuses: ["google-g1": .authExpired], isWorking: true)
        XCTAssertFalse(busy.isAddEnabled)
        XCTAssertFalse(busy.isSwitchEnabled)
        XCTAssertFalse(busy.canSignInAgain(for: "g1"))
    }

    func testSignInAgainIsOnlyForRowsThatNeedIt() {
        let model = make(accounts: [google], statuses: ["google-g1": .ok])
        XCTAssertFalse(model.canSignInAgain(for: "g1"))
        XCTAssertFalse(model.canSignInAgain(for: "unknown"))
    }

    func testRemoveQuestionTextMatchesToday() {
        let question = make(accounts: [google]).removeQuestion(for: "g1")
        XCTAssertEqual(question.title, "Remove me@gmail.test?")
        XCTAssertEqual(question.body, "Its calendars will no longer appear and their Tug and visibility choices are forgotten.")
        XCTAssertEqual(make().removeQuestion(for: "gone").title, "Remove this account?")
    }

    func testRemoveLabelIsRemoveAccountWithTheNameInTheHint() {
        let model = make(accounts: [google])
        XCTAssertEqual(model.removeLabel(for: "g1").label, "Remove account")
        XCTAssertEqual(model.removeLabel(for: "g1").hint, "Removes me@gmail.test")
        XCTAssertEqual(model.removeLabel(for: nil).label, "Remove account")
        XCTAssertNil(model.removeLabel(for: nil).hint)
    }

    func testSelectionAfterRemovingMovesToNextThenPreviousThenNil() {
        let three = make(accounts: [google, microsoft, feed])
        XCTAssertEqual(three.selectionAfterRemoving("g1"), "m1", "the row now in its place")
        XCTAssertEqual(three.selectionAfterRemoving("m1"), "f1")
        XCTAssertEqual(three.selectionAfterRemoving("f1"), "m1", "last row: the previous one")
        XCTAssertNil(make(accounts: [google]).selectionAfterRemoving("g1"))
        XCTAssertNil(three.selectionAfterRemoving("gone"))
    }

    // MARK: The pinned row

    func testPinnedRowStatesOffOnAndAccessOff() {
        let on = make(statuses: ["eventkit": .ok], eventKitEnabled: true).pinned
        XCTAssertTrue(on.isOn)
        XCTAssertEqual(on.statusText, "Connected")
        XCTAssertFalse(on.showsOpenSystemSettings)
        XCTAssertEqual(on.accessibilityLabel, "Use Apple Calendar")

        let off = make(statuses: ["eventkit": .needsPermission], eventKitEnabled: false).pinned
        XCTAssertFalse(off.isOn)
        XCTAssertEqual(off.statusText, "Off")
        XCTAssertFalse(off.showsOpenSystemSettings, "Open System Settings only while the switch is on")

        let denied = make(statuses: ["eventkit": .needsPermission], eventKitEnabled: true).pinned
        XCTAssertEqual(denied.statusText, "Calendar access is off")
        XCTAssertTrue(denied.showsOpenSystemSettings)
    }

    func testPinnedRowIsNeverASelectableRow() {
        let model = make(accounts: [google], statuses: ["eventkit": .ok])
        XCTAssertFalse(model.rows.contains { $0.id == "eventkit" || $0.kindID == "eventkit" })
        XCTAssertFalse(model.isRemoveEnabled(selection: "eventkit"))
        XCTAssertNil(model.selectionAfterRemoving("eventkit"))
    }

    // MARK: Announcements (VoiceOver)

    func testAnnouncementNamesAnAddedOrRemovedAccount() {
        XCTAssertEqual(AccountsListModel.announcement(from: [google], to: [google, microsoft]), "work@contoso.test added")
        XCTAssertEqual(AccountsListModel.announcement(from: [google, microsoft], to: [microsoft]), "me@gmail.test removed")
        XCTAssertNil(AccountsListModel.announcement(from: [google], to: [google]))
        XCTAssertNil(AccountsListModel.announcement(from: [], to: []))
    }
}
