import SwiftUI

/// Chat-style RAG Q&A over ChatMessage storage (§6.3).
struct AskView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: AskViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .navigationTitle("Ask")
        .task {
            if model == nil {
                let vm = AskViewModel(rag: dependencies.ragService, chat: dependencies.chatRepository,
                                      chunks: dependencies.chunkRepository,
                                      documents: dependencies.documentRepository,
                                      sessions: dependencies.sessionRepository)
                model = vm
                await vm.load()
            }
        }
    }

    private func content(_ model: AskViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.messages) { message in
                            if message.role == .user {
                                Text(message.content)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(DS.brandGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .foregroundStyle(.white)
                                    .shadow(color: DS.brand.opacity(0.25), radius: 6, y: 3)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            } else {
                                AnswerCardView(message: message)
                            }
                        }
                        if model.state == .thinking {
                            HStack(spacing: 8) { ProgressView(); Text("Searching your knowledge…").foregroundStyle(.secondary) }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .onChange(of: model.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .overlay {
                if model.messages.isEmpty {
                    ContentUnavailableView("Ask Your Knowledge", systemImage: "sparkles",
                                           description: Text("Ask a question across your sessions and documents."))
                }
            }
            if !model.suggestedFollowUps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.suggestedFollowUps, id: \.self) { chip in
                            Button {
                                Task { await model.askFollowUp(chip) }
                            } label: {
                                Text(chip)
                                    .font(.callout).lineLimit(1)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(.tint.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }
            }
            inputBar(model)
        }
        .background(BrandBackground())
    }

    private func inputBar(_ model: AskViewModel) -> some View {
        HStack(spacing: 8) {
            TextField("Ask a question…", text: Binding(get: { model.draft }, set: { model.draft = $0 }),
                      axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit { Task { await model.send() } }
            Button {
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .accessibilityLabel("Send question")
            .disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty || model.state == .thinking)
        }
        .padding()
    }
}
