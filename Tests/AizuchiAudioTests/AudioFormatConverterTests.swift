import XCTest
import AVFoundation
import CoreMedia
@testable import AizuchiAudio
import AizuchiCore

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

        let expectedFrames = Double(inputFrames) * 48_000 / inputRate
        XCTAssertEqual(Double(output.frameLength), expectedFrames, accuracy: Double(expectedFrames) * 0.05)

        // Energy should survive resampling at roughly the same amplitude (within a few dB).
        let outputChannels = SyntheticAudio.floatChannels(output)
        let level = LevelMeter.level(of: outputChannels[0])
        let inputLevel = LevelMeter.level(of: SyntheticAudio.floatChannels(input)[0])
        XCTAssertEqual(level.rms, inputLevel.rms, accuracy: 3.0)
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
