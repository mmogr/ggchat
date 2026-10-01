import Foundation

/// When this build stops opening, read from the provisioning profile signed
/// into it.
///
/// A build signed by a free Apple team carries a profile that runs out seven
/// days after it was issued, and from then on the phone refuses to open the
/// app. A build made later in those seven days can carry the same profile, so
/// the date is read from it rather than counted from the build.
///
/// The profile is a signed envelope around an XML property list, and
/// the list sits in it as plain text, so the date is read by cutting out the
/// bytes from `<?xml` to `</plist>` and reading `ExpirationDate` from them.
/// The signature is not checked: the date is something to tell a person and
/// decides nothing.
///
/// A build from the App Store or TestFlight carries no profile, and neither
/// does a simulator build, so for those there is no date.
public enum ProvisioningProfile {
    /// The date in the bundle's `embedded.mobileprovision`, or nil when it has
    /// none or the file holds no date.
    public static func expirationDate(of bundle: Bundle) -> Date? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
            let profile = try? Data(contentsOf: url)
        else { return nil }
        return expirationDate(in: profile)
    }

    /// `ExpirationDate` from the property list inside `profile`, or nil when
    /// there is no list in it or the list has no date under that key.
    public static func expirationDate(in profile: Data) -> Date? {
        guard let start = profile.range(of: Data("<?xml".utf8)),
            let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex)
        else { return nil }
        let list = Data(profile[start.lowerBound..<end.upperBound])
        return (try? PropertyListDecoder().decode(Fields.self, from: list))?.expirationDate
    }

    private struct Fields: Decodable {
        let expirationDate: Date?

        enum CodingKeys: String, CodingKey {
            case expirationDate = "ExpirationDate"
        }
    }
}
