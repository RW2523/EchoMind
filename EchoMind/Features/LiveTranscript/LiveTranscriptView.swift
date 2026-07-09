import SwiftUI

/// Live transcription screen. Builds its view model from the environment once,
/// then hands off to the content view (§3.5).
struct LiveTranscriptView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: LiveTranscriptViewModel?

    var body: some View {
        Group {
            if let model {
                LiveTranscriptContent(model: model)
            } else {
                Color.clear
            }
        }
        .navigationTitle("Live Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                model = LiveTranscriptViewModel(
                    audio: dependencies.audioCapturing,
                    transcription: dependencies.transcriptionService,
                    assets: dependencies.speechAssets,
                    sessions: dependencies.sessionRepository,
                    permissions: dependencies.permissions,
                    indexer: dependencies.indexer,
                    reportGenerator: dependencies.reportGenerator,
                    retainAudio: dependencies.settingsStore.audioRetentionEnabled,
                    audioStore: dependencies.audioStore)
            }
        }
    }
}

private struct LiveTranscriptContent: View {
    let model: LiveTranscriptViewModel
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            transcript
            if case .failed(let error) = model.phase {
                errorBanner(error)
            }
            controls
        }
        .background(BrandBackground())
        .onChange(of: scenePhase) { _, newValue in
            // Unlock catch-up: state is already current; re-render happens here.
            _ = newValue
        }
    }

    // MARK: - Status

    @ViewBuilder private var statusBar: some View {
        switch model.phase {
        case .recording, .pausedByInterruption:
            VStack(spacing: DS.md) {
                LiveWaveformView(level: model.level, isActive: model.phase == .recording)
                    .frame(height: 88)
                RecordingIndicatorView(elapsed: model.elapsed,
                                       isPaused: model.phase == .pausedByInterruption)
                    .font(.title3.monospacedDigit())
            }
            .padding(DS.lg)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
            .padding()
        case .preparingAssets(let progress):
            VStack(spacing: 8) {
                ProgressView(value: progress)
                Text("Preparing on-device speech model…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        default:
            EmptyView()
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.finalizedLines) { line in
                        Text(line.text).foregroundStyle(.primary)
                    }
                    if !model.volatileText.isEmpty {
                        Text(model.volatileText).foregroundStyle(.secondary)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .onChange(of: model.finalizedLines.count) { _, _ in
                withAnimation { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onChange(of: model.volatileText) { _, _ in
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
            .overlay {
                if model.finalizedLines.isEmpty && model.volatileText.isEmpty && !isBusy {
                    ContentUnavailableView("Tap Record to start",
                                           systemImage: "mic",
                                           description: Text("Your words appear here, transcribed on-device."))
                }
            }
        }
    }

    private static let bottomID = "transcript-bottom"

    // MARK: - Controls

    private var controls: some View {
        HStack {
            if model.isRecording {
                Button(role: .destructive) {
                    Task { await model.stopTapped() }
                } label: {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    Task { await model.startTapped() }
                } label: {
                    Label("Record", systemImage: "record.circle")
                }
                .buttonStyle(BrandButtonStyle())
                .disabled(isBusy)
            }
        }
        .padding()
        #if DEBUG
        .safeAreaInset(edge: .bottom) {
            DebugSegmentInspectorView(model: model, sessions: dependencies.sessionRepository)
        }
        #endif
    }

    private var isBusy: Bool {
        switch model.phase {
        case .preparingAssets, .stopping: return true
        default: return false
        }
    }

    // MARK: - Errors

    @ViewBuilder private func errorBanner(_ error: TranscriptionError) -> some View {
        VStack(spacing: 8) {
            Text(message(for: error))
                .font(.callout)
                .multilineTextAlignment(.center)
            if needsSettings(error) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.red.opacity(0.1))
    }

    private func needsSettings(_ error: TranscriptionError) -> Bool {
        switch error {
        case .microphoneDenied, .speechDenied: return true
        default: return false
        }
    }

    private func message(for error: TranscriptionError) -> String {
        switch error {
        case .microphoneDenied:
            return "Microphone access is off. Turn it on in Settings to record."
        case .speechDenied:
            return "Speech recognition is off. Turn it on in Settings to transcribe."
        case .localeUnsupported(let id):
            return "On-device transcription isn't available for \(id)."
        case .assetDownloadFailed:
            return "Couldn't download the speech model. Check your connection and try again."
        case .transcriberFailed:
            return "Transcription stopped — your recording up to this point is saved."
        case .sessionActivationFailed:
            return "Couldn't start audio. Try again."
        case .insufficientStorage:
            return "Not enough storage to record — free up space and try again."
        case .speechUnavailable:
            return "Live transcription isn't available here. It needs a physical iPhone — the Simulator has no on-device speech models."
        }
    }
}

/// Simple horizontal level bar (0…1).
private struct LevelBar: View {
    let level: Float
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.tint)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, level))))
            }
        }
        .frame(width: 80, height: 6)
    }
}
