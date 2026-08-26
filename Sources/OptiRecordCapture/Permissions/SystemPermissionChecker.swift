import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import OptiRecordCore

/// TCC status and requests for screen recording and microphone.
///
/// Screen recording has no `authorizationStatus`/`requestAccess` pair the way the
/// microphone does — the only APIs are `CGPreflightScreenCaptureAccess()` (query,
/// no prompt) and `CGRequestScreenCaptureAccess()` (prompt, but only ever prompts
/// once per app install; a refusal is silent forever after). We remember locally
/// whether we already asked so a refused user is routed straight to System Settings
/// instead of calling `CGRequestScreenCaptureAccess()` again and getting nothing.
public final class SystemPermissionChecker: PermissionChecking {
    private static let hasRequestedScreenRecordingAccessKey = "app.optirecord.permissions.hasRequestedScreenRecordingAccess"

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func status(for kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .screenRecording:
            return PermissionStatusMapper.screenRecordingStatus(
                hasAccess: CGPreflightScreenCaptureAccess(),
                hasRequestedBefore: hasRequestedScreenRecordingAccess
            )
        case .microphone:
            return PermissionStatusMapper.map(AVCaptureDevice.authorizationStatus(for: .audio))
        }
    }

    @discardableResult
    public func request(_ kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .screenRecording:
            if CGPreflightScreenCaptureAccess() { return .authorized }
            hasRequestedScreenRecordingAccess = true
            let granted = CGRequestScreenCaptureAccess()
            return granted ? .authorized : .denied

        case .microphone:
            let current = AVCaptureDevice.authorizationStatus(for: .audio)
            guard current == .notDetermined else { return PermissionStatusMapper.map(current) }
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return granted ? .authorized : .denied
        }
    }

    public func openSystemSettings(for kind: PermissionKind) {
        guard let url = URL(string: kind.settingsURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    private var hasRequestedScreenRecordingAccess: Bool {
        get { userDefaults.bool(forKey: Self.hasRequestedScreenRecordingAccessKey) }
        set { userDefaults.set(newValue, forKey: Self.hasRequestedScreenRecordingAccessKey) }
    }
}
