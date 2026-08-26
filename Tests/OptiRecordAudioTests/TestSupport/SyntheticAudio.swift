import AVFoundation
import CoreMedia
import Foundation // for the free-function sin (Darwin libm overlay) used below
@testable import OptiRecordAudio

/// Test-only helpers for building synthetic PCM and turning it into `CMSampleBuffer`s without
/// touching any real device or OS permission — required by docs/TASKS.md so this suite runs
/// on a CI macOS runner with no microphone/screen-recording access.
///
/// Sample buffers are built via `AudioBufferBridging.makeSampleBuffer(from:presentationTime:)`
/// — the module's own production utility for AVAudioPCMBuffer -> CMSampleBuffer — rather than
/// hand-rolled CoreMedia construction here, so these tests exercise real production code
/// instead of a second, parallel (and possibly subtly different) test-only implementation.
enum SyntheticAudio {
    /// A pure sine wave as a standard-format (Float32, non-interleaved) `AVAudioPCMBuffer`.
    static func sineBuffer(
        sampleRate: Double,
        channelCount: Int,
        frameCount: Int,
        frequency: Double,
        amplitude: Float = 0.5,
        phaseStart: Double = 0
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channelCount))!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let data = buffer.floatChannelData else { return buffer }

        let omega = 2.0 * Double.pi * frequency / sampleRate
        for channel in 0..<channelCount {
            for i in 0..<frameCount {
                data[channel][i] = amplitude * Float(sin(omega * Double(i) + phaseStart))
            }
        }
        return buffer
    }

    static func silence(sampleRate: Double, channelCount: Int, frameCount: Int) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channelCount))!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        return buffer
    }

    /// A new buffer holding `count` frames of `buffer` starting at `start`, same format.
    static func slice(_ buffer: AVAudioPCMBuffer, start: Int, count: Int) -> AVAudioPCMBuffer {
        let result = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(count))!
        result.frameLength = AVAudioFrameCount(count)
        guard let source = buffer.floatChannelData, let destination = result.floatChannelData else { return result }
        for channel in 0..<Int(buffer.format.channelCount) {
            destination[channel].update(from: source[channel] + start, count: count)
        }
        return result
    }

    /// Wraps `pcmBuffer` in a `CMSampleBuffer` stamped at `presentationTime`, via the module's
    /// own public bridging utility.
    static func sampleBuffer(from pcmBuffer: AVAudioPCMBuffer, presentationTime: CMTime) throws -> CMSampleBuffer {
        try AudioBufferBridging.makeSampleBuffer(from: pcmBuffer, presentationTime: presentationTime)
    }

    /// Copies an `AVAudioPCMBuffer`'s channel data into plain `[[Float]]` for assertions.
    static func floatChannels(_ buffer: AVAudioPCMBuffer) -> [[Float]] {
        guard let data = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        return (0..<Int(buffer.format.channelCount)).map { channel in
            Array(UnsafeBufferPointer(start: data[channel], count: frameCount))
        }
    }
}

enum SyntheticAudioError: Error {
    case missingFormat
}

extension CMSampleBuffer {
    /// Test-only: decodes this sample buffer's PCM payload back into per-channel Float arrays,
    /// via `AudioBufferBridging`'s (internal, `@testable`-visible) raw-mirror helper — the same
    /// technique `AudioFormatConverter`'s fast path uses. Used to inspect what `TimelineMixer`
    /// actually emitted through `onMixedBuffer` / `onSourceBuffer`.
    func extractFloatChannels() throws -> [[Float]] {
        guard let formatDescription = CMSampleBufferGetFormatDescription(self),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw SyntheticAudioError.missingFormat
        }
        var asbd = asbdPointer.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            throw SyntheticAudioError.missingFormat
        }

        let frameCount = CMSampleBufferGetNumSamples(self)
        let buffer = try AudioBufferBridging.pcmBuffer(mirroring: self, format: format, frameCount: AVAudioFrameCount(frameCount))
        return SyntheticAudio.floatChannels(buffer)
    }
}
