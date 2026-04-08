import SwiftUI

/// Summarizes all currently up-to-date decks in the project.
struct UpToDateSummary: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        if !appState.freshNames.isEmpty {
            Divider()
            VStack(alignment: .leading) {
                Text("Up-to-date Decks (\(appState.freshNames.count))")
                    .font(.subheadline)
                    .bold()
                    .padding(.bottom, 2)
                ScrollView {
                    Text(appState.freshNames.joined(separator: ", "))
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 60)
            }
            .padding(.vertical)
        }
    }
}
