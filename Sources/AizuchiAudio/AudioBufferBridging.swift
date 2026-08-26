import AVFoundation
import CoreMedia
import AudioToolbox

/// Bridges between `CMSampleBuffer` (what capture, `AVAssetWriter`, and the mixer's public
/// callbacks speak) and `AVAudioPCMBuffer` (what `AVAudioConverter` and the mixer's internal
/// math speak).
///
/// `makeSampleBuffer(from:presentationTime:)` is the important direction for callers outside
/// this module: the writer (`AizuchiRecording`) needs it to turn a post-gain, post-mix PCM
/// buffer back into something `AVAssetWriterInput.append(_:)` accepts. It is written carefully
/// and kept `public` for that reason.
public enum AudioBufferBridging {

    public enum BridgingError: Error, LocalizedError, Equatable {
        case emptyBuffer
        case formatDescriptionCreationFailed(OSStatus)
        case sampleBufferCreationFailed(OSStatus)
        case dataCopyFailed(OSStatus)
        case unsupportedInputFormat

        public var errorDescription: String? {
            switch self {
            case .emptyBuffer:
                return "空の音声バッファです"
            case .formatDescriptionCreationFailed(let status):
                return "音声フォーマットの作成に失敗しました (status \(status))"
            case .sampleBufferCreationFailed(let status):
                return "サンプルバッファの作成に失敗しました (status \(status))"
            case .dataCopyFailed(let status):
                return "音声データのコピーに失敗しました (status \(status))"
            case .unsupportedInputFormat:
                return "対応していない音声フォーマットです"
            }
        }
    }

    /// Builds a `CMSampleBuffer` carrying `pcmBuffer`'s samples, stamped at `presentationTime`.
    ///
    /// This is what `TimelineMixer` uses internally to hand `onMixedBuffer` / `onSourceBuffer`
    /// their payload, and what a writer building sidecar files from raw PCM would use too.
    ///
    /// - Important: `presentationTime` is taken as-is; the caller (the mixer, via
    ///   `AudioTimeline.presentationTime(forFrameIndex:)`) is the source of truth for where a
    ///   block belongs on the timeline. This function does no clock math of its own.
    public static func makeSampleBuffer(from pcmBuffer: AVAudioPCMBuffer, presentationTime: CMTime) throws -> CMSampleBuffer {
        guard pcmBuffer.frameLength > 0 else {
            throw BridgingError.emptyBuffer
        }

        // AVAudioFormat.streamDescription is `UnsafePointer<AudioStreamBasicDescription>`;
        // CMAudioFormatDescriptionCreate wants a mutable pointer to a value it copies from,
        // so take a local mutable copy rather than pointing at AVAudioFormat's own storage.
        var asbd = pcmBuffer.format.streamDescription.pointee

        var formatDescription: CMAudioFormatDescription?
        // NOTE(uncertain): argument label spelling/order for CMAudioFormatDescriptionCreate
        // matches the long-standing CoreMedia signature as best remembered; this cannot be
        // compile-checked here (no local Swift toolchain). If CI reports a mismatch, the fix
        // is limited to this one call site.
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw BridgingError.formatDescriptionCreationFailed(formatStatus)
        }

        let frameCount = Int(pcmBuffer.frameLength)
        let sampleRate = pcmBuffer.format.sampleRate
        // One "sample" here means one frame (all channels together), matching how
        // CMSampleBufferGetNumSamples / CMAudioFormatDescriptionGetStreamBasicDescription
        // treat interleaved-or-not PCM: duration is 1 frame's worth of time.
        let timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let creationStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: [timing],
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard creationStatus == noErr, let sampleBuffer else {
            throw BridgingError.sampleBufferCreationFailed(creationStatus)
        }

        let setStatus = CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: pcmBuffer.audioBufferList
        )
        guard setStatus == noErr else {
            throw BridgingError.dataCopyFailed(setStatus)
        }

        return sampleBuffer
    }

    /// Wraps a `CMSampleBuffer`'s raw PCM bytes in an `AVAudioPCMBuffer` with **no** resampling
    /// or channel remapping, using an `AVAudioFormat` built to mirror the sample buffer's own
    /// `AudioStreamBasicDescription` exactly. Used by `AudioFormatConverter` both for its fast
    /// path (already-canonical input) and as the raw input handed to `AVAudioConverter`.
    ///
    /// The caller must already know `sampleBuffer` holds linear PCM matching `format` — this
    /// does a byte-for-byte copy, not a conversion.
    static func pcmBuffer(mirroring sampleBuffer: CMSampleBuffer, format: AVAudioFormat, frameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw BridgingError.unsupportedInputFormat
        }
        buffer.frameLength = frameCount

        // NOTE(uncertain): CMSampleBufferCopyPCMDataIntoAudioBufferList's exact Swift label
        // spelling ("at:frameCount:into:") is remembered from documentation/task guidance but
        // not compiler-verified here. `sampleBuffer.withAudioBufferList { list, _ in ... }`
        // (mentioned in docs/TASKS.md) is the fallback if this call site needs adjusting.
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else {
            throw BridgingError.dataCopyFailed(status)
        }
        return buffer
    }
}
