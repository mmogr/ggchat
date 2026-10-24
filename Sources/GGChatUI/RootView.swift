import SwiftUI

/// Sidebar of conversations, chat on the right. Stock containers only: the
/// system draws the glass.
public struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    // Read only through their bindings (`$showingProviders` and the rest),
    // which the Swift 6.4 indexer records as no read of the property, so
    // periphery reports each as unused. Periphery's repository was archived
    // in August 2026 and will not learn otherwise; the indexer may.
    // periphery:ignore - read only through its binding, see above
    @State private var showingProviders = false
    // periphery:ignore - read only through its binding, see above
    @State private var showingSettings = false
    // periphery:ignore - read only through its binding, see above
    @State private var addingProvider = false
    // periphery:ignore - read only through its binding, see above
    @State private var columns: NavigationSplitViewVisibility = .automatic
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        /// Whether the window is wide and tall enough to keep the list on screen.
        @State private var fits = false
        /// The window as the rule reads it: see `SidebarPinning.measured`.
        @State private var window: CGSize = .zero
        /// Whether the list laid beside the chat on a phone is showing.
        @State private var listShown = true
    #endif
    /// What opening the store had to say.
    private let storeNotice: ShownStoreNotice

    public init(storeNotice: ShownStoreNotice = ShownStoreNotice(nil)) {
        self.storeNotice = storeNotice
    }

    public var body: some View {
        @Bindable var model = model
        // The notice is laid out below the split view, not in a bottom inset
        // over it: under such an inset the chat's composer stayed where it
        // was on an iPhone, and the notice was drawn over it.
        VStack(spacing: 0) {
            layout
                #if os(iOS)
                    // Read by its width and the tallest height seen at it,
                    // so the keyboard coming up does not change the layout
                    // under the field being typed in; see
                    // `SidebarPinning.measured`.
                    .onGeometryChange(for: CGSize.self, of: \.size) { size in
                        window = SidebarPinning.measured(size, after: window)
                        let now = SidebarPinning.fits(window)
                        if now != fits { fits = now }
                    }
                    // The list is put back on each unfolding and each turn
                    // upright, and a hide holds until then; leaving, only a list
                    // kept here is handed back to the system.
                    .onChange(of: pinsSidebar, initial: true) { _, pinned in
                        if pinned {
                            columns = .doubleColumn
                            listShown = true
                        } else if columns == .doubleColumn {
                            columns = .automatic
                        }
                    }
                #endif
            if !storeNotice.lines.isEmpty {
                StoreNoticeView(notice: storeNotice)
            }
        }
        .sheet(isPresented: $showingProviders) {
            ProvidersView()
        }
        .sheet(isPresented: $addingProvider) {
            AddProviderView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        // Here and not on the row that opened it: a row is torn down when
        // its chat is read again or it scrolls away, and a sheet on it would
        // take a picture drawn in the editor with it.
        .sheet(item: $model.enlarged, onDismiss: model.closePictureEditor) { shown in
            EnlargedImage(shown: shown)
        }
        .alert(
            "Something did not work",
            isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })
        ) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
        #if os(iOS)
            .task {
                model.load()
                actOnQuickAction()
                QuickActionInbox.offer(model.quickActions(hasCamera: CameraCapture.isOffered))
            }
            .onChange(of: QuickActionInbox.shared.pending) { actOnQuickAction() }
        #else
            .task { model.load() }
        #endif
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.scene(.foreground)
            case .background:
                model.scene(.background)
                #if os(iOS)
                    QuickActionInbox.offer(model.quickActions(hasCamera: CameraCapture.isOffered))
                #endif
            // `.inactive` is a transient — the notification shade, a call
            // banner, a window losing focus — and a pipe is worth holding
            // through one. Only `.background` means the process is about to
            // stop running.
            default: break
            }
        }
    }
}

extension RootView {
    /// The system's split view, but where a phone keeps the list beside the
    /// chat: there iOS lays the list over the chat and takes it away again,
    /// whatever the split view is asked for, so the two are laid out here.
    @ViewBuilder
    fileprivate var layout: some View {
        #if os(iOS)
            if pinsSidebar, UIDevice.current.userInterfaceIdiom == .phone {
                listBesideTheChat
            } else {
                // Balanced, so the chat narrows beside a list on screen
                // rather than the list being laid over it.
                splitView.navigationSplitViewStyle(.balanced)
            }
        #else
            splitView
        #endif
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
        } detail: {
            detail
        }
    }

    private var sidebar: some View {
        #if os(iOS)
            let beside = widthClass == .regular
        #else
            let beside = false
        #endif
        return ConversationSidebar(
            showingProviders: $showingProviders, showingSettings: $showingSettings,
            addingProvider: $addingProvider, beside: beside
        )
    }

    @ViewBuilder
    private var detail: some View {
        if let conversation = model.selectedConversation {
            ChatView(conversation: conversation)
        } else if let chat = model.openedHubChat {
            HubChatView(chat: chat)
        } else {
            EmptyDetailView(addingProvider: $addingProvider)
        }
    }
}

#if os(iOS)
    extension RootView {
        /// The chat with its sidebar button, in its own navigation stack.
        private var chatColumn: some View {
            NavigationStack {
                detail.toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(
                            listShown ? "Hide the conversation list" : "Show the conversation list",
                            systemImage: "sidebar.leading"
                        ) {
                            withAnimation(reduceMotion ? nil : .snappy) { listShown.toggle() }
                        }
                        .accessibilityIdentifier("conversation-list")
                    }
                }
            }
        }

        /// The list and the chat side by side, the list at its share of the
        /// width, with a button at the chat's leading edge that hides and
        /// shows the list.
        fileprivate var listBesideTheChat: some View {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    if listShown {
                        NavigationStack { sidebar }
                            .frame(width: SidebarPinning.listWidth(beside: proxy.size.width))
                            .transition(.move(edge: .leading))
                        Divider()
                    }
                    chatColumn
                }
            }
        }

        /// See `SidebarPinning`.
        fileprivate var pinsSidebar: Bool {
            widthClass == .regular && fits
        }

        /// Does what a quick action waiting asks, once the model has read
        /// its providers: before that there is none to start a chat with.
        fileprivate func actOnQuickAction() {
            if let action = QuickActionInbox.shared.take() { model.perform(action) }
        }
    }
#endif

/// What the app says when nothing is selected. On first run it is the way
/// in: a first-time user is one button from adding their server.
struct EmptyDetailView: View {
    @Environment(AppModel.self) private var model
    @Binding var addingProvider: Bool

    var body: some View {
        if model.providers.isEmpty {
            ContentUnavailableView {
                Label("No providers", systemImage: "server.rack")
            } description: {
                Text("Add the server that runs your models, or a modelpipe ticket from one.")
            } actions: {
                Button("Add a provider") { addingProvider = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label("No conversation", systemImage: "bubble.left.and.text.bubble.right")
            } description: {
                Text("Start one, and it appears in the sidebar.")
            } actions: {
                Button("New conversation") { model.newConversation() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel.preview)
}
