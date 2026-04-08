import Foundation

/// A utility for matching strings based on similarity algorithms.
public enum StringMatching {
    /// Computes the Jaro-Winkler distance between two strings.
    /// - Parameters:
    ///   - s1: The first string.
    ///   - s2: The second string.
    /// - Returns: A score between 0.0 and 1.0 (1.0 is a perfect match).
    public static func jaroWinkler(_ s1: String, _ s2: String) -> Double {
        if s1 == s2 { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }
        
        let s1Chars = Array(s1)
        let s2Chars = Array(s2)
        let n = s1Chars.count
        let m = s2Chars.count
        
        var matchWindow = max(n, m) / 2 - 1
        if matchWindow < 0 { matchWindow = 0 }
        
        var s1Matched = [Bool](repeating: false, count: n)
        var s2Matched = [Bool](repeating: false, count: m)
        
        var matches = 0
        var transpositions = 0
        
        for i in 0..<n {
            let lo = max(0, i - matchWindow)
            let hi = min(m - 1, i + matchWindow)
            
            if lo <= hi {
                for j in lo...hi {
                    if !s2Matched[j] && s1Chars[i] == s2Chars[j] {
                        s1Matched[i] = true
                        s2Matched[j] = true
                        matches += 1
                        break
                    }
                }
            }
        }
        
        if matches == 0 { return 0.0 }
        
        var k = 0
        for i in 0..<n {
            if !s1Matched[i] { continue }
            while !s2Matched[k] { k += 1 }
            if s1Chars[i] != s2Chars[k] {
                transpositions += 1
            }
            k += 1
        }
        
        let mD = Double(matches)
        let jaro = (mD / Double(n) + mD / Double(m) + (mD - Double(transpositions) / 2.0) / mD) / 3.0
        
        var prefix = 0
        let maxPrefix = min(4, min(n, m))
        for i in 0..<maxPrefix {
            if s1Chars[i] == s2Chars[i] { prefix += 1 }
            else { break }
        }
        
        return jaro + Double(prefix) * 0.1 * (1.0 - jaro)
    }
}
