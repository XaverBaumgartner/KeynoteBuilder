import Foundation
import Combine
import AppKit

@MainActor
class AppState: ObservableObject {
    @Published var staleNames: [String] = []
    @Published var freshNames: [String] = []
    @Published var selectedNames: Set<String> = []
    @Published var deckDataDict: [String: DeckData] = [:]
    @Published var initializationError: String? = nil
    
    @Published var isBuilding = false
    @Published var buildFinished = false
    @Published var buildFinishedDate: Date? = nil
    @Published var builtDeckCount: Int = 0
    @Published var buildError: String? = nil
    @Published var mentiStatuses: [String: Bool] = [:]
    
    private var hasCompletedInitialRefresh = false
    
    var blocksURL: URL? = nil
    var outputsURL: URL? = nil
    var manifestURL: URL? = nil
    
    func toggleSelection(_ name: String) {
        if selectedNames.contains(name) {
            selectedNames.remove(name)
        } else {
            selectedNames.insert(name)
        }
    }
    
    func toggleAll() {
        if selectedNames.count == staleNames.count {
            selectedNames.removeAll()
        } else {
            selectedNames = Set(staleNames)
        }
    }
    
    func performAssembly() async {
        guard let outputDir = outputsURL, let blocksDir = blocksURL, let manifestDir = manifestURL else { return }
        
        isBuilding = true
        buildError = nil
        
        do {
            let deckCount = try await assembleDecks(
                toBuild: Array(selectedNames),
                deckDataDict: deckDataDict,
                blocksURL: blocksDir,
                outputsURL: outputDir,
                manifestURL: manifestDir,
                mentiStatuses: mentiStatuses
            )
            
            self.builtDeckCount = deckCount
            self.isBuilding = false
            self.buildFinished = true
            self.buildFinishedDate = Date()
            
            NSApplication.shared.activate(ignoringOtherApps: true)
        } catch {
            self.isBuilding = false
            self.buildError = "Error building batch of decks: \(error.localizedDescription)"
        }
    }
    
    func refreshDecks() async {
        guard !isBuilding else { return }
        
        let paths = discoverPaths()
        self.blocksURL = paths.blocks
        self.outputsURL = paths.outputs
        self.manifestURL = paths.manifests
        
        let result = await scanDecks(paths: paths, mentiStatuses: self.mentiStatuses)
        self.initializationError = result.error
        
        if result.error != nil {
            return
        }
        
        let newlyStale = Set(result.staleNames).subtracting(self.staleNames)
        
        self.deckDataDict = result.deckDataDict
        self.staleNames = result.staleNames
        self.freshNames = result.freshNames
        
        if self.buildFinished {
            if !newlyStale.isEmpty {
                self.buildFinished = false
                self.buildFinishedDate = nil
            } else if let finishDate = self.buildFinishedDate, Date().timeIntervalSince(finishDate) > 5.0 {
                self.buildFinished = false
                self.buildFinishedDate = nil
            }
        } else if !result.staleNames.isEmpty {
            self.buildFinished = false
            self.buildFinishedDate = nil
        }
        
        // Retain selected names that are still stale, and add new ones
        self.selectedNames = self.selectedNames.intersection(result.staleNames)
        self.selectedNames.formUnion(newlyStale)
        
        // If nothing was selected on the initial load, select all stale decks
        if !self.hasCompletedInitialRefresh {
            if self.selectedNames.isEmpty {
                self.selectedNames = Set(result.staleNames)
            }
            self.hasCompletedInitialRefresh = true
        }
        
        await validateMentiCodes()
    }
    
    private func validateMentiCodes() async {
        var codesToValidate: Set<String> = []
        for deckData in deckDataDict.values {
            codesToValidate.formUnion(collectMentiCodes(deck: deckData.rootDeck))
        }
        
        for code in codesToValidate {
            if mentiStatuses[code] == nil {
                // To avoid multiple requests, mark as in-flight or just validate
                // For simplicity, we just validate if nil
                do {
                    _ = try await getMentimeterURL(code: code)
                    mentiStatuses[code] = true
                } catch {
                    mentiStatuses[code] = false
                }
            }
        }
    }
    
    private func collectMentiCodes(deck: ResolvedDeck) -> [String] {
        var codes: [String] = []
        for m in deck.matches {
            switch m.type {
            case .menti(let code):
                codes.append(code)
            case .config:
                if let nested = m.nestedDeck {
                    codes.append(contentsOf: collectMentiCodes(deck: nested))
                }
            default:
                break
            }
        }
        return codes
    }
}
