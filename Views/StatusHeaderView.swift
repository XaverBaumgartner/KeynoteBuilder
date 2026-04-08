import SwiftUI

/// Displays the current status and overall selection controls.
struct StatusHeaderView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        HStack {
            Text(appState.staleNames.isEmpty ? "Status" : "Stale Decks (\(appState.staleNames.count))")
                .font(.subheadline)
                .bold()
            
            Spacer()
            
            // Allow deselecting/selecting all stale decks if a build hasn't finished.
            if !appState.staleNames.isEmpty && !appState.buildFinished {
                Button(appState.selectedNames.count == appState.staleNames.count ? "Deselect All" : "Select All") {
                    appState.toggleAll()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(.top)
        .padding(.bottom, 4)
    }
}
