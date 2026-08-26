import XCTest
@testable import AizuchiCore

final class RecordingConfigurationTests: XCTestCase {
    func testRetinaSourceIsScaledToThePresetCap() {
        var settings = RecordingSettings.default
        settings.quality = .p1080
        // A 14" MacBook Pro display: 1512x982 points at 2x.
        let config = RecordingConfiguration.resolve(settings: settings, sourceWidth: 1512, sourceHeight: 982, sourceScale: 2)
        XCTAssertEqual(config.height, 1080)
        XCTAssertEqual(config.width, 1662)
    }

    func testDimensionsAreAlwaysEven() {
        var settings = RecordingSettings.default
        settings.quality = .p720
        let config = RecordingConfiguration.resolve(settings: settings, sourceWidth: 1365, sourceHeight: 767, sourceScale: 1)
        XCTAssertEqual(config.width % 2, 0)
        XCTAssertEqual(config.height % 2, 0)
    }

    func testNativePresetKeepsSourceSize() {
        var settings = RecordingSettings.default
        settings.quality = .native
        let config = RecordingConfiguration.resolve(settings: settings, sourceWidth: 3840, sourceHeight: 2160, sourceScale: 1)
        XCTAssertEqual(config.width, 3840)
        XCTAssertEqual(config.height, 2160)
    }

    func testSmallSourceIsNotUpscaled() {
        var settings = RecordingSettings.default
        settings.quality = .p1440
        let config = RecordingConfiguration.resolve(settings: settings, sourceWidth: 800, sourceHeight: 600, sourceScale: 1)
        XCTAssertEqual(config.width, 800)
        XCTAssertEqual(config.height, 600)
    }

    func testManualBitrateWins() {
        var settings = RecordingSettings.default
        settings.manualVideoBitrate = 3_000_000
        let config = RecordingConfiguration.resolve(settings: settings, sourceWidth: 1920, sourceHeight: 1080)
        XCTAssertEqual(config.videoBitrate, 3_000_000)
    }

    func testHevcIsCheaperThanH264AtTheSameSize() {
        let h264 = BitrateCalculator.recommendedBitrate(width: 1920, height: 1080, frameRate: 30, codec: .h264)
        let hevc = BitrateCalculator.recommendedBitrate(width: 1920, height: 1080, frameRate: 30, codec: .hevc)
        XCTAssertLessThan(hevc, h264)
    }

    func testBitrateStaysWithinBounds() {
        let tiny = BitrateCalculator.recommendedBitrate(width: 320, height: 240, frameRate: 10, codec: .hevc)
        let huge = BitrateCalculator.recommendedBitrate(width: 7680, height: 4320, frameRate: 60, codec: .h264)
        XCTAssertEqual(tiny, BitrateCalculator.minimumBitrate)
        XCTAssertEqual(huge, BitrateCalculator.maximumBitrate)
    }

    func testHigherFrameRateRaisesBitrateSublinearly() {
        let at30 = BitrateCalculator.recommendedBitrate(width: 1280, height: 720, frameRate: 30, codec: .h264)
        let at60 = BitrateCalculator.recommendedBitrate(width: 1280, height: 720, frameRate: 60, codec: .h264)
        XCTAssertGreaterThan(at60, at30)
        XCTAssertLessThan(at60, at30 * 2)
    }

    func testAudioSourcesFollowSettings() {
        var settings = RecordingSettings.default
        settings.microphoneEnabled = false
        let config = RecordingConfiguration.resolve(settings: settings, sourceWidth: 1920, sourceHeight: 1080)
        XCTAssertTrue(config.capturesSystemAudio)
        XCTAssertFalse(config.capturesMicrophone)
        XCTAssertTrue(config.capturesAnyAudio)
        XCTAssertEqual(settings.enabledAudioSources, [.system])
    }
}
