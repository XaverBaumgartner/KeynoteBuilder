import Foundation

/// Scans the project folders to find all available decks and their status.
public enum DeckScanner {
    
    /// Scans the project folders to find all available decks and their status.
    /// - Parameters:
    ///   - paths: The application paths.
    ///   - mentiStatuses: A dictionary of Menti codes and their validation status.
    /// - Returns: A `ScanResult` containing all decks, split into stale and fresh.
    public static func scanDecks(paths: AppPaths, mentiStatuses: [String: Bool]) async -> ScanResult {
        let fm = FileManager.default
        
        if !fm.fileExists(atPath: paths.blocks.path) {
            return ScanResult(staleNames: [], freshNames: [], deckDataDict: [:], error: "No blocks/ folder found.")
        }
        
        if !fm.fileExists(atPath: paths.decks.path) {
            return ScanResult(staleNames: [], freshNames: [], deckDataDict: [:], error: "No decks/ folder found. Please create a decks/ folder with .txt config files.")
        }
        
        try? fm.createDirectory(at: paths.outputs, withIntermediateDirectories: true)
        try? fm.createDirectory(at: paths.deckManifests, withIntermediateDirectories: true)
        try? fm.createDirectory(at: paths.outputManifests, withIntermediateDirectories: true)
        
        guard let deckURLsAll = try? fm.contentsOfDirectory(at: paths.decks, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else {
            return ScanResult(staleNames: [], freshNames: [], deckDataDict: [:], error: "Could not read decks folder.")
        }
        
        let configURLs = deckURLsAll.filter { $0.pathExtension.lowercased() == "txt" }
        
        if configURLs.isEmpty {
            return ScanResult(staleNames: [], freshNames: [], deckDataDict: [:], error: "No deck configs (.txt) found in the decks/ folder.")
        }
        
        let sortedConfigURLs = configURLs.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return date1 > date2
        }
        
        let configs = sortedConfigURLs.map { $0.lastPathComponent }
        
        var allFiles: [(name: String, path: String, type: BlockType)] = []
        let enumerator = fm.enumerator(at: paths.blocks, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        while let fileURL = enumerator?.nextObject() as? URL {
            let relativePath = fileURL.path.replacingOccurrences(of: paths.blocks.path + "/", with: "")
            let ext = fileURL.pathExtension.lowercased()
            
            if ext == "key" {
                allFiles.append((name: String(relativePath.dropLast(4)), path: relativePath, type: .keynote))
            } else if ext == "txt" {
                allFiles.append((name: String(relativePath.dropLast(4)), path: relativePath, type: .config))
            }
        }
        
        var staleNames: [String] = []
        var freshNames: [String] = []
        var deckDataDict: [String: DeckData] = [:]
        
        for configNameWithExt in configs {
            let configName = String(configNameWithExt.dropLast(4))
            let configURL = paths.decks.appendingPathComponent(configNameWithExt)
            
            do {
                let rootDeck = try DeckResolver.resolveBlocks(blocksURL: paths.blocks, configURL: configURL, allFiles: allFiles, isDeckRoot: true)
                let inexact = DeckResolver.getAllInexactMatches(deck: rootDeck)
                let stale = ManifestManager.isStale(manifestDir: paths.deckManifests, outputsDir: paths.outputs, blocksURL: paths.blocks, deck: rootDeck, mentiStatuses: mentiStatuses)
                
                let modifiedDate = (try? configURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                deckDataDict[configName] = DeckData(url: configURL, rootDeck: rootDeck, inexactMatches: inexact, modifiedDate: modifiedDate)
                
                if stale {
                    staleNames.append(configName)
                } else {
                    freshNames.append(configName)
                }
            } catch {
                return ScanResult(staleNames: [], freshNames: [], deckDataDict: [:], error: error.localizedDescription)
            }
        }
        
        return ScanResult(staleNames: staleNames, freshNames: freshNames, deckDataDict: deckDataDict, error: nil)
    }
}
