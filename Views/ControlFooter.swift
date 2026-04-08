import SwiftUI

/// Provides the build and termination controls at the bottom of the window.
struct ControlFooter: View {
    @ObservedObject var appState: AppState
    
    private var statusDescription: String {
        if appState.isBuilding {
            return "Building..."
        } else if let error = appState.buildError {
            return error
        } else if appState.staleNames.isEmpty || appState.buildFinished {
            return "Ready"
        } else {
            return "\(appState.selectedNames.count) deck(s) selected"
        }
    }
    
    private var isBuildingOrStaleEmpty: Bool {
        appState.staleNames.isEmpty || appState.buildFinished
    }
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                if appState.isBuilding {
                    ProgressView()
                        .scaleEffect(0.5)
                }
                Text(statusDescription)
                    .foregroundColor(appState.buildError != nil ? .red : .secondary)
            }
            
            Spacer()
            
            // If built or no decks available, show "Close" to terminate.
            if isBuildingOrStaleEmpty {
                Button("Close") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button("Cancel") {
                    NSApplication.shared.terminate(nil)
                }
                .disabled(appState.isBuilding)
                
                Button("Build Selected") {
                    Task {
                        await appState.performAssembly()
                    }
                }
                .disabled(appState.selectedNames.isEmpty || appState.isBuilding)
                .buttonStyle(BorderedProminentButtonStyle())
            }
        }
        .padding()
    }
}
