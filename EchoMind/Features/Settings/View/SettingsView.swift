import SwiftUI

/// Settings, privacy posture, and data controls (§7.1).
struct SettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: SettingsViewModel?
    @State private var showDelete = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .navigationTitle("Settings")
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model?.refreshAvailability() }
        }
        .task {
            if model == nil {
                let vm = SettingsViewModel(
                    availability: dependencies.availabilityMonitor,
                    usageService: dependencies.storageUsageService,
                    exportService: dependencies.dataExportService,
                    wipeService: dependencies.dataWipeService,
                    indexer: dependencies.indexer,
                    settingsStore: dependencies.settingsStore)
                model = vm
                await vm.load()
            } else {
                await model?.load()
            }
        }
    }

    private func content(_ model: SettingsViewModel) -> some View {
        List {
            Section("Apple Intelligence") {
                let status = model.statusText()
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title)
                    if let hint = status.hint {
                        Text(hint).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("On-Device AI") {
                NavigationLink {
                    AIModelsView()
                } label: {
                    Label("AI Models", systemImage: "cpu")
                }
            }

            Section("Transcription Language") {
                if model.locales.isEmpty {
                    Text(model.preferredLocaleIdentifier).foregroundStyle(.secondary)
                } else {
                    Picker("Preferred language", selection: Binding(
                        get: { model.preferredLocaleIdentifier },
                        set: { model.setLocale($0) })) {
                        ForEach(model.locales, id: \.identifier) { locale in
                            Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                                .tag(locale.identifier(.bcp47))
                        }
                    }
                }
            }

            Section {
                Toggle("Keep audio recordings", isOn: Binding(
                    get: { model.audioRetentionEnabled },
                    set: { model.setAudioRetention($0) }))
            } header: {
                Text("Recording Audio")
            } footer: {
                Text("Save each session's audio on-device so you can play it back and tap a line to jump there. Turning this off doesn't delete audio you've already kept.")
            }

            Section("Storage") {
                usageRow("Sessions", model.usage.sessionsBytes)
                usageRow("Documents", model.usage.documentsBytes)
                usageRow("Search index", model.usage.indexBytes)
                usageRow("Audio", model.usage.audioBytes)
                usageRow("Total", model.usage.totalBytes).fontWeight(.semibold)
            }

            Section("Knowledge Index") {
                Button {
                    Task { await model.rebuild(); dependencies.markIndexRebuilt() }
                } label: {
                    HStack {
                        Label("Rebuild Index", systemImage: "arrow.clockwise")
                        if model.isRebuilding { Spacer(); ProgressView() }
                    }
                }
                .disabled(model.isRebuilding)
            }

            Section("Your Data") {
                Button {
                    Task { await model.prepareExport() }
                } label: {
                    Label("Export All Data", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    showDelete = true
                } label: {
                    Label("Delete All Data", systemImage: "trash")
                }
            }

            Section("Recording") {
                Text(AppCopy.recordingConsent)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            DebugStorageSection()
            #endif
        }
        .sheet(isPresented: Binding(get: { model.showShare }, set: { model.showShare = $0 })) {
            ShareSheet(items: model.exportURLs)
        }
        .sheet(isPresented: $showDelete) {
            DeleteAllDataView { Task { await model.deleteAll() } }
        }
    }

    private func usageRow(_ label: String, _ bytes: Int64) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .foregroundStyle(.secondary)
        }
    }
}
