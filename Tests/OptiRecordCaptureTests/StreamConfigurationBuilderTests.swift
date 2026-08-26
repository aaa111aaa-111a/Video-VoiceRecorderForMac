import XCTest
import ScreenCaptureKit
import CoreMedia
import CoreVideo
@testable import OptiRecordCapture
@testable import OptiRecordCore

final class StreamConfigurationBuilderTests: XCTestCase {
    private func makeConfiguration(
        width: Int = 1920, height: Int = 1080, frameRate: Int = 30,
        showsCursor: Bool = true, capturesSystemAudio: Bool = true,
        capturesMicrophone: Bool = false, excludesOwnAudio: Bool = true
    ) -> RecordingConfiguration {
        RecordingConfiguration(
            width: width, height: height, frameRate: frameRate,
            codec: .h264, videoBitrate: 4_000_000, container: .mp4,
            showsCursor: showsCursor,
            capturesSystemAudio: capturesSystemAudio,
            capturesMicrophone: capturesMicrophone,
            excludesOwnAudio: excludesOwnAudio
        )
    }

    func testGeometryAndFrameRateAreCarriedOver() {
        let config = makeConfiguration(width: 1280, height: 720, frameRate: 15)
        let streamConfig = StreamConfigurationBuilder.makeConfiguration(from: config, microphoneDeviceID: nil)
        XCTAssertEqual(streamConfig.width, 1280)
        XCTAssertEqual(streamConfig.height, 720)
        XCTAssertEqual(streamConfig.minimumFrameInterval, CMTime(value: 1, timescale: 15))
    }

    func testFixedCaptureSettings() {
        let streamConfig = StreamConfigurationBuilder.makeConfiguration(from: makeConfiguration(), microphoneDeviceID: nil)
        XCTAssertEqual(streamConfig.queueDepth, 6)
        XCTAssertEqual(streamConfig.pixelFormat, kCVPixelFormatType_32BGRA)
        XCTAssertEqual(streamConfig.sampleRate, 48_000)
        XCTAssertEqual(streamConfig.channelCount, 2)
        XCTAssertFalse(streamConfig.scalesToFit)
    }

    func testAudioFlagsFollowConfiguration() {
        let audioOn = makeConfiguration(capturesSystemAudio: true, excludesOwnAudio: true)
        let streamConfigOn = StreamConfigurationBuilder.makeConfiguration(from: audioOn, microphoneDeviceID: nil)
        XCTAssertTrue(streamConfigOn.capturesAudio)
        XCTAssertTrue(streamConfigOn.excludesCurrentProcessAudio)

        let audioOff = makeConfiguration(capturesSystemAudio: false, excludesOwnAudio: false)
        let streamConfigOff = StreamConfigurationBuilder.makeConfiguration(from: audioOff, microphoneDeviceID: nil)
        XCTAssertFalse(streamConfigOff.capturesAudio)
        XCTAssertFalse(streamConfigOff.excludesCurrentProcessAudio)
    }

    func testShowsCursorFollowsConfiguration() {
        let shown = StreamConfigurationBuilder.makeConfiguration(from: makeConfiguration(showsCursor: true), microphoneDeviceID: nil)
        let hidden = StreamConfigurationBuilder.makeConfiguration(from: makeConfiguration(showsCursor: false), microphoneDeviceID: nil)
        XCTAssertTrue(shown.showsCursor)
        XCTAssertFalse(hidden.showsCursor)
    }

    @available(macOS 15.0, *)
    func testMicrophoneCaptureEnabledOnMacOS15() {
        let config = makeConfiguration(capturesMicrophone: true)
        let streamConfig = StreamConfigurationBuilder.makeConfiguration(from: config, microphoneDeviceID: "device-123")
        XCTAssertTrue(streamConfig.captureMicrophone)
        XCTAssertEqual(streamConfig.microphoneCaptureDeviceID, "device-123")
    }

    func testMicrophoneCaptureDisabledWhenConfigurationDisablesIt() {
        // Runs on every supported OS; the macOS 15+-only property is only asserted
        // via `#available`, so this still compiles (and harmlessly skips the
        // assertion) below macOS 15.
        let config = makeConfiguration(capturesMicrophone: false)
        let streamConfig = StreamConfigurationBuilder.makeConfiguration(from: config, microphoneDeviceID: nil)
        if #available(macOS 15.0, *) {
            XCTAssertFalse(streamConfig.captureMicrophone)
        }
    }
}
