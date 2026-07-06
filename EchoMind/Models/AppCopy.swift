import Foundation

/// User-facing copy shared across features so onboarding (Phase 1) and Settings
/// (Phase 9) stay identical. Plain language, not legalese.
nonisolated enum AppCopy {
    static let privacyExplainer = """
    Everything stays on this iPhone. EchoMind has no account, no cloud, and makes \
    no network calls. Your recordings, transcripts, and documents never leave your \
    device.
    """

    static let recordingConsent = """
    You're responsible for letting people know before you record them. Recording \
    laws vary by location and situation — when in doubt, ask for consent first. \
    EchoMind records only while you have a session running.
    """
}
