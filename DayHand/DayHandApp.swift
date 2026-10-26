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
        // Replacing the group rather than adding to it: the system's own Undo
        // is wired to a responder chain this app's lists do not feed, so it
        // would sit there greyed out beside a working one.
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { store.undoLast() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!store.canUndo)
            }
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
