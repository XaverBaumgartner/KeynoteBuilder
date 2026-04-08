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
        let escapedText = StringUtilities.asEscape(displayText)
        
        return """
                -- Insert Pause: \(info)
                set sourceDoc to open POSIX file "\(escapedTemplate)"
                set sl to slide 1 of sourceDoc
                
                set found to false
                repeat with ti in (text items of sl)
                    if (object text of ti) contains "Minuten" or (object text of ti) contains "XX" then
                        set object text of ti to "\(escapedText)"
                        set found to true
                        exit repeat
                    end if
                end repeat
                
                if not found and (count of text items of sl) > 0 then
                    set object text of text item 1 of sl to "\(escapedText)"
                end if
                
                move slide 1 of sourceDoc to end of slides of targetDoc
                close sourceDoc saving no
        """
    }
}
