import Foundation

/// Core logic for resolving, scanning, and managing deck configurations.
public enum DeckResolver {
    
    /// Resolves block references in a configuration file within the "blocks/" folder.
    /// - Parameters:
    ///   - blocksURL: The URL of the directory containing blocks.
    ///   - configURL: The URL of the configuration file to resolve.
    ///   - allFiles: A list of all available files in the blocks directory.
    ///   - visitedURLs: A set of URLs already visited for cycle detection.
    ///   - isDeckRoot: Whether the configuration file is at the root of the "decks/" folder.
    /// - Returns: A `ResolvedDeck` object.
    /// - Throws: `CoreError.circularReference`, `CoreError.unreadableConfig`, `CoreError.ambiguousReference`.
    public static func resolveBlocks(
        blocksURL: URL,
        configURL: URL,
        allFiles: [(name: String, path: String, type: BlockType)],
        visitedURLs: Set<URL> = [],
        isDeckRoot: Bool = false
    ) throws -> ResolvedDeck {
        if visitedURLs.contains(configURL) {
            throw CoreError.circularReference(configURL)
        }
        
        guard let fileContents = try? String(contentsOf: configURL, encoding: .utf8) else {
            throw CoreError.unreadableConfig(configURL)
        }
        
        let lines = fileContents.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var matches: [BlockMatch] = []
        var newVisited = visitedURLs
        newVisited.insert(configURL)
        
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let base = StringUtilities.stripExtension(trimmed)
            
            // If it's a root deck, only match top-level files.
            let candidates = isDeckRoot ? allFiles.filter { !$0.path.contains("/") } : allFiles
            let baseLower = base.lowercased()
            
            // Perform fuzzy matching against actual files in the blocks directory.
            let candidateNames = candidates.map { $0.name.lowercased() }
            
            var bestMatches: [(score: Double, index: Int)] = []
            for i in 0..<candidateNames.count {
                let score = StringMatching.jaroWinkler(baseLower, candidateNames[i])
                bestMatches.append((score: score, index: i))
            }
            
            bestMatches.sort { $0.score > $1.score }
            
            guard let best = bestMatches.first else { continue }
            
            let topScore = best.score
            let ties = bestMatches.filter { abs($0.score - topScore) < 0.001 }
            
            // Ambiguity check.
            if ties.count > 1 {
                let matchedPaths = ties.compactMap { $0.index < candidates.count ? candidates[$0.index].path : nil }
                if Set(matchedPaths).count > 1 {
                    throw CoreError.ambiguousReference(base, matchedPaths)
                }
            }
            
            let matchedFile = candidates[best.index]
            var isFuzzy = baseLower != matchedFile.name.lowercased()
            var blockType = matchedFile.type
            var resolvedRelativePath = matchedFile.path
            
            // Service Detection Logic:
            // If the matched file is one of our special service tempates, extract parameters.
            let matchedNameLower = matchedFile.name.lowercased()
            if matchedNameLower == "menti" {
                let code = StringUtilities.extractMentiCode(trimmed)
                blockType = .menti(code: code)
                resolvedRelativePath = matchedFile.path
                
                // Recalculate fuzzy status against the canonical service string.
                let canonical = blockType.canonicalLine(baseName: matchedFile.name)
                isFuzzy = baseLower != canonical.lowercased()
            } else if matchedNameLower == "pause" {
                let info = StringUtilities.extractPauseInfo(trimmed)
                blockType = .pause(info: info)
                resolvedRelativePath = matchedFile.path
                
                // Recalculate fuzzy status against the canonical service string.
                let canonical = blockType.canonicalLine(baseName: matchedFile.name)
                isFuzzy = baseLower != canonical.lowercased()
            }
            
            var match = BlockMatch(
                originalName: trimmed,
                resolvedRelativePath: resolvedRelativePath,
                isFuzzy: isFuzzy,
                type: blockType,
                nestedDeck: nil
            )
            
            // Recursive resolution for nested config files.
            if matchedFile.type == .config {
                let nestedURL = blocksURL.appendingPathComponent(matchedFile.path)
                match.nestedDeck = try resolveBlocks(blocksURL: blocksURL, configURL: nestedURL, allFiles: allFiles, visitedURLs: newVisited)
            }
            
            matches.append(match)
        }
        
        return ResolvedDeck(url: configURL, matches: matches)
    }
    

    
    /// Corrects configuration files by writing the resolved (canonical) names back to the files.
    public static func writeCorrectedConfigRecursive(deck: ResolvedDeck, blocksURL: URL) throws {
        let currentLevelFuzzy = deck.matches.filter { $0.isFuzzy }
        if !currentLevelFuzzy.isEmpty {
            let content = deck.matches.map { $0.correctionLine }.joined(separator: "\n") + "\n"
            try content.write(to: deck.url, atomically: true, encoding: .utf8)
        }
        
        for m in deck.matches {
            if let nested = m.nestedDeck {
                try writeCorrectedConfigRecursive(deck: nested, blocksURL: blocksURL)
            }
        }
    }
    

    
    /// Helper to collect all inexact (fuzzy) matches in a deck tree.
    public static func getAllInexactMatches(deck: ResolvedDeck) -> [String] {
        var result: [String] = []
        for m in deck.matches {
            if m.isFuzzy {
                let base = StringUtilities.stripExtension(m.originalName)
                result.append("'\(base)' -> '\(m.resolvedRelativePath)'")
            }
            if let nested = m.nestedDeck {
                result.append(contentsOf: getAllInexactMatches(deck: nested))
            }
        }
        return Array(Set(result)).sorted()
    }
    

}
