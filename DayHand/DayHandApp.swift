import SwiftUI

@main
struct DayHandApp: App {
    @StateObject private var store = TodoStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear { Self.tidyMacTitlebar() }
        }
    }

    /// The Mac window shows no title. It is not a document, so there is nothing
    /// to name, and the app is already named in the menu bar and the Dock — the
    /// one piece of chrome left in an app that has no navigation bar, no
    /// toolbar and headers that scroll away. The titlebar itself stays: the
    /// traffic lights live there, and it is the window's drag region.
    private static func tidyMacTitlebar() {
        #if targetEnvironment(macCatalyst)
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.titlebar?.titleVisibility = .hidden
        }
        #endif
    }
}
