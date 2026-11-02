import AppKit
import CalendarCore
import SwiftUI

/// The one accounts list (spec "The shared control"): a bordered box with a selectable list of the signed-in accounts and
/// a bottom bar with `+` (a menu of what can be added) and `-` (remove the selected one). Apple Calendar is not in it: it
/// is its own control above the box (`AppleCalendarRow`). A view over `AccountsListModel`; everything it decides lives
/// there. The pane owns the removal question.
struct AccountsListBox: View {
    let model: AccountsListModel
    @Binding var selection: ConnectionID?
    var signInAgain: (ConnectionID) -> Void
    var add: (String) -> Void
    /// Asks to remove this account (the pane shows the question; confirming removes the selection).
    var remove: (ConnectionID) -> Void

    private static let rowHeight: CGFloat = 43
    private static let maxListHeight: CGFloat = 260

    var body: some View {
        VStack(spacing: 0) {
            listArea
            Divider()
            bar
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Accounts")
    }

    // MARK: List

    @ViewBuilder private var listArea: some View {
        if model.showsEmptyText {
            Text(model.emptyText)
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 14)
        } else {
            List(selection: $selection) {
                ForEach(model.rows) { row in
                    rowView(row).tag(row.id)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: min(CGFloat(model.rows.count) * Self.rowHeight + 2, Self.maxListHeight))
            .onDeleteCommand {
                if let selection, model.isRemoveEnabled(selection: selection) { remove(selection) }
            }
        }
    }

    private func rowView(_ row: AccountsListModel.Row) -> some View {
        HStack(spacing: 10) {
            ProviderIcon(kindID: row.kindID)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                HStack(spacing: 4) {
                    if row.needsAttention {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                    Text(row.statusText)
                        .font(.caption).foregroundStyle(row.needsAttention ? .orange : .secondary)
                    if let noticeText = row.noticeText {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange.opacity(0.7))
                            .help(noticeText)
                    }
                }
            }
            Spacer()
            if row.canSignInAgain {
                Button("Sign in again") { signInAgain(row.id) }
                    .disabled(!model.canSignInAgain(for: row.id))
            }
        }
        .frame(minHeight: Self.rowHeight - 12)
        // One accessibility element per row, reading "Provider, name, status"; its two actions are custom actions.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityAddTraits(selection == row.id ? .isSelected : [])
        .modifier(RowActions(
            canSignInAgain: model.canSignInAgain(for: row.id), canRemove: model.isRemoveEnabled(selection: row.id),
            signInAgain: { signInAgain(row.id) }, remove: { remove(row.id) }))
    }

    // MARK: Bar

    private var bar: some View {
        let removeText = model.removeLabel(for: selection)
        return HStack(spacing: 0) {
            Menu {
                ForEach(model.menuEntries.filter { !$0.isPlaceholder }) { entry in
                    Button(entry.disabledReason.map { "\(entry.title) (\($0))" } ?? entry.title) { add(entry.id) }
                        .disabled(!entry.isEnabled)
                }
                Divider()
                Section("Coming soon") {
                    ForEach(model.menuEntries.filter(\.isPlaceholder)) { entry in
                        Button(entry.title) {}
                            .disabled(true)
                            .accessibilityLabel("\(entry.title), coming soon")
                    }
                }
            } label: {
                Image(systemName: "plus").frame(width: 26, height: 22).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!model.isAddEnabled)
            .help("Add an account")
            .accessibilityLabel("Add account")

            Divider().frame(height: 14)

            Button {
                if let selection { remove(selection) }
            } label: {
                Image(systemName: "minus").frame(width: 26, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!model.isRemoveEnabled(selection: selection))
            .help("Remove the selected account")
            .accessibilityLabel(removeText.label)
            .accessibilityHint(removeText.hint ?? "")
            Spacer()
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.bar)
    }
}

/// Apple Calendar (this Mac): its own bordered control above the accounts box, with the on/off switch and, when Calendar
/// access is off, "Open System Settings". Turning it off hides the Apple calendars and keeps the choices made for them.
struct AppleCalendarRow: View {
    let model: AccountsListModel
    var setEnabled: (Bool) -> Void
    var openSystemSettings: () -> Void

    var body: some View {
        let control = model.appleCalendar
        HStack(spacing: 10) {
            Image(systemName: "calendar").frame(width: 22).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(control.title)
                Text(control.statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if control.showsOpenSystemSettings {
                Button("Open System Settings", action: openSystemSettings)
                    .buttonStyle(.link)
                    .accessibilityHint(control.openSystemSettingsHint)
            }
            Toggle("Enabled", isOn: Binding(get: { control.isOn }, set: setEnabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!model.isSwitchEnabled)
                .accessibilityLabel(control.switchLabel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(control.groupLabel)
    }
}

/// The two VoiceOver actions on a row, added only when they apply.
private struct RowActions: ViewModifier {
    let canSignInAgain: Bool
    let canRemove: Bool
    let signInAgain: () -> Void
    let remove: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: "Sign in again") { if canSignInAgain { signInAgain() } }
            .accessibilityAction(named: "Remove") { if canRemove { remove() } }
    }
}

/// Spoken confirmation of what changed (an account added or removed, a sign-in that failed).
enum AccessibilityAnnouncer {
    @MainActor static func post(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
