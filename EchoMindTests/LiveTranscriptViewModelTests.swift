import Testing
import Foundation
@testable import EchoMind

@MainActor
@Suite struct LiveTranscriptViewModelTests {

    private func waitUntil(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeViewModel(updates: [TranscriptionUpdate],
                               permissions: StubPermissionManager = .init(microphone: .granted, speech: .granted),
                               assets: StubSpeechAssetManager = .init())
    throws -> (LiveTranscriptViewModel, any SessionRepository) {
        let container = try ModelContainerFactory.inMemory()
        let sessions = SwiftDataSessionRepository(modelContainer: container)
        let vm = LiveTranscriptViewModel(
            audio: MockAudioCapturing(),
            transcription: MockTranscriptionService(updates: updates),
            assets: assets, sessions: sessions, permissions: permissions,
            locale: Locale(identifier: "en_US"))
        return (vm, sessions)
    }

    @Test func finalizedUpdatesAppendLinesAndPersistSegments() async throws {
        let (vm, sessions) = try makeViewModel(updates: [
            .init(text: "Hello", isFinal: false, audioRange: 0...1),
            .init(text: "Hello world.", isFinal: true, audioRange: 0...2),
            .init(text: "Second sentence.", isFinal: true, audioRange: 2...4),
        ])
        await vm.startTapped()
        await waitUntil { vm.finalizedLines.count == 2 }

        #expect(vm.finalizedLines.map(\.text) == ["Hello world.", "Second sentence."])
        #expect(vm.volatileText == "")

        // Persisted incrementally — segments are in the store before Stop.
        let all = try await sessions.fetchAll()
        #expect(all.count == 1)
        let segments = try await sessions.fetchSegments(sessionId: all[0].id)
        #expect(segments.count == 2)
    }

    @Test func volatileTextShownThenClearedByFinal() async throws {
        let (vm, _) = try makeViewModel(updates: [
            .init(text: "partial", isFinal: false, audioRange: 0...1),
        ])
        await vm.startTapped()
        await waitUntil { vm.volatileText == "partial" }
        #expect(vm.volatileText == "partial")
        #expect(vm.finalizedLines.isEmpty)
    }

    @Test func stopFinalizesSessionTitleAndDuration() async throws {
        let (vm, sessions) = try makeViewModel(updates: [
            .init(text: "One.", isFinal: true, audioRange: 0...1),
        ])
        await vm.startTapped()
        await waitUntil { vm.finalizedLines.count == 1 }
        await vm.stopTapped()
        #expect(vm.phase == .idle)
        let session = try await sessions.fetchAll().first
        #expect(session?.title.hasPrefix("Meeting ") == true)
    }

    @Test func micDeniedFailsBeforeCreatingSession() async throws {
        let (vm, sessions) = try makeViewModel(
            updates: [],
            permissions: .init(microphone: .denied, speech: .granted))
        await vm.startTapped()
        #expect(vm.phase == .failed(.microphoneDenied))
        #expect(try await sessions.fetchAll().isEmpty)
    }

    @Test func unsupportedLocaleFails() async throws {
        let (vm, _) = try makeViewModel(
            updates: [],
            assets: .init(configuredStatus: .unsupportedLocale))
        await vm.startTapped()
        if case .failed(.localeUnsupported) = vm.phase {} else {
            Issue.record("expected localeUnsupported, got \(vm.phase)")
        }
    }
}
