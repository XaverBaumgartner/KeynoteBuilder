import SwiftUI

/// A row view that handles different types of block matches.
struct MatchItemRow: View {
    let match: BlockMatch
    @ObservedObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let nested = match.nestedDeck {
                let corr = match.isFuzzy ? (old: match.originalName, new: match.resolvedRelativePath) : nil
                DeckTreeView(name: match.resolvedRelativePath, deck: nested, isRoot: false, correction: corr, appState: appState)
            } else {
                switch match.type {
                case .menti:
                    MentiRow(match: match, appState: appState)
                case .pause:
                    PauseRow(match: match)
                default:
                    FileRow(match: match)
                }
            }
        }
    }
}

/// A simple row view for a file match (Keynote).
struct FileRow: View {
    let match: BlockMatch
    
    var body: some View {
        HStack(spacing: 4) {
            if match.isFuzzy {
                CorrectionLabel(old: match.originalName, new: match.displayName, isRoot: false, icon: "doc.richtext")
            } else {
                Image(systemName: "doc.richtext")
                    .foregroundColor(.secondary)
                Text(match.displayName)
                    .foregroundColor(.primary)
            }
        }
        .font(.subheadline)
    }
}

/// A specialized row for Mentimeter slide matches.
struct MentiRow: View {
    let match: BlockMatch
    @ObservedObject var appState: AppState
    
    var body: some View {
        let code = match.type.parameterString ?? ""
        return HStack(spacing: 4) {
            Image(systemName: "qrcode")
                .foregroundColor(.secondary)
            
            if match.isFuzzy {
                HStack(alignment: .center, spacing: 4) {
                    Text(match.originalName)
                        .strikethrough()
                        .foregroundColor(.orange)
                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                        .font(.system(size: 9))
                }
            }
            
            Text(match.displayName)
                .foregroundColor(statusColor(for: code))
                .bold()
            
            if let status = appState.mentiStatuses[code] {
                Image(systemName: status ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(statusColor(for: code))
                    .font(.caption)
            } else {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 12, height: 12)
            }
        }
        .font(.subheadline)
    }
    
    private func statusColor(for code: String) -> Color {
        switch appState.mentiStatuses[code] {
        case .some(true): return .green
        case .some(false): return .red
        case .none: return .secondary
        }
    }
}

/// A label used to display an original name that was automatically corrected.
struct CorrectionLabel: View {
    let old: String
    let new: String
    let isRoot: Bool
    let icon: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
            }
            Text(old)
                .strikethrough()
                .foregroundColor(.orange)
            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.system(size: 9))
            Text(new)
                .foregroundColor(.primary)
                .bold(isRoot)
        }
        .font(isRoot ? .body : .subheadline)
    }
}

/// A specialized row for Pause slide matches.
struct PauseRow: View {
    let match: BlockMatch
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .foregroundColor(.secondary)
            
            if match.isFuzzy {
                HStack(alignment: .center, spacing: 4) {
                    Text(match.originalName)
                        .strikethrough()
                        .foregroundColor(.orange)
                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                        .font(.system(size: 9))
                }
            }
            
            Text(match.displayName)
                .foregroundColor(.blue)
                .bold()
        }
        .font(.subheadline)
    }
}
