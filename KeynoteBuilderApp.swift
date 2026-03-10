import Cocoa
import SwiftUI

@main
struct KeynoteBuilderApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("Keynote Builder", id: "main") {
            ContentView(appState: appState)
                .onAppear {
                    // Start processing logic
                    Task {
                        await appState.refreshDecks()
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 400)
    }
}
