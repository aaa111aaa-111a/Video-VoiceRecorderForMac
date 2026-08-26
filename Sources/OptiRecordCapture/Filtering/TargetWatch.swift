import Foundation
import OptiRecordCore

/// Decides which running application's termination should end a capture.
///
/// Pure and independent of ScreenCaptureKit/AppKit, so it is directly unit
/// testable. `SCStreamScreenCapturer` uses this to subscribe to
/// `NSWorkspace.didTerminateApplicationNotification` for the one app (if any) the
/// current `CaptureTarget` belongs to.
enum TargetWatch {
    /// `nil` means "nothing to watch": a whole-display target has no single owning
    /// app, and a window whose owning app we could not determine falls back to
    /// whatever `SCStreamDelegate.stream(_:didStopWithError:)` reports on its own
    /// once the window is gone.
    static func bundleIdentifierToWatch(for target: CaptureTarget, in snapshot: ShareableContentSnapshot) -> String? {
        switch target {
        case .display:
            return nil
        case .application(let bundleIdentifier, _):
            return bundleIdentifier
        case .window(let id):
            return snapshot.window(id: id)?.bundleIdentifier
        }
    }
}
