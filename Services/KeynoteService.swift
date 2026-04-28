import Foundation
import AppKit

/// Provides services for interacting with Apple Keynote via AppleScript.
public enum KeynoteService {
    
    /// Errors specific to script execution.
    public enum ScriptError: Error, LocalizedError {
        case executionFailed(String)
        
        public var errorDescription: String? {
            switch self {
            case .executionFailed(let msg):
                return msg
            }
        }
    }
    
    /// Executes an AppleScript string.
    /// - Parameter code: The AppleScript source code to execute.
    /// - Returns: The string value returned by the script.
    /// - Throws: `ScriptError.executionFailed`.
    public static func runApplescript(_ code: String) throws -> String {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: code) else {
            throw ScriptError.executionFailed("Failed to compile AppleScript source.")
        }
        
        let result = script.executeAndReturnError(&errorInfo)
        
        if let errorDescription = errorInfo?[NSAppleScript.errorMessage] as? String {
            throw ScriptError.executionFailed(errorDescription)
        } else if errorInfo != nil {
            throw ScriptError.executionFailed("Unknown AppleScript error occurred.")
        }
        
        return result.stringValue ?? ""
    }
    
    /// Assembles multiple decks based on the provided identifiers and data.
    /// - Parameters:
    ///   - toBuild: List of deck names to build.
    ///   - deckDataDict: Mapping of deck names to their resolved data.
    ///   - paths: The application paths.
    ///   - mentiStatuses: Validation status of various Menti codes.
    /// - Returns: The number of decks successfully processed.
    /// - Throws: Any error that occurred during the process.
    public static func assembleDecks(
        toBuild: [String],
        deckDataDict: [String: DeckData],
        paths: AppPaths,
        mentiStatuses: [String: Bool]
    ) async throws -> Int {
        var processedCount = 0
        
        // 1. Build cache pool from valid output manifests
        let validOutputs = ManifestManager.getValidOutputManifests(outputsDir: paths.outputs, manifestDir: paths.outputManifests)
        
        for configName in toBuild {
            guard let deckData = deckDataDict[configName] else { continue }
            
            // If there are fuzzy matches, write the corrected config file before building.
            if !deckData.inexactMatches.isEmpty {
                try DeckResolver.writeCorrectedConfigRecursive(deck: deckData.rootDeck, blocksURL: paths.blocks)
            }
            
            let blocks = CacheChunkPlanner.collectAssemblableBlocks(deck: deckData.rootDeck, blocksURL: paths.blocks, mentiStatuses: mentiStatuses)
            if blocks.isEmpty { continue }

            let outputFile = paths.outputs.appendingPathComponent("\(configName).key")
            let escapedOutput = StringUtilities.asEscape(outputFile.path)
            let agendaText = AgendaService.generateAgendaString(from: deckData.rootDeck)
            var tempFilesToDelete: [URL] = []
            
            var script = "tell application \"Keynote\"\n    activate\n"
            script += "    set targetDoc to make new document\n"
            script += "    set blockCounts to \"\"\n"
            
            let chunks = CacheChunkPlanner.findOptimalChunks(targetBlocks: blocks, validOutputs: validOutputs)
            
            for chunk in chunks {
                if let cacheFile = chunk.sourceURL {
                    // Contiguous CACHE HIT (Length > 1)
                    let escaped = StringUtilities.asEscape(cacheFile.path)
                    let start = chunk.sourceStartIndex
                    let count = chunk.sourceTotalCount
                    let end = start + count - 1
                    
                    script += """
                            set sourceDoc to open POSIX file "\(escaped)"
                            set totalSource to count of slides of sourceDoc
                            if totalSource > \(end) then
                                delete (slides \(end + 1) thru totalSource of sourceDoc)
                            end if
                            if \(start) > 1 then
                                delete (slides 1 thru \(start - 1) of sourceDoc)
                            end if
                            
                    """
                    // Swift counts were already computed during sequence matching.
                    // We just append exactly the concatenated list to blockCounts.
                    script += "        set blockCounts to blockCounts & \"\(chunk.blockCountsString)\"\n"
                    script += """
                            move slides of sourceDoc to end of slides of targetDoc
                            close sourceDoc saving no
                    
                    """
                } else {
                    // No valid contiguous sequence, or L = 1. Process individually.
                    let cblock = chunk.blocks[0]
                    let isAgenda = (StringUtilities.filenameOnly(cblock.path).lowercased() == "agenda")
                    
                    switch cblock.type {
                    case .existingKeynote(let url):
                        if isAgenda {
                            let agendaScript = AgendaService.getAgendaAssemblyScript(agendaText: agendaText, templateURL: url)
                            script += agendaScript + "\n"
                            script += "    set blockCounts to blockCounts & \"1,\"\n"
                        } else {
                            let escaped = StringUtilities.asEscape(url.path)
                            script += """
                                    set sourceDoc to open POSIX file "\(escaped)"
                                    set c to count of slides of sourceDoc
                                    set blockCounts to blockCounts & c & ","
                                    move slides of sourceDoc to end of slides of targetDoc
                                    close sourceDoc saving no
                            
                            """
                        }
                    case .menti(let code):
                        if mentiStatuses[code] == true {
                            do {
                                let tempUrl = try await MentiService.generateMentiSlide(code: code, blocksURL: paths.blocks, outputURL: paths.outputs)
                                tempFilesToDelete.append(tempUrl)
                                let escaped = StringUtilities.asEscape(tempUrl.path)
                                script += """
                                        set sourceDoc to open POSIX file "\(escaped)"
                                        set c to count of slides of sourceDoc
                                        set blockCounts to blockCounts & c & ","
                                        move slides of sourceDoc to end of slides of targetDoc
                                        close sourceDoc saving no
                                
                                """
                            } catch {
                                print("Warning: Failed to generate Menti slide for \(code): \(error)")
                            }
                        } else {
                            script += "    set blockCounts to blockCounts & \"0,\"\n"
                        }
                    case .pause(let info):
                        let templateURL = paths.blocks.appendingPathComponent("Pause.key")
                        let pauseScript = PauseService.getPauseAssemblyScript(info: info, templateURL: templateURL)
                        script += pauseScript + "\n"
                        script += "    set blockCounts to blockCounts & \"1,\"\n"
                    }
                }
            }
            
            script += """
                delete slide 1 of targetDoc
                save targetDoc in POSIX file "\(escapedOutput)"
                close targetDoc saving yes
                return blockCounts
            end tell
            """
            
            let resultString = try await Task.detached(priority: .userInitiated) {
                try runApplescript(script)
            }.value
            
            // Clean up temporary files
            for url in tempFilesToDelete {
                try? FileManager.default.removeItem(at: url)
            }
            
            let counts = resultString.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            let outFP = FileUtilities.fileFingerprint(url: outputFile)
            
            // Build the new OutputManifest for caching future builds
            var cacheEntries: [CacheEntry] = []
            var currentIdx = 1
            for (idx, cblock) in blocks.enumerated() {
                let c = idx < counts.count ? counts[idx] : 0
                cacheEntries.append(CacheEntry(path: cblock.path, blockFingerprint: cblock.fingerprint, startIndex: currentIdx, count: c))
                currentIdx += c
            }
            
            let outputManifest = OutputManifest(deckName: configName, outputFingerprint: outFP, totalSlides: currentIdx - 1, cachedBlocks: cacheEntries)
            let outManifestURL = paths.outputManifests.appendingPathComponent("\(configName).manifest")
            try ManifestManager.writeOutputManifest(url: outManifestURL, manifest: outputManifest)
            
            let deckManifest = ManifestManager.computeDeckManifest(blocksURL: paths.blocks, deck: deckData.rootDeck, mentiStatuses: mentiStatuses)
            let deckManifestURL = ManifestManager.buildManifestURL(manifestDir: paths.deckManifests, configURL: deckData.url)
            try ManifestManager.writeDeckManifest(url: deckManifestURL, manifest: deckManifest)
            
            processedCount += 1
        }
        
        return processedCount
    }
    

}
