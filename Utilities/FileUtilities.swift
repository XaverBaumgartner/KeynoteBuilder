import Foundation

/// A collection of utility functions for file system operations.
public enum FileUtilities {
    /// Computes a fingerprint for a file based on its modification date and size.
    /// - Parameter url: The URL of the file to fingerprint.
    /// - Returns: A string representing the fingerprint, or an empty string if the file is unreadable.
    static func fileFingerprint(url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mtime = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber else {
            return ""
        }
        return "\(Int(mtime.timeIntervalSince1970))-\(size.intValue)"
    }
    
    /// Discovers the standard application paths relative to the executable or the current directory.
    /// - Returns: An `AppPaths` object containing the discovered URLs.
    static func discoverPaths() -> AppPaths {
        let fm = FileManager.default
        let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        var rootURL = executableURL.deletingLastPathComponent()
        
        let rootPath = rootURL.path
        // Handle running within an app bundle or from the command line/Xcode.
        if rootPath.hasSuffix("Contents/MacOS") || rootPath.hasSuffix("Contents/Resources") {
            rootURL = rootURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        } else {
            rootURL = URL(fileURLWithPath: fm.currentDirectoryPath)
        }
        
        let blocksDir = rootURL.appendingPathComponent("blocks")
        let decksDir = rootURL.appendingPathComponent("decks")
        let outputsDir = rootURL.appendingPathComponent("outputs")
        let manifestsDir = outputsDir.appendingPathComponent(".manifests")
        
        return AppPaths(blocks: blocksDir, decks: decksDir, outputs: outputsDir, manifests: manifestsDir)
    }
}
