import EventKit
import Foundation
import Testing
import TimeTugKit
@testable import EventKitSource

/// Stands in for the system's calendar prompt: the status it reports, what the prompt answers, and how often it was shown.
private final class FakeAuthorization: EventStoreAuthorization, @unchecked Sendable {
    struct PromptFailed: Error {}
    private let lock = NSLock()
    private var current: EKAuthorizationStatus
    private let answer: Result<Bool, PromptFailed>
    private var prompts = 0

    init(status: EKAuthorizationStatus, answer: Result<Bool, PromptFailed> = .success(true)) {
        current = status
        self.answer = answer
    }

    var promptCount: Int { lock.withLock { prompts } }
    func status() -> EKAuthorizationStatus { lock.withLock { current } }

    /// A grant changes the status the way the system does; a refusal leaves it where it was (denied once asked).
    func requestFullAccess() async throws -> Bool {
        lock.withLock { prompts += 1 }
        let granted = try answer.get()
        lock.withLock { current = granted ? .fullAccess : .denied }
        return granted
    }
}

private func source(_ authorization: FakeAuthorization, notifications: NotificationCenter = NotificationCenter()) -> EventKitSource {
    EventKitSource(store: EKEventStore(), contacts: ContactEmailResolver(), authorization: authorization, notifications: notifications)
}

@Test func theSourceIsKnownAsEventkitAndAppleCalendar() {
    // Stored calendar keys and settings start with `eventkit/`: the engine uses `id()` as the source id.
    let source = EventKitSource()
    #expect(source.id() == "eventkit" && EventKitSource.sourceID == "eventkit")
    #expect(source.displayName() == "Apple Calendar")
}

// MARK: requestAccess

@Test func requestAccessThatIsGrantedAsksOnceAndLetsReadsThrough() async throws {
    let authorization = FakeAuthorization(status: .notDetermined, answer: .success(true))
    let source = source(authorization)
    #expect(throws: FfiError.Source(.needsPermission)) { try source.requireAccess() }
    await source.requestAccess()
    #expect(authorization.promptCount == 1)
    try source.requireAccess()
}

@Test func requestAccessThatIsDeniedReturnsAndReadsStillNeedPermission() async {
    let authorization = FakeAuthorization(status: .notDetermined, answer: .success(false))
    let source = source(authorization)
    await source.requestAccess()
    #expect(authorization.promptCount == 1)
    #expect(throws: FfiError.Source(.needsPermission)) { try source.requireAccess() }
    await #expect(throws: FfiError.Source(.needsPermission)) { _ = try await source.calendars() }
    await #expect(throws: FfiError.Source(.needsPermission)) { _ = try await source.eventsIn(start: Date(), end: Date()) }
}

@Test func requestAccessWhenAlreadyGrantedDoesNotAskAgain() async throws {
    let authorization = FakeAuthorization(status: .fullAccess)
    let source = source(authorization)
    await source.requestAccess()
    #expect(authorization.promptCount == 0)
    try source.requireAccess()
}

@Test func requestAccessWhenThePromptFailsReturnsAndLeavesAccessOff() async {
    let authorization = FakeAuthorization(status: .notDetermined, answer: .failure(.init()))
    let source = source(authorization)
    await source.requestAccess()
    #expect(authorization.promptCount == 1)
    #expect(throws: FfiError.Source(.needsPermission)) { try source.requireAccess() }
}

@Test func writeOnlyAccessIsNotEnoughToRead() {
    #expect(throws: FfiError.Source(.needsPermission)) { try source(FakeAuthorization(status: .writeOnly)).requireAccess() }
}

// MARK: setChangeHandler

/// A `SystemChangeHandler` without the engine behind it (UniFFI's `noHandle` fake), recording what the host tells it.
private final class RecordingHandler: SystemChangeHandler, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []

    init() { super.init(noHandle: NoHandle()) }
    required init(unsafeFromHandle handle: UInt64) { fatalError("not backed by an engine") }

    var calls: [String] { lock.withLock { log } }
    override func calendarsChanged() { lock.withLock { log.append("calendarsChanged") } }
    override func eventsChanged(calendarIds: [String]?) { lock.withLock { log.append("eventsChanged(\(calendarIds.map { "\($0)" } ?? "nil"))") } }
    override func sourceFailed(error: SourceError) { lock.withLock { log.append("sourceFailed") } }
}

@Test func aStoreChangedNotificationCallsTheHandlerOnce() async {
    let center = NotificationCenter()
    let source = source(FakeAuthorization(status: .fullAccess), notifications: center)
    let handler = RecordingHandler()
    await source.setChangeHandler(handler: handler)
    #expect(handler.calls.isEmpty)
    center.post(name: .EKEventStoreChanged, object: source.store)
    #expect(handler.calls == ["calendarsChanged"])
}

@Test func eachStoreChangeIsOneCallAndAnotherStoresChangesAreIgnored() async {
    let center = NotificationCenter()
    let source = source(FakeAuthorization(status: .fullAccess), notifications: center)
    let handler = RecordingHandler()
    await source.setChangeHandler(handler: handler)
    center.post(name: .EKEventStoreChanged, object: EKEventStore())
    #expect(handler.calls.isEmpty)
    center.post(name: .EKEventStoreChanged, object: source.store)
    center.post(name: .EKEventStoreChanged, object: source.store)
    #expect(handler.calls == ["calendarsChanged", "calendarsChanged"])
}

@Test func aContactsGrantMakesTheHostFetchEventsAgain() async {
    let center = NotificationCenter()
    let source = source(FakeAuthorization(status: .fullAccess), notifications: center)
    let handler = RecordingHandler()
    await source.setChangeHandler(handler: handler)
    center.post(name: ContactEmailResolver.accessGranted, object: nil)
    #expect(handler.calls == ["eventsChanged(nil)"])
}

@Test func aNewHandlerReplacesTheOldOneAndNothingIsSentBeforeItIsSet() async {
    let center = NotificationCenter()
    let source = source(FakeAuthorization(status: .fullAccess), notifications: center)
    center.post(name: .EKEventStoreChanged, object: source.store)   // no handler yet: nobody to tell, nothing to crash
    let first = RecordingHandler(), second = RecordingHandler()
    await source.setChangeHandler(handler: first)
    await source.setChangeHandler(handler: second)
    center.post(name: .EKEventStoreChanged, object: source.store)
    #expect(first.calls.isEmpty)
    #expect(second.calls == ["calendarsChanged"])
}

@Test func aReleasedSourceStopsListening() async {
    let center = NotificationCenter()
    let handler = RecordingHandler()
    let store = EKEventStore()
    do {
        let source = EventKitSource(store: store, contacts: ContactEmailResolver(), authorization: FakeAuthorization(status: .fullAccess), notifications: center)
        await source.setChangeHandler(handler: handler)
    }
    center.post(name: .EKEventStoreChanged, object: store)
    #expect(handler.calls.isEmpty)
}

// MARK: the availability fallback (the rule of `Availability.closest(in:)` in 1.x)

@Test func closestAvailabilityIsTheValueItselfOrTheNearestSupported() {
    let all: Set<Availability> = [.busy, .free, .tentative, .unavailable]
    for value in all { #expect(EventKitMapping.closest(value, in: all) == value) }
    #expect(EventKitMapping.closest(.tentative, in: [.busy, .free]) == .busy)
    #expect(EventKitMapping.closest(.unavailable, in: [.free]) == .free)
    #expect(EventKitMapping.closest(.busy, in: [.free]) == .free)
    #expect(EventKitMapping.closest(.free, in: [.busy]) == .busy)
    #expect(EventKitMapping.closest(.busy, in: []) == nil)   // a calendar that tracks no availability
}
