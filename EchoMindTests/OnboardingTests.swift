import Testing
import Foundation
import SwiftData
@testable import EchoMind

@MainActor
@Suite struct OnboardingTests {

    private func makeViewModel() throws -> (OnboardingViewModel, AppSettingsStore, () -> Bool) {
        let container = try ModelContainerFactory.inMemory()
        let store = AppSettingsStore(container: container)
        var completed = false
        let vm = OnboardingViewModel(settingsStore: store) { completed = true }
        return (vm, store, { completed })
    }

    @Test func advancesThroughStepsInOrder() throws {
        let (vm, _, _) = try makeViewModel()
        #expect(vm.step == .welcome)
        vm.advance(); #expect(vm.step == .privacy)
        vm.advance(); #expect(vm.step == .consent)
        vm.advance(); #expect(vm.step == .permissionPriming)
    }

    @Test func consentWrittenOnLeavingConsentStep() throws {
        let (vm, store, _) = try makeViewModel()
        vm.advance() // privacy
        vm.advance() // consent
        #expect(store.consentAcknowledged == false)
        vm.advance() // leaves consent -> permissionPriming
        #expect(store.consentAcknowledged == true)
    }

    @Test func onboardingCompleteOnlyWrittenAtEnd() throws {
        let (vm, store, completed) = try makeViewModel()
        vm.advance(); vm.advance(); vm.advance() // now at permissionPriming
        #expect(store.onboardingComplete == false)
        #expect(completed() == false)
        vm.advance() // final step
        #expect(store.onboardingComplete == true)
        #expect(completed() == true)
    }

    @Test func backNavigationClampsAtWelcome() throws {
        let (vm, _, _) = try makeViewModel()
        vm.advance() // privacy
        vm.goBack(); #expect(vm.step == .welcome)
        vm.goBack(); #expect(vm.step == .welcome) // no-op at first step
    }
}
