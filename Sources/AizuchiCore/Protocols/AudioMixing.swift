import Foundation
import CoreMedia

/// Sums system audio and microphone onto one timeline.
///
/// Buffers arrive from two clock domains with independent drift, so the mixer places
/// every sample at its **absolute frame position** on the timeline rather than
/// appending it. Gaps become silence; drift stops accumulating. See docs/ARCHITECTURE.md.
public protocol AudioMixing: AnyObject {
    /// Frame zero of the output. Must be called before any `append`.
    func prepare(timeline: AudioTimeline, sources: Set<AudioSource>, format: AudioStreamFormat) throws

    /// Called from capture queues. Buffers for a disabled source are ignored.
    func append(_ sampleBuffer: CMSampleBuffer, from source: AudioSource)

    /// Linear gain, 1.0 == unity. Applied before summing.
    func setGain(_ gain: Float, for source: AudioSource)
    func setMuted(_ muted: Bool, for source: AudioSource)

    /// Mixed PCM, one block at a time, in timeline order. Called on the mixer's queue.
    var onMixedBuffer: ((CMSampleBuffer) -> Void)? { get set }
    /// Per-source, post-gain levels for the meters. Roughly 20 times a second.
    var onLevels: ((AudioSource, AudioLevel) -> Void)? { get set }
    /// Per-source passthrough for the optional sidecar stem files.
    var onSourceBuffer: ((AudioSource, CMSampleBuffer) -> Void)? { get set }

    /// Emit whatever is buffered and stop. Called once, at the end of a recording.
    func drain()
    func reset()
}

/// Writes encoded media to disk.
///
/// The implementation owns an `AVAssetWriter`. `appendVideo` / `appendAudio` are
/// called from capture and mixer queues and must be non-blocking.
public protocol MediaWriting: AnyObject {
    var isWriting: Bool { get }

    func start(configuration: RecordingConfiguration, outputURL: URL) throws

    /// The first video buffer starts the writer session; audio before it is dropped.
    func appendVideo(_ sampleBuffer: CMSampleBuffer)
    func appendAudio(_ sampleBuffer: CMSampleBuffer, to track: AudioTrackKind)

    /// Flush and close. Safe to call once; later calls throw `RecorderError.notRecording`.
    func finish() async throws -> RecordingResult

    /// Abandon the recording and delete partial files.
    func cancel() async
}
