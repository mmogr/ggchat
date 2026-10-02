import Foundation
import GGChatCore
import Security

/// A Keychain that fails, so the app's behaviour when it does is not a guess.
///
/// Support rather than private to one suite: three now drive it — what a
/// failed credential write leaves behind, what it does to a pipe a pairing
/// has just brought up, and what a dial says when a read is refused.
final class FailingSecrets: Secrets, @unchecked Sendable {
    let inner = InMemorySecrets()
    var failOn: SecretKind
    /// The credential whose reads are refused, the way the Keychain refuses
    /// a read before the device's first unlock; nil refuses none.
    var refusesToRead: SecretKind?

    init(failOn: SecretKind) {
        self.failOn = failOn
    }

    func secret(_ kind: SecretKind, for providerID: UUID) throws -> String? {
        if kind == refusesToRead {
            throw KeychainError(status: errSecInteractionNotAllowed, kind: kind, reading: true)
        }
        return try inner.secret(kind, for: providerID)
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
