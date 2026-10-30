import SwiftUI

/// The model browser in a sheet of its own, which "Find a model…" under
/// This iPhone in the model list opens, and the pill's "Too big": the
/// browser's page (`ModelBrowserList`) under "Find a model", with Done.
struct ModelBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    let browser: ModelBrowser

    var body: some View {
        NavigationStack {
            ModelBrowserList(browser: browser)
                .navigationTitle("Find a model")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 480)
        #endif
    }
}

/// The model browser as a page of a stack that is already up, as Settings'
/// "Models on this iPhone" pushes it: one opening, made as the page first
/// appears, which reads this device.
struct ModelBrowserPage: View {
    @Environment(AppModel.self) private var model
    @State private var browser: ModelBrowser?

    var body: some View {
        // A Group with nothing in it takes no modifiers, so the page holds a
        // spinner until its browser is made, or onAppear would never run.
        Group {
            if let browser {
                ModelBrowserList(browser: browser)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Models on this iPhone")
        .onAppear {
            if browser == nil { browser = model.makeModelBrowser() }
        }
    }
}
