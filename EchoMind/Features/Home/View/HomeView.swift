import SwiftUI

/// Home dashboard: an animated hero, quick actions, and recent sessions as
/// frosted cards over the living aurora backdrop.
struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: HomeViewModel?
    @Namespace private var heroNamespace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.xl) {
                header.revealOnAppear(delay: 0.02)
                primaryAction.revealOnAppear(delay: 0.08)
                HStack(spacing: DS.md) {
                    quickAction(title: "Ask", subtitle: "Your knowledge",
                                icon: "sparkles") { AskView() }
                    quickAction(title: "Import", subtitle: "Docs & PDFs",
                                icon: "doc.badge.plus") { KnowledgeView() }
                }
                .revealOnAppear(delay: 0.14)
                recentSection.revealOnAppear(delay: 0.2)
            }
            .padding(DS.lg)
            .padding(.top, DS.sm)
        }
        .background(BrandBackground())
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Welcome to")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("EchoMind")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .vividForeground()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryAction: some View {
        NavigationLink {
            LiveTranscriptView()
                .navigationTransition(.zoom(sourceID: "record", in: heroNamespace))
        } label: {
            HStack(spacing: DS.lg) {
                ZStack {
                    AnimatedRing(lineWidth: 3).frame(width: 60, height: 60)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(DS.brand)
                        .frame(width: 48, height: 48)
                        .background(.white, in: Circle())
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Start Live Transcript")
                        .font(.title3.weight(.bold)).foregroundStyle(.white)
                    Text("Record & transcribe on-device")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.headline).foregroundStyle(.white.opacity(0.8))
            }
            .padding(DS.lg)
            .frame(maxWidth: .infinity)
            .background(DS.vividGradient, in: RoundedRectangle(cornerRadius: DS.rLg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.rLg, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .glow(DS.brand, radius: 14)
        }
        .buttonStyle(PressableStyle())
        .matchedTransitionSource(id: "record", in: heroNamespace)
    }

    private func quickAction<Destination: View>(title: String, subtitle: String, icon: String,
                                                @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            GlassCard(padding: DS.lg) {
                VStack(alignment: .leading, spacing: DS.md) {
                    Image(systemName: icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(DS.brandGradient, in: RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
                        .glow(DS.brand, radius: 6)
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder private var recentSection: some View {
        if let model, !model.recent.isEmpty {
            VStack(alignment: .leading, spacing: DS.md) {
                Text("Recent").font(.title3.weight(.bold)).padding(.leading, DS.xs)
                ForEach(Array(model.recent.enumerated()), id: \.element.id) { index, session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        GlassCard(padding: DS.md) {
                            SessionRow(session: session, repository: dependencies.sessionRepository)
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .revealOnAppear(delay: 0.22 + Double(index) * 0.05)
                }
            }
        } else {
            GlassCard {
                HStack(spacing: DS.md) {
                    Image(systemName: "waveform")
                        .font(.title2).foregroundStyle(DS.brand)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No sessions yet").font(.headline)
                        Text("Tap Start Live Transcript to begin.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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
