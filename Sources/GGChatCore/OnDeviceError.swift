import Foundation

/// Why a call to the engine on this device or to its model library failed,
/// mirroring gglib-ffi's `GglibError` case for case. The payloads are
/// gglib's own sentences and figures; the descriptions say them as this app
/// does.
public enum OnDeviceError: Error, Sendable, Equatable, LocalizedError {
    /// Hugging Face wants a token for this repository.
    case authRequired
    case notFound
    case rateLimited
    /// The device has no room for the download.
    case noSpace
    case network(message: String)
    /// The model needs a budget of `need` bytes and the device gives `have`.
    case doesNotFit(need: UInt64, have: UInt64)
    /// Nothing in this build can run a model on this device.
    case engineUnavailable
    case `internal`(message: String)

    public var errorDescription: String? {
        switch self {
        case .authRequired:
            "This repository needs a Hugging Face token, which this app cannot send yet."
        case .notFound:
            "Hugging Face has no such repository or file."
        case .rateLimited:
            "Hugging Face is limiting requests from this device; try again in a minute."
        case .noSpace:
            "This device has no room for that download."
        case .network(let message):
            "Could not reach Hugging Face: \(message)"
        case .doesNotFit(let need, let have):
            "The model needs \(Self.size(need)) and this device gives a model \(Self.size(have))."
        case .engineUnavailable:
            "This build cannot run a model on this device."
        case .internal(let message):
            message
        }
    }

    private static func size(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
}
