import Foundation

extension AppModel {
    /// Where the in-process mock provider answers in DEBUG builds, the same
    /// address after every launch so a saved mock provider keeps working.
    public static let mockBaseURL = URL(string: "http://127.0.0.1:49151/v1")!

    #if DEBUG
        /// The mock's pace: a word every 25 ms, or one a second under
        /// `-ggchat-slow-mock YES`, which the walk of typing during a reply
        /// passes so that the reply is still running while it types.
        static var mockTokenDelay: Duration {
            UserDefaults.standard.bool(forKey: "ggchat-slow-mock") ? .seconds(1) : .milliseconds(25)
        }
    #endif

    /// Where the DEBUG build's refusing mock answers. Every chat request it
    /// gets is refused before its first token, with the code and the sentence
    /// modelpipe's edge wrote to a phone whose key the serving machine had
    /// forgotten, so the screen that refusal lands on can be walked to.
    public static let refusingMockBaseURL = URL(string: "http://127.0.0.1:49152/v1")!
}
