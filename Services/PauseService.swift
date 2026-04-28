import Foundation
import AppKit

/// Provides services for generating Pause slides with custom duration or time.
public enum PauseService {
    
    /// Generates the AppleScript snippet to handle an in-place Pause slide modification.
    /// - Parameters:
    ///   - info: The duration or time info (e.g., "15" or "12:34").
    ///   - templateURL: The URL of the Pause.key template.
    /// - Returns: An AppleScript string.
    public static func getPauseAssemblyScript(info: String, templateURL: URL) -> String {
        // Format the display text using the centralized formatter
        let displayText = StringUtilities.formatPauseDisplay(info)
        
        let escapedTemplate = StringUtilities.asEscape(templateURL.path)
        let replacementScript = AppleScriptUtilities.replaceTextInSlideScript(
            replacements: [("Minuten", displayText), ("XX", displayText)],
            applyFallbackToItem1: true
        )
        
        return """
                -- Insert Pause: \(info)
                set sourceDoc to open POSIX file "\(escapedTemplate)"
                set sl to slide 1 of sourceDoc
                \(replacementScript)
                move slide 1 of sourceDoc to end of slides of targetDoc
                close sourceDoc saving no
        """
    }
}
