import Foundation

/// Defines the file URLs for key directories used by the application.
public struct AppPaths {
    /// URL for the "blocks" directory.
    public let blocks: URL
    
    /// URL for the "decks" directory.
    public let decks: URL
    
    /// URL for the "outputs" directory.
    public let outputs: URL
    
    /// URL where the deck manifests are stored (decks/.manifests).
    public let deckManifests: URL
    
    /// URL where the output cache manifests are stored (outputs/.manifests).
    public let outputManifests: URL
    
    /// Initializes a new `AppPaths`.
    public init(blocks: URL, decks: URL, outputs: URL, deckManifests: URL, outputManifests: URL) {
        self.blocks = blocks
        self.decks = decks
        self.outputs = outputs
        self.deckManifests = deckManifests
        self.outputManifests = outputManifests
    }
}
