import CoreMedia
import OptiRecordCore

/// Rewrites a sample buffer's presentation timestamp.
///
/// Pause/resume works by dropping buffers while paused and subtracting the accumulated
/// pause from every later timestamp (`TimelineOffsetter`), so the recording has no dead
/// gap in it. Video and mixed audio go through the same offsetter, which is what keeps
/// them aligned across a pause.
enum SampleBufferRetimer {
    /// Returns a copy of `sampleBuffer` stamped at `presentationTime`, or `nil` if
    /// CoreMedia refuses to make the copy (in which case the caller drops the buffer —
    /// appending it at the wrong time would be worse than losing it).
    static func retimed(_ sampleBuffer: CMSampleBuffer, to presentationTime: CMTime) -> CMSampleBuffer? {
        // Audio buffers carry many samples with one per-sample duration; video carries one.
        // Either way a single timing entry with the original duration is what CoreMedia wants.
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &copy
        )
        guard status == noErr else {
            Log.writer.error("CMSampleBufferCreateCopyWithNewTiming failed: \(status, privacy: .public)")
            return nil
        }
        return copy
    }
}
