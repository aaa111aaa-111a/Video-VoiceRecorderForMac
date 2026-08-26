import AVFoundation
import AizuchiCore

/// The parts of permission-status logic that need no TCC call at all, split out so
/// they are directly exercised by `PermissionStatusMapperTests` without touching real
/// system permission state.
enum PermissionStatusMapper {
    static func map(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// `CGPreflightScreenCaptureAccess()` only ever reports granted vs. not-granted;
    /// unlike the microphone's `AVAuthorizationStatus`, it cannot distinguish "never
    /// asked" from "asked once and refused". `SystemPermissionChecker` tracks whether
    /// it has asked before (`hasRequestedBefore`) itself, so the UI can offer "grant
    /// access" only the first time and "open System Settings" every time after —
    /// `CGRequestScreenCaptureAccess()` only ever prompts once per app install.
    static func screenRecordingStatus(hasAccess: Bool, hasRequestedBefore: Bool) -> PermissionStatus {
        if hasAccess { return .authorized }
        return hasRequestedBefore ? .denied : .notDetermined
    }
}
