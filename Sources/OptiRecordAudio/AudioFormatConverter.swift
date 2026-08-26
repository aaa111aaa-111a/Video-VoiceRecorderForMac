import AVFoundation
import CoreMedia
import AudioToolbox
import os
import OptiRecordCore

/// Converts an arbitrary-format `CMSampleBuffer` (system audio from ScreenCaptureKit, or a
/// microphone from `AVCaptureSession` — possibly mono, possibly a non-48kHz device rate, e.g.
/// a Bluetooth HFP headset at 8/16 kHz) into the canonical PCM format used everywhere
/// downstream: 48 kHz / 2 ch / Float32 / non-interleaved.
///
/// Rebuilds its `AVAudioConverter` whenever the input's `AudioStreamBasicDescription` changes
/// (e.g. the user switches microphones mid-recording). Keeps the *previous* converter alive
/// and in use otherwise, both because rebuilding is comparatively expensive and because a
/// resampling `AVAudioConverter` carries internal filter state across calls — discarding and
/// recreating it on every buffer would reintroduce filter-warm-up artifacts every time.
///
/// Not thread-safe by itself: `inputASBD` / `converter` are plain mutable state. The caller
/// (`TimelineMixer`, via one `AudioFormatConverter` per source inside `MixerSourceState`)
/// confines all use of a given instance to its own single serial queue, so no locking is added
/// here.
public final class AudioFormatConverter {
    /// The format every `convert(_:)` call produces. Always Float32 / non-interleaved per the
    /// `AudioMixing` contract; enforced in `init` rather than trusted silently.
    public let outputFormat: AVAudioFormat

    private var inputASBD: AudioStreamBasicDescription?
    private var sourceFormat: AVAudioFormat?
    private var intermediateFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    public init(outputFormat: AVAudioFormat) {
        precondition(
            outputFormat.commonFormat == .pcmFormatFloat32 && !outputFormat.isInterleaved,
            "AudioFormatConverter requires a non-interleaved Float32 output format"
        )
        self.outputFormat = outputFormat
    }

    /// Converts one `CMSampleBuffer` to a PCM buffer in `outputFormat`.
    ///
    /// Returns `nil` if the sample buffer carries no audio frames, or if the converter
    /// produced no output for this call (can happen on the very first call after a format
    /// change while `AVAudioConverter`'s resampler is still filling its internal history —
    /// a few milliseconds at most; the caller treats "nothing written" the same as a gap,
    /// which is exactly what it is).
    public func convert(_ sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw RecorderError.audioConversionFailed("入力バッファにフォーマット情報がありません")
        }
        guard let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw RecorderError.audioConversionFailed("ストリームディスクリプションを取得できませんでした")
        }
        let asbd = asbdPointer.pointee

        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return nil }
        let frameCount = AVAudioFrameCount(numSamples)

        // Fast path: ScreenCaptureKit hands us 48 kHz / Float32 / non-interleaved audio most
        // of the time. When the input already matches `outputFormat` bit-for-bit, skip
        // AVAudioConverter and the mono-duplication step entirely and just copy the bytes.
        if isAlreadyCanonical(asbd) {
            return try AudioBufferBridging.pcmBuffer(mirroring: sampleBuffer, format: outputFormat, frameCount: frameCount)
        }

        try updateConverterIfNeeded(for: asbd)
        guard let sourceFormat, let intermediateFormat, let converter else {
            throw RecorderError.audioConversionFailed("コンバータが初期化されていません")
        }

        let rawBuffer = try AudioBufferBridging.pcmBuffer(mirroring: sampleBuffer, format: sourceFormat, frameCount: frameCount)

        let ratio = intermediateFormat.sampleRate / max(sourceFormat.sampleRate, 1)
        // A little slack beyond the naive ratio: resamplers can emit a handful more frames
        // than the input-count * ratio would suggest depending on internal filter state.
        let outputCapacity = AVAudioFrameCount((Double(frameCount) * ratio).rounded(.up)) + 32
        guard let intermediateBuffer = AVAudioPCMBuffer(pcmFormat: intermediateFormat, frameCapacity: outputCapacity) else {
            throw RecorderError.audioConversionFailed("変換用バッファを確保できませんでした")
        }

        var suppliedInput = false
        var conversionError: NSError?
        // NOTE(uncertain): this is the standard one-shot-buffer idiom for the block-based
        // AVAudioConverter.convert(to:error:withInputFrom:) API — supply the whole input once,
        // then answer `.noDataNow` — but the exact `AVAudioConverterOutputStatus` returned when
        // a resampling converter can't yet fill `intermediateBuffer` from a single, undersized
        // input chunk (e.g. `.inputRanDry` vs `.haveData` with partial `frameLength`) isn't
        // verified against a compiler here. Only `.error` is treated as fatal below; any other
        // status is read via `intermediateBuffer.frameLength`, which is 0 in the "needs more
        // input" case and thus already handled as "no output for this call" (see doc comment).
        let status = converter.convert(to: intermediateBuffer, error: &conversionError) { _, outStatus in
            if suppliedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outStatus.pointee = .haveData
            return rawBuffer
        }

        guard status != .error else {
            throw RecorderError.audioConversionFailed(conversionError?.localizedDescription ?? "AVAudioConverter でエラーが発生しました")
        }
        guard intermediateBuffer.frameLength > 0 else { return nil }

        return try finalize(intermediateBuffer)
    }

    // MARK: - Fast path detection

    private func isAlreadyCanonical(_ asbd: AudioStreamBasicDescription) -> Bool {
        asbd.mFormatID == kAudioFormatLinearPCM
            && (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
            && (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
            && (asbd.mFormatFlags & kAudioFormatFlagIsPacked) != 0
            && asbd.mBitsPerChannel == 32
            && asbd.mChannelsPerFrame == outputFormat.channelCount
            && abs(asbd.mSampleRate - outputFormat.sampleRate) < 0.5
    }

    // MARK: - Converter (re)construction

    private func updateConverterIfNeeded(for asbd: AudioStreamBasicDescription) throws {
        if let existing = inputASBD, Self.asbdsMatch(existing, asbd) {
            return
        }

        guard asbd.mFormatID == kAudioFormatLinearPCM else {
            throw RecorderError.audioConversionFailed("非 PCM フォーマットの音声には対応していません")
        }

        var mutableASBD = asbd
        guard let newSourceFormat = AVAudioFormat(streamDescription: &mutableASBD) else {
            throw RecorderError.audioConversionFailed("入力フォーマットを解釈できませんでした")
        }

        // Same channel count as the input; only sample rate and sample type change here.
        // Channel duplication/selection is handled separately in `finalize`, deliberately
        // *not* delegated to AVAudioConverter's own channel mapping — that keeps this class's
        // behavior (mono -> L=R specifically) explicit and independent of AVAudioConverter's
        // more general (and, for our purposes, less predictable) downmix/upmix rules.
        guard let newIntermediateFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputFormat.sampleRate,
            channels: AVAudioChannelCount(max(asbd.mChannelsPerFrame, 1)),
            interleaved: false
        ) else {
            throw RecorderError.audioConversionFailed("中間フォーマットを構築できませんでした")
        }

        guard let newConverter = AVAudioConverter(from: newSourceFormat, to: newIntermediateFormat) else {
            throw RecorderError.audioConversionFailed("AVAudioConverter を作成できませんでした")
        }

        inputASBD = asbd
        sourceFormat = newSourceFormat
        intermediateFormat = newIntermediateFormat
        converter = newConverter

        Log.audio.info("AudioFormatConverter rebuilt converter: \(asbd.mSampleRate, privacy: .public) Hz / \(asbd.mChannelsPerFrame, privacy: .public) ch -> \(self.outputFormat.sampleRate, privacy: .public) Hz / \(self.outputFormat.channelCount, privacy: .public) ch")
    }

    /// Field-by-field comparison rather than `memcmp`: `AudioStreamBasicDescription` has no
    /// documented guarantee against padding bytes, and we only care about the fields that
    /// actually affect how the converter reads the buffer.
    private static func asbdsMatch(_ a: AudioStreamBasicDescription, _ b: AudioStreamBasicDescription) -> Bool {
        a.mFormatID == b.mFormatID
            && a.mFormatFlags == b.mFormatFlags
            && a.mSampleRate == b.mSampleRate
            && a.mBitsPerChannel == b.mBitsPerChannel
            && a.mChannelsPerFrame == b.mChannelsPerFrame
            && a.mBytesPerFrame == b.mBytesPerFrame
            && a.mBytesPerPacket == b.mBytesPerPacket
            && a.mFramesPerPacket == b.mFramesPerPacket
    }

    // MARK: - Finalization (mono -> stereo duplication, channel count reconciliation)

    /// Copies `intermediate` (canonical rate/type, but the *input's* channel count) into a
    /// fresh buffer in `outputFormat`, so every value this class returns has `outputFormat`
    /// applied by reference — nothing downstream needs to reason about "close enough" formats.
    private func finalize(_ intermediate: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let final = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: intermediate.frameLength) else {
            throw RecorderError.audioConversionFailed("出力バッファを確保できませんでした")
        }
        final.frameLength = intermediate.frameLength

        guard let intermediateData = intermediate.floatChannelData, let finalData = final.floatChannelData else {
            throw RecorderError.audioConversionFailed("チャンネルデータを取得できませんでした")
        }

        let frameCount = Int(intermediate.frameLength)
        let inputChannelCount = Int(intermediate.format.channelCount)
        let outputChannelCount = Int(outputFormat.channelCount)

        if inputChannelCount == 1 {
            // Mono -> every output channel gets the same signal (L = R for stereo).
            let mono = intermediateData[0]
            for channel in 0..<outputChannelCount {
                finalData[channel].update(from: mono, count: frameCount)
            }
        } else {
            // NOTE(uncertain): for inputChannelCount > outputChannelCount (e.g. a surround
            // input, which capture in this app should never actually produce) this takes the
            // first `outputChannelCount` channels and drops the rest, rather than downmixing.
            // Mic/system capture in practice is always mono or stereo, so this path is
            // exercised for stereo-in/stereo-out only; documented here in case that changes.
            for channel in 0..<outputChannelCount {
                let sourceChannel = min(channel, inputChannelCount - 1)
                finalData[channel].update(from: intermediateData[sourceChannel], count: frameCount)
            }
        }

        return final
    }
}
