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
        let pattern = "(\\d[\\s-]*){8}"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else {
            return ""
        }
        let codeWithNoise = String(s[Range(match.range, in: s)!])
        let digits = codeWithNoise.filter(\.isNumber)
        if digits.count == 8 {
            return "\(digits.prefix(4)) \(digits.suffix(4))"
        }
        return digits
    }
    /// Extracts pause information (duration or specific time) from a string.
    /// - Parameter s: The string to search.
    /// - Returns: The extracted info (e.g., "15" or "12:34").
    static func extractPauseInfo(_ s: String) -> String {
        let normalized = s.lowercased()
        
        // 1. Check for time delimiters (:, ;, ., ,)
        let timePattern = "(\\d{1,2})[\\:;\\.,](\\d{2})"
        if let regex = try? NSRegularExpression(pattern: timePattern),
           let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let hRange = Range(match.range(at: 1), in: s),
           let mRange = Range(match.range(at: 2), in: s) {
            return "\(s[hRange]):\(s[mRange])"
        }
        
        // 2. Check for "bis" followed by digits (treat as time HH:00 or HH:MM)
        if normalized.contains("bis") {
            let digitPattern = "\\d+"
            if let regex = try? NSRegularExpression(pattern: digitPattern),
               let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let range = Range(match.range, in: s) {
                let digits = String(s[range])
                if digits.count <= 2 {
                    return "\(digits):00"
                } else if digits.count == 4 {
                    // fall through to military time logic
                } else {
                    return digits
                }
            }
        }

        // 3. Check for 4-digit military time (e.g., 1330 -> 13:30)
        let militaryPattern = "\\b(\\d{2})(\\d{2})\\b"
        if let regex = try? NSRegularExpression(pattern: militaryPattern),
           let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let hRange = Range(match.range(at: 1), in: s),
           let mRange = Range(match.range(at: 2), in: s) {
            let h = Int(s[hRange]) ?? 0
            let m = Int(s[mRange]) ?? 0
            if h < 24 && m < 60 {
                return "\(s[hRange]):\(s[mRange])"
            }
        }
        
        // 4. Default to duration if it's a number
        let digitPattern = "\\d+"
        if let regex = try? NSRegularExpression(pattern: digitPattern),
           let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let range = Range(match.range, in: s) {
            let digits = String(s[range])
            // If it's over 1000, treat it as military time if not already handled
            if let val = Int(digits), val >= 100, val <= 2359 && digits.count >= 3 {
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
    
    /// Formats the display label for a Pause slide.
    /// - Parameter info: The extracted info ("15" or "12:34").
    /// - Returns: A formatted string ("15 Minuten" or "bis 12:34").
    static func formatPauseDisplay(_ info: String) -> String {
        if info.contains(":") {
            return "bis \(info)"
        } else {
            return "\(info) Minuten"
        }
    }
}
