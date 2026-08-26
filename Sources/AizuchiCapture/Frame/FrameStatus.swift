import CoreMedia
import ScreenCaptureKit

/// Only `.complete` video frames carry a freshly-rendered image. ScreenCaptureKit
/// also delivers `.idle` / `.blank` / `.suspended` (and possibly other future
/// statuses) sample buffers to keep the stream's timing information flowing; those
/// must never reach the writer, or the recorded video would show duplicated or stale
/// frames.
enum FrameStatus {
    // NOTE(uncertain): the `[[SCStreamFrameInfo: Any]]` attachment dictionary shape
    // and the `SCStreamFrameInfo.status` key mirror the pattern from Apple's own
    // ScreenCaptureKit sample code, but this cannot be compile-checked here (no local
    // Swift toolchain — see docs/AGENT_GUIDE.md). If the cast below ever fails to
    // bridge, `isComplete` degrades to "keep every frame" rather than silently
    // dropping all video, which is the safer failure direction.
    static func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let rawStatus = attachments[.status] as? Int,
              let status = SCStreamFrameInfoStatus(rawValue: rawStatus) else {
            return true
        }
        return status == .complete
    }
}
