import Foundation

/// A collection of utility functions for string manipulation and extraction.
public enum StringUtilities {
    /// Extensions that the application recognizes and handles.
    static let extensions = [".key", ".txt"]
    
    /// Removes the file extension from a string if it's in the allowed list.
    /// - Parameter s: The string to modify.
    /// - Returns: The string without the file extension.
    static func stripExtension(_ s: String) -> String {
        let lower = s.lowercased()
        for ext in extensions {
            if lower.hasSuffix(ext) {
                return String(s.dropLast(ext.count))
            }
        }
        return s
    }
    
    /// Extracts the filename from a path and strips recognized extensions.
    /// - Parameter path: The full or relative file path.
    /// - Returns: The clean filename.
    static func filenameOnly(_ path: String) -> String {
        let fileName = (path as NSString).lastPathComponent
        return stripExtension(fileName)
    }
    
    /// Escapes special characters for use in AppleScript strings.
    /// - Parameter s: The string to escape.
    /// - Returns: The escaped string.
    static func asEscape(_ s: String) -> String {
        return s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
    }
    
    /// Extracts an 8-digit Menti code from a string.
    /// - Parameter s: The string to search.
    /// - Returns: A formatted 8-digit code (e.g. "1234 5678") if found, otherwise the digits only.
    static func extractMentiCode(_ s: String) -> String {
        if let match = firstMatch("(\\d[\\s-]*){8}", in: s), match.count > 0 {
            let codeWithNoise = match[0]
            let digits = codeWithNoise.filter(\.isNumber)
            if digits.count == 8 {
                return "\(digits.prefix(4)) \(digits.suffix(4))"
            }
            return digits
        }
        return ""
    }
    
    /// Extracts pause information (duration or specific time) from a string.
    /// - Parameter s: The string to search.
    /// - Returns: The extracted info (e.g., "15" or "12:34").
    static func extractPauseInfo(_ s: String) -> String {
        let normalized = s.lowercased()
        
        // 0. "Minuten" super-word (High Priority)
        if let minRange = normalized.range(of: "minuten") {
            let beforeMin = String(s[..<minRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            // Match a time-like pattern (1:30) or a simple number (15)
            if let match = firstMatch("(\\d{1,2}[\\:;\\.,](\\d{2})|\\d+(?:[\\.,]\\d+)?)\\s*$", in: beforeMin), match.count >= 2 {
                let val = match[1]
                // If it looks like a time but has "Minuten", return it with the suffix 
                // to prevent formatPauseDisplay from adding "bis "
                if val.contains(":") || val.contains(".") || val.contains(",") || val.contains(";") {
                    return "\(val) Minuten"
                }
                return val
            }
        }
        
        // 1. Explicit duration units (h, std, stunden)
        if let match = firstMatch("(\\d+(?:[\\.,]\\d+)?)\\s*(?:h|std|stunden)", in: normalized), match.count > 1 {
            let numString = match[1].replacingOccurrences(of: ",", with: ".")
            if let val = Double(numString) {
                return "\(Int(round(val * 60)))"
            }
        }

        // 2. Determine search range for time (prioritize after "bis")
        var timeSearchString = s
        if let bisRange = normalized.range(of: "bis") {
            timeSearchString = String(s[bisRange.upperBound...])
        }
        
        // 3. Time delimiters (:, ;, ., ,) with range validation
        if let match = firstMatch("(\\d{1,2})[\\:;\\.,](\\d{2})", in: timeSearchString), match.count == 3 {
            let h = Int(match[1]) ?? 0
            let m = Int(match[2]) ?? 0
            if h < 24 && m < 60 {
                return String(format: "%02d:%02d", h, m)
            }
        }
        
        // 4. "Uhr" support (e.g. "12 Uhr" or "12:30 Uhr")
        if let uhrRange = normalized.range(of: "uhr") {
            let beforeUhr = String(s[..<uhrRange.lowerBound])
            if let match = firstMatch("(\\d{1,2})(?:[\\:;\\.,](\\d{2}))?\\s*$", in: beforeUhr.trimmingCharacters(in: .whitespaces)), match.count >= 2 {
                let h = Int(match[1]) ?? 0
                let m = (match.count > 2 && !match[2].isEmpty) ? (Int(match[2]) ?? 0) : 0
                if h < 24 && m < 60 {
                    return String(format: "%02d:%02d", h, m)
                }
            }
        }

        // 5. "bis" followed by digits (including HH MM)
        if normalized.contains("bis") {
            // Try HH MM pattern first (e.g. "bis 12 30")
            if let match = firstMatch("bis\\s*(\\d{1,2})\\s+(\\d{2})", in: normalized), match.count == 3 {
                let h = Int(match[1]) ?? 0
                let m = Int(match[2]) ?? 0
                if h < 24 && m < 60 {
                    return String(format: "%02d:%02d", h, m)
                }
            }
            
            if let match = firstMatch("\\d+", in: timeSearchString), match.count > 0 {
                let digits = match[0]
                if digits.count <= 2 {
                    return "\(digits):00"
                } else if digits.count == 4 {
                    let h = Int(digits.prefix(2)) ?? 0
                    let m = Int(digits.suffix(2)) ?? 0
                    if h < 24 && m < 60 {
                        return String(format: "%02d:%02d", h, m)
                    }
                }
            }
        }

        // 6. 4-digit military time fallback
        if let match = firstMatch("\\b(\\d{2})(\\d{2})\\b", in: s), match.count == 3 {
            let h = Int(match[1]) ?? 0
            let m = Int(match[2]) ?? 0
            if h < 24 && m < 60 {
                return "\(match[1]):\(match[2])"
            }
        }
        
        // 7. Default to duration if it's a number
        if let match = firstMatch("\\d+", in: s), match.count > 0 {
            let digits = match[0]
            // If 3-4 digits, try to interpret as military time
            if let val = Int(digits), digits.count >= 3 && digits.count <= 4 {
                let h = val / 100
                let m = val % 100
                if h < 24 && m < 60 {
                    return String(format: "%02d:%02d", h, m)
                }
            }
            return digits
        }
        
        return ""
    }
    
    // Helper function for regex extraction
    private static func firstMatch(_ pattern: String, in s: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else {
            return nil
        }
        var groups: [String] = []
        for i in 0..<match.numberOfRanges {
            let nsRange = match.range(at: i)
            if nsRange.location != NSNotFound, let range = Range(nsRange, in: s) {
                groups.append(String(s[range]))
            } else {
                groups.append("") 
            }
        }
        return groups
    }
    
    /// Formats the display label for a Pause slide.
    /// - Parameter info: The extracted info ("15" or "12:34").
    /// - Returns: A formatted string ("15 Minuten" or "bis 12:34").
    static func formatPauseDisplay(_ info: String) -> String {
        if info.isEmpty {
            return "Bis gleich!"
        }
        // If it already has the suffix, it's a duration-with-delimiter (e.g. "1:30 Minuten")
        if info.hasSuffix(" Minuten") {
            return info
        }
        if info.contains(":") {
            return "bis \(info)"
        } else {
            return "\(info) Minuten"
        }
    }
}
