import Foundation
import TimeTugKit

/// Reads from `primary` (the shared keychain group); an item found only in `legacy` (the app's old private keychain
/// item) is copied into `primary` and then removed from `legacy`. If the copy fails the legacy item is kept and still
/// served, so a credential is never lost to a failed migration. An actor, so the check-then-copy cannot interleave
/// with another call.
public actor MigratingCredentialStore: TimeTugKit.CredentialStore {
    private let primary: any CredentialStore
    private let legacy: any CredentialStore

    public init(primary: any CredentialStore, legacy: any CredentialStore) {
        self.primary = primary
        self.legacy = legacy
    }

    public func secrets(connectionId connectionID: String) async throws -> [String: String]? {
        try await credentialSnapshot(connectionId: connectionID)?.secrets
    }

    public func credentialSnapshot(connectionId connectionID: String) async throws -> CredentialSnapshot? {
        if let current = try await primary.credentialSnapshot(connectionId: connectionID) { return current }
        guard let old = try await legacy.credentialSnapshot(connectionId: connectionID) else { return nil }
        do {
            try await primary.setSecrets(secrets: old.secrets, connectionId: connectionID)
        } catch {
            return old   // keep serving (and updating) the legacy item; the next read tries the copy again
        }
        // Best effort: a leftover legacy item is harmless because the primary wins from now on.
        try? await legacy.removeSecrets(connectionId: connectionID)
        return try await primary.credentialSnapshot(connectionId: connectionID) ?? old
    }

    public func setSecrets(secrets: [String: String], connectionId connectionID: String) async throws {
        try await primary.setSecrets(secrets: secrets, connectionId: connectionID)
        try? await legacy.removeSecrets(connectionId: connectionID)
    }

    public func removeSecrets(connectionId connectionID: String) async throws {
        try await primary.removeSecrets(connectionId: connectionID)
        try await legacy.removeSecrets(connectionId: connectionID)
    }

    public func updateRefreshToken(token: String, connectionId connectionID: String, expectedRevision: UUID) async throws -> Bool {
        if try await primary.credentialSnapshot(connectionId: connectionID) != nil {
            return try await primary.updateRefreshToken(token: token, connectionId: connectionID, expectedRevision: expectedRevision)
        }
        return try await legacy.updateRefreshToken(token: token, connectionId: connectionID, expectedRevision: expectedRevision)
    }
}
