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
            var baseName = match.displayName
            
            // Strip info for special types in the agenda
            switch match.type {
            case .menti:
                baseName = "Menti"
            case .pause:
                baseName = "Pause"
            default:
                break
            }
            
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
        let replacementScript = AppleScriptUtilities.replaceTextInSlideScript(
            replacements: [("XX", agendaText)],
            applyFallbackToItem1: true
        )
        
        return """
                -- Insert Agenda
                set sourceDoc to open POSIX file "\(escapedTemplate)"
                set sl to slide 1 of sourceDoc
                \(replacementScript)
                move slide 1 of sourceDoc to end of slides of targetDoc
                close sourceDoc saving no
        """
    }
}
