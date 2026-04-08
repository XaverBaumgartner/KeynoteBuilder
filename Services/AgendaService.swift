import Foundation
import AppKit

/// Provides services for generating dynamic Agenda slides.
public enum AgendaService {
    
    /// Generates the agenda text as a numbered list from the top-level deck matches.
    /// - Parameter deck: The root deck.
    /// - Returns: A formatted agenda string.
    public static func generateAgendaString(from deck: ResolvedDeck) -> String {
        let excludedNames = ["willkommen", "schluss", "agenda"]
        var agendaItems: [String] = []
        
        for match in deck.matches {
            let baseName = match.displayName
            
            // Check if it should be excluded
            if !excludedNames.contains(baseName.lowercased()) {
                agendaItems.append(baseName)
            }
        }
        
        // Format as a simple newline-separated list
        var result = ""
        for item in agendaItems {
            result += "\(item)\n"
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Generates the AppleScript snippet to handle an in-place Agenda slide modification.
    /// - Parameters:
    ///   - agendaText: The numbered list text.
    ///   - templateURL: The URL of the Agenda.key block.
    /// - Returns: An AppleScript string.
    public static func getAgendaAssemblyScript(agendaText: String, templateURL: URL) -> String {
        let escapedTemplate = StringUtilities.asEscape(templateURL.path)
        let escapedText = StringUtilities.asEscape(agendaText)
        
        return """
                -- Insert Agenda
                set sourceDoc to open POSIX file "\(escapedTemplate)"
                set sl to slide 1 of sourceDoc
                
                set found to false
                repeat with ti in (text items of sl)
                    if (object text of ti) contains "XX" then
                        set object text of ti to "\(escapedText)"
                        set found to true
                        exit repeat
                    end if
                end repeat
                
                if not found and (count of text items of sl) > 0 then
                    -- Fallback to the first text item if the placeholder is not found
                    set object text of text item 1 of sl to "\(escapedText)"
                end if
                
                move slide 1 of sourceDoc to end of slides of targetDoc
                close sourceDoc saving no
        """
    }
}
