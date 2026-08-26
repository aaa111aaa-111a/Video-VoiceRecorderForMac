import Foundation
import CoreGraphics
import AizuchiCore

/// Translates whatever `SCShareableContent`/`SCStream` throw into a `RecorderError`
/// the UI knows how to explain, per docs/AGENT_GUIDE.md ("OS の NSError をそのまま
/// UI に上げない").
///
/// ScreenCaptureKit's own `SCStreamError` type almost certainly has a case for "user
/// declined screen recording permission", but this module cannot verify exact case
/// names against a compiler (no local Swift toolchain). Rather than guess at
/// `SCStreamError.Code` names and risk a CI compile failure we cannot see coming,
/// this leans on `CGPreflightScreenCaptureAccess()` — a small, stable, long-documented
/// CoreGraphics API — as the trustworthy signal for "this is a permission problem".
enum ScreenCaptureErrorTranslator {
    enum Context {
        case availableContent
        case startCapture
        case streamStopped
    }

    static func translate(_ error: Error, context: Context, hasScreenRecordingAccess: Bool = CGPreflightScreenCaptureAccess()) -> RecorderError {
        if let recorderError = error as? RecorderError {
            return recorderError
        }
        if let filterError = error as? ContentFilterBuilder.FilterError {
            switch filterError {
            case .displayNotFound, .windowNotFound, .applicationNotFound:
                return .captureTargetDisappeared
            }
        }
        if !hasScreenRecordingAccess {
            return .screenRecordingPermissionDenied
        }

        let nsError = error as NSError
        switch context {
        case .availableContent:
            return .noCaptureTargetAvailable
        case .startCapture:
            return .captureStartFailed(nsError.localizedDescription)
        case .streamStopped:
            return .captureStopped(nsError.localizedDescription)
        }
    }
}
