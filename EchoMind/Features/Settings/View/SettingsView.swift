import SwiftUI

/// Settings tab placeholder. Model status, storage usage, export, and data
/// controls land in Phase 9. Hosts the debug storage smoke test in DEBUG.
struct SettingsView: View {
    var body: some View {
        List {
            Section("Privacy") {
                Text(AppCopy.privacyExplainer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
