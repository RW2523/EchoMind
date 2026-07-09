import SwiftUI

/// Date-sorted, searchable session list — grouped by AI meeting category (R2),
/// with filter chips, over the aurora backdrop.
struct SessionsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: SessionsViewModel?
    @State private var searchText = ""
    @State private var selectedCategory: String?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .navigationTitle("Sessions")
        .task {
            if model == nil {
                let vm = SessionsViewModel(repository: dependencies.sessionRepository,
                                           audioStore: dependencies.audioStore)
                model = vm
                await vm.load()
            }
        }
    }

    private func content(_ model: SessionsViewModel) -> some View {
        let visible = selectedCategory.map { cat in model.sessions.filter { ($0.tags.first ?? "") == cat } }
            ?? model.sessions
        let groups = Self.grouped(visible)

        return List {
            if categories(model).count > 1 {
                filterChips(model).listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(groups, id: \.0) { category, sessions in
                Section {
                    ForEach(sessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            SessionRow(session: session, repository: dependencies.sessionRepository)
                        }
                        .listRowBackground(rowBackground)
                        .listRowSeparator(.hidden)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { sessions[$0].id }
                        Task { await model.delete(ids: ids) }
                    }
                } header: {
                    if groups.count > 1 || category != "Ungrouped" {
                        HStack(spacing: 6) {
                            Circle().fill(Self.color(for: category)).frame(width: 9, height: 9)
                            Text(category)
                            Text("\(sessions.count)").foregroundStyle(.secondary)
                        }
                        .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BrandBackground())
        .overlay {
            if model.sessions.isEmpty {
                ContentUnavailableView("No Sessions Yet", systemImage: "waveform",
                                       description: Text("Recorded sessions appear here."))
            }
        }
        .searchable(text: $searchText, prompt: "Search transcripts")
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(300))
            await model.applySearch(searchText)
        }
        .refreshable { await model.load() }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
            .fill(.regularMaterial)
            .shadow(color: .black.opacity(0.07), radius: 8, y: 4)
            .padding(.vertical, 4)
    }

    private func filterChips(_ model: SessionsViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: selectedCategory == nil) { selectedCategory = nil }
                ForEach(categories(model), id: \.self) { category in
                    chip(category, selected: selectedCategory == category, dot: Self.color(for: category)) {
                        selectedCategory = selectedCategory == category ? nil : category
                    }
                }
            }
            .padding(.horizontal).padding(.vertical, 6)
        }
    }

    private func chip(_ title: String, selected: Bool, dot: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
                Text(title).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(selected ? AnyShapeStyle(DS.brandGradient) : AnyShapeStyle(.regularMaterial),
                        in: Capsule())
            .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func categories(_ model: SessionsViewModel) -> [String] {
        Array(Set(model.sessions.compactMap { $0.tags.first }.filter { !$0.isEmpty })).sorted()
    }

    // MARK: - Grouping helpers

    private static func grouped(_ sessions: [SessionSnapshot]) -> [(String, [SessionSnapshot])] {
        Dictionary(grouping: sessions) { $0.tags.first?.isEmpty == false ? $0.tags.first! : "Ungrouped" }
            .sorted { a, b in
                if a.key == "Ungrouped" { return false }
                if b.key == "Ungrouped" { return true }
                return a.key < b.key
            }
            .map { ($0.key, $0.value) }
    }

    private static let palette: [Color] = [
        DS.brand,
        Color(red: 0.35, green: 0.72, blue: 0.98),   // sky
        Color(red: 0.55, green: 0.5, blue: 0.98),    // periwinkle
        Color(red: 0.98, green: 0.62, blue: 0.35),   // amber
        Color(red: 0.3, green: 0.82, blue: 0.6),     // teal
        Color(red: 0.95, green: 0.45, blue: 0.6),    // rose
    ]

    static func color(for category: String) -> Color {
        guard category != "Ungrouped" else { return .secondary }
        let hash = abs(category.hashValue)
        return palette[hash % palette.count]
    }
}
