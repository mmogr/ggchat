import os

/// What a launch does before the window has anything to draw, marked for
/// Instruments as intervals under the `launch` category, in every build:
/// `make phone` installs a Release one, and that is the launch that is slow
/// (#59). Each name is a constant, and nothing a person wrote is recorded.
enum LaunchSignposts {
    static let signposter = OSSignposter(subsystem: "com.mattogrady.ggchat", category: "launch")

    /// Runs `work` inside an interval called `name`.
    static func interval<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        try signposter.withIntervalSignpost(name, around: work)
    }
}
