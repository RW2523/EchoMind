import SwiftUI

/// Chat-style RAG Q&A over ChatMessage storage (§6.3).
struct AskView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: AskViewModel?
    @State private var voice: VoiceSessionController?
    @State private var showVoiceMode = false

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
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(model.messages) { message in
                            if message.role == .user {
                                Text(message.content)
                                    .padding(.horizontal, 16).padding(.vertical, 11)
                                    .background(DS.brandGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: 300, alignment: .trailing)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            } else {
                                AnswerCardView(message: message)
                            }
                        }
                        if model.state == .thinking {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "sparkles").font(.footnote.weight(.semibold))
                                    .foregroundStyle(DS.brandLight)
                                    .frame(width: 28, height: 28)
                                    .background(DS.brand.opacity(0.18), in: Circle())
                                TypingIndicator()
                                Spacer(minLength: 0)
                            }
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
                                    .foregroundStyle(DS.brandLight)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(DS.brand.opacity(0.14), in: Capsule())
                                    .overlay(Capsule().strokeBorder(DS.brand.opacity(0.3), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }
            }
            // The inline strip covers push-to-talk (single spoken question). Hands-free
            // is the full-screen conversation below.
            if let voice, voice.isActive, !voice.isHandsFree { voiceStrip(voice) }
            inputBar(model)
        }
        .background(BrandBackground())
        .fullScreenCover(isPresented: $showVoiceMode) {
            if let voice {
                VoiceConversationView(voice: voice) { showVoiceMode = false }
            }
        }
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
        let empty = model.draft.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("Message EchoMind…", text: Binding(get: { model.draft }, set: { model.draft = $0 }),
                          axis: .vertical)
                    .lineLimit(1...5)
                    .onSubmit { Task { await model.send() } }
                if let voice, voice.canSpeak, !voice.isActive, empty {
                    Button { Task { await voice.startListening() } } label: {
                        Image(systemName: "mic.fill").font(.callout).foregroundStyle(DS.brandLight)
                    }
                    .accessibilityLabel("Ask by voice")
                    .disabled(model.state == .thinking)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .background(DS.bgElevated.opacity(0.5), in: Capsule())
            .overlay(Capsule().strokeBorder(DS.stroke.opacity(0.25), lineWidth: 1))

            // Send, or open the full-screen voice conversation when there's nothing to send.
            if let voice, voice.canSpeak, !voice.isActive, empty {
                circleButton("waveform", label: "Voice conversation", disabled: model.state == .thinking) {
                    showVoiceMode = true
                }
            } else {
                circleButton("arrow.up", label: "Send question",
                             disabled: empty || model.state == .thinking) {
                    Task { await model.send() }
                }
            }
        }
        .padding(.horizontal).padding(.vertical, DS.sm)
    }

    private func circleButton(_ systemName: String, label: String, disabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(disabled ? AnyShapeStyle(Color.gray.opacity(0.3)) : AnyShapeStyle(DS.brandGradient),
                            in: Circle())
        }
        .disabled(disabled)
        .accessibilityLabel(label)
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

/// Three animated dots — the "assistant is typing" indicator (ChatGPT-style).
private struct TypingIndicator: View {
    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(DS.brandLight.opacity(phase == i ? 1 : 0.35))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == i ? 1.2 : 1)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.4).repeatForever()) { phase = 0 }
            Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.25)) { phase = (phase + 1) % 3 }
            }
        }
    }
}
