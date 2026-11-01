import GGChatCore
import SwiftUI

/// Where a chat kept here is renamed, from every place that offers it: a
/// field holding the title shown, Cancel and Rename. Clearing the field gives
/// the chat its first question's title back (`renameConversation`).
private struct RenameChat: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var renaming: UUID?
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert("Rename chat", isPresented: isPresented) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    if let renaming { model.renameConversation(renaming, to: name) }
                }
            } message: {
                Text("Leave it empty to name the chat by its first question.")
            }
            .onChange(of: renaming) { _, id in
                name = id.flatMap { id in model.conversations.first { $0.id == id }?.displayTitle } ?? ""
            }
    }

    private var isPresented: Binding<Bool> {
        Binding {
            renaming != nil
        } set: {
            if !$0 { renaming = nil }
        }
    }
}

extension View {
    /// Offers to rename the chat `renaming` names while it names one.
    func renamingChat(_ renaming: Binding<UUID?>) -> some View {
        modifier(RenameChat(renaming: renaming))
    }
}
