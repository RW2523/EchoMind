import Testing
@testable import EchoMind

@Suite struct PermissionManagerTests {

    @Test func stubReportsConfiguredStates() async {
        let stub = StubPermissionManager(microphone: .granted, speech: .denied)
        #expect(stub.microphoneState() == .granted)
        #expect(stub.speechState() == .denied)
        #expect(await stub.requestMicrophone() == .granted)
        #expect(await stub.requestSpeech() == .denied)
    }

    @Test func stubDefaultsToNotDetermined() {
        let stub = StubPermissionManager()
        #expect(stub.microphoneState() == .notDetermined)
        #expect(stub.speechState() == .notDetermined)
    }

    @Test func liveManagerReadsWithoutCrashing() {
        // On the simulator these are `.notDetermined`; the point is that the
        // status reads are side-effect-free and never trap.
        let manager = PermissionManager()
        _ = manager.microphoneState()
        _ = manager.speechState()
    }
}
