import Foundation

public enum AssemblableBlock {
    case existingKeynote(URL)
    case menti(code: String)
    case pause(info: String)
}

public struct CacheableBlock {
    public let type: AssemblableBlock
    public let path: String
    public let fingerprint: String
}

public struct CacheChunk {
    public let blocks: [CacheableBlock]
    public let sourceURL: URL?
    public let sourceStartIndex: Int
    public let sourceTotalCount: Int
    public let blockCountsString: String
}

public enum CacheChunkPlanner {
    public static func findOptimalChunks(targetBlocks: [CacheableBlock], validOutputs: [(url: URL, manifest: OutputManifest)]) -> [CacheChunk] {
        var chunks: [CacheChunk] = []
        var i = 0
        let n = targetBlocks.count
        
        while i < n {
            var bestLength = 0
            var bestURL: URL? = nil
            var bestStartIndex = 0
            var bestCount = 0
            var bestCountString = ""
            
            for output in validOutputs {
                let cachedBlocks = output.manifest.cachedBlocks
                for j in 0..<cachedBlocks.count {
                    var currentLength = 0
                    var currentCount = 0
                    var currentCountString = ""
                    
                    while i + currentLength < n && j + currentLength < cachedBlocks.count {
                        let target = targetBlocks[i + currentLength]
                        if StringUtilities.filenameOnly(target.path).lowercased() == "agenda" { break }
                        
                        let cached = cachedBlocks[j + currentLength]
                        if target.path == cached.path && target.fingerprint == cached.blockFingerprint && cached.count > 0 {
                            currentLength += 1
                            currentCount += cached.count
                            currentCountString += "\(cached.count),"
                        } else {
                            break
                        }
                    }
                    if currentLength > bestLength {
                        bestLength = currentLength
                        bestURL = output.url
                        bestStartIndex = cachedBlocks[j].startIndex
                        bestCount = currentCount
                        bestCountString = currentCountString
                    }
                }
            }
            
            // Only aggregate if L > 1
            if bestLength > 1 {
                let slice = Array(targetBlocks[i..<i+bestLength])
                chunks.append(CacheChunk(blocks: slice, sourceURL: bestURL, sourceStartIndex: bestStartIndex, sourceTotalCount: bestCount, blockCountsString: bestCountString))
                i += bestLength
            } else {
                let slice = [targetBlocks[i]]
                chunks.append(CacheChunk(blocks: slice, sourceURL: nil, sourceStartIndex: 0, sourceTotalCount: 0, blockCountsString: ""))
                i += 1
            }
        }
        return chunks
    }
    
    public static func collectAssemblableBlocks(deck: ResolvedDeck, blocksURL: URL, mentiStatuses: [String: Bool]) -> [CacheableBlock] {
        var blocks: [CacheableBlock] = []
        for m in deck.matches {
            switch m.type {
            case .keynote:
                let blockFile = blocksURL.appendingPathComponent(m.resolvedRelativePath)
                let fp = FileUtilities.fileFingerprint(url: blockFile)
                blocks.append(CacheableBlock(type: .existingKeynote(blockFile), path: m.resolvedRelativePath, fingerprint: fp))
            case .menti(let code):
                let status = mentiStatuses[code] ?? false
                let fp = status ? "VALID" : "INVALID"
                blocks.append(CacheableBlock(type: .menti(code: code), path: "menti:\(code)", fingerprint: fp))
            case .pause(let info):
                blocks.append(CacheableBlock(type: .pause(info: info), path: "pause:\(info)", fingerprint: "PRESENT"))
            case .config:
                if let nested = m.nestedDeck {
                    blocks.append(contentsOf: collectAssemblableBlocks(deck: nested, blocksURL: blocksURL, mentiStatuses: mentiStatuses))
                }
            }
        }
        return blocks
    }
}
