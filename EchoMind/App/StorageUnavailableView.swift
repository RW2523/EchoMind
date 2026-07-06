import SwiftUI

/// Blocking screen shown when the on-disk store can't be opened (disk full or
/// corrupt). Never `fatalError` in release — surface the error honestly (§2.3).
struct StorageUnavailableView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.trianglebadge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Storage unavailable")
                .font(.title2.bold())
            Text("EchoMind couldn't open its local database. Free up space and relaunch.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
