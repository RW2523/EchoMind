import Foundation

/// Normalized authorization state for microphone and speech permissions,
/// mapped from the OS-specific enums by `PermissionManager` (§2.8).
nonisolated enum PermissionState: Sendable, Equatable {
    case notDetermined
    case granted
    case denied
}
