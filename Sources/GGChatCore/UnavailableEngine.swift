/// The engine in a build that has none, which is every build until gglib's
/// engine is linked: a release build, a simulator, the Mac, and a DEBUG
/// build launched without `-ggchat-mock-engine`. Nothing on-device is
/// offered where this is the engine, because ``isAvailable`` is false.
///
/// Unlike `UnavailablePipeConnector`, this one is returned. It is also the
/// sentinel `scripts/check_no_mock_in_release.sh` looks for, to prove it
/// really opened the release objects that would hold `MockEngine` if a
/// release build carried it.
public struct UnavailableEngine: LocalEngine {
    public init() {}

    public var isAvailable: Bool { false }

    /// Always throws ``OnDeviceError/engineUnavailable``. The reading is not
    /// looked at: it is not what is wrong.
    public func serve(reading: DeviceReading) async throws -> any EngineSession {
        throw OnDeviceError.engineUnavailable
    }
}

/// The model library in a build with no engine. Every call that asks
/// something throws ``OnDeviceError/engineUnavailable``: a library whose
/// models nothing can run has nothing worth saying.
public struct UnavailableLibrary: ModelLibrary {
    public init() {}

    public func suggested(reading: DeviceReading) async throws -> [Suggestion] {
        throw OnDeviceError.engineUnavailable
    }

    public func search(query: String, cursor: String?) async throws -> SearchPage {
        throw OnDeviceError.engineUnavailable
    }

    public func quantizations(repo: String, reading: DeviceReading) async throws -> [QuantOffer] {
        throw OnDeviceError.engineUnavailable
    }

    public func installed() async throws -> [InstalledModel] {
        throw OnDeviceError.engineUnavailable
    }

    public func remove(id: Int64) async throws {
        throw OnDeviceError.engineUnavailable
    }

    public func download(repo: String, quantization: String) async throws -> AsyncStream<DownloadProgress> {
        throw OnDeviceError.engineUnavailable
    }

    /// Nothing is in flight to pause.
    public func pauseAll() async {}

    /// Nothing was paused.
    public func resumeAll() async {}
}
