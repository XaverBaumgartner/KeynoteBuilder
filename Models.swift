import Foundation

struct DeckData {
    let path: String
    let url: URL
    let matchedNames: [String]
    let inexactMatches: [String]
}

struct BuildInfo {
    let name: String
    let path: String
    let url: URL
    let matches: [String]
}
