import SwiftUI

/// Type-to-confirm wipe (§7.1): the user must type DELETE.
struct DeleteAllDataView: View {
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""

    private static let phrase = "DELETE"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This permanently deletes every session, document, transcript, and chat on this iPhone. It cannot be undone.")
                        .foregroundStyle(.secondary)
                    TextField("Type \(Self.phrase) to confirm", text: $confirmation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                Section {
                    Button("Delete Everything", role: .destructive) {
                        onConfirm()
                        dismiss()
                    }
                    .disabled(confirmation != Self.phrase)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Delete All Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
