import Foundation
import XCTest

@testable import GGChatCore

#if canImport(Security)
    import Security

    /// `KeychainSecrets` reaching a fake Security.framework. The real calls need
    /// a signed build carrying the Keychain entitlement, so what is checked here
    /// is every decision the type makes around them: which call goes first, what
    /// each dictionary carries, and which statuses are recoverable.
    final class KeychainSecretsTests: XCTestCase {
        private let provider = UUID(uuidString: "6C1F1C9E-0000-4000-8000-00000000AAAA")!
        private var fake = FakeKeychain()

        override func setUp() {
            super.setUp()
            fake = FakeKeychain()
        }

        private func secrets(accessGroup: String? = nil) -> KeychainSecrets {
            KeychainSecrets(service: "com.example.test", accessGroup: accessGroup, items: fake)
        }

        private var apiKeyAccount: String { "\(provider.uuidString).apiKey" }

        // MARK: - update, then add

        /// The save that happens every time after the first one.
        func testAnItemThatIsAlreadyThereIsUpdatedAndNeverAdded() throws {
            fake.answers(.update, with: errSecSuccess)

            try secrets().setSecret("second-token", .token, for: provider)

            XCTAssertEqual(fake.operations, [.update], "a successful update must end the save")
            XCTAssertEqual(fake.calls.first?.attributes?.text, "second-token")
        }

        /// The first save of a credential: the update misses, and only then is
        /// the item added.
        func testAnItemThatIsNotThereIsAddedOnlyAfterTheUpdateMisses() throws {
            fake.answers(.update, with: errSecItemNotFound)
            fake.answers(.add, with: errSecSuccess)

            try secrets().setSecret("first-token", .token, for: provider)

            XCTAssertEqual(fake.operations, [.update, .add], "the update has to be tried first")
        }

        /// An update that fails for a reason other than a missing item is a real
        /// failure. Adding over it would report `errSecDuplicateItem` and lose
        /// the status that actually explains it.
        func testAnUpdateThatFailsForAnyOtherReasonIsNotRetriedAsAnAdd() {
            fake.answers(.update, with: errSecAuthFailed)

            XCTAssertThrowsError(try secrets().setSecret("t", .token, for: provider)) { error in
                XCTAssertEqual(error as? KeychainError, KeychainError(status: errSecAuthFailed, kind: .token))
            }
            XCTAssertEqual(fake.operations, [.update], "a hard update failure must not fall through to add")
        }

        func testAnAddThatFailsSaysWhichCredentialAndWhichStatus() {
            fake.answers(.update, with: errSecItemNotFound)
            fake.answers(.add, with: errSecMissingEntitlement)

            XCTAssertThrowsError(try secrets().setSecret("k", .apiKey, for: provider)) { error in
                let keychain = error as? KeychainError
                XCTAssertEqual(keychain, KeychainError(status: errSecMissingEntitlement, kind: .apiKey))
                XCTAssertEqual(
                    keychain?.errorDescription,
                    "The API key could not be saved to the Keychain: "
                        + "this build is not signed, so it has no Keychain access (-34018).")
            }
        }

        // MARK: - what the dictionaries carry

        /// The added item is a generic password under the service, keyed by
        /// provider and kind, readable once the device has been unlocked once.
        func testTheAddCarriesTheItemsIdentityItsValueAndItsAccessibility() throws {
            fake.answers(.update, with: errSecItemNotFound)

            try secrets().setSecret("sk-abc", .apiKey, for: provider)

            let add = try XCTUnwrap(fake.calls.last)
            XCTAssertEqual(add.operation, .add)
            XCTAssertEqual(add.query.itemClass, kSecClassGenericPassword as String)
            XCTAssertEqual(add.query.service, "com.example.test")
            XCTAssertEqual(add.query.account, apiKeyAccount)
            XCTAssertEqual(add.query.text, "sk-abc")
            XCTAssertEqual(add.query.accessible, kSecAttrAccessibleAfterFirstUnlock as String)
            XCTAssertNil(add.query.accessGroup, "the app shares no access group; see ADR 0003, rejected")
        }

        /// The update's query identifies the item and its attributes carry the
        /// change. Sending the value in the query instead would match nothing.
        func testTheUpdateIdentifiesTheItemAndCarriesTheValueSeparately() throws {
            fake.answers(.update, with: errSecSuccess)

            try secrets().setSecret("sk-new", .apiKey, for: provider)

            let update = try XCTUnwrap(fake.calls.first)
            XCTAssertEqual(update.query.account, apiKeyAccount)
            XCTAssertNil(update.query.data, "the query must identify, not carry the value")
            XCTAssertEqual(update.attributes?.text, "sk-new")
            XCTAssertEqual(update.attributes?.accessible, kSecAttrAccessibleAfterFirstUnlock as String)
        }

        func testTheAccessGroupIsSentOnlyWhenThereIsOne() throws {
            try secrets(accessGroup: "ABCDE12345.com.example.test").setSecret("t", .ticket, for: provider)
            XCTAssertEqual(fake.calls.first?.query.accessGroup, "ABCDE12345.com.example.test")

            fake = FakeKeychain()
            try secrets().setSecret("t", .ticket, for: provider)
            XCTAssertNil(fake.calls.first?.query.accessGroup)
        }

        func testEachKindOfCredentialGetsItsOwnAccount() throws {
            for kind in SecretKind.allCases {
                try secrets().setSecret("v", kind, for: provider)
            }
            let accounts = fake.calls.compactMap(\.query.account)
            XCTAssertEqual(Set(accounts).count, SecretKind.allCases.count, "kinds must not share an item")
            XCTAssertTrue(accounts.allSatisfy { $0.hasPrefix(provider.uuidString) })
        }

        // MARK: - reading

        func testTheStoredCredentialComesBackOut() throws {
            fake.holds("sk-stored")

            XCTAssertEqual(try secrets().secret(.apiKey, for: provider), "sk-stored")

            let read = try XCTUnwrap(fake.calls.first)
            XCTAssertEqual(read.operation, .copyMatching)
            XCTAssertTrue(read.query.returnsData, "without kSecReturnData the match carries no value")
            XCTAssertEqual(read.query.matchLimit, kSecMatchLimitOne as String)
            XCTAssertEqual(read.query.account, apiKeyAccount)
        }

        /// A provider with no token set is normal, not an error.
        func testACredentialThatWasNeverSavedReadsAsNothing() throws {
            fake.answers(.copyMatching, with: errSecItemNotFound)
            XCTAssertNil(try secrets().secret(.token, for: provider))
        }

        /// A match that is not data is not a credential.
        func testAMatchThatIsNotDataReadsAsNothing() throws {
            fake.answersWithSomethingOtherThanData()
            XCTAssertNil(try secrets().secret(.token, for: provider))
        }

        func testAReadThatFailsForAnyOtherReasonThrows() {
            fake.answers(.copyMatching, with: errSecInteractionNotAllowed)
            XCTAssertThrowsError(try secrets().secret(.ticket, for: provider)) { error in
                XCTAssertEqual(
                    error as? KeychainError, KeychainError(status: errSecInteractionNotAllowed, kind: .ticket))
            }
        }

        // MARK: - deleting

        func testANilValueDeletesTheItemAndWritesNothing() throws {
            try secrets().setSecret(nil, .token, for: provider)

            XCTAssertEqual(fake.operations, [.delete])
            XCTAssertEqual(fake.calls.first?.query.account, "\(provider.uuidString).token")
            XCTAssertNil(fake.calls.first?.query.data)
        }

        /// `addProvider` rolls back by deleting what it wrote, and a credential
        /// that never got written must not turn the rollback into a failure.
        func testDeletingSomethingThatWasNeverThereIsNotAFailure() throws {
            fake.answers(.delete, with: errSecItemNotFound)
            XCTAssertNoThrow(try secrets().setSecret(nil, .token, for: provider))
        }

        func testADeleteThatFailsThrows() {
            fake.answers(.delete, with: errSecAuthFailed)
            XCTAssertThrowsError(try secrets().setSecret(nil, .token, for: provider)) { error in
                XCTAssertEqual(error as? KeychainError, KeychainError(status: errSecAuthFailed, kind: .token))
            }
        }

        /// Removing a provider must leave none of its three credentials behind.
        func testRemoveAllDeletesEveryKindOfCredential() throws {
            try secrets().removeAll(for: provider)

            XCTAssertEqual(fake.operations, [.delete, .delete, .delete])
            XCTAssertEqual(
                Set(fake.calls.compactMap(\.query.account)),
                Set(SecretKind.allCases.map { "\(provider.uuidString).\($0.rawValue)" }))
        }
    }
#endif
