import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import ImageIO

/// Provides services for generating Mentimeter-integrated Keynote slides.
public enum MentiService {
    
    /// Fetches the Mentimeter audience URL for a given code.
    /// - Parameter code: The 8-digit Menti code.
    /// - Returns: The full participation URL.
    /// - Throws: `CoreError.mentiError`.
    public static func getMentimeterURL(code: String) async throws -> String {
        let digits = code.filter(\.isNumber)
        guard digits.count == 8 else { throw CoreError.mentiError("Invalid code: \(code)") }

        let apiURL = URL(string: "https://www.menti.com/core/audience/slide-deck/\(digits)/participation-key")!
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: apiURL))

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CoreError.mentiError("Menti code not found or expired.")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["participation_key"] as? String else {
            throw CoreError.mentiError("Invalid response from Menti.")
        }

        return "https://menti.com/\(key)"
    }
    
    /// Generates a QR code image as PNG data.
    /// - Parameters:
    ///   - text: The URL or text to encode.
    ///   - size: The target pixel size (square).
    /// - Returns: The PNG encoded data.
    /// - Throws: `CoreError.mentiError`.
    public static func makeQRPNGData(for text: String, size: Int) throws -> Data {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        guard let raw = filter.outputImage else { throw CoreError.mentiError("QR generation failed.") }

        let scale = CGFloat(size) / raw.extent.width
        let scaled = raw.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            throw CoreError.mentiError("QR generation failed.")
        }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CoreError.mentiError("QR generation failed.")
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { throw CoreError.mentiError("QR generation failed.") }

        return data as Data
    }
    
    /// Generates a temporary Keynote slide for a Menti code by modifying a template.
    /// - Parameters:
    ///   - code: The Menti code.
    ///   - blocksURL: The URL of the blocks directory.
    ///   - outputURL: The destination outputs folder.
    /// - Returns: The URL of the generated Keynote file.
    public static func generateMentiSlide(code: String, blocksURL: URL, outputURL: URL) async throws -> URL {
        let resolvedURL = try await getMentimeterURL(code: code)
        let digits = code.filter(\.isNumber)
        let codeLabel = "Code: \(digits.prefix(4)) \(digits.suffix(4))"
        
        let templateURL = blocksURL.appendingPathComponent("Menti.key")
        if !FileManager.default.fileExists(atPath: templateURL.path) {
            throw CoreError.mentiError("Menti Template not found at \(templateURL.path)")
        }
        
        let tempOutput = outputURL.deletingLastPathComponent().appendingPathComponent("menti_temp_\(digits).key").path
        
        try rebuildZip(
            templatePath: templateURL.path,
            replacements: [
                "Data/mentimeter_qr_code-9078.png": try makeQRPNGData(for: resolvedURL, size: 2000),
                "Data/mentimeter_qr_code-small-9079.png": try makeQRPNGData(for: resolvedURL, size: 256)
            ],
            outputPath: tempOutput
        )
        
        try updateMentiText(in: tempOutput, url: resolvedURL, codeLabel: codeLabel)
        return URL(fileURLWithPath: tempOutput)
    }
    
    /// Replaces specific files within a zipped (Keynote) bundle.
    private static func rebuildZip(templatePath: String, replacements: [String: Data], outputPath: String) throws {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("menti_assembly_\(ProcessInfo.processInfo.processIdentifier)_\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", templatePath, "-d", tmp.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            throw CoreError.mentiError("unzip failed with status \(unzip.terminationStatus) for \(templatePath)")
        }
        
        for (entry, data) in replacements {
            let dest = tmp.appendingPathComponent(entry)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: dest)
        }

        try? fm.removeItem(atPath: outputPath)

        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = tmp
        zip.arguments = ["-r", "-X", outputPath, "."]
        try zip.run()
        zip.waitUntilExit()
        guard zip.terminationStatus == 0 else {
            throw CoreError.mentiError("zip failed with status \(zip.terminationStatus) for \(outputPath)")
        }
    }
    
    /// Updates the text items in the generated Keynote slide via AppleScript.
    private static func updateMentiText(in keyPath: String, url: String, codeLabel: String) throws {
        let script = """
            tell application "Keynote"
                set targetDoc to open POSIX file "\(StringUtilities.asEscape(keyPath))"
                set sl to slide 1 of targetDoc
                -- Text items 3 and 4 match the template's structure.
                set object text of text item 4 of sl to "\(StringUtilities.asEscape(url))"
                set object text of text item 3 of sl to "\(StringUtilities.asEscape(codeLabel))"
                save targetDoc
                close targetDoc saving yes
            end tell
            """
        _ = try KeynoteService.runApplescript(script)
    }
}
