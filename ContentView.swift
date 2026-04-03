import Foundation
import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {

            if let error = appState.initializationError {
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
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading) {
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
                        .padding(.bottom, 4)
                        
                        if appState.staleNames.isEmpty && appState.freshNames.isEmpty {
                            VStack {
                                ProgressView("Analyzing decks...")
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if appState.buildFinished {
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 40))
                                Text("Assembly Complete!")
                                    .font(.headline)
                                Text("Built \(appState.builtDeckCount) deck(s).")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if appState.staleNames.isEmpty {
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
                        } else {
                            List(appState.staleNames, id: \.self) { name in
                                if let deckData = appState.deckDataDict[name] {
                                    DeckTreeView(name: name, deck: deckData.rootDeck, isRoot: true, appState: appState)
                                }
                            }
                        }
                    }
                    .padding()
                    
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
                        .padding()
                    }
                }
                
                Divider()
                
                HStack {
                    if appState.isBuilding {
                        ProgressView()
                            .scaleEffect(0.5)
                            .padding(.trailing, 4)
                        Text("Building...")
                            .foregroundColor(.secondary)
                    } else if let error = appState.buildError {
                        Text(error)
                            .foregroundColor(.red)
                    } else if appState.staleNames.isEmpty || appState.buildFinished {
                        Text("Ready")
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(appState.selectedNames.count) deck(s) selected")
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if appState.staleNames.isEmpty || appState.buildFinished {
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if isRoot {
                    Toggle("", isOn: Binding(
                        get: { appState.selectedNames.contains(name) },
                        set: { _ in appState.toggleSelection(name) }
                    ))
                    .labelsHidden()
                } else {
                    Spacer().frame(width: 14)
                }
                
                if let correction = correction {
                    HStack(alignment: .center, spacing: 4) {
                        Image(systemName: "arrow.triangle.swap")
                            .foregroundColor(.orange)
                        Text(correction.old)
                            .strikethrough()
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)
                            .font(.system(size: 9))
                        Text(correction.new)
                            .foregroundColor(isRoot ? .primary : .secondary)
                            .bold(isRoot)
                    }
                    .font(isRoot ? .body : .subheadline)
                } else {
                    HStack(spacing: 4) {
                        if !isRoot {
                            Image(systemName: "square.stack.3d.up")
                                .foregroundColor(.secondary)
                        }
                        Text(name)
                            .font(isRoot ? .body : .subheadline)
                            .bold(isRoot)
                    }
                }
                
                if !isRoot && deck.url.pathExtension == "txt" {
                    Text("(config)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(deck.matches) { match in
                    VStack(alignment: .leading, spacing: 2) {
                        if let nested = match.nestedDeck {
                            let corr = match.isFuzzy ? (old: match.originalName, new: match.resolvedRelativePath) : nil
                            DeckTreeView(name: match.resolvedRelativePath, deck: nested, isRoot: false, correction: corr, appState: appState)
                        } else {
                            if match.isFuzzy {
                                HStack(alignment: .center, spacing: 4) {
                                    Image(systemName: "arrow.triangle.swap")
                                        .foregroundColor(.orange)
                                    Text(match.originalName)
                                        .strikethrough()
                                        .foregroundColor(.secondary)
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 9))
                                    Text(match.resolvedRelativePath)
                                        .foregroundColor(.secondary)
                                }
                                .font(.caption)
                                .padding(.leading, 20)
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.richtext")
                                        .foregroundColor(.secondary)
                                    Text(match.resolvedRelativePath)
                                        .foregroundColor(.secondary)
                                }
                                .font(.caption)
                                .padding(.leading, 20)
                            }
                        }
                    }
                }
            }
            .padding(.leading, 20)
        }
        .padding(.vertical, 2)
    }
}
