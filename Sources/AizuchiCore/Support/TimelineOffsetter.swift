import Foundation
import CoreMedia

/// Pause/resume without leaving a gap in the file.
///
/// Capture keeps running while paused (stopping and restarting `SCStream` is slow and
/// re-prompts nothing but does drop frames), so instead we drop buffers during the pause
/// and subtract the paused duration from every later timestamp. Video and audio share one
/// offsetter, which is what keeps them in sync across a pause.
public struct TimelineOffsetter: Equatable, Sendable {
    public private(set) var accumulatedPause: CMTime = .zero
    public private(set) var pauseStartedAt: CMTime?

    public init() {}

    public var isPaused: Bool { pauseStartedAt != nil }

    public mutating func pause(at time: CMTime) {
        guard pauseStartedAt == nil else { return }
        pauseStartedAt = time
    }

    public mutating func resume(at time: CMTime) {
        guard let start = pauseStartedAt else { return }
        let delta = CMTimeSubtract(time, start)
        if delta > .zero {
            accumulatedPause = CMTimeAdd(accumulatedPause, delta)
        }
        pauseStartedAt = nil
    }

    /// True while paused: the caller should throw the buffer away.
    public func shouldDrop(_ presentationTime: CMTime) -> Bool {
        isPaused
    }

    /// Presentation time as it should appear in the output file.
    public func adjust(_ presentationTime: CMTime) -> CMTime {
        CMTimeSubtract(presentationTime, accumulatedPause)
    }

    public mutating func reset() {
        accumulatedPause = .zero
        pauseStartedAt = nil
    }
}

/// Converts between host-clock timestamps and absolute sample positions on the
/// mix timeline. Shared by the mixer and the writer so both agree on frame zero.
public struct AudioTimeline: Equatable, Sendable {
    public let anchor: CMTime
    public let sampleRate: Double

    public init(anchor: CMTime, sampleRate: Double) {
        self.anchor = anchor
        self.sampleRate = sampleRate
    }

    /// Absolute frame index of a presentation timestamp. Can be negative for
    /// buffers that arrived from before the anchor.
    public func frameIndex(for presentationTime: CMTime) -> Int64 {
        let seconds = CMTimeGetSeconds(CMTimeSubtract(presentationTime, anchor))
        guard seconds.isFinite else { return 0 }
        return Int64((seconds * sampleRate).rounded())
    }

    public func presentationTime(forFrameIndex index: Int64) -> CMTime {
        CMTimeAdd(anchor, CMTime(value: index, timescale: CMTimeScale(sampleRate)))
    }
}
