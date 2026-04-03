import Foundation
import AppKit

struct BlockMatch: Identifiable, Codable, Hashable {
    var id = UUID()
    let originalName: String
    let resolvedRelativePath: String
    let isFuzzy: Bool
    let type: BlockType
    var nestedDeck: ResolvedDeck?
}

enum BlockType: String, Codable {
    case keynote
    case config
}

struct ResolvedDeck: Codable, Hashable {
    let url: URL
    let matches: [BlockMatch]
}

struct DeckData: Codable {
    let url: URL
    let rootDeck: ResolvedDeck
    let inexactMatches: [String] // For backward compatibility or top-level reporting
}

private struct BuildInfo {
    let name: String
    let url: URL
    let keynotePaths: [String]
}

struct AppPaths {
    let root: URL
    let blocks: URL
    let decks: URL
    let outputs: URL
    let manifests: URL
}

struct ScanResult {
    let staleNames: [String]
    let freshNames: [String]
    let deckDataDict: [String: DeckData]
    let error: String?
}

enum CoreError: Error, LocalizedError {
    case fileNotFound(URL)
    case unreadableConfig(URL)
    case writeFailed(URL)
    case circularReference(URL)
    case ambiguousReference(String, [String])

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.path)"
        case .unreadableConfig(let url):
            return "Could not read config file: \(url.path)"
        case .writeFailed(let url):
            return "Could not write to file: \(url.path)"
        case .circularReference(let url):
            return "Circular reference detected in config: \(url.lastPathComponent)"
        case .ambiguousReference(let name, let matches):
            return "Ambiguous reference for '\(name)': matches both \(matches.joined(separator: " and "))."
        }
    }
}

func resolveBlocks(blocksURL: URL, configURL: URL, visitedURLs: Set<URL> = [], isDeckRoot: Bool = false) throws -> ResolvedDeck {
    if visitedURLs.contains(configURL) {
        throw CoreError.circularReference(configURL)
    }
    
    guard let fileContents = try? String(contentsOf: configURL, encoding: .utf8) else {
        throw CoreError.unreadableConfig(configURL)
    }
    
    let fm = FileManager.default
    var allFiles: [(name: String, path: String, type: BlockType)] = []
    
    let enumerator = fm.enumerator(at: blocksURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
    while let fileURL = enumerator?.nextObject() as? URL {
        let relativePath = fileURL.path.replacingOccurrences(of: blocksURL.path + "/", with: "")
        let ext = fileURL.pathExtension.lowercased()
        
        if ext == "key" {
            allFiles.append((name: String(relativePath.dropLast(4)), path: relativePath, type: .keynote))
        } else if ext == "txt" {
            allFiles.append((name: String(relativePath.dropLast(4)), path: relativePath, type: .config))
        }
    }
    
    let lines = fileContents.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    var matches: [BlockMatch] = []
    var newVisited = visitedURLs
    newVisited.insert(configURL)
    
    for rawLine in lines {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        var base = trimmed
        if base.lowercased().hasSuffix(".key") || base.lowercased().hasSuffix(".txt") {
            base = String(base.dropLast(4))
        }
        
        // Restriction: Decks can't reference subblocks
        if isDeckRoot && base.contains("/") {
             // We'll ignore it or handle it as an error? The prompt says "but NOT subblocks".
             // Let's just filter candidates to top-level only if isDeckRoot.
        }
        
        let candidates = isDeckRoot ? allFiles.filter { !$0.path.contains("/") } : allFiles
        
        let baseLower = base.lowercased()
        var bestMatches: [(score: Double, index: Int)] = []
        
        for i in 0..<candidates.count {
            let score = jaroWinkler(baseLower, candidates[i].name.lowercased())
            bestMatches.append((score: score, index: i))
        }
        
        bestMatches.sort { $0.score > $1.score }
        
        guard let best = bestMatches.first else { continue }
        
        // Ambiguity check: if there are multiple matches with the same score but different types/paths
        let topScore = best.score
        let ties = bestMatches.filter { abs($0.score - topScore) < 0.001 }
        if ties.count > 1 {
            let matchedPaths = ties.map { candidates[$0.index].path }
            // Check if they actually point to different files or just same basename in different folders
            if Set(matchedPaths).count > 1 {
                throw CoreError.ambiguousReference(base, matchedPaths)
            }
        }
        
        let matchedFile = candidates[best.index]
        let isFuzzy = baseLower != matchedFile.name.lowercased()
        
        var match = BlockMatch(
            originalName: trimmed,
            resolvedRelativePath: matchedFile.path,
            isFuzzy: isFuzzy,
            type: matchedFile.type,
            nestedDeck: nil
        )
        
        if matchedFile.type == .config {
            let nestedURL = blocksURL.appendingPathComponent(matchedFile.path)
            match.nestedDeck = try resolveBlocks(blocksURL: blocksURL, configURL: nestedURL, visitedURLs: newVisited)
        }
        
        matches.append(match)
    }
    
    return ResolvedDeck(url: configURL, matches: matches)
}

func getAllInexactMatches(deck: ResolvedDeck) -> [String] {
    var result: [String] = []
    for m in deck.matches {
        if m.isFuzzy {
            let base = m.originalName.hasSuffix(".key") || m.originalName.hasSuffix(".txt") ? String(m.originalName.dropLast(4)) : m.originalName
            result.append("'\(base)' -> '\(m.resolvedRelativePath)'")
        }
        if let nested = m.nestedDeck {
            result.append(contentsOf: getAllInexactMatches(deck: nested))
        }
    }
    return Array(Set(result)).sorted()
}

func getAllKeynotePaths(deck: ResolvedDeck) -> [String] {
    var paths: [String] = []
    for m in deck.matches {
        if m.type == .keynote {
            paths.append(m.resolvedRelativePath)
        } else if let nested = m.nestedDeck {
            paths.append(contentsOf: getAllKeynotePaths(deck: nested))
        }
    }
    return paths
}

func writeCorrectedConfigRecursive(deck: ResolvedDeck, blocksURL: URL) throws {
    // Only write if there are fuzzy matches at this level
    let currentLevelFuzzy = deck.matches.filter { $0.isFuzzy }
    if !currentLevelFuzzy.isEmpty {
        let content = deck.matches.map { $0.resolvedRelativePath }.joined(separator: "\n") + "\n"
        try content.write(to: deck.url, atomically: true, encoding: .utf8)
    }
    
    for m in deck.matches {
        if let nested = m.nestedDeck {
            try writeCorrectedConfigRecursive(deck: nested, blocksURL: blocksURL)
        }
    }
}

func buildManifestURL(manifestDir: URL, configURL: URL) -> URL {
    let configName = configURL.deletingPathExtension().lastPathComponent
    return manifestDir.appendingPathComponent("\(configName).manifest")
}

func readManifest(url: URL) -> [String: String] {
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

func writeManifest(url: URL, manifest: [String: String]) throws {
    let dir = url.deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: dir.path) {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
    }
    
    var lines: [String] = []
    if let config = manifest["CONFIG"] {
        lines.append("CONFIG=\(config)")
    }
    // Nested configs
    for key in manifest.keys.sorted().filter({ $0.hasPrefix("NESTED:") }) {
        lines.append("\(key)=\(manifest[key]!)")
    }
    for key in manifest.keys.sorted().filter({ $0.hasPrefix("BLOCK:") }) {
        lines.append("\(key)=\(manifest[key]!)")
    }
    
    let content = lines.joined(separator: "\n") + "\n"
    do {
        try content.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        throw CoreError.writeFailed(url)
    }
}

func computeManifest(blocksURL: URL, deck: ResolvedDeck) -> [String: String] {
    var manifest: [String: String] = [:]
    manifest["CONFIG"] = fileFingerprint(url: deck.url)
    for m in deck.matches {
        if m.type == .keynote {
            let blockFile = blocksURL.appendingPathComponent(m.resolvedRelativePath)
            let fp = fileFingerprint(url: blockFile)
            if !fp.isEmpty {
                manifest["BLOCK:\(m.resolvedRelativePath)"] = fp
            }
        } else if let nested = m.nestedDeck {
            let nestedManifest = computeManifest(blocksURL: blocksURL, deck: nested)
            // Flatten nested manifest with a prefix to avoid collisions
            for (key, val) in nestedManifest {
                manifest["NESTED:\(m.resolvedRelativePath):\(key)"] = val
            }
        }
    }
    return manifest
}

func isStale(manifestDir: URL, outputsDir: URL, blocksURL: URL, deck: ResolvedDeck) -> Bool {
    let murl = buildManifestURL(manifestDir: manifestDir, configURL: deck.url)
    if !FileManager.default.fileExists(atPath: murl.path) { return true }
    
    let configName = deck.url.deletingPathExtension().lastPathComponent
    let finalKeyURL = outputsDir.appendingPathComponent("\(configName).key")
    if !FileManager.default.fileExists(atPath: finalKeyURL.path) { return true }
    
    let oldManifest = readManifest(url: murl)
    let currentManifest = computeManifest(blocksURL: blocksURL, deck: deck)
    
    if oldManifest.count != currentManifest.count { return true }
    
    for (key, val) in currentManifest {
        if oldManifest[key] != val { return true }
    }
    return false
}

//////////////// Utils //////////////////

func fileFingerprint(url: URL) -> String {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let mtime = attributes[.modificationDate] as? Date,
          let size = attributes[.size] as? NSNumber else {
        return ""
    }
    return "\(Int(mtime.timeIntervalSince1970))-\(size.intValue)"
}

func asEscape(_ s: String) -> String {
    return s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
}

enum ScriptError: Error, LocalizedError {
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .executionFailed(let msg):
            return msg
        }
    }
}

func runApplescript(_ code: String) throws -> String {
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

func jaroWinkler(_ s1: String, _ s2: String) -> Double {
    if s1 == s2 { return 1.0 }
    if s1.isEmpty || s2.isEmpty { return 0.0 }
    
    let s1Chars = Array(s1)
    let s2Chars = Array(s2)
    let n = s1Chars.count
    let m = s2Chars.count
    
    var matchWindow = max(n, m) / 2 - 1
    if matchWindow < 0 { matchWindow = 0 }
    
    var s1Matched = [Bool](repeating: false, count: n)
    var s2Matched = [Bool](repeating: false, count: m)
    
    var matches = 0
    var transpositions = 0
    
    for i in 0..<n {
        let lo = max(0, i - matchWindow)
        let hi = min(m - 1, i + matchWindow)
        
        if lo <= hi {
            for j in lo...hi {
                if !s2Matched[j] && s1Chars[i] == s2Chars[j] {
                    s1Matched[i] = true
                    s2Matched[j] = true
                    matches += 1
                    break
                }
            }
        }
    }
    
    if matches == 0 { return 0.0 }
    
    var k = 0
    for i in 0..<n {
        if !s1Matched[i] { continue }
        while !s2Matched[k] { k += 1 }
        if s1Chars[i] != s2Chars[k] {
            transpositions += 1
        }
        k += 1
    }
    
    let mD = Double(matches)
    let jaro = (mD / Double(n) + mD / Double(m) + (mD - Double(transpositions) / 2.0) / mD) / 3.0
    
    var prefix = 0
    let maxPrefix = min(4, min(n, m))
    for i in 0..<maxPrefix {
        if s1Chars[i] == s2Chars[i] { prefix += 1 }
        else { break }
    }
    
    return jaro + Double(prefix) * 0.1 * (1.0 - jaro)
}

func assembleDecks(toBuild: [String], deckDataDict: [String: DeckData], blocksURL: URL, outputsURL: URL, manifestURL: URL) async throws -> Int {
    var buildConfigs: [BuildInfo] = []
    var assembleAs = "tell application \"Keynote Creator Studio\"\n    activate\n"
    
    for configName in toBuild {
        guard let deckData = deckDataDict[configName] else { continue }
        if !deckData.inexactMatches.isEmpty {
            try writeCorrectedConfigRecursive(deck: deckData.rootDeck, blocksURL: blocksURL)
        }
        
        let keynotePaths = getAllKeynotePaths(deck: deckData.rootDeck)
        if !keynotePaths.isEmpty {
            buildConfigs.append(BuildInfo(name: configName, url: deckData.url, keynotePaths: keynotePaths))
            
            let outputFile = outputsURL.appendingPathComponent("\(configName).key")
            let inputPathsAs = keynotePaths.map { asEscape(blocksURL.appendingPathComponent($0).path) }
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
            let newManifest = computeManifest(blocksURL: blocksURL, deck: deckData.rootDeck)
            let murl = buildManifestURL(manifestDir: manifestURL, configURL: bc.url)
            try writeManifest(url: murl, manifest: newManifest)
        }
    }
    
    return toBuild.count
}

func discoverPaths() -> AppPaths {
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
    
    return AppPaths(root: rootURL, blocks: blocksDir, decks: decksDir, outputs: outputsDir, manifests: manifestsDir)
}

func scanDecks(paths: AppPaths) async -> ScanResult {
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
    
    var staleNames: [String] = []
    var freshNames: [String] = []
    var deckDataDict: [String: DeckData] = [:]
    
    for configNameWithExt in configs {
        let configName = String(configNameWithExt.dropLast(4))
        let configURL = paths.decks.appendingPathComponent(configNameWithExt)
        
        do {
            let rootDeck = try resolveBlocks(blocksURL: paths.blocks, configURL: configURL, isDeckRoot: true)
            let inexact = getAllInexactMatches(deck: rootDeck)
            let stale = isStale(manifestDir: paths.manifests, outputsDir: paths.outputs, blocksURL: paths.blocks, deck: rootDeck)
            
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