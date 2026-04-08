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
        var buildConfigs: [(name: String, url: URL)] = []
        var assembleAs = "tell application \"Keynote\"\n    activate\n"
        
        for configName in toBuild {
            guard let deckData = deckDataDict[configName] else { continue }
            
            // If there are fuzzy matches, write the corrected config file before building.
            if !deckData.inexactMatches.isEmpty {
                try DeckResolver.writeCorrectedConfigRecursive(deck: deckData.rootDeck, blocksURL: paths.blocks)
            }
            
            let blocks = collectAssemblableBlocks(deck: deckData.rootDeck, blocksURL: paths.blocks)
            if !blocks.isEmpty {
                buildConfigs.append((name: configName, url: deckData.url))
                
                let outputFile = paths.outputs.appendingPathComponent("\(configName).key")
                let escapedOutput = StringUtilities.asEscape(outputFile.path)
                let agendaText = AgendaService.generateAgendaString(from: deckData.rootDeck)
                
                assembleAs += """
                    -- Build: \(configName)
                    set targetDoc to make new document
                    save targetDoc in POSIX file "\(escapedOutput)"
                
                """
                
                for block in blocks {
                    switch block {
                    case .existingKeynote(let url):
                        if StringUtilities.filenameOnly(url.path).lowercased() == "agenda" {
                            let agendaScript = AgendaService.getAgendaAssemblyScript(agendaText: agendaText, templateURL: url)
                            assembleAs += agendaScript + "\n"
                        } else {
                            let escaped = StringUtilities.asEscape(url.path)
                            assembleAs += """
                                    set sourceDoc to open POSIX file "\(escaped)"
                                    move slides of sourceDoc to end of slides of targetDoc
                                    close sourceDoc saving no
                            
                            """
                        }
                    case .menti(let code):
                        if mentiStatuses[code] == true {
                            do {
                                let tempUrl = try await MentiService.generateMentiSlide(code: code, blocksURL: paths.blocks, outputURL: paths.outputs)
                                let escaped = StringUtilities.asEscape(tempUrl.path)
                                assembleAs += """
                                        set sourceDoc to open POSIX file "\(escaped)"
                                        move slides of sourceDoc to end of slides of targetDoc
                                        close sourceDoc saving no
                                
                                """
                            } catch {
                                print("Warning: Failed to generate Menti slide for \(code): \(error)")
                            }
                        }
                    case .pause(let info):
                        let templateURL = paths.blocks.appendingPathComponent("Pause.key")
                        let pauseScript = PauseService.getPauseAssemblyScript(info: info, templateURL: templateURL)
                        assembleAs += pauseScript + "\n"
                    }
                }
                
                assembleAs += """
                    delete slide 1 of targetDoc
                    save targetDoc
                    close targetDoc saving yes
                
                """
            }
        }
        
        assembleAs += "end tell"
        
        if !buildConfigs.isEmpty {
            let _ = try await Task.detached(priority: .userInitiated) {
                try runApplescript(assembleAs)
            }.value

            for bc in buildConfigs {
                guard let deckData = deckDataDict[bc.name] else { continue }
                let newManifest = DeckResolver.computeManifest(blocksURL: paths.blocks, deck: deckData.rootDeck, mentiStatuses: mentiStatuses)
                let murl = DeckResolver.buildManifestURL(manifestDir: paths.manifests, configURL: bc.url)
                try DeckResolver.writeManifest(url: murl, manifest: newManifest)
            }
        }
        
        return toBuild.count
    }
    
    /// Internal helper to collect all buildable units (Keynote files or Menti codes).
    private enum AssemblableBlock {
        case existingKeynote(URL)
        case menti(code: String)
        case pause(info: String)
    }
    
    private static func collectAssemblableBlocks(deck: ResolvedDeck, blocksURL: URL) -> [AssemblableBlock] {
        var blocks: [AssemblableBlock] = []
        for m in deck.matches {
            switch m.type {
            case .keynote:
                blocks.append(.existingKeynote(blocksURL.appendingPathComponent(m.resolvedRelativePath)))
            case .menti(let code):
                blocks.append(.menti(code: code))
            case .pause(let info):
                blocks.append(.pause(info: info))
            case .config:
                if let nested = m.nestedDeck {
                    blocks.append(contentsOf: collectAssemblableBlocks(deck: nested, blocksURL: blocksURL))
                }
            }
        }
        return blocks
    }
}
