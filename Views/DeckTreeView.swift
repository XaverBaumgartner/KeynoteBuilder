import SwiftUI

/// A recursive view that displays a deck and its nested blocks or configurations.
struct DeckTreeView: View {
    let name: String
    let deck: ResolvedDeck
    let isRoot: Bool
    let correction: (old: String, new: String)?
    @ObservedObject var appState: AppState

    init(name: String, deck: ResolvedDeck, isRoot: Bool, correction: (old: String, new: String)? = nil, appState: AppState) {
        self.name = name
        self.deck = deck
        self.isRoot = isRoot
        self.correction = correction
        self.appState = appState
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if isRoot {
                    Toggle("", isOn: Binding(
                        get: { appState.selectedNames.contains(name) },
                        set: { _ in appState.toggleSelection(name) }
                    ))
                    .labelsHidden()
                    .frame(width: 16)
                } 
                if let correction = correction {
                    CorrectionLabel(old: correction.old, new: correction.new, isRoot: isRoot, icon: isRoot ? "" : "square.stack.3d.up")
                } else {
                    HStack(spacing: 4) {
                        if !isRoot {
                            Image(systemName: "square.stack.3d.up")
                                .foregroundColor(.secondary)
                        }
                        Text(name)
                            .font(isRoot ? .body : .subheadline)
                            .foregroundColor(.primary)
                            .bold(isRoot)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(deck.matches) { match in
                    MatchItemRow(match: match, appState: appState)
                }
            }
            .padding(.leading, isRoot ? 28 : 20)
        }
        .padding(.vertical, 2)
    }
}
