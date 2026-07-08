import Testing
@testable import EchoMind

@Suite struct FeatureRouterTests {
    let router = FeatureRouter()
    let modelID = LocalModelCatalog.default.id

    @Test func autoPrefersAppleWhenEligible() {
        let b = router.backend(availability: .tierA, localModelID: modelID,
                               preference: .auto, thermal: .nominal)
        #expect(b == .appleFoundation)
    }

    @Test func autoFallsBackToLocalWhenAppleUnavailable() {
        let b = router.backend(availability: .tierB(.deviceNotEligible), localModelID: modelID,
                               preference: .auto, thermal: .nominal)
        #expect(b == .local(modelID: modelID))
    }

    @Test func autoIsRetrievalOnlyWithNoModelAndNoApple() {
        let b = router.backend(availability: .tierB(.appleIntelligenceNotEnabled), localModelID: nil,
                               preference: .auto, thermal: .nominal)
        #expect(b == .retrievalOnly)
    }

    @Test func preferLocalUsesLocalEvenWhenAppleEligible() {
        let b = router.backend(availability: .tierA, localModelID: modelID,
                               preference: .preferLocal, thermal: .nominal)
        #expect(b == .local(modelID: modelID))
    }

    @Test func preferLocalFallsBackToAppleWithoutModel() {
        let b = router.backend(availability: .tierA, localModelID: nil,
                               preference: .preferLocal, thermal: .nominal)
        #expect(b == .appleFoundation)
    }

    @Test func appleOnlyNeverUsesLocal() {
        let b = router.backend(availability: .tierB(.deviceNotEligible), localModelID: modelID,
                               preference: .appleOnly, thermal: .nominal)
        #expect(b == .retrievalOnly)
    }

    @Test func localOnlyNeverUsesApple() {
        let b = router.backend(availability: .tierA, localModelID: nil,
                               preference: .localOnly, thermal: .nominal)
        #expect(b == .retrievalOnly)
    }

    @Test func criticalThermalForcesRetrievalOnly() {
        let b = router.backend(availability: .tierA, localModelID: modelID,
                               preference: .localOnly, thermal: .critical)
        #expect(b == .retrievalOnly)
    }

    @Test func seriousThermalKeepsAppleButSkipsLocalInAuto() {
        let b = router.backend(availability: .tierB(.deviceNotEligible), localModelID: modelID,
                               preference: .auto, thermal: .serious)
        #expect(b == .retrievalOnly)   // local suppressed under serious heat
    }

    @Test func contextSizeMatchesCatalogForLocal() {
        let size = router.contextSize(for: .local(modelID: modelID))
        #expect(size == LocalModelCatalog.default.contextSize)
    }

    @Test func contextSizeFallsBackForApple() {
        #expect(router.contextSize(for: .appleFoundation) == TokenBudgeter.fallbackContextSize)
    }
}
