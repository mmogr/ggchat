import Foundation
import Synchronization

@testable import GGChatCore

#if canImport(Security)
    import Security

    /// Which of the four `SecItem` calls was made.
    enum KeychainOperation: String, Sendable, Equatable {
        case copyMatching
        case update
        case add
        case delete
    }

    /// What a test cares about in a query or attribute dictionary. `[String: Any]`
    /// is not `Sendable` and cannot be kept in a `Mutex`, so the fake reads the
    /// keys out at call time and records those.
    struct KeychainFields: Sendable, Equatable {
        var itemClass: String?
        var service: String?
        var account: String?
        var accessGroup: String?
        var accessible: String?
        var data: Data?
        var returnsData: Bool
        var matchLimit: String?

        init(_ dictionary: [String: Any]) {
            itemClass = dictionary[kSecClass as String] as? String
            service = dictionary[kSecAttrService as String] as? String
            account = dictionary[kSecAttrAccount as String] as? String
            accessGroup = dictionary[kSecAttrAccessGroup as String] as? String
            accessible = dictionary[kSecAttrAccessible as String] as? String
            data = dictionary[kSecValueData as String] as? Data
            returnsData = dictionary[kSecReturnData as String] as? Bool ?? false
            matchLimit = dictionary[kSecMatchLimit as String] as? String
        }

        /// The credential this dictionary carries, read back as a string.
        var text: String? { data.map { String(decoding: $0, as: UTF8.self) } }
    }

    /// One recorded call: which operation, the dictionary it was given, and for
    /// an update the separate attributes dictionary.
    struct KeychainCall: Sendable, Equatable {
        var operation: KeychainOperation
        var query: KeychainFields
        var attributes: KeychainFields?
    }

    /// Stands in for Security.framework. It answers each operation with the
    /// status the test scripted and records the calls in the order they arrived,
    /// so a test can assert on the order and not only on the outcome.
    final class FakeKeychain: KeychainItems, Sendable {
        private struct State: Sendable {
            var statuses: [KeychainOperation: OSStatus] = [:]
            var calls: [KeychainCall] = []
            var storedText: String?
            var answersWithANonDataValue = false
        }

        /// What a read answers with. `CFTypeRef` is not `Sendable`, so the value
        /// is built outside the lock from these.
        private struct Answer: Sendable {
            var status: OSStatus
            var text: String?
            var isNotData: Bool
        }

        private let state = Mutex(State())

        /// Every call so far, in order.
        var calls: [KeychainCall] { state.withLock { $0.calls } }

        /// Just the operations, for asserting on order.
        var operations: [KeychainOperation] { state.withLock { $0.calls.map(\.operation) } }

        /// What the named operation answers. An operation left unscripted answers
        /// `errSecItemNotFound` for a read or an update and `errSecSuccess` for an
        /// add or a delete, which is an empty Keychain taking its first save.
        func answers(_ operation: KeychainOperation, with status: OSStatus) {
            state.withLock { $0.statuses[operation] = status }
        }

        /// The credential `copyMatching` hands back, and the success that goes
        /// with it.
        func holds(_ text: String) {
            state.withLock {
                $0.storedText = text
                $0.statuses[.copyMatching] = errSecSuccess
            }
        }

        /// A successful match whose value is not `Data`, which is what a query
        /// that asked for attributes rather than data would get back.
        func answersWithSomethingOtherThanData() {
            state.withLock {
                $0.answersWithANonDataValue = true
                $0.statuses[.copyMatching] = errSecSuccess
            }
        }

        func copyMatching(_ query: [String: Any]) -> (status: OSStatus, value: CFTypeRef?) {
            let answer = state.withLock { state in
                state.calls.append(KeychainCall(operation: .copyMatching, query: KeychainFields(query)))
                return Answer(
                    status: state.statuses[.copyMatching] ?? errSecItemNotFound,
                    text: state.storedText,
                    isNotData: state.answersWithANonDataValue)
            }
            if answer.isNotData { return (answer.status, NSNumber(value: 1)) }
            return (answer.status, answer.text.map { Data($0.utf8) as NSData })
        }

        func update(_ query: [String: Any], with attributes: [String: Any]) -> OSStatus {
            record(.update, query, attributes, unscripted: errSecItemNotFound)
        }

        func add(_ attributes: [String: Any]) -> OSStatus {
            record(.add, attributes, nil, unscripted: errSecSuccess)
        }

        func delete(_ query: [String: Any]) -> OSStatus {
            record(.delete, query, nil, unscripted: errSecSuccess)
        }

        private func record(
            _ operation: KeychainOperation, _ query: [String: Any], _ attributes: [String: Any]?,
            unscripted: OSStatus
        ) -> OSStatus {
            let call = KeychainCall(
                operation: operation, query: KeychainFields(query),
                attributes: attributes.map(KeychainFields.init))
            return state.withLock { state in
                state.calls.append(call)
                return state.statuses[operation] ?? unscripted
            }
        }
    }
#endif
