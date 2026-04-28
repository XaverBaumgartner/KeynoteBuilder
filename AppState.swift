import Foundation
import Combine
import AppKit

/// The main application state management object, coordinating between services and the UI.
@MainActor
class AppState: ObservableObject {
    // MARK: - Published Properties
    
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
    
    // MARK: - Private Properties
    
    private var hasCompletedInitialRefresh = false
    
    var blocksURL: URL? = nil
    var outputsURL: URL? = nil
    var deckManifestsURL: URL? = nil
    var outputManifestsURL: URL? = nil
    
    // MARK: - Actions
    
    /// Toggles the selection status of a deck.
    func toggleSelection(_ name: String) {
        if selectedNames.contains(name) {
            selectedNames.remove(name)
        } else {
            selectedNames.insert(name)
        }
    }
    
    /// Toggles selection for all currently stale decks.
    func toggleAll() {
        if selectedNames.count == staleNames.count {
            selectedNames.removeAll()
        } else {
            selectedNames = Set(staleNames)
        }
    }
    
    /// Performs the assembly process for all selected decks.
    func performAssembly() async {
        guard let outputDir = outputsURL, let blocksDir = blocksURL, let deckMan = deckManifestsURL, let outMan = outputManifestsURL else { return }
        
        isBuilding = true
        buildError = nil
        
        let paths = AppPaths(blocks: blocksDir, decks: blocksDir.deletingLastPathComponent().appendingPathComponent("decks"), outputs: outputDir, deckManifests: deckMan, outputManifests: outMan)
        
        do {
            let deckCount = try await KeynoteService.assembleDecks(
                toBuild: Array(selectedNames),
                deckDataDict: deckDataDict,
                paths: paths,
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
    
    /// Scans the filesystem for decks and updates the state.
    func refreshDecks() async {
        guard !isBuilding else { return }
        
        let paths = FileUtilities.discoverPaths()
        self.blocksURL = paths.blocks
        self.outputsURL = paths.outputs
        self.deckManifestsURL = paths.deckManifests
        self.outputManifestsURL = paths.outputManifests
        
        let result = await DeckScanner.scanDecks(paths: paths, mentiStatuses: self.mentiStatuses)
        self.initializationError = result.error
        
        if result.error != nil {
            return
        }
        
        let newlyStale = Set(result.staleNames).subtracting(self.staleNames)
        var editedStale = Set<String>()
        
        for name in result.staleNames {
            if let oldDate = self.deckDataDict[name]?.modifiedDate,
               let newDate = result.deckDataDict[name]?.modifiedDate,
               newDate > oldDate {
                editedStale.insert(name)
            }
        }
        
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
        
        if !self.hasCompletedInitialRefresh {
            // On initial load, select only the topmost stale deck
            if let firstStale = result.staleNames.first {
                self.selectedNames = [firstStale]
            } else {
                self.selectedNames = []
            }
            self.hasCompletedInitialRefresh = true
        } else {
            // Retain selected names that are still stale, and add new ones / edited ones
            self.selectedNames = self.selectedNames.intersection(result.staleNames)
            self.selectedNames.formUnion(newlyStale)
            self.selectedNames.formUnion(editedStale)
        }
        
        await validateMentiCodes()
    }
    
    // MARK: - Private Helpers
    
    /// Validates all Menti codes found in the current decks.
    private func validateMentiCodes() async {
        var codesToValidate: Set<String> = []
        for deckData in deckDataDict.values {
            codesToValidate.formUnion(collectMentiCodes(deck: deckData.rootDeck))
        }
        
        for code in codesToValidate {
            if mentiStatuses[code] == nil {
                do {
                    _ = try await MentiService.getMentimeterURL(code: code)
                    mentiStatuses[code] = true
                } catch {
                    mentiStatuses[code] = false
                }
            }
        }
    }
    
    /// Recursively collects all Menti codes from a deck.
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
