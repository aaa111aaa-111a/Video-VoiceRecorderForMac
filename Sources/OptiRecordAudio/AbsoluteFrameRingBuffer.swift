import AVFoundation

/// A ring buffer addressed by absolute frame position rather than write order.
///
/// System audio and the microphone arrive from independent clock domains (see
/// docs/ARCHITECTURE.md "音声同期の設計"). Each source writes its converted PCM at the
/// absolute frame index its own PTS maps to via `AudioTimeline.frameIndex(for:)` — never at
/// "wherever the last write left off". That is what keeps drift from accumulating: every
/// write is independently positioned, so a source running fractionally fast or slow just
/// shows up with slightly different gaps between writes, not a growing offset.
///
/// Writes **overwrite** the target slots; they never sum. Frames that are never written read
/// back as silence (the backing storage starts zeroed, and `read` re-zeroes what it consumes
/// so a slot never replays stale audio if the ring wraps back around to it).
///
/// Not thread-safe on its own. `TimelineMixer` confines all access to one source's ring buffer
/// to its single serial queue, so no locking is needed here.
final class AbsoluteFrameRingBuffer {
    let capacityFrames: Int
    let channelCount: Int

    /// `storage[channel][slot]`. `slot = frameIndex mod capacityFrames`.
    private var storage: [[Float]]

    /// The highest absolute frame index ever written (inclusive), or `-1` if nothing has been
    /// written yet. Used by the mixer to decide "has this source produced audio at least up to
    /// this point" without needing to track every individual written frame.
    private(set) var highestWrittenFrameIndex: Int64 = -1

    init(capacityFrames: Int, channelCount: Int) {
        precondition(capacityFrames > 0 && channelCount > 0)
        self.capacityFrames = capacityFrames
        self.channelCount = channelCount
        self.storage = Array(repeating: Array(repeating: Float(0), count: capacityFrames), count: channelCount)
    }

    private func slot(for frameIndex: Int64) -> Int {
        let capacity = Int64(capacityFrames)
        let m = frameIndex % capacity
        return Int(m < 0 ? m + capacity : m)
    }

    /// Overwrites `frameCount` frames of `buffer`, starting at `sourceOffsetFrames` within it,
    /// into the ring starting at absolute position `startFrameIndex`.
    ///
    /// `sourceOffsetFrames` lets a caller write only the tail of a buffer whose head has
    /// already fallen before the point the mixer has emitted output through (see
    /// `TimelineMixer`'s "late buffer" handling) without allocating a trimmed copy.
    func write(from buffer: AVAudioPCMBuffer, startFrameIndex: Int64, sourceOffsetFrames: Int = 0) {
        guard let data = buffer.floatChannelData else { return }
        let totalFrames = Int(buffer.frameLength)
        let frameCount = totalFrames - sourceOffsetFrames
        guard frameCount > 0 else { return }

        let sourceChannelCount = Int(buffer.format.channelCount)
        for channel in 0..<channelCount {
            // If the source has fewer channels than the ring (shouldn't happen once
            // AudioFormatConverter has run, but stay defensive), fall back to its last channel.
            let sourceChannel = min(channel, sourceChannelCount - 1)
            let source = data[sourceChannel]
            // Mutate the nested array in place through the double subscript (rather than
            // copying `storage[channel]` out to a local `var`, which would defeat Swift's
            // in-place COW mutation and copy the whole capacity-sized array on every write).
            for i in 0..<frameCount {
                storage[channel][slot(for: startFrameIndex + Int64(i))] = source[sourceOffsetFrames + i]
            }
        }
        highestWrittenFrameIndex = max(highestWrittenFrameIndex, startFrameIndex + Int64(frameCount) - 1)
    }

    /// Reads `frameCount` frames starting at absolute position `startFrameIndex` into
    /// `destination` (one pointer per channel, each with room for at least `frameCount`
    /// frames), zeroing what it reads afterward so a later wraparound never replays it.
    /// Frames that were never written come back as `0`.
    /// `destination` matches `AVAudioPCMBuffer.floatChannelData`: the array of channel
    /// pointers is immutable, the samples each one points at are not.
    func read(into destination: UnsafePointer<UnsafeMutablePointer<Float>>, frameCount: Int, startFrameIndex: Int64) {
        guard frameCount > 0 else { return }
        for channel in 0..<channelCount {
            let dest = destination[channel]
            for i in 0..<frameCount {
                let idx = slot(for: startFrameIndex + Int64(i))
                dest[i] = storage[channel][idx]
                storage[channel][idx] = 0
            }
        }
    }

    /// True once this source has written at least through frame `endFrameIndexExclusive - 1`
    /// — i.e. it has *some* data covering the block ending there, though earlier gaps within
    /// that span may still read back as silence. That's the readiness signal `TimelineMixer`
    /// uses to decide a block can be emitted before its 200 ms deadline.
    func hasData(through endFrameIndexExclusive: Int64) -> Bool {
        highestWrittenFrameIndex >= endFrameIndexExclusive - 1
    }
}
