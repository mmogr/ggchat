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
    public struct KeychainError: Error, Sendable, Equatable {
        public var status: OSStatus
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
                throw KeychainError(status: status)
            }
        }

        public func setSecret(_ value: String?, _ kind: SecretKind, for providerID: UUID) throws {
            let query = baseQuery(kind, providerID)
            guard let value else {
                let status = SecItemDelete(query as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    throw KeychainError(status: status)
                }
                return
            }
            let attributes: [String: Any] = [
                kSecValueData as String: Data(value.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ]
            let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if update == errSecSuccess { return }
            guard update == errSecItemNotFound else { throw KeychainError(status: update) }
            let add = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
            guard add == errSecSuccess else { throw KeychainError(status: add) }
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
