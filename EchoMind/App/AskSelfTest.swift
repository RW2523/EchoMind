import Foundation

#if DEBUG
/// DEBUG-only end-to-end check, triggered by the `--selftest-ask` launch
/// argument: seeds + indexes the sample document, then runs a conversational
/// and a grounded question through the real RAG pipeline and prints results.
/// Verifies embeddings + FoundationModels work on the current device/simulator.
enum AskSelfTest {
    static func runIfRequested(_ dependencies: AppDependencies) async {
        guard CommandLine.arguments.contains("--selftest-ask") else { return }
        print("[SelfTest] availability = \(dependencies.availabilityMonitor.status)")

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
        print("[SelfTest] done")
    }

    private static func ask(_ dependencies: AppDependencies, _ question: String) async {
        do {
            let result = try await dependencies.ragService.ask(question)
            switch result {
            case .conversational(let answer):
                print("[SelfTest] Q:\"\(question)\" -> CONVERSATIONAL: \(answer)")
            case .grounded(let answer, let sources):
                print("[SelfTest] Q:\"\(question)\" -> GROUNDED (\(sources.count) src): \(answer)")
            case .retrievalOnly(let passages, let reason):
                print("[SelfTest] Q:\"\(question)\" -> RETRIEVAL-ONLY (\(passages.count) passages, \(reason))")
            }
        } catch {
            print("[SelfTest] Q:\"\(question)\" failed: \(error)")
        }
    }
}
#endif
