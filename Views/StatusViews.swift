import SwiftUI

/// A view displayed when an error occurs during initialization or building.
struct ErrorOverlay: View {
    let error: String
    
    var body: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.largeTitle)
                .padding()
            Text(error)
                .multilineTextAlignment(.center)
                .padding()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A view displayed while the application is analyzing decks.
struct LoadingStateView: View {
    var body: some View {
        VStack {
            ProgressView("Analyzing decks...")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A view displayed after a successful build.
struct CompletionStateView: View {
    let builtCount: Int
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
                .font(.system(size: 40))
            Text("Assembly Complete!")
                .font(.headline)
            Text("Built \(builtCount) deck(s).")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A view displayed when all detected decks are already up-to-date.
struct UpToDateStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 40))
            Text("All decks are up-to-date.")
                .font(.headline)
            Text("Nothing to build.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
