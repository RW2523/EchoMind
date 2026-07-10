import Foundation
@testable import EchoMind

/// Whether the OS sentence-embedding model asset is installed. Fresh CI simulator
/// images (GitHub's macOS runners) ship WITHOUT it — `NLEmbedding` then throws
/// `.unavailable` — so NLEmbedding-dependent gates skip there instead of failing.
/// Local Macs and real devices have the asset, so the gates still guard where the
/// numbers are meaningful.
enum EmbeddingTestSupport {
    static func modelAvailable() async -> Bool {
        (try? await NLEmbeddingService().embed(["probe"]).first) != nil
    }
}
