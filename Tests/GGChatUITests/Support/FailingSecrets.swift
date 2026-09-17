import Foundation
import GGChatCore

/// A Keychain that fails, so the app's behaviour when it does is not a guess.
///
/// Support rather than private to one suite: two now drive it — what a failed
/// credential write leaves behind, and what it does to a pipe a pairing has
/// just brought up.
final class FailingSecrets: Secrets, @unchecked Sendable {
    let inner = InMemorySecrets()
    var failOn: SecretKind

    init(failOn: SecretKind) {
        self.failOn = failOn
    }

    func secret(_ kind: SecretKind, for providerID: UUID) throws -> String? {
        try inner.secret(kind, for: providerID)
    }

    func setSecret(_ value: String?, _ kind: SecretKind, for providerID: UUID) throws {
        if kind == failOn, value != nil {
            throw KeychainError(status: -34018, kind: kind)
        }
        try inner.setSecret(value, kind, for: providerID)
    }

    func removeAll(for providerID: UUID) throws {
        try inner.removeAll(for: providerID)
    }
}
