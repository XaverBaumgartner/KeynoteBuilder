import Foundation

/// Represents a configuration file where all block references have been resolved.
public struct ResolvedDeck: Codable, Hashable {
    /// The URL of the configuration file this deck represents.
    public let url: URL
    
    /// A list of matches found within the configuration file.
    public let matches: [BlockMatch]
    
    /// Initializes a new `ResolvedDeck`.
    /// - Parameters:
    ///   - url: The configuration file URL.
    ///   - matches: The list of resolved block matches.
    public init(url: URL, matches: [BlockMatch]) {
        self.url = url
        self.matches = matches
    }
}
