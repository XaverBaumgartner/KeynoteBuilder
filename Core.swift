import Foundation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import ImageIO

struct BlockMatch: Identifiable, Codable, Hashable {
    var id = UUID()
    let originalName: String
    let resolvedRelativePath: String
    let isFuzzy: Bool
    let type: BlockType
    var nestedDeck: ResolvedDeck?
}

enum BlockType: Codable, Hashable {
    case keynote
    case config
    case menti(code: String)

    var rawValue: String {
        switch self {
        case .keynote: return "keynote"
        case .config: return "config"
        case .menti(let code): return "menti:\(code)"
        }
    }
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
    case unreadableConfig(URL)
    case writeFailed(URL)
    case circularReference(URL)
    case ambiguousReference(String, [String])
    case mentiError(String)

    var errorDescription: String? {
        switch self {
        case .unreadableConfig(let url):
            return "Could not read config file: \(url.path)"
        case .writeFailed(let url):
            return "Could not write to file: \(url.path)"
        case .circularReference(let url):
            return "Circular reference detected in config: \(url.lastPathComponent)"
        case .ambiguousReference(let name, let matches):
            return "Ambiguous reference for '\(name)': matches both \(matches.joined(separator: " and "))."
        case .mentiError(let msg):
            return "Menti Error: \(msg)"
        }
    }
}

func resolveBlocks(blocksURL: URL, configURL: URL, allFiles: [(name: String, path: String, type: BlockType)], visitedURLs: Set<URL> = [], isDeckRoot: Bool = false) throws -> ResolvedDeck {
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
        let base = stripExtension(trimmed)
        
        let candidates = isDeckRoot ? allFiles.filter { !$0.path.contains("/") } : allFiles
        
        let baseLower = base.lowercased()
        
        // Add "menti" as a virtual candidate
        var candidateNames = candidates.map { $0.name.lowercased() }
        candidateNames.append("menti")
        
        var bestMatches: [(score: Double, index: Int)] = []
        for i in 0..<candidateNames.count {
            let score = jaroWinkler(baseLower, candidateNames[i])
            bestMatches.append((score: score, index: i))
        }
        
        bestMatches.sort { $0.score > $1.score }
        
        guard let best = bestMatches.first else { continue }
        
        let topScore = best.score
        let ties = bestMatches.filter { abs($0.score - topScore) < 0.001 }
        
        if candidateNames[best.index] == "menti" {
            // It's a menti slide
            let code = extractMentiCode(trimmed)
            let normalized = "menti \(code)"
            let match = BlockMatch(
                originalName: trimmed,
                resolvedRelativePath: normalized, // Virtual path
                isFuzzy: baseLower != normalized.lowercased(),
                type: .menti(code: code),
                nestedDeck: nil
            )
            matches.append(match)
            continue
        }
        
        if ties.count > 1 {
            let matchedPaths = ties.compactMap { $0.index < candidates.count ? candidates[$0.index].path : nil }
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
            match.nestedDeck = try resolveBlocks(blocksURL: blocksURL, configURL: nestedURL, allFiles: allFiles, visitedURLs: newVisited)
        }
        
        matches.append(match)
    }
    
    return ResolvedDeck(url: configURL, matches: matches)
}

enum AssemblableBlock {
    case existingKeynote(URL)
    case menti(code: String)
}

func collectAssemblableBlocks(deck: ResolvedDeck, blocksURL: URL) -> [AssemblableBlock] {
    var blocks: [AssemblableBlock] = []
    for m in deck.matches {
        switch m.type {
        case .keynote:
            blocks.append(.existingKeynote(blocksURL.appendingPathComponent(m.resolvedRelativePath)))
        case .menti(let code):
            blocks.append(.menti(code: code))
        case .config:
            if let nested = m.nestedDeck {
                blocks.append(contentsOf: collectAssemblableBlocks(deck: nested, blocksURL: blocksURL))
            }
        }
    }
    return blocks
}

func extractMentiCode(_ s: String) -> String {
    let pattern = "(\\d[\\s-]*){8}"
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else {
        return ""
    }
    let codeWithNoise = String(s[Range(match.range, in: s)!])
    let digits = codeWithNoise.filter(\.isNumber)
    if digits.count == 8 {
        return "\(digits.prefix(4)) \(digits.suffix(4))"
    }
    return digits
}

func getAllInexactMatches(deck: ResolvedDeck) -> [String] {
    var result: [String] = []
    for m in deck.matches {
        if m.isFuzzy {
            let base = stripExtension(m.originalName)
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

func computeManifest(blocksURL: URL, deck: ResolvedDeck, mentiStatuses: [String: Bool]) -> [String: String] {
    var manifest: [String: String] = [:]
    manifest["CONFIG"] = fileFingerprint(url: deck.url)
    for m in deck.matches {
        switch m.type {
        case .keynote:
            let blockFile = blocksURL.appendingPathComponent(m.resolvedRelativePath)
            let fp = fileFingerprint(url: blockFile)
            if !fp.isEmpty {
                manifest["BLOCK:\(m.resolvedRelativePath)"] = fp
            }
        case .menti(let code):
            let status = mentiStatuses[code] ?? false
            manifest["BLOCK:menti:\(code)"] = status ? "VALID" : "INVALID"
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

func isStale(manifestDir: URL, outputsDir: URL, blocksURL: URL, deck: ResolvedDeck, mentiStatuses: [String: Bool]) -> Bool {
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

//////////////// Utils //////////////////

private func stripExtension(_ s: String) -> String {
    let lower = s.lowercased()
    if lower.hasSuffix(".key") || lower.hasSuffix(".txt") {
        return String(s.dropLast(4))
    }
    return s
}

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

func assembleDecks(toBuild: [String], deckDataDict: [String: DeckData], blocksURL: URL, outputsURL: URL, manifestURL: URL, mentiStatuses: [String: Bool]) async throws -> Int {
    var buildConfigs: [BuildInfo] = []
    var assembleAs = "tell application \"Keynote Creator Studio\"\n    activate\n"
    
    // We need the root URL to find Resources
    let rootURL = blocksURL.deletingLastPathComponent()
    
    for configName in toBuild {
        guard let deckData = deckDataDict[configName] else { continue }
        if !deckData.inexactMatches.isEmpty {
            try writeCorrectedConfigRecursive(deck: deckData.rootDeck, blocksURL: blocksURL)
        }
        
        let blocks = collectAssemblableBlocks(deck: deckData.rootDeck, blocksURL: blocksURL)
        if !blocks.isEmpty {
            var keynotePaths: [String] = []
            var inputPathsToAssemble: [URL] = []
            
            for block in blocks {
                switch block {
                case .existingKeynote(let url):
                    inputPathsToAssemble.append(url)
                    keynotePaths.append(url.path.replacingOccurrences(of: blocksURL.path + "/", with: ""))
                case .menti(let code):
                    if mentiStatuses[code] == true {
                        do {
                            let tempUrl = try await generateMentiSlide(code: code, rootURL: rootURL, outputURL: outputsURL)
                            inputPathsToAssemble.append(tempUrl)
                            // We don't add temp files to manifest paths as they change every time
                        } catch {
                            print("Warning: Failed to generate Menti slide for \(code): \(error)")
                        }
                    }
                }
            }
            
            if !inputPathsToAssemble.isEmpty {
                buildConfigs.append(BuildInfo(name: configName, url: deckData.url, keynotePaths: keynotePaths))
                
                let outputFile = outputsURL.appendingPathComponent("\(configName).key")
                let inputPathsAs = inputPathsToAssemble.map { asEscape($0.path) }
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
    }
    
    assembleAs += "end tell"
    
    if !buildConfigs.isEmpty {
        let _ = try await Task.detached(priority: .userInitiated) {
            try runApplescript(assembleAs)
        }.value

        for bc in buildConfigs {
            guard let deckData = deckDataDict[bc.name] else { continue }
            let newManifest = computeManifest(blocksURL: blocksURL, deck: deckData.rootDeck, mentiStatuses: mentiStatuses)
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
    
    return AppPaths(blocks: blocksDir, decks: decksDir, outputs: outputsDir, manifests: manifestsDir)
}

func scanDecks(paths: AppPaths, mentiStatuses: [String: Bool]) async -> ScanResult {
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

// MARK: - Menti Logic

func getMentimeterURL(code: String) async throws -> String {
    let digits = code.filter(\.isNumber)
    guard digits.count == 8 else { throw CoreError.mentiError("Invalid code: \(code)") }

    let apiURL = URL(string: "https://www.menti.com/core/audience/slide-deck/\(digits)/participation-key")!
    let (data, response) = try await URLSession.shared.data(for: URLRequest(url: apiURL))

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        throw CoreError.mentiError("Menti code not found or expired.")
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let key = json["participation_key"] as? String else {
        throw CoreError.mentiError("Invalid response from Menti.")
    }

    return "https://menti.com/\(key)"
}

func makeQRPNGData(for text: String, size: Int) throws -> Data {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"

    guard let raw = filter.outputImage else { throw CoreError.mentiError("QR generation failed.") }

    let scale = CGFloat(size) / raw.extent.width
    let scaled = raw.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

    let context = CIContext()
    guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
        throw CoreError.mentiError("QR generation failed.")
    }

    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw CoreError.mentiError("QR generation failed.")
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else { throw CoreError.mentiError("QR generation failed.") }

    return data as Data
}

func rebuildZip(templatePath: String, replacements: [String: Data], outputPath: String) throws {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("menti_assembly_\(ProcessInfo.processInfo.processIdentifier)_\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let unzip = Process()
    unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    unzip.arguments = ["-q", templatePath, "-d", tmp.path]
    try unzip.run()
    unzip.waitUntilExit()
    guard unzip.terminationStatus == 0 else {
        throw CoreError.mentiError("unzip failed with status \(unzip.terminationStatus) for \(templatePath)")
    }
    
    for (entry, data) in replacements {
        let dest = tmp.appendingPathComponent(entry)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: dest)
    }

    try? fm.removeItem(atPath: outputPath)

    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zip.currentDirectoryURL = tmp
    zip.arguments = ["-r", "-X", outputPath, "."]
    try zip.run()
    zip.waitUntilExit()
    guard zip.terminationStatus == 0 else {
        throw CoreError.mentiError("zip failed with status \(zip.terminationStatus) for \(outputPath)")
    }
}

func updateMentiText(in keyPath: String, url: String, codeLabel: String) throws {
    let script = """
        tell application "Keynote"
            set targetDoc to open POSIX file "\(asEscape(keyPath))"
            set sl to slide 1 of targetDoc
            set object text of text item 4 of sl to "\(asEscape(url))"
            set object text of text item 3 of sl to "\(asEscape(codeLabel))"
            save targetDoc
            close targetDoc saving yes
        end tell
        """
    _ = try runApplescript(script)
}

func generateMentiSlide(code: String, rootURL: URL, outputURL: URL) async throws -> URL {
    let resourcesURL = rootURL.appendingPathComponent("Resources")
    let resolvedURL = try await getMentimeterURL(code: code)
    let digits = code.filter(\.isNumber)
    let codeLabel = "Code: \(digits.prefix(4)) \(digits.suffix(4))"
    
    let templateURL = resourcesURL.appendingPathComponent("Menti Template.key")
    if !FileManager.default.fileExists(atPath: templateURL.path) {
        throw CoreError.mentiError("Menti Template not found at \(templateURL.path)")
    }
    let templatePath = templateURL.path
    let tempOutput = outputURL.deletingLastPathComponent().appendingPathComponent("menti_temp_\(digits).key").path
    
    try rebuildZip(
        templatePath: templatePath,
        replacements: [
            "Data/mentimeter_qr_code-9078.png": try makeQRPNGData(for: resolvedURL, size: 2000),
            "Data/mentimeter_qr_code-small-9079.png": try makeQRPNGData(for: resolvedURL, size: 256)
        ],
        outputPath: tempOutput
    )
    
    try updateMentiText(in: tempOutput, url: resolvedURL, codeLabel: codeLabel)
    return URL(fileURLWithPath: tempOutput)
}