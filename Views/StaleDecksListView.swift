import SwiftUI

/// Lists all stale decks discovered in the current project.
struct StaleDecksListView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let staleNames = appState.staleNames
                ForEach(Array(staleNames.enumerated()), id: \.offset) { index, name in
                    if let deckData = appState.deckDataDict[name] {
                        DeckTreeView(name: name, deck: deckData.rootDeck, isRoot: true, appState: appState)
                        if index < staleNames.count - 1 {
                            Divider()
                                .opacity(0.5)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}
