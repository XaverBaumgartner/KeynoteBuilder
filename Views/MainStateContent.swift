import SwiftUI

/// Determines which status state to display based on the `AppState`.
struct MainStateContent: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading) {
            if appState.staleNames.isEmpty && appState.freshNames.isEmpty {
                LoadingStateView()
            } else if appState.buildFinished {
                CompletionStateView(builtCount: appState.builtDeckCount)
            } else if appState.staleNames.isEmpty {
                UpToDateStateView()
            } else {
                StaleDecksListView(appState: appState)
            }
        }
    }
}
