import SwiftUI

/// On-device model manager (V2 §B3): choose the AI routing preference, download a
/// local LLM so full AI works with Apple Intelligence off, and manage weights.
struct AIModelsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: AIModelsViewModel?
    @State private var rebuilding = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .navigationTitle("On-Device AI")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                let vm = AIModelsViewModel(downloader: dependencies.modelDownloader,
                                           settings: dependencies.aiSettings)
                model = vm
                await vm.load()
            }
        }
    }

    private func content(_ model: AIModelsViewModel) -> some View {
        @Bindable var model = model
        return List {
            Section {
                Picker("When available", selection: $model.preference) {
                    Text("Automatic").tag(AIPreference.auto)
                    Text("Prefer on-device model").tag(AIPreference.preferLocal)
                    Text("Apple Intelligence only").tag(AIPreference.appleOnly)
                    Text("On-device model only").tag(AIPreference.localOnly)
                }
            } header: {
                Text("AI Engine")
            } footer: {
                Text("Automatic uses Apple Intelligence when your device supports it, and falls back to a downloaded on-device model otherwise. Everything runs locally either way.")
            }

            if !model.engineLinked {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Inference engine not installed").font(.subheadline.weight(.semibold))
                            Text("Add the MLX Swift package in Xcode to enable downloading and running on-device models. Steps are in PACKAGES.md.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }

            if dependencies.embeddingIndexStale {
                Section {
                    Button {
                        Task {
                            rebuilding = true
                            try? await dependencies.indexer.rebuildAll()
                            dependencies.markIndexRebuilt()
                            rebuilding = false
                        }
                    } label: {
                        HStack {
                            Label("Rebuild search index", systemImage: "arrow.triangle.2.circlepath")
                            if rebuilding { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(rebuilding)
                } footer: {
                    Text("Your embedding model changed. Rebuild the index so search uses the new one.")
                }
            }

            Section("Chat models") {
                ForEach(model.chatModels) { item in
                    modelRow(item, model: model)
                }
            }

            Section {
                embeddingRow(builtInSelected: model.selectedEmbeddingModelID == nil, model: model)
                ForEach(model.embeddingModels) { item in
                    modelRow(item, model: model)
                }
            } header: {
                Text("Search embedding")
            } footer: {
                Text("The model that turns your notes into searchable vectors. Built-in works everywhere with no download; EmbeddingGemma is more accurate. Switching takes effect after you restart and rebuild the index.")
            }
        }
        .alert("Download this model?", isPresented: $model.showConsent) {
            Button("Cancel", role: .cancel) { model.cancelConsent() }
            Button("Download") { model.confirmConsent() }
        } message: {
            Text("Model weights are fetched once from Hugging Face over the network. After that, everything runs fully on-device — nothing you record or ask ever leaves your iPhone.")
        }
    }

    private func embeddingRow(builtInSelected: Bool, model: AIModelsViewModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Built-in embedder").font(.headline)
                    if builtInSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.brand).font(.caption)
                    }
                }
                Text("NLEmbedding · on-device, no download").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !builtInSelected {
                Button("Use") { model.useBuiltInEmbedder() }
                    .font(.caption).buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func modelRow(_ item: LocalModel, model: AIModelsViewModel) -> some View {
        let state = model.state(for: item)
        let isSelected = item.kind == .chat
            ? model.selectedModelID == item.id
            : model.selectedEmbeddingModelID == item.id
        VStack(alignment: .leading, spacing: DS.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.displayName).font(.headline)
                        if isSelected, case .ready = state {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.brand).font(.caption)
                        }
                    }
                    Text("\(item.parameterHint) · \(item.approxDownloadDescription)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                trailing(state, item: item, model: model)
            }
            if case .downloading(let p) = state {
                ProgressView(value: p)
            }
            if case .failed(let msg) = state {
                Text(msg).font(.caption).foregroundStyle(.red)
            }
            if case .ready = state, !isSelected {
                Button(item.kind == .chat ? "Use this model" : "Use for search") {
                    if item.kind == .chat { model.select(item) } else { model.useForSearch(item) }
                }
                .font(.caption).buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func trailing(_ state: AIModelsViewModel.ModelState, item: LocalModel, model: AIModelsViewModel) -> some View {
        switch state {
        case .notDownloaded, .failed:
            Button {
                model.requestDownload(item)
            } label: {
                Image(systemName: "arrow.down.circle").font(.title2)
            }
            .buttonStyle(.plain).foregroundStyle(DS.brand)
            .disabled(!model.engineLinked)
        case .downloading:
            ProgressView()
        case .ready:
            Menu {
                Button(role: .destructive) {
                    Task { await model.delete(item) }
                } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title2).foregroundStyle(.secondary)
            }
        }
    }
}
