import Foundation

extension Conversation {
    /// Whether the conversation is as New conversation made it: nothing
    /// asked, no name, no system prompt, and every setting still its
    /// provider's, `defaultModel` the model its provider starts one with.
    /// Such a one holds nothing a person chose, so the list keeps at most
    /// one, the one open: it goes when another is opened, and New
    /// conversation on it is that one again. A model picked, Thinking
    /// turned off, a picture model or a tool server chosen, or the tools
    /// turned off, each makes it kept. Which servers it has been shown is
    /// not a choice and does not.
    public func isUntouched(defaultModel: String?) -> Bool {
        messages.isEmpty
            && title.isEmpty
            && (systemPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && model == defaultModel
            && !thinkingOff
            && imageModelID == nil
            && !toolChoice.off
            && toolChoice.picked.isEmpty
            && branchOf == nil
    }
}
