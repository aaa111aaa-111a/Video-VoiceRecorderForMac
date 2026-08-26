import XCTest
import AVFoundation
import CoreMedia
@testable import AizuchiAudio

final class AudioBufferBridgingTests: XCTestCase {
    func testRoundTripPreservesSamplesAndTiming() throws {
        let sampleRate = 48_000.0
        let frameCount = 512
        let buffer = SyntheticAudio.sineBuffer(sampleRate: sampleRate, channelCount: 2, frameCount: frameCount, frequency: 440, amplitude: 0.3)
        let pts = CMTime(value: 600_000, timescale: CMTimeScale(sampleRate)) // 12.5s at 48kHz

        let sampleBuffer = try AudioBufferBridging.makeSampleBuffer(from: buffer, presentationTime: pts)

        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sampleBuffer), pts)
        XCTAssertEqual(CMSampleBufferGetNumSamples(sampleBuffer), frameCount)

        let extracted = try sampleBuffer.extractFloatChannels()
        let original = SyntheticAudio.floatChannels(buffer)

        XCTAssertEqual(extracted.count, 2)
        for channel in 0..<2 {
            XCTAssertEqual(extracted[channel].count, frameCount)
            for i in 0..<frameCount {
                XCTAssertEqual(extracted[channel][i], original[channel][i], accuracy: 1e-6)
            }
        }
    }

    func testEmptyBufferThrows() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16)!
        buffer.frameLength = 0

        XCTAssertThrowsError(try AudioBufferBridging.makeSampleBuffer(from: buffer, presentationTime: .zero)) { error in
            XCTAssertEqual(error as? AudioBufferBridging.BridgingError, .emptyBuffer)
        }
    }

    func testMonoBufferRoundTrips() throws {
        let buffer = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 1, frameCount: 256, frequency: 220, amplitude: 0.4)
        let sampleBuffer = try AudioBufferBridging.makeSampleBuffer(from: buffer, presentationTime: .zero)
        let extracted = try sampleBuffer.extractFloatChannels()
        let original = SyntheticAudio.floatChannels(buffer)

        XCTAssertEqual(extracted.count, 1)
        for i in 0..<256 {
            XCTAssertEqual(extracted[0][i], original[0][i], accuracy: 1e-6)
        }
    }
}
