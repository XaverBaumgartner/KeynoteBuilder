import Foundation

/// Represents a match found for a block in a configuration file.
public struct BlockMatch: Identifiable, Codable, Hashable {
    /// Unique identifier for the match.
    public var id = UUID()
    
    /// The original name as written in the configuration file.
    public let originalName: String
    
    /// The resolved relative path to the matching file or resource.
    public let resolvedRelativePath: String
    
    /// Indicates whether the match was found using fuzzy matching.
    public let isFuzzy: Bool
    
    /// The type of block that was matched.
    public let type: BlockType
    
    /// If the block is a nested configuration, this contains the resolved deck data.
    public var nestedDeck: ResolvedDeck?
    
    /// The canonical line to write back to the configuration file for corrections.
    public var correctionLine: String {
        switch type {
        case .menti, .pause:
            let base = StringUtilities.stripExtension(resolvedRelativePath)
            return type.canonicalLine(baseName: base)
        default:
            return resolvedRelativePath
        }
    }
    
    /// A friendly name for display in the UI and services (e.g. Agenda).
    public var displayName: String {
        switch type {
        case .keynote, .config:
            return StringUtilities.filenameOnly(resolvedRelativePath)
        case .menti(let code):
            return "Menti \(code)"
        case .pause(let info):
            return "Pause \(StringUtilities.formatPauseDisplay(info))"
        }
    }
    
    /// Initializes a new `BlockMatch`.
    /// - Parameters:
    ///   - originalName: The original name from the config.
    ///   - resolvedRelativePath: The resolved path.
    ///   - isFuzzy: Whether it's a fuzzy match.
    ///   - type: The type of block.
    ///   - nestedDeck: Optional nested deck.
    public init(originalName: String, resolvedRelativePath: String, isFuzzy: Bool, type: BlockType, nestedDeck: ResolvedDeck? = nil) {
        self.originalName = originalName
        self.resolvedRelativePath = resolvedRelativePath
        self.isFuzzy = isFuzzy
        self.type = type
        self.nestedDeck = nestedDeck
    }
}
