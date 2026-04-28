import Foundation

/// Represents the contents of a compiled output Keynote presentation.
public struct OutputManifest: Codable {
    public let deckName: String
    
    /// The fingerprint (mtime-size) of the output Keynote file at the time of assembly.
    public let outputFingerprint: String
    
    public let totalSlides: Int
    
    public let assembledAt: Date
    
    /// A flat list of blocks mapped to their location in the presentation.
    public let cachedBlocks: [CacheEntry]
    
    public init(deckName: String, outputFingerprint: String, totalSlides: Int, assembledAt: Date = Date(), cachedBlocks: [CacheEntry]) {
        self.deckName = deckName
        self.outputFingerprint = outputFingerprint
        self.totalSlides = totalSlides
        self.assembledAt = assembledAt
        self.cachedBlocks = cachedBlocks
    }
}

/// A single cacheable block's entry.
public struct CacheEntry: Codable {
    public let path: String
    public let blockFingerprint: String
    public let startIndex: Int
    public let count: Int
    
    public init(path: String, blockFingerprint: String, startIndex: Int, count: Int) {
        self.path = path
        self.blockFingerprint = blockFingerprint
        self.startIndex = startIndex
        self.count = count
    }
}

/// Where a cached block can be found in a compiled Keynote file.
public struct CacheLocation {
    public let file: URL
    public let startIndex: Int
    public let count: Int
    
    public init(file: URL, startIndex: Int, count: Int) {
        self.file = file
        self.startIndex = startIndex
        self.count = count
    }
}
