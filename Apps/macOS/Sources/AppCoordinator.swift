import AppKit
import AppleIntelligenceInference
import CalendarApple
import CalendarBridge
import CalendarCore
import Combine
import EventKitSource
import KeyboardShortcuts
import Network
import OSLog
import SwiftUI
import TimeTugCore
import TimeTugEngine
import WidgetKit

/// Hosts the engine on the Mac: builds it from the Mac's adapters, forwards commands, and mirrors its state into the
/// views, the status item, the overlay and the widgets. The engine decides what happens and when; this class only
/// decides how it looks.
@MainActor
final class AppCoordinator {
    /// Cheap self-heal for a dropped settings notification from the widget extension.
    private static let settingsSelfHeal: TimeInterval = 300

    let settings = SettingsStore(defaults: GroupDefaults.suite, shared: .appGroup)
    let model = AppModel()
    let navigation = SettingsNavigation()
    let updates = UpdateController(
        driver: AppCoordinator.makeUpdaterDriver(),
        currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")

    /// Sparkle in the direct build (inert in the XCTest host); nothing in the App Store build, which has no Sparkle.
    private static func makeUpdaterDriver() -> UpdaterDriving {
        #if APPSTORE
        return NoOpUpdater()
        #else
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return NoOpUpdater() }
        return SparkleUpdater(includeBetas: { UserDefaults.standard.bool(forKey: UpdateController.betaKey) })
        #endif
    }

    private let eventKit = EventKitSource()
    private lazy var engine = Engine(host: makeHost())
    private lazy var commands = EngineCommandQueue { [engine] command in await engine.send(command) }
    private let engineDiagnostics = OSLogEngineDiagnostics()
    /// The last state rendered; the status item is redrawn from it when a presentation setting changes.
    private var lastState = EngineState.empty
    /// The takeover on screen, until its one closing command (join, snooze, dismiss or closed) is sent.
    private var shownTakeoverID: String?
    /// Behaviour edits sent to the engine and not yet handled, per setting. While a setting has one in flight its
    /// value in the engine's state is older than the one on screen, so it is not mirrored back.
    private var pendingBehaviourWrites: [String: Int] = [:]
    /// States older than this were published before the last settled behaviour edit and never overwrite it.
    private var minimumSettingsRevision: UInt64 = 0
    private var lastPublishedInferenceStatus: InferenceStatus?
    private var stateTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var networkMonitor: NWPathMonitor?
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: StatusItemController?
    private let snapshotStore = WidgetSnapshotStore()
    private var lastWidgetEvents: [WidgetEvent]?
    private var widgetReloadTask: Task<Void, Never>?
    private var settingsSignal: SettingsChangeSignal.Observer?
    private static let widgetLog = Logger(subsystem: "com.timetug.app", category: "widgets")
    private let overlay = OverlayController()
    private lazy var googleOAuthConfig = GoogleOAuthSettings.config()
    private lazy var microsoftOAuthConfig = MicrosoftOAuthSettings.config()
    private lazy var registry = AppConnectors.makeRegistry(google: googleOAuthConfig, microsoft: microsoftOAuthConfig, eventKit: eventKit, diagnostics: AppDiagnostics.shared.log)
    /// Kinds TimeTug supports in code but this build couldn't register — see `AccountsController.unconfiguredKindIDs`.
    private lazy var unconfiguredKindIDs: [String] =
        (googleOAuthConfig == nil ? ["google"] : []) + (microsoftOAuthConfig == nil ? ["microsoft"] : [])
    private let credentials: any CredentialStore = AppCredentials.make()
    private let credentialPrompter = CredentialPrompter()
    private lazy var interaction = LoopbackAuthorizationInteraction(
        openURL: { url in await MainActor.run { NSWorkspace.shared.open(url) } },
        promptCredentials: { [credentialPrompter] fields in try await credentialPrompter.prompt(fields) },
        presenter: BrowserPreferringPresenter(
            sheet: WebAuthenticationSessionPresenter(anchor: { [weak self] in self?.settingsWindow.currentWindow ?? NSApp.keyWindow })))
    lazy var accounts: AccountsController = AccountsController(
        registry: registry, settings: settings, unconfiguredKindIDs: unconfiguredKindIDs,
        credentialPrompter: credentialPrompter, send: { [weak self] command in self?.commands.send(command) })
    private lazy var aboutWindow = AboutWindowController()
    private lazy var settingsWindow = SettingsWindowController { [unowned self] in
        SettingsView(settings: settings, model: model, navigation: navigation, accounts: accounts, updates: updates, onTestTug: { [weak self] in self?.fireTest() },
                     onForgetCorrections: { [weak self] in self?.forgetCorrections() })
    }

    /// The engine's host services: today's files, settings keys, Keychain, sign-in UI, connectors and adapters.
    private func makeHost() -> EngineHost {
        let eventKit = eventKit
        return EngineHost(
            dataDirectory: AppSupportFiles.directory(),
            settings: settings.storage,
            credentials: credentials,
            interaction: interaction,
            signIn: credentialPrompter.signIn,
            registry: registry,
            unconfiguredKindIDs: unconfiguredKindIDs,
            buildSystemSource: { ConnectedSource(eventKit) },
            requestSystemAccess: { _ = await eventKit.requestAccess() },
            textGenerator: AppleIntelligence.makeTextGenerator(),
            diagnostics: engineDiagnostics.sink)
    }

    /// Another copy of TimeTug was opened and left (or was replaced by this one): show the hint unless this pair of
    /// builds was dismissed before.
    func noteCollision(with other: InstanceInfo) {
        let notice = CollisionNotice.make(survivor: .current, other: other)
        let dismissed = GroupDefaults.suite.string(forKey: CollisionNotice.dismissedKey)
        model.collisionNotice = CollisionNotice.shouldShow(notice, dismissedPair: dismissed) ? notice : nil
    }

    func dismissCollisionNotice() {
        guard let notice = model.collisionNotice else { return }
        GroupDefaults.suite.set(notice.pairKey, forKey: CollisionNotice.dismissedKey)
        model.collisionNotice = nil
    }

    func start() async {
        NSApp.appearance = settings.appearanceMode.nsAppearance
        statusItem = StatusItemController(
            popoverContent: Self.makePopoverController(
                DropdownView(
                    model: model,
                    onOpenSettings: { [weak self] in self?.openSettings() },
                    onJoin: { [weak self] url in self?.statusItem?.join(url) },
                    onUnmerge: { [weak self] event in self?.unmerge(event) },
                    onSeparate: { [weak self] event, members in self?.separate(event, members: members) },
                    onMerge: { [weak self] a, b in self?.merge(a, b) },
                    onDismissCollision: { [weak self] in self?.dismissCollisionNotice() }
                )
            ),
            onOpenSettings: { [weak self] in self?.openSettings() },
            onCheckForUpdates: { [weak self] in self?.updates.checkForUpdates() },
            onOpenAbout: { [weak self] in self?.aboutWindow.show(on: self?.statusItem?.clickedScreen) }
        )
        KeyboardShortcuts.onKeyUp(for: .togglePopup) { [weak self] in
            Task { @MainActor in self?.statusItem?.togglePopover() }
        }
        model.popupCardStyle = settings.popupCardStyle
        attachSettings()
        settings.$appearanceMode.dropFirst().sink { mode in
            NSApp.appearance = mode.nsAppearance
        }.store(in: &cancellables)
        settings.$popupCardStyle.dropFirst().sink { [weak self] style in
            self?.model.popupCardStyle = style
        }.store(in: &cancellables)
        settings.$menuBarMode.dropFirst().sink { [weak self] mode in
            self?.commands.send(.setCountdownVisible(mode != .iconOnly), lane: .countdown)
            // The published value arrives before the property changes; redraw once it has.
            Task { @MainActor in self?.updateStatusItem() }
        }.store(in: &cancellables)
        settingsSignal = SettingsChangeSignal.Observer { [weak self] in
            DispatchQueue.main.async { self?.settings.reloadFromShared() }
        }
        Timer.scheduledTimer(withTimeInterval: Self.settingsSelfHeal, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.settings.reloadFromShared() }
        }

        let engine = engine
        let states = await engine.states
        let events = await engine.events
        stateTask = Task { [weak self] in
            for await state in states { self?.render(state) }
        }
        eventTask = Task { [weak self] in
            for await event in events { self?.handle(event) }
        }
        commands.send(.setCountdownVisible(settings.menuBarMode != .iconOnly), lane: .countdown)
        updateStatusItem()
        observeSystemEvents()
        observeNetworkReturn()
        // Loads the ledger and dedup state, requests Apple Calendar access if enabled, builds the sources and
        // refreshes once.
        await engine.send(.start)
        if await engine.currentState().settings.takeover.takeoverCalendarKeys.isEmpty { openSettings(pane: .calendars) }
    }

    /// Hosting controller that reports its content size so the popover is exactly as tall as the popup.
    private static func makePopoverController(_ view: DropdownView) -> NSViewController {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        return controller
    }

    // MARK: - Settings

    /// Behaviour edits in Settings go to the engine; a reload request (widget toggle, self-heal) makes the engine
    /// re-read the storage.
    private func attachSettings() {
        settings.sendBehaviourChange = { [weak self] change in self?.sendBehaviour(change) }
        settings.requestExternalReload = { [weak self] in
            self?.commands.send(.settingsChangedExternally, lane: .externalSettings)
        }
    }

    private func sendBehaviour(_ change: SettingsStore.BehaviourChange) {
        let key: String
        let apply: @Sendable (inout EngineSettings) -> Void
        switch change {
        case .takeover(let old, let new):
            key = "takeover"
            apply = { $0.takeover.applyEdit(from: old, to: new) }
        case .inference(let enabled):
            key = "inference"
            apply = { $0.inferenceEnabled = enabled }
        case .systemCalendar(let enabled):
            key = "systemCalendar"
            apply = { $0.systemCalendarEnabled = enabled }
        }
        pendingBehaviourWrites[key, default: 0] += 1
        commands.send(.applySettings(apply), lane: .behaviour(key)) { [weak self] in
            self?.behaviourWriteFinished(key)
        }
    }

    private func behaviourWriteFinished(_ key: String) {
        pendingBehaviourWrites[key, default: 1] -= 1
        guard pendingBehaviourWrites[key] == 0 else { return }
        let engine = engine
        Task { [weak self] in
            let state = await engine.currentState()
            guard let self else { return }
            minimumSettingsRevision = max(minimumSettingsRevision, state.revision)
            mirrorSettings(state.settings)
        }
    }

    /// Mirrors the engine's behaviour settings, except a setting whose own edit is still in flight.
    private func mirrorSettings(_ engineSettings: EngineSettings) {
        var merged = engineSettings
        let shown = settings.behaviour
        if pendingBehaviourWrites["takeover", default: 0] > 0 { merged.takeover = shown.takeover }
        if pendingBehaviourWrites["inference", default: 0] > 0 { merged.inferenceEnabled = shown.inferenceEnabled }
        if pendingBehaviourWrites["systemCalendar", default: 0] > 0 {
            merged.systemCalendarEnabled = shown.systemCalendarEnabled
        }
        settings.applyEngineSettings(merged)
    }

    // MARK: - State

    private func render(_ state: EngineState) {
        guard state.revision >= lastState.revision else { return }
        lastState = state
        EngineModelMirror.apply(state, to: model)
        accounts.apply(state.accountStatus)
        if state.revision >= minimumSettingsRevision { mirrorSettings(state.settings) }
        // Revision 0 is the placeholder before the engine's first publication; it says nothing about this Mac.
        if state.revision > 0, state.inferenceStatus != lastPublishedInferenceStatus {
            lastPublishedInferenceStatus = state.inferenceStatus
            publishInferenceAvailability(state.inferenceStatus)
        }
        updateStatusItem()
    }

    private func updateStatusItem() {
        let now = Date()
        statusItem?.setTitle(EngineModelMirror.statusTitle(lastState, mode: settings.menuBarMode, now: now))
        statusItem?.setIconState(EngineModelMirror.iconState(lastState, now: now))
    }

    private func publishInferenceAvailability(_ status: InferenceStatus) {
        settings.shared.set(status.isAvailableOnThisMac, for: .inferenceAvailable)
        if #available(macOS 26.0, *) { ControlCenter.shared.reloadAllControls() }
    }

    // MARK: - Events

    private func handle(_ event: EngineEvent) {
        switch event {
        case .takeoverDue(let request, let calendarTitle):
            present(request, calendarTitle: calendarTitle)
        case .takeoverWithdrawn:
            // The Mac never withdrew a takeover that is on screen; a withdrawn armed one simply never comes.
            break
        case .widgetSnapshot(let snapshot):
            publishWidgetSnapshot(snapshot)
        case .joinRequested(let url):
            SafeJoin.open(url, using: { NSWorkspace.shared.open($0) })
        case .diagnostic:
            // Already written to the system log by the host's diagnostics sink.
            break
        }
    }

    /// Writes the agenda snapshot for widgets; reloads their timelines only when the events changed.
    private func publishWidgetSnapshot(_ widgetSnapshot: WidgetSnapshot) {
        do {
            try snapshotStore.write(widgetSnapshot)
        } catch {
            Self.widgetLog.error("widget snapshot not written: \(error.localizedDescription, privacy: .public)")
            return
        }
        if #available(macOS 26.0, *) { ControlCenter.shared.reloadAllControls() }
        guard widgetSnapshot.events != lastWidgetEvents else { return }
        lastWidgetEvents = widgetSnapshot.events
        widgetReloadTask?.cancel()
        widgetReloadTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Takeover

    /// Shows a takeover the engine says is due. Host contract: every takeover gets exactly one closing command
    /// (join, snooze, dismiss, or closed when something else replaces it) on every path.
    private func present(_ request: TakeoverRequest, calendarTitle: String?) {
        let id = request.event.id
        // The same id again (a second test tug that raced the first) replaces the overlay and stays outstanding.
        if let shown = shownTakeoverID, shown != id { closeTakeover(shown, with: .takeoverClosed(eventID: shown)) }
        shownTakeoverID = id
        overlay.show(request, calendarTitle: calendarTitle, actions: .init(
            join: { [weak self] in self?.closeTakeover(id, with: .join(eventID: id)) },
            snooze: { [weak self] seconds in self?.closeTakeover(id, with: .snooze(eventID: id, seconds: seconds)) },
            dismiss: { [weak self] in self?.closeTakeover(id, with: .dismiss(eventID: id)) }
        ))
        commands.send(.takeoverPresented(eventID: id, onScreen: true), lane: .takeover)
    }

    /// Hides the takeover `id` and sends its one closing command; later actions for it do nothing.
    private func closeTakeover(_ id: String, with command: EngineCommand) {
        guard shownTakeoverID == id else { return }
        shownTakeoverID = nil
        overlay.hide()
        commands.send(command, lane: .takeover)
    }

    /// Settings' "Test tug" button: a sample takeover that never touches the ledger. It replaces a takeover on
    /// screen, which is closed first.
    func fireTest() {
        if let shown = shownTakeoverID { closeTakeover(shown, with: .takeoverClosed(eventID: shown)) }
        commands.send(.testTug(title: "Sample meeting", calendarTitle: "Sample calendar"), lane: .takeover)
    }

    // MARK: - Dedup actions

    func unmerge(_ event: TimeTugCalendarEvent) {
        commands.send(.unmerge(event), lane: .dedup)
    }

    func separate(_ event: TimeTugCalendarEvent, members: [MergedMember]) {
        commands.send(.separate(event, members: members), lane: .dedup)
    }

    func merge(_ a: TimeTugCalendarEvent, _ b: TimeTugCalendarEvent) {
        commands.send(.merge(a, b), lane: .dedup)
    }

    private func forgetCorrections() {
        commands.send(.forgetCorrections, lane: .dedup)
    }

    // MARK: - System events

    /// Timers alone are not trusted: the engine recomputes after wake, clock, time zone and day changes. Each one
    /// also re-reads settings a widget may have changed (a dropped notification heals here, as on every refresh).
    private func observeSystemEvents() {
        let report: @Sendable (SystemEvent) -> Void = { [weak self] event in
            Task { @MainActor in self?.reportSystemEvent(event) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in report(.wake) }
        let events: [(Notification.Name, SystemEvent)] = [
            (.NSSystemClockDidChange, .clockChanged), (.NSSystemTimeZoneDidChange, .timeZoneChanged),
            (.NSCalendarDayChanged, .dayChanged),
        ]
        for (name, event) in events {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in report(event) }
        }
    }

    private func reportSystemEvent(_ event: SystemEvent) {
        settings.reloadFromShared()
        commands.send(.system(event))
    }

    /// A source poll backs off for up to 15 minutes after a failure, so refresh as soon as the network returns.
    private func observeNetworkReturn() {
        let monitor = NWPathMonitor()
        let wasSatisfied = PathState()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            guard wasSatisfied.update(to: satisfied), satisfied else { return }
            Task { @MainActor in self?.reportSystemEvent(.networkReturned) }
        }
        monitor.start(queue: DispatchQueue(label: "com.timetug.network-path"))
        networkMonitor = monitor
    }

    func openSettings(pane: SettingsPane? = nil) {
        if let pane { navigation.pane = pane }
        settingsWindow.show(on: statusItem?.clickedScreen)
    }
}

/// Last reported network reachability; the path handler runs on one serial queue, the lock keeps it Sendable.
private final class PathState: @unchecked Sendable {
    private let lock = NSLock()
    private var satisfied = true

    /// Stores `new` and returns whether it differs from the previous value.
    func update(to new: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        defer { satisfied = new }
        return satisfied != new
    }
}
