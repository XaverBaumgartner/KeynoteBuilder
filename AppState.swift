import Foundation
import Combine
import AppKit

struct DeckData {
    let url: URL
    let matchedNames: [String]
    let inexactMatches: [String]
}

private struct BuildInfo {
    let name: String
    let url: URL
    let matches: [String]
}

@MainActor
class AppState: ObservableObject {
    @Published var staleNames: [String] = []
    @Published var freshNames: [String] = []
    @Published var selectedNames: Set<String> = []
    @Published var deckDataDict: [String: DeckData] = [:]
    @Published var initializationError: String? = nil
    
    @Published var buildProgress: Double = 0
    @Published var isBuilding = false
    @Published var buildFinished = false
    @Published var buildFinishedDate: Date? = nil
    @Published var builtDeckCount: Int = 0
    @Published var buildError: String? = nil
    
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
        buildProgress = 0
        buildError = nil
        
        let toBuild = Array(selectedNames)
        let deckCount = toBuild.count
        
        do {
            var buildConfigs: [BuildInfo] = []
            var assembleAs = "tell application \"Keynote Creator Studio\"\n    activate\n"
            
            for configName in toBuild {
                guard let deckInfo = deckDataDict[configName] else { continue }
                if !deckInfo.inexactMatches.isEmpty {
                    try writeCorrectedConfig(configURL: deckInfo.url, matchedNames: deckInfo.matchedNames)
                }
                
                if !deckInfo.matchedNames.isEmpty {
                    buildConfigs.append(BuildInfo(name: configName, url: deckInfo.url, matches: deckInfo.matchedNames))
                    
                    let outputFile = outputDir.appendingPathComponent("\(configName).key")
                    let inputPathsAs = deckInfo.matchedNames.map { asEscape(blocksDir.appendingPathComponent("\($0).key").path) }
                    let asInputs = "{" + inputPathsAs.map { "POSIX file \"\($0)\"" }.joined(separator: ", ") + "}"
                    let escapedOutput = asEscape(outputFile.path)
                    
                    assembleAs += """
                        -- Build: \(configName)
                        set targetDoc to make new document
                        save targetDoc in POSIX file "\(escapedOutput)"
                        
                        set inputList to \(asInputs)
                        repeat with inputPath in inputList
                            set sourceDoc to open inputPath
                            move slides of sourceDoc to end of slides of targetDoc
                            close sourceDoc saving no
                        end repeat
                        
                        delete slide 1 of targetDoc
                        save targetDoc
                        
                        close targetDoc saving yes
                        \n
                    """
                }
            }
            
            assembleAs += "end tell\n"
            
            if !buildConfigs.isEmpty {
                let _ = try await Task.detached(priority: .userInitiated) {
                    try runApplescript(assembleAs)
                }.value

                for bc in buildConfigs {
                    let newManifest = computeManifest(blocksURL: blocksDir, configURL: bc.url, matchedNames: bc.matches)
                    let murl = buildManifestURL(manifestDir: manifestDir, configURL: bc.url)
                    try writeManifest(url: murl, manifest: newManifest)
                }
                
                self.isBuilding = false
                self.buildFinished = true
                self.builtDeckCount = deckCount
                self.buildFinishedDate = Date()
                self.buildProgress = 1.0
                    
            } else {
                self.isBuilding = false
                self.buildFinished = true
                self.builtDeckCount = deckCount
                self.buildFinishedDate = Date()
                self.buildProgress = 1.0
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
        } catch {
            self.isBuilding = false
            self.buildError = "Error building batch of decks: \(error.localizedDescription)"
        }
    }
    
    func refreshDecks() async {
        guard !isBuilding else { return }
        
        let fm = FileManager.default
        let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        var rootURL = executableURL.deletingLastPathComponent()
        
        let rootPath = rootURL.path
        if rootPath.hasSuffix("Contents/MacOS") || rootPath.hasSuffix("Contents/Resources") {
            rootURL = rootURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        } else {
            rootURL = URL(fileURLWithPath: fm.currentDirectoryPath)
        }
        
        let blocksDir = rootURL.appendingPathComponent("blocks")
        let decksDir = rootURL.appendingPathComponent("decks")
        let outputsDir = rootURL.appendingPathComponent("outputs")
        let manifestsDir = outputsDir.appendingPathComponent(".manifests")
        
        self.blocksURL = blocksDir
        self.outputsURL = outputsDir
        self.manifestURL = manifestsDir
        
        if !fm.fileExists(atPath: blocksDir.path) {
            self.initializationError = "No blocks/ folder found."
            return
        }
        
        if !fm.fileExists(atPath: decksDir.path) {
            self.initializationError = "No decks/ folder found. Please create a decks/ folder with .txt config files."
            return
        }
        
        try? fm.createDirectory(at: outputsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: manifestsDir, withIntermediateDirectories: true)
        
        guard let deckFilesAll = try? fm.contentsOfDirectory(atPath: decksDir.path) else {
            self.initializationError = "Could not read decks folder."
            return
        }
        
        let configs = deckFilesAll.filter { $0.hasSuffix(".txt") }.sorted()
        
        if configs.isEmpty {
            self.initializationError = "No deck configs (.txt) found in the decks/ folder."
            return
        }
        
        var newStaleNames: [String] = []
        var newFreshNames: [String] = []
        var newDeckDataDict: [String: DeckData] = [:]
        
        for configNameWithExt in configs {
            let configName = String(configNameWithExt.dropLast(4))
            let configURL = decksDir.appendingPathComponent(configNameWithExt)
            
            do {
                let resolved = try resolveBlocks(blocksURL: blocksDir, configURL: configURL)
                let stale = isStale(manifestDir: manifestsDir, outputsDir: outputsDir, blocksURL: blocksDir, configURL: configURL, matchedNames: resolved.matchedNames)
                
                newDeckDataDict[configName] = DeckData(url: configURL, matchedNames: resolved.matchedNames, inexactMatches: resolved.inexactMatches)
                
                if stale {
                    newStaleNames.append(configName)
                } else {
                    newFreshNames.append(configName)
                }
            } catch {
                print("Error resolving blocks for \(configName): \(error)")
            }
        }
        
        let newlyStale = Set(newStaleNames).subtracting(self.staleNames)
        
        self.deckDataDict = newDeckDataDict
        self.staleNames = newStaleNames
        self.freshNames = newFreshNames
        
        if self.buildFinished {
            if !newlyStale.isEmpty {
                self.buildFinished = false
                self.buildFinishedDate = nil
            } else if let finishDate = self.buildFinishedDate, Date().timeIntervalSince(finishDate) > 5.0 {
                self.buildFinished = false
                self.buildFinishedDate = nil
            }
        } else if !newStaleNames.isEmpty {
            self.buildFinished = false
            self.buildFinishedDate = nil
        }
        
        // Retain selected names that are still stale, and add new ones
        self.selectedNames = self.selectedNames.intersection(newStaleNames)
        self.selectedNames.formUnion(newlyStale)
        
        // If nothing was selected on the initial load, select all stale decks
        if !self.hasCompletedInitialRefresh {
            if self.selectedNames.isEmpty {
                self.selectedNames = Set(newStaleNames)
            }
            self.hasCompletedInitialRefresh = true
        }
    }
}
