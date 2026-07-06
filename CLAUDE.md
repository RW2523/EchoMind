# EchoMind — private meeting memory for iPhone

Live transcription → saved sessions → on-device AI summaries → local RAG Q&A.
Privacy-first: NO network calls anywhere in V1. Min iOS 26.0, Swift 6, SwiftUI,
SwiftData, zero third-party dependencies. Full spec and phase plan: PLAN.md
(product spec) and BUILD_PLAN.md (file-level execution plan).

## Build & test
- Build: xcodebuild -scheme EchoMind -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
- Test:  xcodebuild -scheme EchoMind -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
- Always build after changes. Fix every error and warning you introduced.
- (Substitute any installed simulator name if iPhone 17 Pro is unavailable.)

## Architecture (MVVM + protocol-based services)
- Features/<Feature>/{View,ViewModel}
- Core/Audio          AVAudioEngine capture, session config, interruptions
- Core/Transcription  SpeechAnalyzer behind TranscriptionService protocol
- Core/AI             ModelGateway protocol, FoundationModelService,
                      TokenBudgeter, Summarizer
- Core/RAG            TextChunker, EmbeddingService protocol, VectorSearch,
                      RAGPipeline
- Core/Storage        SwiftData models + repository protocols
- Models/             pure data types

## Hard rules
- Every service = protocol + one implementation; view models depend on protocols.
- All Foundation Models calls go through TokenBudgeter. Never assume more than
  a 4,096-token context. Always handle exceededContextWindowSize. Budgets: PLAN.md §3.
- One fresh LanguageModelSession per call; never accumulate history in a session.
- No force unwraps. No singletons except AppDependencies (composition root).
- No new packages or network calls without asking me first.
- Never edit the .xcodeproj: new Swift files inside existing folders are picked
  up automatically (synchronized groups).
- Audio/speech/embedding work runs off the main thread; UI updates on @MainActor.
- Keep files under ~300 lines; split when larger.
- @Model classes never leave Core/Storage; repositories exchange Sendable
  snapshot structs from Models/. import SwiftData only in Core/Storage and App/.
