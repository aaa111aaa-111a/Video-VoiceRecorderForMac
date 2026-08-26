import XCTest
import CoreMedia
@testable import AizuchiCore

final class TimelineOffsetterTests: XCTestCase {
    private func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 48_000)
    }

    func testUntouchedTimelinePassesTimestampsThrough() {
        let offsetter = TimelineOffsetter()
        XCTAssertEqual(offsetter.adjust(time(12)), time(12))
        XCTAssertFalse(offsetter.isPaused)
    }

    func testPausedBuffersAreDropped() {
        var offsetter = TimelineOffsetter()
        offsetter.pause(at: time(10))
        XCTAssertTrue(offsetter.shouldDrop(time(11)))
        offsetter.resume(at: time(15))
        XCTAssertFalse(offsetter.shouldDrop(time(16)))
    }

    func testPausedDurationIsRemovedFromLaterTimestamps() {
        var offsetter = TimelineOffsetter()
        offsetter.pause(at: time(10))
        offsetter.resume(at: time(15))
        // 5 seconds of pause: material at t=20 lands at t=15 in the file.
        XCTAssertEqual(CMTimeGetSeconds(offsetter.adjust(time(20))), 15, accuracy: 0.0001)
    }

    func testPausesAccumulate() {
        var offsetter = TimelineOffsetter()
        offsetter.pause(at: time(10))
        offsetter.resume(at: time(12))
        offsetter.pause(at: time(20))
        offsetter.resume(at: time(23))
        XCTAssertEqual(CMTimeGetSeconds(offsetter.accumulatedPause), 5, accuracy: 0.0001)
        XCTAssertEqual(CMTimeGetSeconds(offsetter.adjust(time(30))), 25, accuracy: 0.0001)
    }

    func testDoublePauseIsIgnored() {
        var offsetter = TimelineOffsetter()
        offsetter.pause(at: time(10))
        offsetter.pause(at: time(11))
        offsetter.resume(at: time(20))
        XCTAssertEqual(CMTimeGetSeconds(offsetter.accumulatedPause), 10, accuracy: 0.0001)
    }

    func testResumeWithoutPauseIsIgnored() {
        var offsetter = TimelineOffsetter()
        offsetter.resume(at: time(10))
        XCTAssertEqual(offsetter.accumulatedPause, .zero)
    }

    func testResetClearsEverything() {
        var offsetter = TimelineOffsetter()
        offsetter.pause(at: time(1))
        offsetter.resume(at: time(2))
        offsetter.reset()
        XCTAssertEqual(offsetter.accumulatedPause, .zero)
        XCTAssertFalse(offsetter.isPaused)
    }
}

final class AudioTimelineTests: XCTestCase {
    private let anchor = CMTime(seconds: 100, preferredTimescale: 48_000)

    func testAnchorIsFrameZero() {
        let timeline = AudioTimeline(anchor: anchor, sampleRate: 48_000)
        XCTAssertEqual(timeline.frameIndex(for: anchor), 0)
    }

    func testOneSecondIsOneSampleRateOfFrames() {
        let timeline = AudioTimeline(anchor: anchor, sampleRate: 48_000)
        let later = CMTimeAdd(anchor, CMTime(seconds: 1, preferredTimescale: 48_000))
        XCTAssertEqual(timeline.frameIndex(for: later), 48_000)
    }

    func testBuffersBeforeTheAnchorAreNegative() {
        let timeline = AudioTimeline(anchor: anchor, sampleRate: 48_000)
        let earlier = CMTimeSubtract(anchor, CMTime(seconds: 0.5, preferredTimescale: 48_000))
        XCTAssertEqual(timeline.frameIndex(for: earlier), -24_000)
    }

    func testFrameIndexRoundTrips() {
        let timeline = AudioTimeline(anchor: anchor, sampleRate: 48_000)
        let time = timeline.presentationTime(forFrameIndex: 96_000)
        XCTAssertEqual(timeline.frameIndex(for: time), 96_000)
        XCTAssertEqual(CMTimeGetSeconds(time), 102, accuracy: 0.0001)
    }
}
