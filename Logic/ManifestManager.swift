import Foundation

/// Manages deck and output manifests, including staleness checking and structural hashing.
public enum ManifestManager {
    
    /// Checks if a deck is stale (needs a rebuild) using DeckManifests.
    public static func isStale(manifestDir: URL, outputsDir: URL, outputsCacheDir: URL, blocksURL: URL, deck: ResolvedDeck, mentiStatuses: [String: Bool]) -> Bool {
        let murl = buildManifestURL(manifestDir: manifestDir, configURL: deck.url)
        if !FileManager.default.fileExists(atPath: murl.path) { return true }
        
        let configName = deck.url.deletingPathExtension().lastPathComponent
        let finalKeyURL = outputsDir.appendingPathComponent("\(configName).key")
        let cacheKeyURL = outputsCacheDir.appendingPathComponent("\(configName).key")
        if !FileManager.default.fileExists(atPath: finalKeyURL.path) { return true }
        if !FileManager.default.fileExists(atPath: cacheKeyURL.path) { return true }
        
        guard var oldManifest = readDeckManifest(url: murl) else { return true }
        let currentManifest = computeDeckManifest(blocksURL: blocksURL, deck: deck, mentiStatuses: mentiStatuses)
        
        // Output Integrity Check via OutputManifest
        let outputManifestURL = outputsDir.appendingPathComponent(".manifests").appendingPathComponent("\(configName).manifest")
        if let outManifest = readOutputManifest(url: outputManifestURL) {
            let cacheOutputFP = FileUtilities.fileFingerprint(url: cacheKeyURL)
            if cacheOutputFP != outManifest.outputFingerprint {
                return true // Cache was manually changed
            }
            
            let finalAttr = try? FileManager.default.attributesOfItem(atPath: finalKeyURL.path)
            let cacheAttr = try? FileManager.default.attributesOfItem(atPath: cacheKeyURL.path)
            if let finalMtime = finalAttr?[.modificationDate] as? Date,
               let cacheMtime = cacheAttr?[.modificationDate] as? Date {
                if finalMtime < cacheMtime {
                    return true // final is older than the cache, meaning an old file was copied over
                }
            }
        } else {
            return true // No output manifest
        }
        
        // Fast Path Check
        if oldManifest.txtFingerprint == currentManifest.txtFingerprint && oldManifest.resolvedStructureHash == currentManifest.resolvedStructureHash {
            return false
        }
        
        // Structural Check (Cosmetic Healing)
        if oldManifest.resolvedStructureHash == currentManifest.resolvedStructureHash {
            // COSMETIC CHANGE DETECTED: Healing the manifest
            oldManifest.txtFingerprint = currentManifest.txtFingerprint
            try? writeDeckManifest(url: murl, manifest: oldManifest)
            return false // Not stale!
        }
        
        return true // Truly stale
    }
    
    /// Computes a structural hash manifest for a deck and its nested dependencies.
    public static func computeDeckManifest(blocksURL: URL, deck: ResolvedDeck, mentiStatuses: [String: Bool]) -> DeckManifest {
        let txtFingerprint = FileUtilities.fileFingerprint(url: deck.url)
        let rootHash = computeDeckHash(blocksURL: blocksURL, deck: deck, mentiStatuses: mentiStatuses)
        return DeckManifest(configPath: deck.url.lastPathComponent, txtFingerprint: txtFingerprint, resolvedStructureHash: rootHash)
    }
    
    private static func computeDeckHash(blocksURL: URL, deck: ResolvedDeck, mentiStatuses: [String: Bool]) -> String {
        var hashes: [String] = []
        for m in deck.matches {
            switch m.type {
            case .keynote:
                let blockFile = blocksURL.appendingPathComponent(m.resolvedRelativePath)
                let fp = FileUtilities.fileFingerprint(url: blockFile)
                hashes.append(FileUtilities.stringFingerprint("block:\(m.resolvedRelativePath):\(fp)"))
            case .menti(let code):
                let status = mentiStatuses[code] ?? false
                let fp = status ? "VALID" : "INVALID"
                hashes.append(FileUtilities.stringFingerprint("menti:\(code):\(fp)"))
                let templateURL = blocksURL.appendingPathComponent("Menti.key")
                let templateFP = FileUtilities.fileFingerprint(url: templateURL)
                hashes.append(FileUtilities.stringFingerprint("template:Menti.key:\(templateFP)"))
            case .pause(let info):
                hashes.append(FileUtilities.stringFingerprint("pause:\(info):PRESENT"))
                let templateURL = blocksURL.appendingPathComponent("Pause.key")
                let templateFP = FileUtilities.fileFingerprint(url: templateURL)
                hashes.append(FileUtilities.stringFingerprint("template:Pause.key:\(templateFP)"))
            case .config:
                if let nested = m.nestedDeck {
                    let childHash = computeDeckHash(blocksURL: blocksURL, deck: nested, mentiStatuses: mentiStatuses)
                    hashes.append(FileUtilities.stringFingerprint("nested:\(m.resolvedRelativePath):\(childHash)"))
                }
            }
        }
        return FileUtilities.stringFingerprint(hashes.joined(separator: ","))
    }
    
    /// Reads a deck manifest file from the given URL.
    public static func readDeckManifest(url: URL) -> DeckManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DeckManifest.self, from: data)
    }
    
    /// Writes a deck manifest to the given URL.
    public static func writeDeckManifest(url: URL, manifest: DeckManifest) throws {
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(manifest)
            try data.write(to: url)
        } catch {
            throw CoreError.writeFailed(url)
        }
    }
    
    /// Reads an output manifest file.
    public static func readOutputManifest(url: URL) -> OutputManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OutputManifest.self, from: data)
    }
    
    /// Writes an output manifest.
    public static func writeOutputManifest(url: URL, manifest: OutputManifest) throws {
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: url)
    }
    
    /// Returns a manifest file URL for a given config URL.
    public static func buildManifestURL(manifestDir: URL, configURL: URL) -> URL {
        let configName = configURL.deletingPathExtension().lastPathComponent
        return manifestDir.appendingPathComponent("\(configName).manifest")
    }
    
    /// Reads all OutputManifests and returns those that represent currently valid `.key` outputs.
    public static func getValidOutputManifests(outputsDir: URL, outputsCacheDir: URL, manifestDir: URL) -> [(url: URL, manifest: OutputManifest)] {
        var results: [(url: URL, manifest: OutputManifest)] = []
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: manifestDir.path) else { return results }
        
        for file in files where file.hasSuffix(".manifest") {
            let configName = String(file.dropLast(9))
            let cacheKeyURL = outputsCacheDir.appendingPathComponent("\(configName).key")
            let manifestURL = manifestDir.appendingPathComponent(file)
            
            if !FileManager.default.fileExists(atPath: cacheKeyURL.path) { continue }
            guard let manifest = readOutputManifest(url: manifestURL) else { continue }
            
            let currentFP = FileUtilities.fileFingerprint(url: cacheKeyURL)
            if currentFP != manifest.outputFingerprint { continue } // Cache was modified
            
            results.append((cacheKeyURL, manifest))
        }
        
        return results
    }
}
