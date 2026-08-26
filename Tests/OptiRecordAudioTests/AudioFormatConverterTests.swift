import XCTest
import AVFoundation
import CoreMedia
@testable import OptiRecordAudio
import OptiRecordCore

final class AudioFormatConverterTests: XCTestCase {
    private func makeConverter() -> AudioFormatConverter {
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        return AudioFormatConverter(outputFormat: outputFormat)
    }

    /// The fast path: input already 48kHz/2ch/Float32/non-interleaved should pass straight
    /// through with the samples intact.
    func testCanonicalInputPassesThroughUnchanged() throws {
        let converter = makeConverter()
        let input = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 2, frameCount: 1024, frequency: 440, amplitude: 0.4)
        let sampleBuffer = try SyntheticAudio.sampleBuffer(from: input, presentationTime: .zero)

        let output = try converter.convert(sampleBuffer)

        XCTAssertNotNil(output)
        XCTAssertEqual(output?.format.sampleRate, 48_000)
        XCTAssertEqual(output?.format.channelCount, 2)
        XCTAssertEqual(output?.frameLength, 1024)

        let original = SyntheticAudio.floatChannels(input)
        let converted = SyntheticAudio.floatChannels(output!)
        for channel in 0..<2 {
            for i in 0..<1024 {
                XCTAssertEqual(converted[channel][i], original[channel][i], accuracy: 1e-6)
            }
        }
    }

    /// Mono input must be duplicated to every output channel (L = R for stereo output).
    func testMonoInputIsDuplicatedToStereo() throws {
        let converter = makeConverter()
        let input = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 1, frameCount: 960, frequency: 300, amplitude: 0.5)
        let sampleBuffer = try SyntheticAudio.sampleBuffer(from: input, presentationTime: .zero)

        let output = try converter.convert(sampleBuffer)

        XCTAssertNotNil(output)
        XCTAssertEqual(output?.format.channelCount, 2)

        let mono = SyntheticAudio.floatChannels(input)[0]
        let stereo = SyntheticAudio.floatChannels(output!)
        XCTAssertEqual(stereo.count, 2)
        XCTAssertEqual(stereo[0].count, mono.count)
        for i in 0..<mono.count {
            // Same-rate mono -> mono intermediate conversion should be effectively lossless;
            // allow a small tolerance for AVAudioConverter's internal float handling.
            XCTAssertEqual(stereo[0][i], mono[i], accuracy: 1e-3)
            XCTAssertEqual(stereo[1][i], mono[i], accuracy: 1e-3)
        }
    }

    /// A 44.1kHz input must come out at 48kHz, with roughly the expected frame count and with
    /// its signal energy preserved (resampling changes exact sample values, so this checks
    /// invariants rather than byte-for-byte equality).
    func testSampleRateIsConvertedTo48kHz() throws {
        let converter = makeConverter()
        let inputRate = 44_100.0
        let inputFrames = 4410 // 100ms
        let input = SyntheticAudio.sineBuffer(sampleRate: inputRate, channelCount: 2, frameCount: inputFrames, frequency: 440, amplitude: 0.5)
        let sampleBuffer = try SyntheticAudio.sampleBuffer(from: input, presentationTime: .zero)

        let output = try converter.convert(sampleBuffer)

        XCTAssertNotNil(output)
        guard let output else { return }
        XCTAssertEqual(output.format.sampleRate, 48_000)
        XCTAssertEqual(output.format.channelCount, 2)

        // The *first* buffer out of a resampling AVAudioConverter is short: the filter has
        // to fill its history before it can emit, so a few milliseconds stay inside the
        // converter and come out on the next call. That is a small constant latency on the
        // non-48kHz microphone path, not a leak — `testResamplingLosesNoFramesOverTime`
        // below pins the steady-state behaviour. Assert only that we got a substantial,
        // sane amount of audio here.
        let expectedFrames = Double(inputFrames) * 48_000 / inputRate
        XCTAssertGreaterThan(Double(output.frameLength), expectedFrames * 0.85)
        XCTAssertLessThanOrEqual(Double(output.frameLength), expectedFrames * 1.05)

        // Energy should survive resampling at roughly the same amplitude (within a few dB).
        let outputChannels = SyntheticAudio.floatChannels(output)
        let level = LevelMeter.level(of: outputChannels[0])
        let inputLevel = LevelMeter.level(of: SyntheticAudio.floatChannels(input)[0])
        XCTAssertEqual(level.rms, inputLevel.rms, accuracy: 3.0)
    }

    /// The property that actually matters for a long meeting: over a stream of buffers the
    /// resampler must not swallow audio. Whatever the filter holds back at the start comes
    /// out on later calls, so the running total converges on the ideal ratio.
    func testResamplingLosesNoFramesOverTime() throws {
        let converter = makeConverter()
        let inputRate = 44_100.0
        let framesPerBuffer = 4410 // 100ms each
        let bufferCount = 20 // two seconds

        var producedFrames = 0
        for index in 0..<bufferCount {
            let input = SyntheticAudio.sineBuffer(
                sampleRate: inputRate,
                channelCount: 2,
                frameCount: framesPerBuffer,
                frequency: 440,
                amplitude: 0.5
            )
            let presentationTime = CMTime(value: Int64(index * framesPerBuffer), timescale: CMTimeScale(inputRate))
            let sampleBuffer = try SyntheticAudio.sampleBuffer(from: input, presentationTime: presentationTime)
            if let output = try converter.convert(sampleBuffer) {
                producedFrames += Int(output.frameLength)
            }
        }

        let idealFrames = Double(framesPerBuffer * bufferCount) * 48_000 / inputRate
        // Within one buffer's worth: only the converter's priming may still be outstanding.
        XCTAssertEqual(Double(producedFrames), idealFrames, accuracy: 4_800)
    }

    /// A device switch mid-stream (different sample rate/channel count) must not crash or
    /// throw; the converter is expected to rebuild itself for the new format.
    func testFormatChangeMidStreamRebuildsConverter() throws {
        let converter = makeConverter()

        let first = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 1, frameCount: 480, frequency: 300, amplitude: 0.3)
        let firstSampleBuffer = try SyntheticAudio.sampleBuffer(from: first, presentationTime: .zero)
        let firstOutput = try converter.convert(firstSampleBuffer)
        XCTAssertEqual(firstOutput?.format.channelCount, 2)

        let second = SyntheticAudio.sineBuffer(sampleRate: 44_100, channelCount: 2, frameCount: 441, frequency: 300, amplitude: 0.3)
        let secondSampleBuffer = try SyntheticAudio.sampleBuffer(from: second, presentationTime: .zero)
        let secondOutput = try converter.convert(secondSampleBuffer)
        XCTAssertEqual(secondOutput?.format.channelCount, 2)
        XCTAssertEqual(secondOutput?.format.sampleRate, 48_000)

        // Switching back to the first format again should also work (reconstructs once more).
        let third = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 1, frameCount: 480, frequency: 300, amplitude: 0.3)
        let thirdSampleBuffer = try SyntheticAudio.sampleBuffer(from: third, presentationTime: .zero)
        let thirdOutput = try converter.convert(thirdSampleBuffer)
        XCTAssertEqual(thirdOutput?.format.channelCount, 2)
    }
}
