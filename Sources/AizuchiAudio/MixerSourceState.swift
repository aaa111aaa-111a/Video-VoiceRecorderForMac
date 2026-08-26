import Foundation

/// Everything `TimelineMixer` keeps per `AudioSource`. A plain class (not a struct) because
/// it is stored in a dictionary keyed by `AudioSource` and mutated in place on the mixer's
/// serial queue — no need to pay for copy-on-write semantics here.
///
/// Every property is only ever touched from `TimelineMixer`'s single serial queue; see that
/// type's header comment for the concurrency argument.
final class MixerSourceState {
    let converter: AudioFormatConverter
    let ring: AbsoluteFrameRingBuffer

    /// Linear gain, applied before summing into the mix. 1.0 == unity.
    var gain: Float = 1.0
    var muted: Bool = false

    /// Running peak/RMS accumulation between `onLevels` callbacks (~50ms of audio at a time,
    /// spanning a few mix blocks since one block is only ~21ms).
    var levelAccumulator = LevelAccumulator()

    init(converter: AudioFormatConverter, ring: AbsoluteFrameRingBuffer) {
        self.converter = converter
        self.ring = ring
    }
}

/// Accumulates peak/RMS statistics (linear domain) across however many mix blocks make up one
/// `onLevels` reporting window, so the mixer isn't computing dBFS — and calling out to
/// `onLevels` — on every single 21ms block.
struct LevelAccumulator {
    /// Running max of per-block peak amplitude (linear).
    var peak: Float = 0
    /// Sum of (meanSquare * frameCount) across blocks, so the final mean-square is a proper
    /// frame-weighted average rather than an average-of-averages.
    var sumSquares: Double = 0
    var frameCount: Int = 0

    mutating func reset() {
        peak = 0
        sumSquares = 0
        frameCount = 0
    }
}
