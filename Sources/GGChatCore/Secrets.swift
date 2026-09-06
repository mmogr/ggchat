import Foundation
import Synchronization

#if canImport(Security)
    import Security
#endif

/// The three credentials the app keeps, each under its provider's id.
public enum SecretKind: String, Sendable, CaseIterable {
    case apiKey
    case ticket
    case token

    /// What to call it in a sentence shown to someone.
    public var name: String {
        switch self {
        case .apiKey: "API key"
        case .ticket: "ticket"
        case .token: "token"
        }
    }
}

/// Where credentials live. Nothing in a `ProviderConfig` is secret; these are.
public protocol Secrets: Sendable {
    func secret(_ kind: SecretKind, for providerID: UUID) throws -> String?
    func setSecret(_ value: String?, _ kind: SecretKind, for providerID: UUID) throws
    func removeAll(for providerID: UUID) throws
}

public final class InMemorySecrets: Secrets, Sendable {
    private let storage = Mutex<[String: String]>([:])

    public init() {}

    public func secret(_ kind: SecretKind, for providerID: UUID) throws -> String? {
        storage.withLock { $0[Self.key(kind, providerID)] }
    }

    public func setSecret(_ value: String?, _ kind: SecretKind, for providerID: UUID) throws {
        storage.withLock { $0[Self.key(kind, providerID)] = value }
    }

    public func removeAll(for providerID: UUID) throws {
        storage.withLock { store in
            for kind in SecretKind.allCases { store[Self.key(kind, providerID)] = nil }
        }
    }

    static func key(_ kind: SecretKind, _ providerID: UUID) -> String {
        "\(providerID.uuidString).\(kind.rawValue)"
    }
}

#if canImport(Security)
    /// Carries the OSStatus and what the system calls it, because
    /// "operation couldn't be completed" tells a user nothing about a
    /// credential that failed to save.
    public struct KeychainError: Error, Sendable, Equatable, LocalizedError {
        public var status: OSStatus
        public var kind: SecretKind

        public init(status: OSStatus, kind: SecretKind) {
            self.status = status
            self.kind = kind
        }

        public var errorDescription: String? {
            "The \(kind.name) could not be saved to the Keychain: \(reason) (\(status))."
        }

        /// `errSecMissingEntitlement` is the one a developer meets: an app
        /// built without signing has no Keychain access at all.
        var reason: String {
            if status == -34018 {
                return "this build is not signed, so it has no Keychain access"
            }
            return SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "the Keychain refused it"
        }
    }

    /// Generic-password items, one per (provider, kind). `accessGroup` stays
    /// nil until a signing team exists; see ADR 0003.
    public struct KeychainSecrets: Secrets {
        public var service: String
        public var accessGroup: String?

        public init(service: String = "com.mattogrady.ggchat", accessGroup: String? = nil) {
            self.service = service
            self.accessGroup = accessGroup
        }

        public func secret(_ kind: SecretKind, for providerID: UUID) throws -> String? {
            var query = baseQuery(kind, providerID)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            switch status {
            case errSecSuccess:
                guard let data = result as? Data else { return nil }
                return String(decoding: data, as: UTF8.self)
            case errSecItemNotFound:
                return nil
            default:
                throw KeychainError(status: status, kind: kind)
            }
        }

        public func setSecret(_ value: String?, _ kind: SecretKind, for providerID: UUID) throws {
            let query = baseQuery(kind, providerID)
            guard let value else {
                let status = SecItemDelete(query as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    throw KeychainError(status: status, kind: kind)
                }
                return
            }
            let attributes: [String: Any] = [
                kSecValueData as String: Data(value.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ]
            let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if update == errSecSuccess { return }
            guard update == errSecItemNotFound else { throw KeychainError(status: update, kind: kind) }
            let add = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
            guard add == errSecSuccess else { throw KeychainError(status: add, kind: kind) }
        }

        public func removeAll(for providerID: UUID) throws {
            for kind in SecretKind.allCases {
                try setSecret(nil, kind, for: providerID)
            }
        }

        private func baseQuery(_ kind: SecretKind, _ providerID: UUID) -> [String: Any] {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: InMemorySecrets.key(kind, providerID),
            ]
            if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
            return query
        }
    }
#endif
