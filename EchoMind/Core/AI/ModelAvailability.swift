import Foundation
import FoundationModels

/// Device tier (spec §2). The three unavailable reasons stay distinct end-to-end
/// so Settings can show specific, actionable copy.
nonisolated enum AvailabilityStatus: Equatable, Sendable {
    case tierA
    case tierB(TierBReason)

    nonisolated enum TierBReason: Equatable, Sendable {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case unknown
    }
}

@MainActor
protocol AvailabilityProviding: AnyObject {
    var status: AvailabilityStatus { get }
    func refresh()
}

/// Maps `SystemLanguageModel.default.availability`. Refresh at launch and on
/// scenePhase .active so toggling Apple Intelligence reflects without relaunch.
@Observable
@MainActor
final class ModelAvailabilityMonitor: AvailabilityProviding {
    private(set) var status: AvailabilityStatus = .tierB(.unknown)

    init() { refresh() }

    func refresh() {
        switch SystemLanguageModel.default.availability {
        case .available:
            status = .tierA
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: status = .tierB(.deviceNotEligible)
            case .appleIntelligenceNotEnabled: status = .tierB(.appleIntelligenceNotEnabled)
            case .modelNotReady: status = .tierB(.modelNotReady)
            @unknown default: status = .tierB(.unknown)
            }
        }
    }
}
