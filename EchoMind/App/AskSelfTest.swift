import Foundation
import Speech

#if DEBUG
/// DEBUG-only end-to-end check, triggered by the `--selftest-ask` launch
/// argument: seeds + indexes the sample document, then runs a conversational
/// and a grounded question through the real RAG pipeline and prints results.
/// Verifies embeddings + FoundationModels work on the current device/simulator.
enum AskSelfTest {
    static func runIfRequested(_ dependencies: AppDependencies) async {
        guard CommandLine.arguments.contains("--selftest-ask") else { return }
        print("[SelfTest] availability = \(dependencies.availabilityMonitor.status)")

        // Speech locale diagnostics (why "transcription isn't available for <locale>").
        let supported = await SpeechTranscriber.supportedLocales
        let installed = await SpeechTranscriber.installedLocales
        let current = Locale.current
        print("[SelfTest] currentLocale=\(current.identifier) bcp47=\(current.identifier(.bcp47))")
        print("[SelfTest] supportedLocales(\(supported.count))=\(supported.map { $0.identifier(.bcp47) }.prefix(8))")
        print("[SelfTest] installedLocales(\(installed.count))=\(installed.map { $0.identifier(.bcp47) }.prefix(8))")
        if let status = try? await dependencies.speechAssets.status(for: current) {
            print("[SelfTest] assetStatus(current)=\(status)")
        }

        let id = UUID()
        do {
            try await dependencies.documentRepository.create(
                DocumentSnapshot(id: id, title: DebugFixtures.sampleDocumentTitle, fileName: "handbook.md",
                                 fileType: .md, textContent: DebugFixtures.sampleDocumentText,
                                 pageBreaks: [], status: .imported))
            try await dependencies.indexer.indexDocument(id: id)
            print("[SelfTest] indexed sample document OK")
        } catch {
            print("[SelfTest] indexing failed: \(error)")
        }

        await ask(dependencies, "Hi")
        await ask(dependencies, "what is the refund policy?")
        await ask(dependencies, "who leads the security team?")
        // Synthesis probe: the answer must COMBINE separate passages, not quote one.
        await ask(dependencies, "what should a new employee know about refunds and security?")
        // Premise-correction probe (field bug): a wrong user assertion must be
        // corrected from the passages, not adopted or agreed with.
        await ask(dependencies, "John leads the security team, right?")
        // Anti-parrot probe (field bug): after a full answer sits in history, a NEW
        // narrow question must get a fresh answer, not the previous one re-emitted.
        let priorAnswer = "Customers may request a refund within 30 days of purchase. Refunds are processed within 5 business days to the original payment method. Digital goods are non-refundable once downloaded."
        let history = [ChatTurn(role: .user, content: "what is the refund policy?"),
                       ChatTurn(role: .assistant, content: priorAnswer)]
        do {
            let result = try await dependencies.ragService.ask("are digital goods refundable?", history: history)
            let text = result.spokenText
            let parroted = RAGPipeline.isNearDuplicate(text, of: priorAnswer)
            print("[SelfTest] FOLLOW-UP \(parroted ? "PARROTED ✗" : "fresh ✓"): \(text.prefix(140))")
        } catch {
            print("[SelfTest] FOLLOW-UP failed: \(error)")
        }

        // Anti-confabulation probes (college field-report patterns). A second
        // document also exercises cross-document attribution.
        let trapId = UUID()
        do {
            try await dependencies.documentRepository.create(
                DocumentSnapshot(id: trapId, title: DebugFixtures.confabulationTrapTitle,
                                 fileName: "falcon.md", fileType: .md,
                                 textContent: DebugFixtures.confabulationTrapText,
                                 pageBreaks: [], status: .imported))
            try await dependencies.indexer.indexDocument(id: trapId)
            print("[SelfTest] indexed confabulation-trap document OK")
        } catch {
            print("[SelfTest] trap indexing failed: \(error)")
        }
        // Nearby-number trap: must answer 5,800 / 5,000 / 400 / 400 — never "22,000".
        await ask(dependencies, "how many clips are in the falcon dataset and how are they split?")
        // Negation/attribution trap: the correct answer is the PROCESSOR stores it.
        await ask(dependencies, "does falcon store credit card details?")
        // Absent-term trap: must be NOT-FOUND, never a confabulated explanation.
        await ask(dependencies, "what is the XQRT-9 module in my documents?")

        // Voice text path: the SAME streaming pipeline the voice agent consumes
        // (shared retrieveContext + streamed prose). Proves retrieval + streaming
        // generation end-to-end; only mic/TTS remain device-only.
        if let streaming = dependencies.ragService as? StreamingRAGService {
            var final = ""
            var chunks = 0
            do {
                for try await cumulative in streaming.askStreaming("what is the refund policy?", history: []) {
                    final = cumulative
                    chunks += 1
                }
                print("[SelfTest] VOICE-STREAM ok (\(chunks) chunks, \(final.count) chars): \(final.prefix(140))")
            } catch {
                print("[SelfTest] VOICE-STREAM failed: \(error)")
            }
        }
        print("[SelfTest] done")
    }

    private static func ask(_ dependencies: AppDependencies, _ question: String) async {
        do {
            let result = try await dependencies.ragService.ask(question, history: [])
            switch result {
            case .conversational(let answer, let followUps):
                print("[SelfTest] Q:\"\(question)\" -> CONVERSATIONAL: \(answer) · followUps=\(followUps)")
            case .grounded(let answer, let sources, let followUps):
                print("[SelfTest] Q:\"\(question)\" -> GROUNDED (\(sources.count) src): \(answer) · followUps=\(followUps)")
            case .notFound(let answer, _):
                print("[SelfTest] Q:\"\(question)\" -> NOT-FOUND: \(answer.prefix(140))")
            case .retrievalOnly(let passages, let reason):
                print("[SelfTest] Q:\"\(question)\" -> RETRIEVAL-ONLY (\(passages.count) passages, \(reason))")
            }
        } catch {
            print("[SelfTest] Q:\"\(question)\" failed: \(error)")
        }
    }
}
#endif
