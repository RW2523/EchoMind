import SwiftUI

/// R3 transparency: every durable fact EchoMind remembers, with its kind and a
/// swipe to forget. On-device memory the user can actually audit.
struct MemoryView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var facts: [MemoryFactSnapshot] = []

    var body: some View {
        List {
            ForEach(facts) { fact in
                HStack(spacing: DS.md) {
                    Image(systemName: fact.kind.symbol)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(DS.brandGradient, in: RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.text)
                        Text(fact.kind.rawValue.capitalized)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.07), radius: 8, y: 4)
                        .padding(.vertical, 4))
                .listRowSeparator(.hidden)
                .swipeActions {
                    Button(role: .destructive) {
                        Task { try? await dependencies.memoryStore.delete(id: fact.id); await load() }
                    } label: { Label("Forget", systemImage: "trash") }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BrandBackground())
        .overlay {
            if facts.isEmpty {
                ContentUnavailableView("Nothing Remembered Yet", systemImage: "brain",
                                       description: Text("As you record meetings, EchoMind remembers durable facts — people, projects, decisions — and uses them to answer with context from every past meeting."))
            }
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        facts = (try? await dependencies.memoryStore.all()) ?? []
    }
}
