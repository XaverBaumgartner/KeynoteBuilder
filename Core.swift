import Foundation

enum CoreError: Error, LocalizedError {
    case fileNotFound(URL)
    case unreadableConfig(URL)
    case writeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.path)"
        case .unreadableConfig(let url):
            return "Could not read config file: \(url.path)"
        case .writeFailed(let url):
            return "Could not write to file: \(url.path)"
        }
    }
}

func resolveBlocks(blocksURL: URL, configURL: URL) throws -> (matchedNames: [String], inexactMatches: [String]) {
    guard let fileContents = try? String(contentsOf: configURL, encoding: .utf8) else {
        throw CoreError.unreadableConfig(configURL)
    }
    
    let fm = FileManager.default
    guard let blockFilesAll = try? fm.contentsOfDirectory(atPath: blocksURL.path) else {
        throw CoreError.fileNotFound(blocksURL)
    }
    
    let blockFiles = blockFilesAll.filter { $0.lowercased().hasSuffix(".key") }
        .map { String($0.dropLast(4)) }
    let filesLower = blockFiles.map { $0.lowercased() }
    
    let lines = fileContents.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    
    var matchedNames: [String] = []
    var inexactMatches: [String] = []
    
    for rawName in lines {
        let trimmed = rawName.trimmingCharacters(in: .whitespaces)
        var base = trimmed
        if base.lowercased().hasSuffix(".key") {
            base = String(base.dropLast(4))
        }
        let baseLower = base.lowercased()
        
        var bestIdx: Int? = nil
        var bestScore = -1.0
        
        for i in 0..<blockFiles.count {
            let score = jaroWinkler(baseLower, filesLower[i])
            if score > bestScore {
                bestScore = score
                bestIdx = i
            }
        }
        
        guard let bestIndex = bestIdx else { continue }
        
        let matchedBase = blockFiles[bestIndex]
        if base != matchedBase {
            inexactMatches.append("'\(base)' -> '\(matchedBase)'")
        }
        matchedNames.append(matchedBase)
    }
    
    return (matchedNames, inexactMatches)
}

func writeCorrectedConfig(configURL: URL, matchedNames: [String]) throws {
    let content = matchedNames.joined(separator: "\n") + "\n"
    do {
        try content.write(to: configURL, atomically: true, encoding: .utf8)
    } catch {
        throw CoreError.writeFailed(configURL)
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

func computeManifest(blocksURL: URL, configURL: URL, matchedNames: [String]) -> [String: String] {
    var manifest: [String: String] = [:]
    manifest["CONFIG"] = fileFingerprint(url: configURL)
    for name in matchedNames {
        let blockFile = blocksURL.appendingPathComponent("\(name).key")
        let fp = fileFingerprint(url: blockFile)
        if !fp.isEmpty {
            manifest["BLOCK:\(name)"] = fp
        }
    }
    return manifest
}

func isStale(manifestDir: URL, outputsDir: URL, blocksURL: URL, configURL: URL, matchedNames: [String]) -> Bool {
    let murl = buildManifestURL(manifestDir: manifestDir, configURL: configURL)
    if !FileManager.default.fileExists(atPath: murl.path) { return true }
    
    let configName = configURL.deletingPathExtension().lastPathComponent
    let finalKeyURL = outputsDir.appendingPathComponent("\(configName).key")
    if !FileManager.default.fileExists(atPath: finalKeyURL.path) { return true }
    
    let oldManifest = readManifest(url: murl)
    let currentManifest = computeManifest(blocksURL: blocksURL, configURL: configURL, matchedNames: matchedNames)
    
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