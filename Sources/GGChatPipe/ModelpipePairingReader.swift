import GGChatCore
import Modelpipe

/// The real thing behind `PairingReader`: modelpipe's own parse of the
/// string, and no second one here.
///
/// `mpReadPairing` is what `mpPair` reads the string with, so what the form
/// accepts is exactly what pairing accepts. It is a real decode rather than
/// a look at the shape, which is why a ticket with a bad checksum is refused
/// as it is typed instead of at the dial.
///
/// No closure to substitute, unlike `ModelpipeConnector`'s dial and pairing.
/// There is nothing here to drive except the call itself: a fake would only
/// prove that a test's own parser agrees with the test.
///
/// This is the one place `mpReadPairing` is called. `ModelpipeConnector`
/// reads a ticket through here rather than calling the binding a second time,
/// so the mapping from a refused read to a sentence exists once — which is
/// the whole argument this change makes about the parse itself.
public struct ModelpipePairingReader: PairingReader {
    /// What the last arm below shows when the binding throws something that
    /// is not an `MpPairError`.
    ///
    /// A fixed sentence, and none of the thrown error's own words. uniffi's
    /// `rustCallWithError` throws `UniffiInternalError` for a lift failure or
    /// a Rust panic, and that type is a `LocalizedError` whose text is for
    /// whoever wrote the binding — "Raw enum value doesn't match any cases",
    /// a panic message. Passing it on would put exactly the rendering the
    /// README says never reaches a person in front of one, and it would break
    /// `PairingReadError.malformed`'s promise that the sentence never carries
    /// what was pasted, since a panic message can.
    static let unreadable = "That pairing string could not be read."

    public init() {}

    public func read(_ pairing: String) -> Result<ReadPairing, PairingReadError> {
        do {
            let read = try mpReadPairing(pairing: pairing)
            return .success(ReadPairing(ticket: read.ticket, hasCode: read.hasCode))
        } catch let error as MpPairError {
            return .failure(Self.refusal(for: error))
        } catch {
            return .failure(.malformed(message: Self.unreadable))
        }
    }

    /// A refused read as something worth showing a person.
    ///
    /// Exhaustive and with no `default`, for the reason `ModelpipeConnector`
    /// gives where it maps the same enum: a case modelpipe adds is a compile
    /// error here rather than a sentence nobody wrote. `message()` and never
    /// `localizedDescription`, because uniffi generates the latter as
    /// `String(reflecting: self)`.
    ///
    /// Every arm is `.malformed`, and that is not a shrug. Reading a string
    /// dials nothing and presents nothing, so `BadPairingString` is the only
    /// case this call can produce; the rest are listed to be counted by the
    /// compiler, and each of them arriving here would still mean what was
    /// handed over could not be read as a pairing string.
    static func refusal(for error: MpPairError) -> PairingReadError {
        switch error {
        case .NoCode, .BadPairingString, .Dial, .Unreached, .Refused, .Exchange, .Unexpected, .Unknown:
            .malformed(message: error.message())
        }
    }
}
