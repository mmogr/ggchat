import Foundation
import XCTest

@testable import GGChatUI

/// Settings' line saying when this build stops opening.
final class SettingsBuildExpiryTests: XCTestCase {
    /// The day where the person is, in the locale's medium style: 07:00 in
    /// Sydney on the 6th is still the 5th in UTC.
    @MainActor
    func testTheLineSaysTheDayThisBuildStopsOpeningWhereThePersonIs() throws {
        let expiry = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-05T20:00:00Z"))
        let locale = Locale(identifier: "en_GB")
        var sydney = Calendar(identifier: .gregorian)
        sydney.timeZone = try XCTUnwrap(TimeZone(identifier: "Australia/Sydney"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        XCTAssertEqual(
            SettingsView.expiryLine(expiry, locale: locale, calendar: sydney), "This build stops opening on 6 Oct 2026")
        XCTAssertEqual(
            SettingsView.expiryLine(expiry, locale: locale, calendar: utc), "This build stops opening on 5 Oct 2026")
        // A locale whose medium date differs from en_GB's and en_AU's, so the
        // line is seen to follow the locale it is given.
        XCTAssertEqual(
            SettingsView.expiryLine(expiry, locale: Locale(identifier: "de_DE"), calendar: sydney),
            "This build stops opening on 06.10.2026")
    }

    /// No date, from a build with no profile in it, is no row.
    @MainActor
    func testABuildWithNoDateHasNoLine() {
        let calendar = Calendar(identifier: .gregorian)
        XCTAssertNil(SettingsView.expiryLine(nil, locale: Locale(identifier: "en_GB"), calendar: calendar))
    }
}
