import Foundation
import Testing
import TimeTugKit
@testable import CalendarApple

/// A store whose writes fail, like a keychain group the build is not entitled to.
private final class FailingWrites: CredentialStore {
    struct Failure: Error {}
    func secrets(connectionId: String) async throws -> [String: String]? { nil }
    func setSecrets(secrets: [String: String], connectionId: String) async throws { throw Failure() }
    func removeSecrets(connectionId: String) async throws {}
    func credentialSnapshot(connectionId: String) async throws -> CredentialSnapshot? { nil }
    func updateRefreshToken(token: String, connectionId: String, expectedRevision: UUID) async throws -> Bool { false }
}

@Suite struct MigratingCredentialStoreTests {
    @Test func readsThePrimaryWithoutTouchingTheLegacyStore() async throws {
        let primary = InMemoryCredentialStore(), legacy = InMemoryCredentialStore()
        try await primary.setSecrets(secrets: ["t": "new"], connectionId: "a")
        try await legacy.setSecrets(secrets: ["t": "old"], connectionId: "a")
        let store = MigratingCredentialStore(primary: primary, legacy: legacy)
        #expect(try await store.secrets(connectionId: "a") == ["t": "new"])
        #expect(try await legacy.secrets(connectionId: "a") == ["t": "old"])
    }

    @Test func movesALegacyItemIntoThePrimaryOnFirstRead() async throws {
        let primary = InMemoryCredentialStore(), legacy = InMemoryCredentialStore()
        try await legacy.setSecrets(secrets: ["t": "old"], connectionId: "a")
        let store = MigratingCredentialStore(primary: primary, legacy: legacy)
        #expect(try await store.secrets(connectionId: "a") == ["t": "old"])
        #expect(try await primary.secrets(connectionId: "a") == ["t": "old"])
        #expect(try await legacy.secrets(connectionId: "a") == nil)
    }

    @Test func returnsNilWhenNeitherStoreHasTheItem() async throws {
        let store = MigratingCredentialStore(primary: InMemoryCredentialStore(), legacy: InMemoryCredentialStore())
        #expect(try await store.secrets(connectionId: "a") == nil)
        #expect(try await store.credentialSnapshot(connectionId: "a") == nil)
    }

    @Test func aFailedPrimaryWriteKeepsTheLegacyItemAndStillServesIt() async throws {
        let legacy = InMemoryCredentialStore()
        try await legacy.setSecrets(secrets: ["t": "old"], connectionId: "a")
        let store = MigratingCredentialStore(primary: FailingWrites(), legacy: legacy)
        #expect(try await store.secrets(connectionId: "a") == ["t": "old"])
        #expect(try await legacy.secrets(connectionId: "a") == ["t": "old"])
    }

    @Test func writesGoToThePrimaryAndClearAStaleLegacyCopy() async throws {
        let primary = InMemoryCredentialStore(), legacy = InMemoryCredentialStore()
        try await legacy.setSecrets(secrets: ["t": "old"], connectionId: "a")
        let store = MigratingCredentialStore(primary: primary, legacy: legacy)
        try await store.setSecrets(secrets: ["t": "fresh"], connectionId: "a")
        #expect(try await primary.secrets(connectionId: "a") == ["t": "fresh"])
        #expect(try await legacy.secrets(connectionId: "a") == nil)
    }

    @Test func removeClearsBothStores() async throws {
        let primary = InMemoryCredentialStore(), legacy = InMemoryCredentialStore()
        try await primary.setSecrets(secrets: ["t": "x"], connectionId: "a")
        try await legacy.setSecrets(secrets: ["t": "y"], connectionId: "a")
        let store = MigratingCredentialStore(primary: primary, legacy: legacy)
        try await store.removeSecrets(connectionId: "a")
        #expect(try await primary.secrets(connectionId: "a") == nil)
        #expect(try await legacy.secrets(connectionId: "a") == nil)
    }

    @Test func refreshTokenRotationTargetsTheStoreHoldingTheItem() async throws {
        let primary = InMemoryCredentialStore(), legacy = InMemoryCredentialStore()
        try await legacy.setSecrets(secrets: ["refresh_token": "old"], connectionId: "a")
        let store = MigratingCredentialStore(primary: primary, legacy: legacy)
        let snapshot = try #require(try await store.credentialSnapshot(connectionId: "a"))
        #expect(try await store.updateRefreshToken(token: "rotated", connectionId: "a", expectedRevision: snapshot.revision))
        #expect(try await primary.secrets(connectionId: "a")?["refresh_token"] == "rotated")
        #expect(try await legacy.secrets(connectionId: "a") == nil)
    }

    @Test func aStaleRevisionDoesNotRotateTheToken() async throws {
        let primary = InMemoryCredentialStore()
        try await primary.setSecrets(secrets: ["refresh_token": "current"], connectionId: "a")
        let store = MigratingCredentialStore(primary: primary, legacy: InMemoryCredentialStore())
        #expect(try await store.updateRefreshToken(token: "x", connectionId: "a", expectedRevision: UUID()) == false)
        #expect(try await primary.secrets(connectionId: "a")?["refresh_token"] == "current")
    }

    @Test func rotationFallsBackToTheLegacyItemWhenTheCopyFailed() async throws {
        let legacy = InMemoryCredentialStore()
        try await legacy.setSecrets(secrets: ["refresh_token": "old"], connectionId: "a")
        let store = MigratingCredentialStore(primary: FailingWrites(), legacy: legacy)
        let snapshot = try #require(try await store.credentialSnapshot(connectionId: "a"))
        #expect(try await store.updateRefreshToken(token: "rotated", connectionId: "a", expectedRevision: snapshot.revision))
        #expect(try await legacy.secrets(connectionId: "a")?["refresh_token"] == "rotated")
    }
}
