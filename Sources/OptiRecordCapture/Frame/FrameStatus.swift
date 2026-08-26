import CoreMedia
import ScreenCaptureKit

/// Only `.complete` video frames carry a freshly-rendered image. ScreenCaptureKit
/// also delivers `.idle` / `.blank` / `.suspended` (and possibly other future
/// statuses) sample buffers to keep the stream's timing information flowing; those
/// must never reach the writer, or the recorded video would show duplicated or stale
/// frames.
enum FrameStatus {
    // `SCStreamFrameInfo` is the attachment *key* type (.status, .displayTime,
    // .contentRect); the value under .status is an `SCFrameStatus` raw value.
    // If the bridge ever fails, this degrades to "keep every frame" rather than
    // dropping all video, which is the safer failure direction.
    static func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let rawStatus = attachments[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else {
            return true
        }
        return status == .complete
    }
}
