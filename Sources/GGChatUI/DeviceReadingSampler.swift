import Foundation
import GGChatCore

#if os(iOS)
    import os
#endif

/// The one place this device's memory is read: its physical memory, and
/// what this process can still allocate, as gglib wants them to judge what
/// fits. Only read, never reckoned with: the budget a model may spend, and
/// every verdict made from it, are gglib's.
///
/// Read once each time the model browser opens, so every verdict on it is
/// made from the same reading, and once per serve of the engine; see
/// `AppModel+Library` and `AppModel+Engine`.
enum DeviceReadingSampler {
    /// A reading on iOS. Nil elsewhere: no engine runs there, and
    /// `os_proc_available_memory` is iOS's.
    nonisolated static func sample() -> DeviceReading? {
        #if os(iOS)
            #if targetEnvironment(simulator)
                let simulator = true
            #else
                let simulator = false
            #endif
            return DeviceReading(
                physicalBytes: ProcessInfo.processInfo.physicalMemory,
                availableBytes: UInt64(os_proc_available_memory()), isSimulator: simulator)
        #else
            return nil
        #endif
    }
}
