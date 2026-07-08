import Foundation

/// Which inference backend answers a request (V2 §B4). Pure decision logic — no
/// I/O, no framework types — so it's exhaustively unit-testable. Keeps Apple
/// Foundation Models primary on eligible devices while letting a downloaded local
/// model serve everyone else (or everyone, by preference), and degrades to
/// retrieval-only under thermal pressure rather than cooking the phone.
nonisolated enum InferenceBackend: Equatable, Sendable {
    case appleFoundation
    case local(modelID: String)
    case retrievalOnly          // no generator available/allowed right now
}

/// User-facing preference (Settings). `auto` is the shipping default.
nonisolated enum AIPreference: String, CaseIterable, Sendable, Codable {
    case auto           // Apple if eligible, else local
    case preferLocal    // local if ready, else Apple
    case appleOnly
    case localOnly
}

/// Thermal gate mirrors `ProcessInfo.ThermalState` without importing it, so tests
/// can drive every branch.
nonisolated enum ThermalLevel: Sendable {
    case nominal, fair, serious, critical
}

nonisolated struct FeatureRouter: Sendable {
    /// Decide the backend for a generation request.
    /// - localModelID: id of a downloaded, loadable model, or nil if none.
    func backend(availability: AvailabilityStatus,
                 localModelID: String?,
                 preference: AIPreference,
                 thermal: ThermalLevel) -> InferenceBackend {
        // Under critical heat, refuse to run any generator; retrieval still works.
        if thermal == .critical { return .retrievalOnly }

        let appleReady = availability == .tierA
        // Serious (not critical) heat: keep Apple FM (NPU, cool) but avoid spinning
        // up the heavier local GPU path unless the user demands local-only.
        let localAllowedUnderHeat = thermal != .serious

        func local() -> InferenceBackend? {
            guard let id = localModelID, localAllowedUnderHeat else { return nil }
            return .local(modelID: id)
        }

        switch preference {
        case .appleOnly:
            return appleReady ? .appleFoundation : .retrievalOnly
        case .localOnly:
            return local() ?? .retrievalOnly
        case .auto:
            if appleReady { return .appleFoundation }
            return local() ?? .retrievalOnly
        case .preferLocal:
            return local() ?? (appleReady ? .appleFoundation : .retrievalOnly)
        }
    }

    /// Context window to budget against for the chosen backend.
    func contextSize(for backend: InferenceBackend) -> Int {
        switch backend {
        case .appleFoundation, .retrievalOnly:
            return TokenBudgeter.fallbackContextSize
        case .local(let id):
            return LocalModelCatalog.model(id: id)?.contextSize ?? TokenBudgeter.fallbackContextSize
        }
    }
}

extension ThermalLevel {
    /// Bridge from `ProcessInfo.ThermalState` at the call site.
    init(processInfo state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .fair
        }
    }
}
