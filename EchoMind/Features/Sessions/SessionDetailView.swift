import SwiftUI

/// Full transcript, rename, export, delete, and audio playback for a session (§4.2, P17).
struct SessionDetailView: View {
    let session: SessionSnapshot
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: SessionDetailViewModel?

    var body: some View {
        Group {
            if let model {
                SessionDetailContent(model: model, audioURL: audioURL)
            } else {
                Color.clear
            }
        }
        .task {
            if model == nil {
                let vm = SessionDetailViewModel(
                    session: session,
                    repository: dependencies.sessionRepository,
                    summarizer: dependencies.summarizer,
                    availability: dependencies.availabilityMonitor,
                    audioStore: dependencies.audioStore,
                    diarizer: dependencies.diarizer,
                    reportGenerator: dependencies.reportGenerator)
                model = vm
                await vm.load()
            }
        }
    }

    private var audioURL: URL? {
        dependencies.audioStore.exists(session.id) ? dependencies.audioStore.url(for: session.id) : nil
    }
}

private struct SessionDetailContent: View {
    @Bindable var model: SessionDetailViewModel
    let audioURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var showRename = false
    @State private var showDelete = false
    @State private var playback = AudioPlaybackService()

    var body: some View {
        List {
            SummarySectionView(model: model)
            if audioURL != nil {
                Section("Recording") {
                    AudioPlayerBar(playback: playback)
                }
            }
            Section {
                if model.segments.isEmpty {
                    Text("No transcript").foregroundStyle(.secondary)
                } else {
                    ForEach(model.segments) { segment in
                        if audioURL != nil {
                            Button { playback.playFrom(segment.startTime) } label: {
                                TranscriptSegmentRow(segment: segment)
                            }
                            .buttonStyle(.plain)
                        } else {
                            TranscriptSegmentRow(segment: segment)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Transcript")
                    if model.isIdentifyingSpeakers {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Text("Identifying speakers…").font(.caption).textCase(nil)
                    }
                }
            }
        }
        .task {
            if let audioURL { playback.load(url: audioURL) }
        }
        .onDisappear { playback.stop() }
        .navigationTitle(model.session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ShareLink(item: model.markdownExport,
                              preview: SharePreview(model.session.title)) {
                        Label("Export as Markdown", systemImage: "doc.text")
                    }
                    ShareLink(item: model.textExport,
                              preview: SharePreview(model.session.title)) {
                        Label("Export as Text", systemImage: "doc.plaintext")
                    }
                    if model.canIdentifySpeakers {
                        Divider()
                        Button {
                            Task { await model.identifySpeakers() }
                        } label: {
                            Label("Identify Speakers", systemImage: "person.2.wave.2")
                        }
                        .disabled(model.isIdentifyingSpeakers)
                    }
                    Divider()
                    Button { showRename = true } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) { showDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Session actions")
            }
        }
        .alert("Rename Session", isPresented: $showRename) {
            TextField("Title", text: $model.draftTitle)
            Button("Save") { Task { await model.commitRename() } }
            Button("Cancel", role: .cancel) { model.draftTitle = model.session.title }
        }
        .confirmationDialog("Delete this session?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await model.delete(); dismiss() }
            }
        } message: {
            Text("The transcript, its knowledge entries, and its audio will be removed.")
        }
    }
}

/// Play/pause + scrubber for a retained recording (P17).
private struct AudioPlayerBar: View {
    @Bindable var playback: AudioPlaybackService

    var body: some View {
        HStack(spacing: DS.md) {
            Button { playback.togglePlay() } label: {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(DS.brand)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

            VStack(spacing: 2) {
                Slider(value: Binding(get: { playback.currentTime },
                                      set: { playback.seek(to: $0) }),
                       in: 0...max(playback.duration, 0.1))
                HStack {
                    Text(Self.time(playback.currentTime)).monospacedDigit()
                    Spacer()
                    Text(Self.time(playback.duration)).monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private static func time(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
