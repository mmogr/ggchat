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

    /// The four `SecItem` calls `KeychainSecrets` makes, behind a name a test
    /// can stand in for. The Keychain is unreachable without a signed build
    /// carrying the entitlement, so no unit test can call the real functions;
    /// this seam is what makes the decisions above them testable instead.
    protocol KeychainItems: Sendable {
        func copyMatching(_ query: [String: Any]) -> (status: OSStatus, value: CFTypeRef?)
        func update(_ query: [String: Any], with attributes: [String: Any]) -> OSStatus
        func add(_ attributes: [String: Any]) -> OSStatus
        func delete(_ query: [String: Any]) -> OSStatus
    }

    /// Security.framework itself. Four forwarding calls and no decisions, so
    /// that everything a test cannot reach is everything a test cannot get
    /// wrong. This type is the disclosed untested remainder.
    struct SystemKeychain: KeychainItems {
        func copyMatching(_ query: [String: Any]) -> (status: OSStatus, value: CFTypeRef?) {
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result)
        }

        func update(_ query: [String: Any], with attributes: [String: Any]) -> OSStatus {
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        }

        func add(_ attributes: [String: Any]) -> OSStatus {
            SecItemAdd(attributes as CFDictionary, nil)
        }

        func delete(_ query: [String: Any]) -> OSStatus {
            SecItemDelete(query as CFDictionary)
        }
    }

    /// Generic-password items, one per (provider, kind), in this build's own
    /// default access group and never synchronizable, so a credential stays
    /// on the device that saved it. ADR 0003 proposed sharing them and was
    /// rejected; the app passes no `accessGroup`.
    public struct KeychainSecrets: Secrets {
        public var service: String
        public var accessGroup: String?
        let items: any KeychainItems

        public init(service: String = "com.mattogrady.ggchat", accessGroup: String? = nil) {
            self.init(service: service, accessGroup: accessGroup, items: SystemKeychain())
        }

        init(service: String = "com.mattogrady.ggchat", accessGroup: String? = nil, items: any KeychainItems) {
            self.service = service
            self.accessGroup = accessGroup
            self.items = items
        }

        public func secret(_ kind: SecretKind, for providerID: UUID) throws -> String? {
            var query = baseQuery(kind, providerID)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            let (status, result) = items.copyMatching(query)
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

        /// The Keychain has no upsert. An item already there must be updated,
        /// because adding over it fails with `errSecDuplicateItem`, and an item
        /// not there yet must be added, because updating nothing fails with
        /// `errSecItemNotFound`. Update first and add only on that one status:
        /// the first save of a credential and every save after it both work,
        /// and any other failure is reported rather than retried.
        public func setSecret(_ value: String?, _ kind: SecretKind, for providerID: UUID) throws {
            let query = baseQuery(kind, providerID)
            guard let value else {
                let status = items.delete(query)
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    throw KeychainError(status: status, kind: kind)
                }
                return
            }
            let attributes: [String: Any] = [
                kSecValueData as String: Data(value.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ]
            let update = items.update(query, with: attributes)
            if update == errSecSuccess { return }
            guard update == errSecItemNotFound else { throw KeychainError(status: update, kind: kind) }
            let add = items.add(query.merging(attributes) { $1 })
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
