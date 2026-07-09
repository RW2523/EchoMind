import Testing
@testable import EchoMind

@Suite struct TurnEndpointerTests {
    @Test func doesNotEndpointBeforeAnySpeech() {
        var e = TurnEndpointer(holdInterval: 0.8)
        e.update(transcript: "", now: 0)
        #expect(e.shouldEndTurn(now: 10) == false)
    }

    @Test func endpointsAfterSilenceHold() {
        var e = TurnEndpointer(holdInterval: 0.8)
        e.update(transcript: "hello", now: 1.0)
        #expect(e.shouldEndTurn(now: 1.5) == false)   // 0.5s < hold
        #expect(e.shouldEndTurn(now: 1.8) == true)    // 0.8s ≥ hold
    }

    @Test func continuedSpeechResetsTheHold() {
        var e = TurnEndpointer(holdInterval: 0.8)
        e.update(transcript: "hello", now: 1.0)
        e.update(transcript: "hello there", now: 1.5)     // still talking
        #expect(e.shouldEndTurn(now: 2.0) == false)       // only 0.5s since change
        #expect(e.shouldEndTurn(now: 2.3) == true)        // 0.8s since last change
    }

    @Test func hasSpeechTracksNonEmptyTranscript() {
        var e = TurnEndpointer()
        #expect(e.hasSpeech == false)
        e.update(transcript: "hi", now: 0)
        #expect(e.hasSpeech == true)
    }

    @Test func resetClearsEverything() {
        var e = TurnEndpointer(holdInterval: 0.8)
        e.update(transcript: "hi", now: 1.0)
        e.reset()
        #expect(e.hasSpeech == false)
        #expect(e.shouldEndTurn(now: 100) == false)
    }
}

@Suite struct SpeechSynthesizerResolverTests {
    let resolver = SpeechSynthesizerResolver()
    let kokoro = "kokoro-82m"
    let chat = "qwen2.5-1.5b-instruct-4bit"

    @Test func fallsBackToSystemWhenPackageAbsent() {
        #expect(resolver.choice(selectedVoiceModelID: kokoro, isDownloaded: { _ in true },
                                packageLinked: false) == .systemAV)
    }

    @Test func fallsBackWhenNoneSelected() {
        #expect(resolver.choice(selectedVoiceModelID: nil, isDownloaded: { _ in true },
                                packageLinked: true) == .systemAV)
    }

    @Test func fallsBackWhenNotDownloaded() {
        #expect(resolver.choice(selectedVoiceModelID: kokoro, isDownloaded: { _ in false },
                                packageLinked: true) == .systemAV)
    }

    @Test func rejectsNonTTSModel() {
        #expect(resolver.choice(selectedVoiceModelID: chat, isDownloaded: { _ in true },
                                packageLinked: true) == .systemAV)
    }

    @Test func resolvesKokoroWhenReady() {
        #expect(resolver.choice(selectedVoiceModelID: kokoro, isDownloaded: { $0 == self.kokoro },
                                packageLinked: true) == .kokoro(modelID: kokoro))
    }

    @Test func identitiesAreStable() {
        #expect(VoiceChoice.systemAV.identity == "av.system")
        #expect(VoiceChoice.kokoro(modelID: kokoro).identity == "kokoro:\(kokoro)")
    }
}
