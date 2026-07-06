import SwiftUI

/// Settings tab placeholder. Model status, storage usage, export, and data
/// controls land in Phase 9. Hosts the debug storage smoke test in DEBUG.
struct SettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var isRebuilding = false

    var body: some View {
        List {
            Section("Privacy") {
                Text(AppCopy.privacyExplainer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Knowledge Index") {
                Button {
                    Task {
                        isRebuilding = true
                        try? await dependencies.indexer.rebuildAll()
                        isRebuilding = false
                    }
                } label: {
                    HStack {
                        Label("Rebuild Index", systemImage: "arrow.clockwise")
                        if isRebuilding { Spacer(); ProgressView() }
                    }
                }
                .disabled(isRebuilding)
            }
            #if DEBUG
            DebugStorageSection()
            #endif
        }
        .navigationTitle("Settings")
    }
}

#if DEBUG
#Preview {
    NavigationStack { SettingsView() }
        .environment(AppDependencies.preview())
}
#endif
