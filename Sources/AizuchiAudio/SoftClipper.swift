import AVFoundation
import Foundation // for the free-function tanh (Darwin libm overlay) used below

/// Soft clip applied to the mixed output only — never to the individual per-source stems
/// (`onSourceBuffer` gets the post-gain, pre-sum signal, untouched by this).
///
/// Only engages once simple summation pushes a sample past `linearThreshold`; below that,
/// audio passes through byte-for-byte unchanged, so ordinary conversation levels are never
/// distorted just because two sources happen to be summed. See docs/TASKS.md.
enum SoftClipper {
    /// |x| below this passes through untouched.
    static let linearThreshold: Float = 0.7

    /// tanh-shaped curve above `linearThreshold`, continuous in both value and slope at the
    /// threshold (so there's no audible "kink"), asymptoting to ±1.0 (0 dBFS) as the input
    /// grows without bound.
    static func clip(_ x: Float) -> Float {
        let magnitude = abs(x)
        guard magnitude > linearThreshold else { return x }
        let sign: Float = x < 0 ? -1 : 1
        let headroom = 1 - linearThreshold
        let excess = magnitude - linearThreshold
        let compressed = linearThreshold + headroom * tanh(excess / headroom)
        return sign * compressed
    }

    /// Applies `clip(_:)` in place to every sample of every channel.
    static func apply(to buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        for channel in 0..<channelCount {
            let samples = data[channel]
            for i in 0..<frameCount {
                samples[i] = clip(samples[i])
            }
        }
    }
}
