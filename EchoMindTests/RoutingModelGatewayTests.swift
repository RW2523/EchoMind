import Testing
import Foundation
import FoundationModels
@testable import EchoMind

/// Records which backend a routed call landed on via its `respond` return value.
private actor RecordingGateway: ModelGateway {
    let name: String
    init(name: String) { self.name = name }

    func respond(instructions: String, prompt: String, maxOutputTokens: Int) async throws -> String { name }

    func generate<T: Generable & Sendable>(instructions: String, prompt: String, as type: T.Type, maxOutputTokens: Int) async throws -> T {
        throw ModelGatewayError.generationFailed(name)
    }
}

@Suite struct RoutingModelGatewayTests {
    private func makeGateway(availability: AvailabilityStatus,
                             localModelID: String?,
                             preference: AIPreference,
                             thermal: ThermalLevel,
                             hasLocal: Bool) -> RoutingModelGateway {
        RoutingModelGateway(
            apple: RecordingGateway(name: "apple"),
            local: hasLocal ? RecordingGateway(name: "local") : nil,
            context: {
                .init(availability: availability, localModelID: localModelID,
                      preference: preference, thermal: thermal)
            })
    }

    @Test func routesToAppleWhenEligible() async throws {
        let g = makeGateway(availability: .tierA, localModelID: "m", preference: .auto,
                            thermal: .nominal, hasLocal: true)
        #expect(try await g.respond(instructions: "", prompt: "", maxOutputTokens: 8) == "apple")
    }

    @Test func routesToLocalWhenAppleUnavailable() async throws {
        let g = makeGateway(availability: .tierB(.deviceNotEligible), localModelID: "m",
                            preference: .auto, thermal: .nominal, hasLocal: true)
        #expect(try await g.respond(instructions: "", prompt: "", maxOutputTokens: 8) == "local")
    }

    @Test func throwsModelUnavailableWhenNothingCanRun() async {
        let g = makeGateway(availability: .tierB(.appleIntelligenceNotEnabled), localModelID: nil,
                            preference: .auto, thermal: .nominal, hasLocal: false)
        await #expect(throws: ModelGatewayError.self) {
            _ = try await g.respond(instructions: "", prompt: "", maxOutputTokens: 8)
        }
    }

    @Test func suppressesLocalWhenNoLocalGatewayWired() async {
        // localModelID is set, but no local gateway exists → must not route local.
        let g = makeGateway(availability: .tierB(.deviceNotEligible), localModelID: "m",
                            preference: .localOnly, thermal: .nominal, hasLocal: false)
        await #expect(throws: ModelGatewayError.self) {
            _ = try await g.respond(instructions: "", prompt: "", maxOutputTokens: 8)
        }
    }
}
