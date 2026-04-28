import Foundation

/// Represents the state of a parsed deck configuration, using a Merkle-tree root hash
/// to determine if any of its dependencies or structure have changed.
public struct DeckManifest: Codable {
    public let configPath: String
    
    /// Fingerprint of the raw .txt configuration file.
    public var txtFingerprint: String
    
    /// The root hash of the resolved structure tree (Merkle root).
    public let resolvedStructureHash: String
    
    public let lastCheckedAt: Date
    
    public init(configPath: String, txtFingerprint: String, resolvedStructureHash: String, lastCheckedAt: Date = Date()) {
        self.configPath = configPath
        self.txtFingerprint = txtFingerprint
        self.resolvedStructureHash = resolvedStructureHash
        self.lastCheckedAt = lastCheckedAt
    }
}
