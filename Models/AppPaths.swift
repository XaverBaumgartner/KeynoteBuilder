import Foundation

/// Defines the file URLs for key directories used by the application.
public struct AppPaths {
    /// URL for the "blocks" directory.
    public let blocks: URL
    
    /// URL for the "decks" directory.
    public let decks: URL
    
    /// URL for the "outputs" directory.
    public let outputs: URL
    
    /// URL where the build manifests are stored.
    public let manifests: URL
    
    /// Initializes a new `AppPaths`.
    public init(blocks: URL, decks: URL, outputs: URL, manifests: URL) {
        self.blocks = blocks
        self.decks = decks
        self.outputs = outputs
        self.manifests = manifests
    }
}
