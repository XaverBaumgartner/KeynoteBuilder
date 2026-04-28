import Foundation

/// Contains a root deck and meta-information for top-level reporting.
public struct DeckData: Codable {
    /// The source URL of the configuration file.
    public let url: URL
    
    /// The root resolved deck which may contain nested decks.
    public let rootDeck: ResolvedDeck
    
    /// A list of humans-readable descriptions of any inexact (fuzzy) matches found.
    public let inexactMatches: [String]
    
    /// The last modification date of the configuration file.
    public let modifiedDate: Date
    
    /// Initializes a new `DeckData`.
    /// - Parameters:
    ///   - url: The configuration file URL.
    ///   - rootDeck: The resolved root deck.
    ///   - inexactMatches: List of fuzzy match descriptions.
    ///   - modifiedDate: The modification date of the config.
    public init(url: URL, rootDeck: ResolvedDeck, inexactMatches: [String], modifiedDate: Date) {
        self.url = url
        self.rootDeck = rootDeck
        self.inexactMatches = inexactMatches
        self.modifiedDate = modifiedDate
    }
}
