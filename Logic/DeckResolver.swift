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
        try? fm.createDirectory(at: paths.manifests, withIntermediateDirectories: true)
        
        guard let deckFilesAll = try? fm.contentsOfDirectory(atPath: paths.decks.path) else {
            return ScanResult(staleNames: [], freshNames: [], deckDataDict: [:], error: "Could not read decks folder.")
        }
        
        let configs = deckFilesAll.filter { $0.hasSuffix(".txt") }
        
        if configs.isEmpty {
            return ScanResult(staleNames: [], freshNames: [], deckDataDict: [:], error: "No deck configs (.txt) found in the decks/ folder.")
        }
        
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
                let rootDeck = try resolveBlocks(blocksURL: paths.blocks, configURL: configURL, allFiles: allFiles, isDeckRoot: true)
                let inexact = getAllInexactMatches(deck: rootDeck)
                let stale = isStale(manifestDir: paths.manifests, outputsDir: paths.outputs, blocksURL: paths.blocks, deck: rootDeck, mentiStatuses: mentiStatuses)
                
                deckDataDict[configName] = DeckData(url: configURL, rootDeck: rootDeck, inexactMatches: inexact)
                
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
    
    /// Checks if a deck is stale (needs a rebuild).
    /// - Parameters:
    ///   - manifestDir: Manifest directory URL.
    ///   - outputsDir: Output directory URL.
    ///   - blocksURL: Blocks directory URL.
    ///   - deck: The resolved deck.
    ///   - mentiStatuses: Validated Menti statuses.
    /// - Returns: `true` if stale, `false` otherwise.
    public static func isStale(manifestDir: URL, outputsDir: URL, blocksURL: URL, deck: ResolvedDeck, mentiStatuses: [String: Bool]) -> Bool {
        let murl = buildManifestURL(manifestDir: manifestDir, configURL: deck.url)
        if !FileManager.default.fileExists(atPath: murl.path) { return true }
        
        let configName = deck.url.deletingPathExtension().lastPathComponent
        let finalKeyURL = outputsDir.appendingPathComponent("\(configName).key")
        if !FileManager.default.fileExists(atPath: finalKeyURL.path) { return true }
        
        let oldManifest = readManifest(url: murl)
        let currentManifest = computeManifest(blocksURL: blocksURL, deck: deck, mentiStatuses: mentiStatuses)
        
        if oldManifest.count != currentManifest.count { return true }
        
        for (key, val) in currentManifest {
            if oldManifest[key] != val { return true }
        }
        return false
    }
    
    /// Computes a full manifest for a deck and its nested dependencies.
    public static func computeManifest(blocksURL: URL, deck: ResolvedDeck, mentiStatuses: [String: Bool]) -> [String: String] {
        var manifest: [String: String] = [:]
        manifest["CONFIG"] = FileUtilities.fileFingerprint(url: deck.url)
        for m in deck.matches {
            switch m.type {
            case .keynote:
                let blockFile = blocksURL.appendingPathComponent(m.resolvedRelativePath)
                let fp = FileUtilities.fileFingerprint(url: blockFile)
                if !fp.isEmpty {
                    manifest["BLOCK:\(m.resolvedRelativePath)"] = fp
                }
            case .menti(let code):
                let status = mentiStatuses[code] ?? false
                manifest["BLOCK:menti:\(code)"] = status ? "VALID" : "INVALID"
                
                // Track the Menti template fingerprint so changes to it trigger a rebuild.
                let templateURL = blocksURL.appendingPathComponent("Menti.key")
                let templateFP = FileUtilities.fileFingerprint(url: templateURL)
                if !templateFP.isEmpty {
                    manifest["TEMPLATE:menti"] = templateFP
                }
            case .pause(let info):
                manifest["BLOCK:pause:\(info)"] = "PRESENT"
                
                // Track the Pause template fingerprint so changes to it trigger a rebuild.
                let templateURL = blocksURL.appendingPathComponent("Pause.key")
                let templateFP = FileUtilities.fileFingerprint(url: templateURL)
                if !templateFP.isEmpty {
                    manifest["TEMPLATE:pause"] = templateFP
                }
            case .config:
                if let nested = m.nestedDeck {
                    let nestedManifest = computeManifest(blocksURL: blocksURL, deck: nested, mentiStatuses: mentiStatuses)
                    for (key, val) in nestedManifest {
                        manifest["NESTED:\(m.resolvedRelativePath):\(key)"] = val
                    }
                }
            }
        }
        return manifest
    }
    
    /// Reads a manifest file from the given URL.
    public static func readManifest(url: URL) -> [String: String] {
        var manifest: [String: String] = [:]
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return manifest
        }
        for line in content.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                manifest[parts[0]] = parts[1]
            }
        }
        return manifest
    }
    
    /// Writes a manifest to the given URL.
    public static func writeManifest(url: URL, manifest: [String: String]) throws {
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        
        var lines: [String] = []
        if let config = manifest["CONFIG"] {
            lines.append("CONFIG=\(config)")
        }
        for key in manifest.keys.sorted().filter({ $0.hasPrefix("NESTED:") }) {
            lines.append("\(key)=\(manifest[key]!)")
        }
        for key in manifest.keys.sorted().filter({ $0.hasPrefix("BLOCK:") }) {
            lines.append("\(key)=\(manifest[key]!)")
        }
        for key in manifest.keys.sorted().filter({ $0.hasPrefix("TEMPLATE:") }) {
            lines.append("\(key)=\(manifest[key]!)")
        }
        
        let content = lines.joined(separator: "\n") + "\n"
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw CoreError.writeFailed(url)
        }
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
    
    /// Returns a manifest file URL for a given config URL.
    public static func buildManifestURL(manifestDir: URL, configURL: URL) -> URL {
        let configName = configURL.deletingPathExtension().lastPathComponent
        return manifestDir.appendingPathComponent("\(configName).manifest")
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
