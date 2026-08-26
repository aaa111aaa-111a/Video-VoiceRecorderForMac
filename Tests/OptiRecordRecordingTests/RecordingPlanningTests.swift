import AVFoundation
import XCTest
@testable import OptiRecordCore
@testable import OptiRecordRecording

final class MicrophoneStrategyTests: XCTestCase {
    func testMicrophoneOffMeansNoCapture() {
        XCTAssertEqual(
            RecordingPlanner.microphoneStrategy(capturesMicrophone: false, deviceUID: nil, supportsStreamMicrophone: true),
            .none
        )
    }

    func testModernMacOSWithDefaultInputUsesScreenCaptureKit() {
        // Same clock as system audio: the best case for staying in sync.
        XCTAssertEqual(
            RecordingPlanner.microphoneStrategy(capturesMicrophone: true, deviceUID: nil, supportsStreamMicrophone: true),
            .screenCaptureKit
        )
    }

    func testOlderMacOSFallsBackToAVCapture() {
        XCTAssertEqual(
            RecordingPlanner.microphoneStrategy(capturesMicrophone: true, deviceUID: nil, supportsStreamMicrophone: false),
            .avCapture
        )
    }

    func testAChosenDeviceAlwaysUsesAVCapture() {
        // ScreenCaptureKit's own microphone capture cannot be pointed at a specific device.
        XCTAssertEqual(
            RecordingPlanner.microphoneStrategy(capturesMicrophone: true, deviceUID: "usb-mic", supportsStreamMicrophone: true),
            .avCapture
        )
    }

    func testOnlyAVCaptureNeedsTheSeparateCapturer() {
        XCTAssertTrue(MicrophoneStrategy.avCapture.usesSeparateCapturer)
        XCTAssertFalse(MicrophoneStrategy.screenCaptureKit.usesSeparateCapturer)
        XCTAssertFalse(MicrophoneStrategy.none.usesSeparateCapturer)
    }
}

final class SourceGeometryTests: XCTestCase {
    private let snapshot = ShareableContentSnapshot.oneDisplay

    func testDisplayGeometryUsesTheDisplayScale() {
        let geometry = SourceGeometry.resolve(target: .display(id: 1), snapshot: snapshot)
        XCTAssertEqual(geometry, SourceGeometry(width: 1512, height: 982, scale: 2))
    }

    func testApplicationGeometryFollowsItsDisplay() {
        let geometry = SourceGeometry.resolve(target: .application(bundleIdentifier: "us.zoom.xos", displayID: 1), snapshot: snapshot)
        XCTAssertEqual(geometry?.width, 1512)
    }

    func testWindowGeometryUsesTheWindowFrame() {
        let geometry = SourceGeometry.resolve(target: .window(id: 10), snapshot: snapshot)
        XCTAssertEqual(geometry, SourceGeometry(width: 1280, height: 720, scale: 2))
    }

    func testMissingTargetsResolveToNil() {
        XCTAssertNil(SourceGeometry.resolve(target: .display(id: 99), snapshot: snapshot))
        XCTAssertNil(SourceGeometry.resolve(target: .window(id: 99), snapshot: snapshot))
        XCTAssertNil(SourceGeometry.resolve(target: .application(bundleIdentifier: "us.zoom.xos", displayID: 99), snapshot: snapshot))
    }
}

final class OutputLocationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("optirecord-output-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testPrepareCreatesTheDirectory() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        _ = try OutputLocation.prepare(directory: directory, minimumFreeMegabytes: 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }

    func testPrepareRefusesWhenTheDiskIsTooFull() throws {
        // Ten terabytes free is a bar no test machine clears.
        XCTAssertThrowsError(try OutputLocation.prepare(directory: directory, minimumFreeMegabytes: 10_000_000)) { error in
            guard case OutputLocation.Failure.diskSpaceLow = error else {
                return XCTFail("expected diskSpaceLow, got \(error)")
            }
        }
    }

    func testOutputURLUsesTheTemplateAndContainer() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var settings = RecordingSettings.default
        settings.container = .mov
        settings.fileNameTemplate = "{app}"

        let url = OutputLocation.outputURL(
            directory: directory,
            settings: settings,
            targetLabel: "Zoom ミーティング",
            date: Date(timeIntervalSince1970: 1_756_200_232)
        )

        XCTAssertEqual(url.lastPathComponent, "Zoom ミーティング.mov")
        XCTAssertEqual(url.deletingLastPathComponent().path, directory.path)
    }

    func testOutputURLAvoidsOverwritingAnExistingRecording() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var settings = RecordingSettings.default
        settings.fileNameTemplate = "{app}"
        let taken = directory.appendingPathComponent("Zoom.mp4")
        FileManager.default.createFile(atPath: taken.path, contents: Data("x".utf8))

        let url = OutputLocation.outputURL(directory: directory, settings: settings, targetLabel: "Zoom", date: Date())

        XCTAssertEqual(url.lastPathComponent, "Zoom 2.mp4")
    }

    func testNoBookmarkFallsBackToTheDefaultFolder() {
        XCTAssertEqual(OutputLocation.directory(from: nil), OutputFileNaming.defaultDirectory)
    }

    func testAGarbageBookmarkFallsBackRatherThanFailing() {
        XCTAssertEqual(OutputLocation.directory(from: Data("not a bookmark".utf8)), OutputFileNaming.defaultDirectory)
    }
}

final class AssetWriterSettingsTests: XCTestCase {
    private func configuration(codec: VideoCodecPreference) -> RecordingConfiguration {
        var settings = RecordingSettings.default
        settings.codec = codec
        return RecordingConfiguration.resolve(settings: settings, sourceWidth: 1920, sourceHeight: 1080)
    }

    func testVideoSettingsCarryTheResolvedGeometryAndBitrate() {
        let config = configuration(codec: .h264)
        let settings = AssetWriterMediaWriter.videoSettings(for: config)

        XCTAssertEqual(settings[AVVideoWidthKey] as? Int, 1920)
        XCTAssertEqual(settings[AVVideoHeightKey] as? Int, 1080)
        let compression = settings[AVVideoCompressionPropertiesKey] as? [String: Any]
        XCTAssertEqual(compression?[AVVideoAverageBitRateKey] as? Int, config.videoBitrate)
        XCTAssertEqual(compression?[AVVideoExpectedSourceFrameRateKey] as? Int, config.frameRate)
        XCTAssertNotNil(compression?[AVVideoProfileLevelKey], "H.264 needs an explicit profile level")
    }

    func testHevcOmitsTheH264ProfileLevel() {
        let settings = AssetWriterMediaWriter.videoSettings(for: configuration(codec: .hevc))
        let compression = settings[AVVideoCompressionPropertiesKey] as? [String: Any]
        XCTAssertNil(compression?[AVVideoProfileLevelKey])
    }

    func testAudioSettingsMatchTheCanonicalMixFormat() {
        let config = configuration(codec: .h264)
        let settings = AssetWriterMediaWriter.audioSettings(for: config)

        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 48_000)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 2)
        XCTAssertEqual(settings[AVFormatIDKey] as? UInt32, kAudioFormatMPEG4AAC)
    }
}
