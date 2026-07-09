import Foundation

/// Groups meetings by concept (R2). A session's vector is the normalized mean of
/// its chunk embeddings (already stored — zero extra inference); similar meetings
/// land in the same cluster. Pure, deterministic, and **order-invariant** (inputs
/// are canonically sorted before greedy assignment), so the same set of sessions
/// always yields the same groups regardless of insertion order. Math owns the
/// grouping; the LLM only names clusters (see `MeetingClassifier`).
nonisolated struct SessionVector: Sendable, Equatable {
    let id: UUID
    let vector: [Float]        // L2-normalized
}

nonisolated struct SessionCluster: Sendable, Equatable {
    var id: Int
    var memberIDs: [UUID]
    var label: String
    var sum: [Float]           // running sum of member vectors

    var centroid: [Float] { ClusterMath.normalize(sum) }
}

nonisolated struct SessionClusterer: Sendable {
    /// Cosine threshold to join an existing cluster (tuned via fixtures; default 0.55).
    let threshold: Float

    init(threshold: Float = 0.55) { self.threshold = threshold }

    /// Cluster all vectors from scratch, deterministically.
    func cluster(_ vectors: [SessionVector]) -> [SessionCluster] {
        var clusters: [SessionCluster] = []
        for vector in vectors.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            assign(vector, to: &clusters)
        }
        return clusters
    }

    /// Incrementally place one vector: join the nearest cluster at/above threshold,
    /// else start a new one. Returns the cluster id it landed in.
    @discardableResult
    func assign(_ vector: SessionVector, to clusters: inout [SessionCluster]) -> Int {
        var bestIndex = -1
        var bestSim = threshold
        for (i, cluster) in clusters.enumerated() {
            let sim = ClusterMath.dot(vector.vector, cluster.centroid)
            if sim >= bestSim {
                bestSim = sim
                bestIndex = i
            }
        }
        if bestIndex >= 0 {
            clusters[bestIndex].memberIDs.append(vector.id)
            clusters[bestIndex].sum = ClusterMath.add(clusters[bestIndex].sum, vector.vector)
            return clusters[bestIndex].id
        }
        let newID = (clusters.map(\.id).max() ?? -1) + 1
        clusters.append(SessionCluster(id: newID, memberIDs: [vector.id], label: "", sum: vector.vector))
        return newID
    }
}

nonisolated enum ClusterMath {
    static func normalize(_ v: [Float]) -> [Float] {
        var norm: Float = 0
        for x in v { norm += x * x }
        norm = norm.squareRoot()
        guard norm > 1e-6 else { return v }
        return v.map { $0 / norm }
    }

    static func meanNormalized(_ vectors: [[Float]]) -> [Float]? {
        guard let dim = vectors.first?.count, dim > 0,
              vectors.allSatisfy({ $0.count == dim }) else { return nil }
        var sum = [Float](repeating: 0, count: dim)
        for v in vectors { for i in 0..<dim { sum[i] += v[i] } }
        return normalize(sum)
    }

    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var s: Float = 0
        for i in 0..<a.count { s += a[i] * b[i] }
        return s
    }

    static func add(_ a: [Float], _ b: [Float]) -> [Float] {
        guard a.count == b.count else { return a }
        var out = a
        for i in 0..<a.count { out[i] += b[i] }
        return out
    }
}
