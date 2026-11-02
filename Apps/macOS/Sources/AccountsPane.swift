import AppKit
import CalendarCore
import SwiftUI
import TimeTugCore

struct AccountsPane: View {
    @ObservedObject var accounts: AccountsController
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: SettingsNavigation
    @State private var pendingRemoval: ConnectionID?

    private var listModel: AccountsListModel {
        accounts.listModel(statuses: model.statuses, notices: model.notices, eventKitEnabled: settings.eventKitEnabled)
    }

    var body: some View {
        let listModel = listModel
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose where TimeTug reads your calendars from.")
                    .font(.callout).foregroundStyle(.secondary)
                AccountsListBox(
                    model: listModel, selection: $accounts.selection,
                    signInAgain: { accounts.beginReauthorize(connectionID: $0) },
                    add: { accounts.beginAddAccount(kindID: $0) },
                    remove: { askToRemove($0) },
                    setEnabled: { enabled in Task { await accounts.setEventKitEnabled(enabled) } },
                    openSystemSettings: Self.openCalendarPrivacySettings)
                if accounts.isWorking { waitingRow }
                if let message = accounts.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.orange)
                }
                if !accounts.unconfiguredKindIDs.isEmpty { configurationWarning }

                diagnosticsSection
            }
            .padding(16)
        }
        .settingsHighlight("accounts", navigation: navigation)
        .modifier(CredentialSheetPresenter(prompter: accounts.credentialPrompter))
        .onChange(of: accounts.accounts) { old, new in
            if let message = AccountsListModel.announcement(from: old, to: new) { AccessibilityAnnouncer.post(message) }
            // A question about an account the engine has since dropped has nothing left to confirm.
            if let id = pendingRemoval, !new.contains(where: { $0.connectionID == id }) { pendingRemoval = nil }
        }
        .onChange(of: accounts.isWorking) { _, working in
            // The removal would be ignored while a sign-in runs (L9), so do not leave the question open.
            if working { pendingRemoval = nil }
        }
        .onChange(of: accounts.errorMessage) { _, message in
            if let message { AccessibilityAnnouncer.post(message) }
        }
        .confirmationDialog(
            listModel.removeQuestion(for: pendingRemoval ?? "").title, isPresented: removalBinding, titleVisibility: .visible
        ) {
            // Cancel is the default; Remove is the destructive choice (spec "Accessibility").
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
                .keyboardShortcut(.defaultAction)
            Button("Remove", role: .destructive) {
                if let id = pendingRemoval {
                    accounts.selection = id
                    accounts.removeSelection()
                }
                pendingRemoval = nil
            }
        } message: {
            Text(listModel.removeQuestion(for: pendingRemoval ?? "").body)
        }
    }

    /// `-`, Delete, or a row's VoiceOver "Remove": ask first (L3). Nothing is sent until the person confirms.
    private func askToRemove(_ id: ConnectionID) {
        guard listModel.isRemoveEnabled(selection: id) else { return }
        pendingRemoval = id
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SettingsText.diagnostics).font(.headline)
            HStack(spacing: 8) {
                Button("Copy Diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(AppDiagnostics.shared.report(), forType: .string)
                }
                Button("Clear") { AppDiagnostics.shared.clear() }
            }
            Text("A short log of recent calendar activity to share when reporting a problem. It contains no feed links or event titles.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .settingsHighlight("diagnostics", navigation: navigation)
    }

    private var configurationWarning: some View {
        Label {
            Text("This build is missing configuration for some account types, so they can't be added right now.")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }

    private var waitingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(accounts.waitingText).font(.callout)
            Button("Cancel") { accounts.cancelAuthorization() }.buttonStyle(.link)
        }
    }

    private static func openCalendarPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
