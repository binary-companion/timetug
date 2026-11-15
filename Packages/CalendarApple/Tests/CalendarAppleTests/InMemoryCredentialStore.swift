import Foundation
import TimeTugKit

/// A credential store for tests: secrets and revisions live in memory.
actor InMemoryCredentialStore: TimeTugKit.CredentialStore {
    private var items: [String: (secrets: [String: String], revision: UUID)] = [:]

    func secrets(connectionId: String) async throws -> [String: String]? { items[connectionId]?.secrets }

    func setSecrets(secrets: [String: String], connectionId: String) async throws {
        items[connectionId] = (secrets, UUID())
    }

    func removeSecrets(connectionId: String) async throws { items[connectionId] = nil }

    func credentialSnapshot(connectionId: String) async throws -> CredentialSnapshot? {
        items[connectionId].map { CredentialSnapshot(secrets: $0.secrets, revision: $0.revision) }
    }

    func updateRefreshToken(token: String, connectionId: String, expectedRevision: UUID) async throws -> Bool {
        guard var item = items[connectionId], item.revision == expectedRevision else { return false }
        item.secrets["refresh_token"] = token
        items[connectionId] = item
        return true
    }
}
