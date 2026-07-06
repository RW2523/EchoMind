import Testing
import AVFoundation
@testable import EchoMind

@Suite struct AudioInterruptionStateMachineTests {
    let machine = AudioInterruptionStateMachine()

    @Test func interruptionBeganWhileRecordingPauses() {
        #expect(machine.handle(.interruptionBegan, while: .recording) == [.pauseCapture])
    }

    @Test func interruptionBeganWhileIdleIsNoOp() {
        #expect(machine.handle(.interruptionBegan, while: .idle).isEmpty)
    }

    @Test func interruptionEndedWithResumeResumes() {
        #expect(machine.handle(.interruptionEnded(shouldResume: true), while: .pausedByInterruption) == [.resumeCapture])
    }

    @Test func interruptionEndedWithoutResumeStaysPaused() {
        #expect(machine.handle(.interruptionEnded(shouldResume: false), while: .pausedByInterruption) == [.surfacePausedState])
    }

    @Test func interruptionEndedWhileNotPausedIsNoOp() {
        #expect(machine.handle(.interruptionEnded(shouldResume: true), while: .recording).isEmpty)
    }

    @Test func newDeviceWhileRecordingReinstallsTap() {
        #expect(machine.handle(.routeChanged(reason: .newDeviceAvailable), while: .recording) == [.reinstallTap])
    }

    @Test func oldDeviceUnavailableWhileRecordingReinstallsTap() {
        #expect(machine.handle(.routeChanged(reason: .oldDeviceUnavailable), while: .recording) == [.reinstallTap])
    }

    @Test func routeChangeWhileIdleIsNoOp() {
        #expect(machine.handle(.routeChanged(reason: .newDeviceAvailable), while: .idle).isEmpty)
    }

    @Test func unrelatedRouteReasonIsNoOp() {
        #expect(machine.handle(.routeChanged(reason: .categoryChange), while: .recording).isEmpty)
    }

    @Test func mediaResetWhileRecordingRebuilds() {
        #expect(machine.handle(.mediaServicesReset, while: .recording) == [.rebuildEngine])
    }

    @Test func mediaResetWhileIdleIsNoOp() {
        #expect(machine.handle(.mediaServicesReset, while: .idle).isEmpty)
    }
}
