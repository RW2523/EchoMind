import SwiftUI

/// Home dashboard (V2 §D): a gradient hero action, quick actions, and recent
/// sessions as cards on the brand backdrop.
struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: HomeViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: DS.lg) {
                primaryAction
                HStack(spacing: DS.md) {
                    quickAction(title: "Ask", subtitle: "Your knowledge", icon: "sparkles") { AskView() }
                    quickAction(title: "Import", subtitle: "Docs & PDFs", icon: "doc.badge.plus") { KnowledgeView() }
                }
                recentSection
            }
            .padding(DS.lg)
        }
        .background(BrandBackground())
        .navigationTitle("EchoMind")
        .task {
            if model == nil {
                let vm = HomeViewModel(repository: dependencies.sessionRepository)
                model = vm
                await vm.load()
            } else {
                await model?.load()
            }
        }
    }

    private var primaryAction: some View {
        NavigationLink {
            LiveTranscriptView()
        } label: {
            HStack(spacing: DS.lg) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(DS.brand)
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.9), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Live Transcript").font(.title3.weight(.semibold)).foregroundStyle(.white)
                    Text("Record & transcribe on-device").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.7))
            }
            .padding(DS.lg)
            .frame(maxWidth: .infinity)
            .background(DS.brandGradient, in: RoundedRectangle(cornerRadius: DS.rLg, style: .continuous))
            .shadow(color: DS.brand.opacity(0.35), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func quickAction<Destination: View>(title: String, subtitle: String, icon: String,
                                                @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            GlassCard(padding: DS.lg) {
                VStack(alignment: .leading, spacing: DS.sm) {
                    Image(systemName: icon).font(.title2).foregroundStyle(DS.brand)
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var recentSection: some View {
        if let model, !model.recent.isEmpty {
            VStack(alignment: .leading, spacing: DS.md) {
                Text("Recent").font(.headline).padding(.leading, DS.xs)
                ForEach(model.recent) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        GlassCard(padding: DS.md) {
                            SessionRow(session: session, repository: dependencies.sessionRepository)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            GlassCard {
                HStack(spacing: DS.md) {
                    Image(systemName: "waveform").font(.title2).foregroundStyle(.secondary)
                    Text("Your sessions will appear here.").foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { HomeView() }
        .environment(AppDependencies.preview())
        .echoMindStyle()
}
#endif
