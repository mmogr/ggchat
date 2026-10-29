import SwiftUI

#if os(iOS)
    import UIKit
#endif

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
        /// Whether the window is wide and tall enough to keep the list on screen.
        @State private var fits = false
        /// The window as the rule reads it: see `SidebarPinning.measured`.
        @State private var window: CGSize = .zero
        /// Whether the window is an open Duo on its side; see `BookPages`.
        @State private var sideways = false
        /// The window's fold while the phone is half open; see `Fold`.
        @State private var folds: [CGRect] = []
    #endif
    /// What opening the store had to say.
    private let storeNotice: ShownStoreNotice
    #if os(iOS)
        /// Each time the system says it is short of memory.
        private let memoryWarnings = NotificationCenter.default.publisher(
            for: UIApplication.didReceiveMemoryWarningNotification)
    #endif

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
                        let turned = BookPages.opensSideways(window, anyHeight: Fold.isFaked)
                        if turned != sideways { sideways = turned }
                    }
                    // Half opening and laying flat change no size: only the
                    // fold comes and goes.
                    .onGeometryChange(for: [CGRect].self) { proxy in
                        Fold.windowDivisions(in: proxy)
                    } action: {
                        folds = $0
                    }
                    // Leaving, only a list kept here is handed back to the
                    // system.
                    .onChange(of: pinsSidebar, initial: true) { _, pinned in
                        if pinned {
                            columns = .doubleColumn
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
        // Here, as the enlarged picture is, so every way in opens the same
        // one: the composer's model list and the panel's, and the empty
        // screens.
        .sheet(item: Bindable(model.onDevice).modelBrowser) { browser in
            ModelBrowserView(browser: browser)
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
            // The system is short of memory: this device's engine is put
            // down unless a reply is going through it (ADR 0015).
            .onReceive(memoryWarnings) { _ in model.memoryWarning() }
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
    /// chat or is an open Duo on its side: there iOS lays the list over the
    /// chat and takes it away again, whatever the split view is asked for, so
    /// the two are laid out here.
    @ViewBuilder
    fileprivate var layout: some View {
        #if os(iOS)
            if phoneLayout != .system {
                PhoneColumns(layout: phoneLayout, folds: folds) {
                    sidebar(beside: true)
                } detail: {
                    detail
                }
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
            sidebar(beside: widthClass == .regular)
        #else
            sidebar(beside: false)
        #endif
    }

    private func sidebar(beside: Bool) -> some View {
        ConversationSidebar(
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
        /// See `SidebarPinning`.
        fileprivate var pinsSidebar: Bool {
            widthClass == .regular && fits
        }

        /// Which of the layouts a phone gets. Not the phone's alone: an iPad
        /// keeps the system's split view in every pose.
        fileprivate var phoneLayout: PhoneLayout {
            guard UIDevice.current.userInterfaceIdiom == .phone else { return .system }
            if pinsSidebar { return .listBeside }
            guard sideways else { return .system }
            return BookPages.pages(in: window, folds: folds) == nil ? .flat : .pages
        }

        /// Does what a quick action waiting asks, once the model has read
        /// its providers: before that there is none to start a chat with.
        fileprivate func actOnQuickAction() {
            if let action = QuickActionInbox.shared.take() { model.perform(action) }
        }
    }
#endif

/// What the app says when nothing is selected. On first run it is the way
/// in: a first-time user is one button from Add provider, where they add
/// their server, or, where this build runs models on this device, find one
/// to run here.
struct EmptyDetailView: View {
    @Environment(AppModel.self) private var model
    @Binding var addingProvider: Bool

    var body: some View {
        if model.providers.isEmpty {
            ContentUnavailableView {
                Label("No providers", systemImage: "server.rack")
            } description: {
                Text(Self.firstRun(runsModelsHere: model.runsModelsHere))
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

extension EmptyDetailView {
    /// What first run says the providers are: This iPhone among them only
    /// where Add provider offers it.
    static func firstRun(runsModelsHere: Bool) -> String {
        runsModelsHere
            ? "Add the server that runs your models, a modelpipe ticket from one, or a model to run on this iPhone."
            : "Add the server that runs your models, or a modelpipe ticket from one."
    }
}

#Preview {
    RootView()
        .environment(AppModel.preview)
}
