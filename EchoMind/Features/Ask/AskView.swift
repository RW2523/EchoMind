import SwiftUI

/// Chat-style RAG Q&A over ChatMessage storage (§6.3).
struct AskView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: AskViewModel?
    @State private var voice: VoiceSessionController?

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
                let input = LiveVoiceInput(audio: dependencies.audioCapturing,
                                           transcription: dependencies.transcriptionService,
                                           permissions: dependencies.permissions,
                                           assets: dependencies.speechAssets)
                voice = VoiceSessionController(input: input, synthesizer: dependencies.makeSpeechSynthesizer(),
                                               onQuestion: { question in await vm.askVoice(question) },
                                               onQuestionStream: { question in vm.askVoiceStream(question) })
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
            if let voice, voice.isActive { voiceStrip(voice) }
            inputBar(model)
        }
        .background(BrandBackground())
    }

    @ViewBuilder
    private func voiceStrip(_ voice: VoiceSessionController) -> some View {
        HStack(spacing: DS.md) {
            Image(systemName: icon(for: voice.state))
                .font(.title3).foregroundStyle(DS.brand)
                .symbolEffect(.variableColor.iterative, isActive: voice.state == .listening || voice.state == .speaking)
            VStack(alignment: .leading, spacing: 2) {
                Text(label(for: voice.state)).font(.caption.weight(.semibold))
                if !voice.partialTranscript.isEmpty {
                    Text(voice.partialTranscript).font(.subheadline).lineLimit(2)
                }
            }
            Spacer()
            if voice.state == .listening && !voice.isHandsFree {
                Button {
                    Task { await voice.finishAndAsk() }
                } label: {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(DS.brand)
                }
                .accessibilityLabel("Finish and ask")
            }
            if voice.state == .speaking && voice.isHandsFree {
                Button { voice.bargeIn() } label: {
                    Image(systemName: "hand.raised.fill").font(.title3).foregroundStyle(DS.brand)
                }
                .accessibilityLabel("Interrupt")
            }
            Button { voice.cancel() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
            }
            .accessibilityLabel("Cancel voice")
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
        .padding(.horizontal).padding(.bottom, 4)
    }

    private func inputBar(_ model: AskViewModel) -> some View {
        HStack(spacing: 8) {
            TextField("Ask a question…", text: Binding(get: { model.draft }, set: { model.draft = $0 }),
                      axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit { Task { await model.send() } }
            if let voice, voice.canSpeak, !voice.isActive, model.draft.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    Task { await voice.startConversation() }
                } label: {
                    Image(systemName: "waveform.badge.mic").font(.title2)
                }
                .accessibilityLabel("Hands-free conversation")
                .disabled(model.state == .thinking)
                Button {
                    Task { await voice.startListening() }
                } label: {
                    Image(systemName: "mic.circle.fill").font(.title2)
                }
                .accessibilityLabel("Ask by voice")
                .disabled(model.state == .thinking)
            } else {
                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .accessibilityLabel("Send question")
                .disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty || model.state == .thinking)
            }
        }
        .padding()
    }

    private func icon(for state: VoiceSessionController.State) -> String {
        switch state {
        case .listening: return "waveform"
        case .thinking: return "ellipsis.circle"
        case .speaking: return "speaker.wave.2.fill"
        case .failed: return "exclamationmark.triangle"
        case .idle: return "mic"
        }
    }

    private func label(for state: VoiceSessionController.State) -> String {
        switch state {
        case .listening: return "Listening…"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking…"
        case .failed(let message): return message
        case .idle: return ""
        }
    }
}
