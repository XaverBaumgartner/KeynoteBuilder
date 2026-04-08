import Foundation

/// Defines errors that can occur during deck resolution and assembly.
public enum CoreError: Error, LocalizedError {
    /// The configuration file could not be read.
    case unreadableConfig(URL)
    /// Writing to a file failed.
    case writeFailed(URL)
    /// A circular reference was detected in the configuration.
    case circularReference(URL)
    /// Multiple files matched the same name.
    case ambiguousReference(String, [String])
    /// An error related to Mentimeter integration.
    case mentiError(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableConfig(let url):
            return "Could not read config file: \(url.path)"
        case .writeFailed(let url):
            return "Could not write to file: \(url.path)"
        case .circularReference(let url):
            return "Circular reference detected in config: \(url.lastPathComponent)"
        case .ambiguousReference(let name, let matches):
            return "Ambiguous reference for '\(name)': matches both \(matches.joined(separator: " and "))."
        case .mentiError(let msg):
            return "Menti Error: \(msg)"
        }
    }
}
