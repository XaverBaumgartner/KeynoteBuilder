import Foundation

/// Provides generic AppleScript generation utilities for Keynote manipulation.
public enum AppleScriptUtilities {
    
    /// Generates an AppleScript snippet that loops through text items of a slide variable (which must be named `sl` in AppleScript)
    /// and replaces the text of items that contain the specified placeholders.
    /// - Parameters:
    ///   - replacements: A dictionary where the key is the string to search for (e.g. "XX"),
    ///                   and the value is the text that should replace the entire text item.
    ///   - applyFallbackToItem1: If true and no match is found for the first replacement, it falls back to replacing text item 1.
    /// - Returns: AppleScript string snippet.
    public static func replaceTextInSlideScript(replacements: [(placeholder: String, replacement: String)], applyFallbackToItem1: Bool = false) -> String {
        var script = ""
        
        for (i, pair) in replacements.enumerated() {
            let escapedPlaceholder = StringUtilities.asEscape(pair.placeholder)
            let escapedReplacement = StringUtilities.asEscape(pair.replacement)
            
            script += """
                    set found_\(i) to false
                    repeat with ti in (text items of sl)
                        if (object text of ti) contains "\(escapedPlaceholder)" then
                            set object text of ti to "\(escapedReplacement)"
                            set found_\(i) to true
                            exit repeat
                        end if
                    end repeat
                    
            """
            
            if applyFallbackToItem1 && i == 0 {
                script += """
                        if not found_\(i) and (count of text items of sl) > 0 then
                            set object text of text item 1 of sl to "\(escapedReplacement)"
                        end if
                        
                """
            }
        }
        
        return script
    }
}
