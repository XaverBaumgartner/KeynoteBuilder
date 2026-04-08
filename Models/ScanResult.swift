import Foundation

/// The result of scanning the decks directory.
public struct ScanResult {
    /// List of names for decks that need to be rebuilt.
    public let staleNames: [String]
    
    /// List of names for decks that are currently up-to-date.
    public let freshNames: [String]
    
    /// A dictionary mapping deck names to their resolved data.
    public let deckDataDict: [String: DeckData]
    
    /// An error message if the scan failed.
    public let error: String?
    
    /// Initializes a new `ScanResult`.
    /// - Parameters:
    ///   - staleNames: Stale decks.
    ///   - freshNames: Fresh decks.
    ///   - deckDataDict: Map of deck names to data.
    ///   - error: Optional error message.
    public init(staleNames: [String], freshNames: [String], deckDataDict: [String: DeckData], error: String? = nil) {
        self.staleNames = staleNames
        self.freshNames = freshNames
        self.deckDataDict = deckDataDict
        self.error = error
    }
}
