import SwiftUI

@main
struct InkflowApp: App {
    @State private var store = ClipStore()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Palette.accent)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .task { store.seedPreviewIfNeeded(); await store.cloud.resume() }
        }
    }
}
