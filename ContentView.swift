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
                                VStack(alignment: .leading, spacing: 2) {
                                    Toggle(name, isOn: Binding(
                                        get: { appState.selectedNames.contains(name) },
                                        set: { _ in appState.toggleSelection(name) }
                                    ))
                                    
                                    if let deck = appState.deckDataDict[name], !deck.inexactMatches.isEmpty {
                                        VStack(alignment: .leading, spacing: 2) {
                                            ForEach(deck.inexactMatches, id: \.self) { matchStr in
                                                let parts = matchStr.components(separatedBy: "' -> '")
                                                if parts.count == 2 {
                                                    let oldName = parts[0].replacingOccurrences(of: "'", with: "")
                                                    let newName = parts[1].replacingOccurrences(of: "'", with: "")
                                                    
                                                    HStack(alignment: .top, spacing: 4) {
                                                        Image(systemName: "arrow.triangle.swap")
                                                            .foregroundColor(.secondary)
                                                        Text(oldName)
                                                            .foregroundColor(.secondary)
                                                        Image(systemName: "arrow.right")
                                                            .foregroundColor(.secondary)
                                                            .font(.system(size: 10, weight: .bold))
                                                        Text(newName)
                                                            .foregroundColor(.primary)
                                                            .bold()
                                                    }
                                                    .font(.caption)
                                                } else {
                                                    Text(matchStr)
                                                        .foregroundColor(.secondary)
                                                        .font(.caption)
                                                }
                                            }
                                        }
                                        .padding(.leading, 24)
                                        .padding(.bottom, 4)
                                    }
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
        .frame(minWidth: 550, minHeight: 350)
        .onReceive(timer) { _ in
            if !appState.isBuilding {
                Task {
                    await appState.refreshDecks()
                }
            }
        }
    }
}
