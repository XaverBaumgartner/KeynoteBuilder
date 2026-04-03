import Foundation
import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            if let error = appState.initializationError {
                ErrorOverlay(error: error)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    StatusHeader(appState: appState)
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
            if !appState.isBuilding {
                Task {
                    await appState.refreshDecks()
                }
            }
        }
    }
}


struct ErrorOverlay: View {
    let error: String
    
    var body: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.largeTitle)
                .padding()
            Text(error)
                .multilineTextAlignment(.center)
                .padding()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StatusHeader: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        HStack {
            Text(appState.staleNames.isEmpty ? "Status" : "Stale Decks (\(appState.staleNames.count))")
                .font(.subheadline)
                .bold()
            
            Spacer()
            
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

struct LoadingStateView: View {
    var body: some View {
        VStack {
            ProgressView("Analyzing decks...")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CompletionStateView: View {
    let builtCount: Int
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
                .font(.system(size: 40))
            Text("Assembly Complete!")
                .font(.headline)
            Text("Built \(builtCount) deck(s).")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UpToDateStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 40))
            Text("All decks are up-to-date.")
                .font(.headline)
            Text("Nothing to rebuild.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StaleDecksListView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(appState.staleNames.enumerated()), id: \.offset) { index, name in
                    if let deckData = appState.deckDataDict[name] {
                        DeckTreeView(name: name, deck: deckData.rootDeck, isRoot: true, appState: appState)
                        if index < appState.staleNames.count - 1 {
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

struct ControlFooter: View {
    @ObservedObject var appState: AppState
    
    private var statusDescription: String {
        if appState.isBuilding {
            return "Building..."
        } else if let error = appState.buildError {
            return error
        } else if appState.staleNames.isEmpty || appState.buildFinished {
            return "Ready"
        } else {
            return "\(appState.selectedNames.count) deck(s) selected"
        }
    }
    
    private var isBuildingOrStaleEmpty: Bool {
        appState.staleNames.isEmpty || appState.buildFinished
    }
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                if appState.isBuilding {
                    ProgressView()
                        .scaleEffect(0.5)
                }
                Text(statusDescription)
                    .foregroundColor(appState.buildError != nil ? .red : .secondary)
            }
            
            Spacer()
            
            if isBuildingOrStaleEmpty {
                Button("Close") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button("Cancel") {
                    NSApplication.shared.terminate(nil)
                }
                .disabled(appState.isBuilding)
                
                Button("Rebuild Selected") {
                    Task {
                        await appState.performAssembly()
                    }
                }
                .disabled(appState.selectedNames.isEmpty || appState.isBuilding)
                .buttonStyle(BorderedProminentButtonStyle())
            }
        }
        .padding()
    }
}


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

struct CorrectionLabel: View {
    let old: String
    let new: String
    let isRoot: Bool
    let icon: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
            }
            Text(old)
                .strikethrough()
                .foregroundColor(.orange)
            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.system(size: 9))
            Text(new)
                .foregroundColor(.primary)
                .bold(isRoot)
        }
        .font(isRoot ? .body : .subheadline)
    }
}

struct MatchItemRow: View {
    let match: BlockMatch
    @ObservedObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let nested = match.nestedDeck {
                let corr = match.isFuzzy ? (old: match.originalName, new: match.resolvedRelativePath) : nil
                DeckTreeView(name: match.resolvedRelativePath, deck: nested, isRoot: false, correction: corr, appState: appState)
            } else {
                FileRow(match: match)
            }
        }
    }
}

struct FileRow: View {
    let match: BlockMatch
    
    var body: some View {
        HStack(spacing: 4) {
            if match.isFuzzy {
                CorrectionLabel(old: match.originalName, new: match.resolvedRelativePath, isRoot: false, icon: "doc.richtext")
            } else {
                Image(systemName: "doc.richtext")
                    .foregroundColor(.secondary)
                Text(match.resolvedRelativePath)
                    .foregroundColor(.primary)
            }
        }
        .font(.subheadline)
    }
}
