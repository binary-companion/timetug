import Foundation
import TimeTugKit
import Security
import Testing
@testable import CalendarApple

private func makeStore() -> KeychainCredentialStore {
    KeychainCredentialStore(service: "com.timetug.tests.\(UUID().uuidString)")
}
/// `.enabled(if:)` needs a synchronous condition, so probe the Keychain with the Security API directly.
private func keychainAvailable() -> Bool {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.timetug.tests.probe.\(UUID().uuidString)",
        kSecAttrAccount as String: "probe",
        kSecValueData as String: Data("1".utf8),
    ]
    guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { return false }
    SecItemDelete(query as CFDictionary)
    return true
}

@Test(.enabled(if: keychainAvailable())) func setGetOverwriteRemove() async throws {
    let store = makeStore()
    #expect(try await store.secrets(connectionId: "c1") == nil)
    try await store.setSecrets(secrets: ["refresh_token": "r1"], connectionId: "c1")
    #expect(try await store.secrets(connectionId: "c1") == ["refresh_token": "r1"])
    try await store.setSecrets(secrets: ["refresh_token": "r2", "extra": "x"], connectionId: "c1")
    #expect(try await store.secrets(connectionId: "c1") == ["refresh_token": "r2", "extra": "x"])
    try await store.removeSecrets(connectionId: "c1")
    #expect(try await store.secrets(connectionId: "c1") == nil)
    try await store.removeSecrets(connectionId: "c1")   // idempotent
}

@Test(.enabled(if: keychainAvailable())) func connectionsAreIsolated() async throws {
    let store = makeStore()
    try await store.setSecrets(secrets: ["a": "1"], connectionId: "c1")
    try await store.setSecrets(secrets: ["a": "2"], connectionId: "c2")
    #expect(try await store.secrets(connectionId: "c1") == ["a": "1"])
    try await store.removeSecrets(connectionId: "c1")
    try await store.removeSecrets(connectionId: "c2")
}

@Test(.enabled(if: keychainAvailable())) func legacyCredentialIsMigratedAndRotationCannotUndoNewSignIn() async throws {
    let service = "com.timetug.tests.\(UUID().uuidString)"
    let store = KeychainCredentialStore(service: service)
    let old = try JSONEncoder().encode(["refresh_token": "old"])
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: "c1",
        kSecValueData as String: old,
    ]
    #expect(SecItemAdd(query as CFDictionary, nil) == errSecSuccess)
    defer { SecItemDelete(query as CFDictionary) }
    let snapshot = try #require(try await store.credentialSnapshot(connectionId: "c1"))
    #expect(snapshot.secrets["refresh_token"] == "old")
    #expect(try await store.updateRefreshToken(token: "rotated", connectionId: "c1", expectedRevision: snapshot.revision))
    try await store.setSecrets(secrets: ["refresh_token": "new-sign-in"], connectionId: "c1")
    #expect(try await store.updateRefreshToken(token: "stale", connectionId: "c1", expectedRevision: snapshot.revision) == false)
    #expect(try await store.secrets(connectionId: "c1")?["refresh_token"] == "new-sign-in")
}
