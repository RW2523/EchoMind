import Foundation
import Speech

@MainActor
@Observable
final class SettingsViewModel {
    var usage: StorageUsage = .zero
    var isRebuilding = false
    var isDeleting = false
    var exportURLs: [URL] = []
    var showShare = false
    var locales: [Locale] = []
    var preferredLocaleIdentifier: String
    var audioRetentionEnabled: Bool

    let availability: any AvailabilityProviding

    private let usageService: any StorageUsageService
    private let exportService: any DataExportService
    private let wipeService: any DataWipeService
    private let indexer: any IndexerService
    private let settingsStore: AppSettingsStore

    init(availability: any AvailabilityProviding,
         usageService: any StorageUsageService,
         exportService: any DataExportService,
         wipeService: any DataWipeService,
         indexer: any IndexerService,
         settingsStore: AppSettingsStore) {
        self.availability = availability
        self.usageService = usageService
        self.exportService = exportService
        self.wipeService = wipeService
        self.indexer = indexer
        self.settingsStore = settingsStore
        self.preferredLocaleIdentifier = settingsStore.preferredLocale ?? Locale.current.identifier(.bcp47)
        self.audioRetentionEnabled = settingsStore.audioRetentionEnabled
    }

    func setAudioRetention(_ enabled: Bool) {
        audioRetentionEnabled = enabled
        settingsStore.setAudioRetentionEnabled(enabled)
    }

    func load() async {
        availability.refresh()
        usage = (try? await usageService.usage()) ?? .zero
        locales = await SpeechTranscriber.supportedLocales
    }

    func refreshAvailability() { availability.refresh() }

    func setLocale(_ identifier: String) {
        preferredLocaleIdentifier = identifier
        settingsStore.setPreferredLocale(identifier)
    }

    func rebuild() async {
        isRebuilding = true
        try? await indexer.rebuildAll()
        isRebuilding = false
        await load()
    }

    func prepareExport() async {
        exportURLs = (try? await exportService.exportAll()) ?? []
        showShare = !exportURLs.isEmpty
    }

    func deleteAll() async {
        isDeleting = true
        try? await wipeService.deleteAllData()
        isDeleting = false
        await load()
    }

    func statusText() -> (title: String, hint: String?) {
        switch availability.status {
        case .tierA:
            return ("Apple Intelligence ready", nil)
        case .tierB(.deviceNotEligible):
            return ("Not available", "This iPhone doesn't support Apple Intelligence.")
        case .tierB(.appleIntelligenceNotEnabled):
            return ("Off", "Enable Apple Intelligence in iOS Settings for summaries and answers.")
        case .tierB(.modelNotReady):
            return ("Preparing", "The on-device model is still downloading. Try again later.")
        case .tierB(.unknown):
            return ("Unavailable", nil)
        }
    }
}
