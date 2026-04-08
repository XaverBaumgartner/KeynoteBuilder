import SwiftUI

/// The root view of the application, managing the main layout and timer-based refreshes.
struct ContentView: View {
    @ObservedObject var appState: AppState
    
    /// A timer that triggers a deck refresh every second.
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            if let error = appState.initializationError {
                ErrorOverlay(error: error)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    StatusHeaderView(appState: appState)
                    MainStateContent(appState: appState)
                    UpToDateSummary(appState: appState)
                }
                .padding(.horizontal)
                
                Divider()
                ControlFooter(appState: appState)
            }
        }
        .frame(minWidth: 550, minHeight: 450)
        .onReceive(timer) { _ in
            // Periodically refresh the deck status unless a build is in progress.
            if !appState.isBuilding {
                Task {
                    await appState.refreshDecks()
                }
            }
        }
    }
}
