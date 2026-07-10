import Foundation
import LocalAuthentication

/// Device-owner authentication seam for the app lock (F4). `@MainActor` protocol
/// (like `VoiceInput`) because `LAContext` presents system UI; the controller and
/// tests depend on this seam, never on LocalAuthentication directly.
@MainActor
protocol AppLockAuthenticating {
    /// True when the device can authenticate at all (biometrics or passcode).
    var isAvailable: Bool { get }
    /// User-facing name of the strongest available method ("Face ID", "Touch ID",
    /// "Optic ID", or "Passcode") for Settings copy and the unlock button.
    var methodName: String { get }
    /// Run the system authentication prompt. False on failure or cancel.
    func authenticate(reason: String) async -> Bool
}

@MainActor
final class BiometricAppLock: AppLockAuthenticating {
    var isAvailable: Bool {
        // Fresh context per query — LAContext caches evaluation state.
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    var methodName: String {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return "Passcode"
        }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        // .deviceOwnerAuthentication = biometrics with passcode fallback, so the
        // user is never locked out by a failed Face ID read.
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: reason)) ?? false
    }
}
