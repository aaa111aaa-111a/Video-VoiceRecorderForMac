import XCTest
import AVFoundation
import CoreMedia
@testable import AizuchiAudio
@testable import AizuchiCore

/// These tests never rely on the mixer's real-time 10ms output timer or on wall-clock sleeps:
/// every mixer under test is built with `autoStartTimer: false`, and assertions run after
/// `drain()`, which flushes everything buffered synchronously regardless of host time (see
/// `TimelineMixer.drain`'s doc comment). That is what makes "100ms late", "mid-stream gap",
/// and "drift" all reproducible deterministically in CI with no real device or delay involved.
final class TimelineMixerTests: XCTestCase {
    /// An arbitrary, nonzero anchor (as a real recording's would be — a host-clock PTS, not
    /// zero) so tests don't accidentally pass only because they special-case frame zero.
    private let anchor = CMTime(value: 48_000_000, timescale: 48_000)
    private var timeline: AudioTimeline { AudioTimeline(anchor: anchor, sampleRate: 48_000) }

    private func makeMixer(sources: Set<AudioSource> = [.system, .microphone]) throws -> TimelineMixer {
        let mixer = TimelineMixer(autoStartTimer: false)
        try mixer.prepare(timeline: timeline, sources: sources, format: .canonical)
        return mixer
    }

    // MARK: - Summing

    func testTwoSourcesAtSamePositionAreSummed() throws {
        let mixer = try makeMixer()
        var mixedBuffers: [CMSampleBuffer] = []
        mixer.onMixedBuffer = { mixedBuffers.append($0) }

        let blockFrames = AudioStreamFormat.mixBlockFrames
        let systemInput = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 2, frameCount: blockFrames, frequency: 440, amplitude: 0.2)
        let micInput = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 2, frameCount: blockFrames, frequency: 220, amplitude: 0.15, phaseStart: .pi / 3)

        let pts = timeline.presentationTime(forFrameIndex: 0)
        mixer.append(try SyntheticAudio.sampleBuffer(from: systemInput, presentationTime: pts), from: .system)
        mixer.append(try SyntheticAudio.sampleBuffer(from: micInput, presentationTime: pts), from: .microphone)

        mixer.drain()

        XCTAssertEqual(mixedBuffers.count, 1)
        let mixed = try mixedBuffers[0].extractFloatChannels()
        let sys = SyntheticAudio.floatChannels(systemInput)
        let mic = SyntheticAudio.floatChannels(micInput)
        for channel in 0..<2 {
            for i in 0..<blockFrames {
                XCTAssertEqual(mixed[channel][i], sys[channel][i] + mic[channel][i], accuracy: 1e-4)
            }
        }
    }

    // MARK: - Position correctness despite late delivery

    func testSourceAppendedLateInCallOrderStillLandsAtItsOwnPTSPosition() throws {
        let mixer = try makeMixer()
        var mixedBuffers: [CMSampleBuffer] = []
        mixer.onMixedBuffer = { mixedBuffers.append($0) }

        let blockFrames = AudioStreamFormat.mixBlockFrames
        let amp: Float = 0.2

        let systemBlock0 = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 2, frameCount: blockFrames, frequency: 440, amplitude: amp)
        mixer.append(try SyntheticAudio.sampleBuffer(from: systemBlock0, presentationTime: timeline.presentationTime(forFrameIndex: 0)), from: .system)

        // Several more system blocks stream in (call order) before the mic's block-0 chunk is
        // finally delivered, simulating ~100ms of scheduling/driver delay on the mic's path.
        // The mic buffer's own PTS still says "frame 0" — it must land there regardless of
        // when append() happened to be called.
        for i in 1...5 {
            let block = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 2, frameCount: blockFrames, frequency: 440, amplitude: amp)
            let pts = timeline.presentationTime(forFrameIndex: Int64(i * blockFrames))
            mixer.append(try SyntheticAudio.sampleBuffer(from: block, presentationTime: pts), from: .system)
        }

        let micBlock0 = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 2, frameCount: blockFrames, frequency: 220, amplitude: amp, phaseStart: .pi / 4)
        mixer.append(try SyntheticAudio.sampleBuffer(from: micBlock0, presentationTime: timeline.presentationTime(forFrameIndex: 0)), from: .microphone)

        mixer.drain()

        XCTAssertEqual(mixedBuffers.count, 6)
        let firstBlock = try mixedBuffers[0].extractFloatChannels()
        let expectedSystem = SyntheticAudio.floatChannels(systemBlock0)
        let expectedMic = SyntheticAudio.floatChannels(micBlock0)
        for channel in 0..<2 {
            for i in 0..<blockFrames {
                XCTAssertEqual(firstBlock[channel][i], expectedSystem[channel][i] + expectedMic[channel][i], accuracy: 1e-4)
            }
        }
    }

    // MARK: - Gaps become silence, without shifting later data

    func testGapIsFilledWithSilenceWithoutShiftingLaterBlocks() throws {
        let mixer = try makeMixer(sources: [.system])
        var mixedBuffers: [CMSampleBuffer] = []
        mixer.onMixedBuffer = { mixedBuffers.append($0) }

        let blockFrames = AudioStreamFormat.mixBlockFrames
        let reference = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 2, frameCount: blockFrames * 3, frequency: 440, amplitude: 0.3)

        let block0 = SyntheticAudio.slice(reference, start: 0, count: blockFrames)
        // Block 1, [blockFrames, 2*blockFrames), is deliberately never appended.
        let block2 = SyntheticAudio.slice(reference, start: 2 * blockFrames, count: blockFrames)

        mixer.append(try SyntheticAudio.sampleBuffer(from: block0, presentationTime: timeline.presentationTime(forFrameIndex: 0)), from: .system)
        mixer.append(try SyntheticAudio.sampleBuffer(from: block2, presentationTime: timeline.presentationTime(forFrameIndex: Int64(2 * blockFrames))), from: .system)

        mixer.drain()

        XCTAssertEqual(mixedBuffers.count, 3)
        let out0 = try mixedBuffers[0].extractFloatChannels()
        let out1 = try mixedBuffers[1].extractFloatChannels()
        let out2 = try mixedBuffers[2].extractFloatChannels()
        let refChannels = SyntheticAudio.floatChannels(reference)

        for channel in 0..<2 {
            for i in 0..<blockFrames {
                XCTAssertEqual(out0[channel][i], refChannels[channel][i], accuracy: 1e-4)
                XCTAssertEqual(out1[channel][i], 0, accuracy: 1e-6, "gap block should be silence")
                // Block 2's content matches the reference at its OWN absolute position
                // (2*blockFrames + i) -- not shifted earlier by the missing block 1.
                XCTAssertEqual(out2[channel][i], refChannels[channel][2 * blockFrames + i], accuracy: 1e-4)
            }
        }
    }

    // MARK: - Drift does not accumulate

    func testDriftingSourceStillLandsAtItsOwnPTSPositionEachTime() throws {
        let mixer = try makeMixer(sources: [.system])
        var mixedBuffers: [CMSampleBuffer] = []
        mixer.onMixedBuffer = { mixedBuffers.append($0) }

        let blockFrames = AudioStreamFormat.mixBlockFrames
        let driftFramesPerBlock = 50
        let blockCount = 10
        let lastBlockStart = (blockCount - 1) * (blockFrames + driftFramesPerBlock)
        let referenceFrameCount = lastBlockStart + blockFrames + 16
        let reference = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 2, frameCount: referenceFrameCount, frequency: 440, amplitude: 0.3)

        var blockStarts: [Int] = []
        for i in 0..<blockCount {
            let start = i * (blockFrames + driftFramesPerBlock)
            blockStarts.append(start)
            let block = SyntheticAudio.slice(reference, start: start, count: blockFrames)
            let pts = timeline.presentationTime(forFrameIndex: Int64(start))
            mixer.append(try SyntheticAudio.sampleBuffer(from: block, presentationTime: pts), from: .system)
        }

        mixer.drain()

        // Sanity-check the test setup itself really does drift: by the last block, the
        // drifted start position differs from where naive block-count * blockFrames placement
        // would have put it.
        let naiveLastStart = (blockCount - 1) * blockFrames
        XCTAssertEqual(lastBlockStart - naiveLastStart, (blockCount - 1) * driftFramesPerBlock)

        let highestWritten = lastBlockStart + blockFrames - 1
        let expectedOutputBlocks = highestWritten / blockFrames + 1
        XCTAssertEqual(mixedBuffers.count, expectedOutputBlocks)

        // Reassemble everything the mixer emitted into one continuous buffer...
        var assembled = [[Float]](repeating: [Float](repeating: 0, count: expectedOutputBlocks * blockFrames), count: 2)
        for (blockIndex, buffer) in mixedBuffers.enumerated() {
            let extracted = try buffer.extractFloatChannels()
            for channel in 0..<2 {
                for i in 0..<blockFrames {
                    assembled[channel][blockIndex * blockFrames + i] = extracted[channel][i]
                }
            }
        }

        // ...and confirm every block landed at its own (drifted) absolute position, not at
        // a naively-incremented one that would have compounded the drift.
        let refChannels = SyntheticAudio.floatChannels(reference)
        for start in blockStarts {
            for channel in 0..<2 {
                for i in 0..<blockFrames {
                    XCTAssertEqual(assembled[channel][start + i], refChannels[channel][start + i], accuracy: 1e-4)
                }
            }
        }
    }

    // MARK: - Gain and mute

    func testGainAndMuteAreApplied() throws {
        let mixer = try makeMixer()
        var mixedBuffers: [CMSampleBuffer] = []
        var sourceBuffers: [AudioSource: [CMSampleBuffer]] = [.system: [], .microphone: []]
        mixer.onMixedBuffer = { mixedBuffers.append($0) }
        mixer.onSourceBuffer = { source, buffer in sourceBuffers[source, default: []].append(buffer) }

        mixer.setGain(0.5, for: .system)
        mixer.setMuted(true, for: .microphone)

        let blockFrames = AudioStreamFormat.mixBlockFrames
        let systemInput = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 2, frameCount: blockFrames, frequency: 440, amplitude: 0.4)
        let micInput = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 2, frameCount: blockFrames, frequency: 220, amplitude: 0.4)

        let pts = timeline.presentationTime(forFrameIndex: 0)
        mixer.append(try SyntheticAudio.sampleBuffer(from: systemInput, presentationTime: pts), from: .system)
        mixer.append(try SyntheticAudio.sampleBuffer(from: micInput, presentationTime: pts), from: .microphone)

        mixer.drain()

        XCTAssertEqual(mixedBuffers.count, 1)
        let mixed = try mixedBuffers[0].extractFloatChannels()
        let sys = SyntheticAudio.floatChannels(systemInput)
        for channel in 0..<2 {
            for i in 0..<blockFrames {
                // Mic is muted (contributes nothing); system is attenuated to 0.5 gain.
                XCTAssertEqual(mixed[channel][i], sys[channel][i] * 0.5, accuracy: 1e-4)
            }
        }

        // onSourceBuffer carries the post-gain, pre-sum signal for each source individually.
        XCTAssertEqual(sourceBuffers[.system]?.count, 1)
        XCTAssertEqual(sourceBuffers[.microphone]?.count, 1)
        let systemOut = try sourceBuffers[.system]![0].extractFloatChannels()
        let micOut = try sourceBuffers[.microphone]![0].extractFloatChannels()
        for channel in 0..<2 {
            for i in 0..<blockFrames {
                XCTAssertEqual(systemOut[channel][i], sys[channel][i] * 0.5, accuracy: 1e-4)
                XCTAssertEqual(micOut[channel][i], 0, accuracy: 1e-6, "muted source should be silent")
            }
        }
    }

    // MARK: - Late-after-drain buffers don't corrupt later output

    func testLateBufferAfterDrainIsDroppedAndDoesNotAffectLaterBlocks() throws {
        let mixer = try makeMixer(sources: [.system])
        var mixedBuffers: [CMSampleBuffer] = []
        mixer.onMixedBuffer = { mixedBuffers.append($0) }

        let blockFrames = AudioStreamFormat.mixBlockFrames
        let block0 = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 2, frameCount: blockFrames, frequency: 440, amplitude: 0.3)
        mixer.append(try SyntheticAudio.sampleBuffer(from: block0, presentationTime: timeline.presentationTime(forFrameIndex: 0)), from: .system)
        mixer.drain()
        XCTAssertEqual(mixedBuffers.count, 1)

        // A stray re-delivery of already-emitted block 0 data must not resurrect old output.
        let lateRedelivery = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 2, frameCount: blockFrames, frequency: 9_999, amplitude: 0.9)
        mixer.append(try SyntheticAudio.sampleBuffer(from: lateRedelivery, presentationTime: timeline.presentationTime(forFrameIndex: 0)), from: .system)

        let block1 = SyntheticAudio.sineBuffer(sampleRate: 48_000, channelCount: 2, frameCount: blockFrames, frequency: 550, amplitude: 0.3)
        mixer.append(try SyntheticAudio.sampleBuffer(from: block1, presentationTime: timeline.presentationTime(forFrameIndex: Int64(blockFrames))), from: .system)

        mixer.drain()

        XCTAssertEqual(mixedBuffers.count, 2)
        let out1 = try mixedBuffers[1].extractFloatChannels()
        let expected1 = SyntheticAudio.floatChannels(block1)
        for channel in 0..<2 {
            for i in 0..<blockFrames {
                XCTAssertEqual(out1[channel][i], expected1[channel][i], accuracy: 1e-4)
            }
        }
    }
}
