import Foundation
import CryptoKit

/// A collection of utility functions for file system operations.
public enum FileUtilities {
    /// Computes a fingerprint for a file.
    /// For .txt files, it uses the SHA-256 hash of the content.
    /// For other files (like .key packages), it uses the modification date and size.
    /// - Parameter url: The URL of the file to fingerprint.
    /// - Returns: A string representing the fingerprint, or an empty string if the file is unreadable.
    /// Computes a SHA-256 fingerprint for a given string.
    public static func stringFingerprint(_ text: String) -> String {
        let data = Data(text.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    static func fileFingerprint(url: URL) -> String {
        let path = url.path
        let ext = url.pathExtension.lowercased()
        
        if ext == "txt" {
            // For text files, use content hashing for robustness against simple "saves"
            if let data = try? Data(contentsOf: url) {
                let hashed = SHA256.hash(data: data)
                return hashed.compactMap { String(format: "%02x", $0) }.joined()
            }
        }
        
        // Fallback for .key files and others: mtime + size
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
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
        let outputsCacheDir = outputsDir.appendingPathComponent(".cache")
        let deckManifestsDir = decksDir.appendingPathComponent(".manifests")
        let outputManifestsDir = outputsDir.appendingPathComponent(".manifests")
        
        return AppPaths(blocks: blocksDir, decks: decksDir, outputs: outputsDir, outputsCache: outputsCacheDir, deckManifests: deckManifestsDir, outputManifests: outputManifestsDir)
    }
}
