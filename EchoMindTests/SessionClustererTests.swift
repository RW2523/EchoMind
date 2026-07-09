import Testing
import Foundation
@testable import EchoMind

@Suite struct SessionClustererTests {
    /// 12 sessions across 4 clearly-separated concept groups (4D axis directions
    /// with small jitter), 3 per group.
    private func fixture() -> [SessionVector] {
        let bases: [[Float]] = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
        var out: [SessionVector] = []
        for (g, base) in bases.enumerated() {
            for k in 0..<3 {
                var v = base
                v[(g + k) % 4] += 0.06 * Float(k + 1)   // small within-group jitter
                out.append(SessionVector(id: UUID(), vector: ClusterMath.normalize(v)))
            }
        }
        return out
    }

    private func memberSets(_ clusters: [SessionCluster]) -> Set<Set<UUID>> {
        Set(clusters.map { Set($0.memberIDs) })
    }

    @Test func clustersFourConceptGroups() {
        let clusters = SessionClusterer(threshold: 0.55).cluster(fixture())
        #expect(clusters.count == 4)
        // ≥10/12 correctly grouped → here all 4 clusters hold exactly 3.
        #expect(clusters.filter { $0.memberIDs.count == 3 }.count == 4)
    }

    @Test func orderInvariant() {
        let clusterer = SessionClusterer()
        let vectors = fixture()
        #expect(memberSets(clusterer.cluster(vectors)) == memberSets(clusterer.cluster(vectors.reversed())))
    }

    @Test func distinctVectorStartsNewCluster() {
        let clusterer = SessionClusterer()
        var clusters: [SessionCluster] = []
        clusterer.assign(SessionVector(id: UUID(), vector: [1, 0, 0, 0]), to: &clusters)
        clusterer.assign(SessionVector(id: UUID(), vector: [0, 1, 0, 0]), to: &clusters)
        #expect(clusters.count == 2)
    }

    @Test func similarVectorJoinsExistingCluster() {
        let clusterer = SessionClusterer()
        var clusters: [SessionCluster] = []
        let a = UUID(), b = UUID()
        clusterer.assign(SessionVector(id: a, vector: ClusterMath.normalize([1, 0.1, 0, 0])), to: &clusters)
        clusterer.assign(SessionVector(id: b, vector: ClusterMath.normalize([1, 0.2, 0, 0])), to: &clusters)
        #expect(clusters.count == 1)
        #expect(Set(clusters[0].memberIDs) == Set([a, b]))
    }

    @Test func centroidIsUnitLengthAfterMerge() {
        let clusterer = SessionClusterer()
        var clusters: [SessionCluster] = []
        clusterer.assign(SessionVector(id: UUID(), vector: ClusterMath.normalize([1, 0.1, 0, 0])), to: &clusters)
        clusterer.assign(SessionVector(id: UUID(), vector: ClusterMath.normalize([1, 0.2, 0, 0])), to: &clusters)
        let c = clusters[0].centroid
        #expect(abs(ClusterMath.dot(c, c) - 1) < 1e-4)   // normalized
    }

    @Test func emptyInputYieldsNoClusters() {
        #expect(SessionClusterer().cluster([]).isEmpty)
    }

    @Test func meanNormalizedIsUnitLength() throws {
        let m = try #require(ClusterMath.meanNormalized([[1, 0], [0, 1]]))
        #expect(abs(ClusterMath.dot(m, m) - 1) < 1e-5)
        #expect(ClusterMath.meanNormalized([[1, 0], [1, 0, 0]]) == nil)   // mismatched dims
    }
}
