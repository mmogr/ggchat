import Foundation

/// `GGLIB_DATA_DIR` pointed at a folder under a test's own root, so gglib
/// never resolves the user's data root, and put back as it was when the
/// test ends. The variable is process-wide, so ``restore()`` runs in every
/// tearDown that made one.
struct GglibDataRoot {
    private static let name = "GGLIB_DATA_DIR"
    private let previous: String?

    init(under root: URL) {
        previous = ProcessInfo.processInfo.environment[Self.name]
        setenv(Self.name, root.appending(path: "gglib-data-root").path(percentEncoded: false), 1)
    }

    func restore() {
        if let previous {
            setenv(Self.name, previous, 1)
        } else {
            unsetenv(Self.name)
        }
    }
}
