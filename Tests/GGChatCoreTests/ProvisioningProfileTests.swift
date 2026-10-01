import Foundation
import XCTest

@testable import GGChatCore

/// When this build stops opening, read from the profile signed into it.
///
/// The blobs are built here rather than kept as a real profile: a real one
/// names a team, its certificate and every device it was made for. Their
/// shape is a real one's, a signed envelope with bytes that are not text on
/// both sides of the list, and a list whose keys come in a free-team
/// profile's order, `CreationDate` ahead of `ExpirationDate`.
final class ProvisioningProfileTests: XCTestCase {
    private static let expiry = "2026-10-06T07:46:00Z"

    /// The list is read from between the envelope's bytes, and the date is
    /// the one under `ExpirationDate`, not the first date in the list.
    func testTheDateIsReadFromTheListInsideTheEnvelope() throws {
        let read = ProvisioningProfile.expirationDate(in: Self.profile(expiring: Self.expiry))
        XCTAssertEqual(read, try Self.instant(Self.expiry))
    }

    /// No list, or the start of one with no end, is no date rather than a
    /// guess.
    func testABlobWithNoListHasNoDate() {
        XCTAssertNil(ProvisioningProfile.expirationDate(in: Self.envelopeStart + Self.envelopeEnd))
        XCTAssertNil(ProvisioningProfile.expirationDate(in: Data()))
        let cut = Self.list(expiring: Self.expiry).replacingOccurrences(of: "</plist>", with: "")
        XCTAssertNil(ProvisioningProfile.expirationDate(in: Self.envelopeStart + Data(cut.utf8) + Self.envelopeEnd))
    }

    func testAListWithoutAnExpirationDateHasNoDate() {
        XCTAssertNil(ProvisioningProfile.expirationDate(in: Self.profile(expiring: nil)))
    }

    /// A simulator build, and one from the App Store or TestFlight, has no
    /// profile in its bundle.
    func testABundleWithNoProfileHasNoDate() throws {
        let bundle = try bundle(holding: nil)
        XCTAssertNil(ProvisioningProfile.expirationDate(of: bundle))
    }

    /// The file is looked for under the name Xcode gives it in an iOS app.
    func testABundlesProfileIsReadUnderItsName() throws {
        let bundle = try bundle(holding: Self.profile(expiring: Self.expiry))
        XCTAssertEqual(ProvisioningProfile.expirationDate(of: bundle), try Self.instant(Self.expiry))
    }

    // MARK: - Blobs

    /// The start of a CMS envelope as a profile's begins, up to the length
    /// of the list it carries.
    private static let envelopeStart = Data([
        0x30, 0x80, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02, 0xA0, 0x80, 0x30,
        0x80, 0x02, 0x01, 0x01, 0x31, 0x0F, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03,
        0x04, 0x02, 0x01, 0x05, 0x00, 0x30, 0x80, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01,
        0x07, 0x01, 0xA0, 0x80, 0x24, 0x80, 0x04, 0x82, 0x10, 0x9C,
    ])

    /// What follows the list: the end of its octet string, then the start of
    /// the certificates, with bytes that are not UTF-8.
    private static let envelopeEnd = Data([
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xA0, 0x82, 0x0E, 0x40, 0x30, 0x82, 0x04, 0x34, 0x30, 0x82,
        0x03, 0x1C, 0xA0, 0x03, 0x02, 0x01, 0x02, 0x02, 0x08, 0xFF, 0xFE, 0xC3, 0x28, 0x9D, 0xE1, 0x00,
    ])

    private static func profile(expiring expiry: String?) -> Data {
        envelopeStart + Data(list(expiring: expiry).utf8) + envelopeEnd
    }

    private static func list(expiring expiry: String?) -> String {
        let expiration = expiry.map { "\t<key>ExpirationDate</key>\n\t<date>\($0)</date>\n" } ?? ""
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            \t<key>AppIDName</key>
            \t<string>XC com example ggchat</string>
            \t<key>ApplicationIdentifierPrefix</key>
            \t<array>
            \t<string>ABCDE12345</string>
            \t</array>
            \t<key>CreationDate</key>
            \t<date>2026-09-29T07:46:00Z</date>
            \t<key>Platform</key>
            \t<array>
            \t\t<string>iOS</string>
            \t</array>
            \t<key>DeveloperCertificates</key>
            \t<array>
            \t\t<data>MIIFwzCCBKugAwIBAgIQ</data>
            \t</array>
            \t<key>Entitlements</key>
            \t<dict>
            \t\t<key>application-identifier</key>
            \t\t<string>ABCDE12345.com.example.ggchat</string>
            \t\t<key>get-task-allow</key>
            \t\t<true/>
            \t</dict>
            \(expiration)\t<key>Name</key>
            \t<string>iOS Team Provisioning Profile: com.example.ggchat</string>
            \t<key>ProvisionedDevices</key>
            \t<array>
            \t\t<string>00008150-0000000000000001</string>
            \t</array>
            \t<key>TimeToLive</key>
            \t<integer>7</integer>
            \t<key>Version</key>
            \t<integer>1</integer>
            </dict>
            </plist>
            """
    }

    private static func instant(_ text: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: text))
    }

    /// A directory of its own each time, written before the bundle is made,
    /// because a bundle caches what it found.
    private func bundle(holding profile: Data?) throws -> Bundle {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProvisioningProfileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        if let profile {
            try profile.write(to: directory.appendingPathComponent("embedded.mobileprovision"))
        }
        return try XCTUnwrap(Bundle(url: directory))
    }
}
