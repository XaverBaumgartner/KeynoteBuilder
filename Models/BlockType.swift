import Foundation

/// Defines the possible types of blocks that can be matched.
public enum BlockType: Codable, Hashable {
    /// A Keynote file.
    case keynote
    /// A nested configuration file (.txt).
    case config
    /// A Menti slide identified by its code.
    case menti(code: String)
    /// A Pause slide with duration or time information.
    case pause(info: String)
    
    /// Returns a string representation of the block type.
    public var rawValue: String {
        switch self {
        case .keynote: return "keynote"
        case .config: return "config"
        case .menti(let code): return "menti:\(code)"
        case .pause(let info): return "pause:\(info)"
        }
    }
    
    /// Returns the parameters for a service block to be appended to the filename in config files.
    public var parameterString: String? {
        switch self {
        case .menti(let code): return code
        case .pause(let info): return info
        default: return nil
        }
    }
    
    /// Returns the canonical line representation for a block (e.g. "Pause 15 Minuten").
    /// - Parameter baseName: The filename or service keyword.
    /// - Returns: The full canonical line.
    public func canonicalLine(baseName: String) -> String {
        switch self {
        case .menti(let code):
            return "\(baseName) \(code)"
        case .pause(let info):
            return "\(baseName) \(StringUtilities.formatPauseDisplay(info))"
        default:
            return baseName
        }
    }
}
