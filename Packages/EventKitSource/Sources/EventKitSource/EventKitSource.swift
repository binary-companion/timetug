import EventKit
import Foundation
import TimeTugKit

/// What `EventKitSource` needs to know about calendar access, so tests can stand in for the system prompt.
protocol EventStoreAuthorization: Sendable {
    func status() -> EKAuthorizationStatus
    func requestFullAccess() async throws -> Bool
}

/// The real thing: `EKEventStore`'s class-level status and its prompt. `EKEventStore` is documented as safe to use from
/// any thread, but EventKit does not mark it `Sendable`.
struct SystemEventStoreAuthorization: EventStoreAuthorization, @unchecked Sendable {
    let store: EKEventStore
    func status() -> EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    func requestFullAccess() async throws -> Bool { try await store.requestFullAccessToEvents() }
}

/// Apple Calendar via EventKit (includes iCloud, Google and Exchange accounts added to macOS), as the engine's
/// `SystemCalendarSource`. EventKit types never leave this module. Its id is the constant "eventkit" (existing stored
/// calendar keys start with `eventkit/`); the engine uses `id()` as the source id.
public final class EventKitSource: SystemCalendarSource, @unchecked Sendable {
    public static let sourceID = "eventkit"
    public static let sourceDisplayName = "Apple Calendar"
    let store: EKEventStore
    let contacts: ContactEmailResolver
    let authorization: any EventStoreAuthorization
    private let notifications: NotificationCenter
    private let observerLock = NSLock()
    private var observers: [NSObjectProtocol] = []

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
        self.contacts = ContactEmailResolver()
        self.authorization = SystemEventStoreAuthorization(store: store)
        self.notifications = .default
    }

    init(
        store: EKEventStore, contacts: ContactEmailResolver, authorization: (any EventStoreAuthorization)? = nil,
        notifications: NotificationCenter = .default
    ) {
        self.store = store
        self.contacts = contacts
        self.authorization = authorization ?? SystemEventStoreAuthorization(store: store)
        self.notifications = notifications
    }

    deinit { removeObservers() }

    public func id() -> String { Self.sourceID }
    public func displayName() -> String { Self.sourceDisplayName }
    public func capabilities() -> SourceCapabilities {
        SourceCapabilities(
            canWrite: true, providedFields: [.reminders, .series, .participation, .supportedAvailabilities, .recurrenceRules], syncKind: .notification,
            writableFields: [.title, .notes, .location, .timing, .availability, .reminders, .recurrence],
            controlsNotifications: false, recurrenceScopes: [.thisInstance, .thisAndFollowing, .allInSeries])
    }

    /// Prompts for calendar access if undetermined. A grant, a refusal and a failed prompt all return normally: the
    /// engine finds out through the next read, which throws `needsPermission` without access.
    public func requestAccess() async {
        if authorization.status() == .fullAccess { return }
        _ = try? await authorization.requestFullAccess()
    }

    /// A store-changed notification tells the handler the calendars changed; a Contacts grant, which makes participant
    /// emails resolvable, tells it to fetch events again. A second call replaces the first handler.
    public func setChangeHandler(handler: SystemChangeHandler) async {
        observe(handler)
    }

    func observe(_ handler: any SystemChangeHandlerProtocol) {
        let changed = notifications.addObserver(forName: .EKEventStoreChanged, object: store, queue: nil) { _ in
            handler.calendarsChanged()
        }
        let grant = notifications.addObserver(forName: ContactEmailResolver.accessGranted, object: nil, queue: nil) { _ in
            handler.eventsChanged(calendarIds: nil)
        }
        observerLock.withLock {
            observers.forEach(notifications.removeObserver)
            observers = [changed, grant]
        }
    }

    private func removeObservers() {
        observerLock.withLock {
            observers.forEach(notifications.removeObserver)
            observers = []
        }
    }

    public func calendars() async throws -> [CalendarDescriptor] {
        try requireAccess()
        let defaultCalendar = store.defaultCalendarForNewEvents
        return store.calendars(for: .event).map {
            let account = $0.source?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return CalendarDescriptor(
                id: $0.calendarIdentifier, title: $0.title, service: .eventKit, colorHex: EventKitMapping.hex(from: $0.cgColor),
                permissions: CalendarPermissions(canViewDetails: true, canEdit: $0.allowsContentModifications),
                isDefault: EventKitMapping.isDefault(
                    calendarID: $0.calendarIdentifier, calendarSourceID: $0.source?.sourceIdentifier,
                    defaultCalendarID: defaultCalendar?.calendarIdentifier, defaultSourceID: defaultCalendar?.source?.sourceIdentifier),
                accountName: (account?.isEmpty ?? true) ? nil : account, kind: EventKitMapping.kind($0.type),
                provider: EventKitMapping.provider(sourceType: $0.source?.sourceType, calendarType: $0.type),
                supportedAvailabilities: EventKitMapping.supportedAvailabilities($0.supportedEventAvailabilities))
        }
    }

    public func eventsIn(start: Timestamp, end: Timestamp) async throws -> [CalendarEvent] {
        try requireAccess()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        let resolved = contacts.emails(for: Self.unresolvedParticipants(in: events))
        return events.map { map($0, resolvedEmails: resolved) }
    }

    /// The distinct participants whose address is not an email (so matching would lose them).
    static func unresolvedParticipants(in events: [EKEvent]) -> [UnresolvedParticipant] {
        var seen = Set<String>()
        var result: [UnresolvedParticipant] = []
        for event in events {
            for participant in (event.attendees ?? []) + (event.organizer.map { [$0] } ?? []) {
                let url = participant.url.absoluteString
                guard calendarUserAddressEmail(address: url) == nil, seen.insert(url).inserted else { continue }
                result.append(UnresolvedParticipant(url: url, predicate: participant.contactPredicate))
            }
        }
        return result
    }

    func requireAccess() throws {
        guard authorization.status() == .fullAccess else { throw FfiError.Source(.needsPermission) }
    }

    private func attendee(_ p: EKParticipant, isOrganizer: Bool, resolvedEmails: [String: [String]], preferredDomains: Set<String>) -> Attendee {
        let email = calendarUserAddressEmail(address: p.url.absoluteString)
            ?? ContactEmailResolver.choose(resolvedEmails[p.url.absoluteString] ?? [], preferredDomains: preferredDomains)
        return Attendee(name: p.name, email: email, role: EventKitMapping.role(p),
                 response: EventKitMapping.response(p.participantStatus) ?? .needsAction,
                 isSelf: p.isCurrentUser, isOrganizer: isOrganizer)
    }

    /// `resolvedEmails` (participant URL to a contact's emails) fills in participants EventKit gave no email for.
    func map(_ event: EKEvent, resolvedEmails: [String: [String]] = [:]) -> CalendarEvent {
        let known = ((event.attendees ?? []) + (event.organizer.map { [$0] } ?? []))
            .compactMap { calendarUserAddressEmail(address: $0.url.absoluteString) }
        let domains = Set(known.compactMap { $0.split(separator: "@").last.map(String.init) })
        let attendees = (event.attendees ?? []).map { attendee($0, isOrganizer: false, resolvedEmails: resolvedEmails, preferredDomains: domains) }
        let me = (event.attendees ?? []).first { $0.isCurrentUser }
        var start = event.startDate ?? Date(), end = event.endDate ?? start
        var zone = event.timeZone ?? .current
        if event.isAllDay {
            // Floating device-local dates: normalize to the canonical form in the device zone.
            let calendar = Calendar.current
            (start, end) = EventKitMapping.canonicalAllDay(start: start, end: end, calendar: calendar)
            zone = calendar.timeZone
        }
        let isSeries = event.hasRecurrenceRules || event.isDetached
        // One value feeds both ids, so a ref never has an occurrence `eventID` with a nil `seriesID`.
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        return CalendarEvent(
            eventID: EventKitMapping.eventID(identifier: identifier, occurrenceDate: event.occurrenceDate ?? start, isOccurrence: isSeries),
            uid: event.calendarItemExternalIdentifier,
            uidScope: EventKitMapping.uidScope(provider: EventKitMapping.provider(sourceType: event.calendar.source?.sourceType, calendarType: event.calendar.type)),
            calendarID: event.calendar.calendarIdentifier,
            title: event.title ?? "(No title)",
            notes: event.notes, location: event.location, start: start, end: end, timeZone: zone,
            isAllDay: event.isAllDay, status: EventKitMapping.status(event.status),
            availability: EventKitMapping.availability(event.availability),
            series: EventKitMapping.series(isOccurrence: isSeries, identifier: identifier, occurrenceDate: event.occurrenceDate),
            attendees: attendees, organizer: event.organizer.map { attendee($0, isOrganizer: true, resolvedEmails: resolvedEmails, preferredDomains: domains) },
            conferences: detectConferences(structured: [], location: event.location, url: event.url, notes: event.notes),
            reminders: (event.alarms ?? []).map(EventKitMapping.reminder),
            url: event.url, version: EventKitWriteMapping.version(event.lastModifiedDate),
            lastModified: event.lastModifiedDate, created: event.creationDate,
            participation: EventKitMapping.participation(selfStatus: me?.participantStatus, organizerIsCurrentUser: event.organizer?.isCurrentUser ?? false),
            sourceID: EventKitSource.sourceID)
    }
}
