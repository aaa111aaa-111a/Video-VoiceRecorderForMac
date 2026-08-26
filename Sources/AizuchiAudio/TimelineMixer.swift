import AVFoundation
import CoreMedia
import os
import AizuchiCore

/// Sums system audio and microphone onto one absolute-frame-position timeline. See
/// docs/ARCHITECTURE.md "音声同期の設計" for the design this implements.
///
/// ## Concurrency
/// All mutable state (`timeline`, `enabledSources`, `perSourceState`, `nextBlockStartFrameIndex`,
/// `emittedFrameIndex`, `outputTimer`) lives behind `queue`, one private serial
/// `DispatchQueue`. Every protocol method hops onto `queue` (`async` for the hot paths —
/// `append`, `setGain`, `setMuted`, matching the "don't block the caller" rule in
/// docs/AGENT_GUIDE.md's thread table — `sync` for `prepare`/`drain`, which are each called
/// once, outside any hot path, and whose callers need their side effects — including the
/// trailing `onMixedBuffer` calls `drain` makes — visible by the time the call returns). No
/// lock is used anywhere; the serial queue is the only synchronization primitive.
///
/// `@unchecked Sendable`: instances cross real thread boundaries (SCStream's queue and
/// AVCaptureSession's queue both call `append` on the same instance; see
/// docs/AGENT_GUIDE.md's thread table), but every access is funneled through `queue`, so this
/// is safe despite the compiler not being able to prove it structurally.
public final class TimelineMixer: AudioMixing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.aizuchi.audio.timeline-mixer")

    /// Blocks are emitted `AudioStreamFormat.mixBlockFrames` at a time; a source whose ring
    /// hasn't caught up to a block's deadline this long after it is treated as silent for
    /// that block rather than stalling output indefinitely.
    private static let maxWaitMilliseconds: Int64 = 200
    /// One reporting window's worth of frames for `onLevels`, "roughly 20 times a second" per
    /// the `AudioMixing` doc comment.
    private static let levelWindowMilliseconds: Double = 50
    /// 2 seconds of audio per source, matching docs/TASKS.md's sizing guidance.
    private static let ringCapacitySeconds: Double = 2
    /// Safety valve against a runaway catch-up loop in `pumpOutput` (e.g. if the host clock
    /// jumps forward, from a long debugger pause or similar) — bounds a single 10ms timer tick
    /// to emitting at most this many blocks before waiting for the next tick.
    private static let maxBlocksPerTick = 200

    private var timeline: AudioTimeline?
    private var canonicalFormat: AVAudioFormat?
    private var enabledSources: Set<AudioSource> = []
    private var perSourceState: [AudioSource: MixerSourceState] = [:]

    /// Absolute frame index of the next block `pumpOutput`/`drain` should emit.
    private var nextBlockStartFrameIndex: Int64 = 0
    /// Absolute frame index up to which output has already been emitted. `.min` means nothing
    /// has been emitted yet (so nothing counts as "late" relative to it). Used both to decide
    /// whether an incoming `append` is too late to matter and, for symmetry, is always kept in
    /// sync with `nextBlockStartFrameIndex` after every emitted block.
    private var emittedFrameIndex: Int64 = .min

    private var outputTimer: DispatchSourceTimer?
    private var levelWindowFrames: Int = 0
    private var timeoutFrames: Int64 = 0

    /// Whether `prepare` starts the 10ms output timer automatically. Always `true` in
    /// production (the public, no-argument `init()` below). Tests that only ever call `drain()`
    /// — which flushes everything buffered without depending on wall-clock time at all — pass
    /// `false` so a stray timer tick can never race a test's `append`/`drain` sequence; DispatchQueue
    /// FIFO ordering already makes that sequence deterministic on its own (see `append`'s doc
    /// comment), but disabling the timer removes even the theoretical possibility of a third
    /// party (the timer) enqueueing work on `queue` in between.
    private let autoStartTimer: Bool

    public init() {
        self.autoStartTimer = true
    }

    /// Test-only entry point (`internal`, reached via `@testable import`). See `autoStartTimer`.
    init(autoStartTimer: Bool) {
        self.autoStartTimer = autoStartTimer
    }

    public var onMixedBuffer: ((CMSampleBuffer) -> Void)?
    public var onLevels: ((AudioSource, AudioLevel) -> Void)?
    public var onSourceBuffer: ((AudioSource, CMSampleBuffer) -> Void)?

    // MARK: - AudioMixing

    public func prepare(timeline: AudioTimeline, sources: Set<AudioSource>, format: AudioStreamFormat) throws {
        guard let avFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: AVAudioChannelCount(format.channelCount)) else {
            throw RecorderError.audioConversionFailed("正準フォーマットを構築できませんでした")
        }

        let ringCapacityFrames = max(1, Int((format.sampleRate * Self.ringCapacitySeconds).rounded()))
        let levelWindowFrames = max(1, Int((format.sampleRate * Self.levelWindowMilliseconds / 1000).rounded()))
        let timeoutFrames = Int64((format.sampleRate * Double(Self.maxWaitMilliseconds) / 1000).rounded())

        queue.sync {
            outputTimer?.cancel()
            outputTimer = nil

            self.timeline = timeline
            self.canonicalFormat = avFormat
            self.enabledSources = sources
            self.nextBlockStartFrameIndex = 0
            self.emittedFrameIndex = .min
            self.levelWindowFrames = levelWindowFrames
            self.timeoutFrames = timeoutFrames

            var states: [AudioSource: MixerSourceState] = [:]
            for source in sources {
                states[source] = MixerSourceState(
                    converter: AudioFormatConverter(outputFormat: avFormat),
                    ring: AbsoluteFrameRingBuffer(capacityFrames: ringCapacityFrames, channelCount: Int(avFormat.channelCount))
                )
            }
            self.perSourceState = states

            if autoStartTimer {
                startTimer()
            }
        }
    }

    /// Hops to `queue` and returns immediately — never blocks the capture queue that calls it
    /// (SCStream's or AVCaptureSession's; see docs/AGENT_GUIDE.md's thread table).
    ///
    /// Because `queue` is serial and FIFO regardless of whether work was enqueued via `async`
    /// or `sync`, a sequence of calls made in order from one thread — e.g. several `append`s
    /// followed by `drain()` in a test — always finishes each `append`'s work before `drain`'s
    /// begins, even though `append` enqueues asynchronously and `drain` synchronously. That is
    /// what makes the mixer deterministically testable without sleeping.
    public func append(_ sampleBuffer: CMSampleBuffer, from source: AudioSource) {
        queue.async { [weak self] in
            self?.handleAppend(sampleBuffer, from: source)
        }
    }

    public func setGain(_ gain: Float, for source: AudioSource) {
        queue.async { [weak self] in
            self?.perSourceState[source]?.gain = gain
        }
    }

    public func setMuted(_ muted: Bool, for source: AudioSource) {
        queue.async { [weak self] in
            self?.perSourceState[source]?.muted = muted
        }
    }

    /// Emits every block still buffered and stops the output timer. Runs synchronously on
    /// `queue` — by the time this returns, every trailing `onMixedBuffer`/`onSourceBuffer`/
    /// `onLevels` call this flush produces has already fired. Called once, at the end of a
    /// recording, from outside `queue` (never from within a mixer callback, which would
    /// deadlock on `queue.sync`).
    public func drain() {
        queue.sync {
            handleDrain()
        }
    }

    public func reset() {
        queue.async { [weak self] in
            self?.handleReset()
        }
    }

    // MARK: - queue-confined implementation

    private func handleAppend(_ sampleBuffer: CMSampleBuffer, from source: AudioSource) {
        guard let timeline, enabledSources.contains(source), let state = perSourceState[source] else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid else { return }

        let converted: AVAudioPCMBuffer?
        do {
            converted = try state.converter.convert(sampleBuffer)
        } catch {
            Log.audio.error("AudioFormatConverter failed for \(source.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        guard let pcmBuffer = converted, pcmBuffer.frameLength > 0 else { return }

        let startFrameIndex = timeline.frameIndex(for: pts)
        let frameCount = Int64(pcmBuffer.frameLength)
        let endFrameIndex = startFrameIndex + frameCount

        if endFrameIndex <= emittedFrameIndex {
            Log.audio.notice("late buffer dropped for \(source.rawValue, privacy: .public): buffer end frame \(endFrameIndex, privacy: .public) is behind already-emitted frame \(self.emittedFrameIndex, privacy: .public)")
            return
        }

        if startFrameIndex < emittedFrameIndex {
            // Partially late: the buffer straddles the already-emitted boundary. Keep only
            // the tail that's still ahead of it; the head is unrecoverable (its output block
            // already went out) so log it as dropped rather than writing it silently.
            let dropFrames = Int(emittedFrameIndex - startFrameIndex)
            Log.audio.notice("late buffer partially dropped (\(dropFrames, privacy: .public) of \(frameCount, privacy: .public) frames) for \(source.rawValue, privacy: .public)")
            state.ring.write(from: pcmBuffer, startFrameIndex: emittedFrameIndex, sourceOffsetFrames: dropFrames)
        } else {
            state.ring.write(from: pcmBuffer, startFrameIndex: startFrameIndex)
        }
    }

    private func handleDrain() {
        outputTimer?.cancel()
        outputTimer = nil
        guard timeline != nil else { return }

        let highestWritten = perSourceState.values.map(\.ring.highestWrittenFrameIndex).max() ?? (nextBlockStartFrameIndex - 1)
        while nextBlockStartFrameIndex <= highestWritten {
            emitBlock(start: nextBlockStartFrameIndex)
            nextBlockStartFrameIndex += Int64(AudioStreamFormat.mixBlockFrames)
        }
    }

    private func handleReset() {
        outputTimer?.cancel()
        outputTimer = nil
        timeline = nil
        canonicalFormat = nil
        perSourceState.removeAll()
        enabledSources.removeAll()
        nextBlockStartFrameIndex = 0
        emittedFrameIndex = .min
    }

    // MARK: - Output timer

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            self?.pumpOutput()
        }
        timer.resume()
        outputTimer = timer
    }

    private func pumpOutput() {
        guard let timeline else { return }
        let nowFrameIndex = timeline.frameIndex(for: CMClockGetTime(CMClockGetHostTimeClock()))

        var emitted = 0
        while emitted < Self.maxBlocksPerTick {
            let blockEnd = nextBlockStartFrameIndex + Int64(AudioStreamFormat.mixBlockFrames)
            let allSourcesReady = enabledSources.allSatisfy { perSourceState[$0]?.ring.hasData(through: blockEnd) ?? false }
            let deadlinePassed = nowFrameIndex >= blockEnd + timeoutFrames
            guard allSourcesReady || deadlinePassed else { break }

            emitBlock(start: nextBlockStartFrameIndex)
            nextBlockStartFrameIndex = blockEnd
            emitted += 1
        }
    }

    // MARK: - Mixing

    private func emitBlock(start: Int64) {
        guard let timeline, let canonicalFormat else { return }
        let frameCount = AudioStreamFormat.mixBlockFrames
        let avFrameCount = AVAudioFrameCount(frameCount)
        let presentationTime = timeline.presentationTime(forFrameIndex: start)

        guard let mixBuffer = AVAudioPCMBuffer(pcmFormat: canonicalFormat, frameCapacity: avFrameCount) else {
            emittedFrameIndex = start + Int64(frameCount)
            return
        }
        mixBuffer.frameLength = avFrameCount
        zero(mixBuffer)

        // Iterate AudioSource.allCases (not perSourceState.keys) for a stable, deterministic
        // per-block ordering — matters for onSourceBuffer callback order, not for correctness.
        for source in AudioSource.allCases {
            guard enabledSources.contains(source), let state = perSourceState[source] else { continue }

            guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: canonicalFormat, frameCapacity: avFrameCount) else { continue }
            sourceBuffer.frameLength = avFrameCount
            zero(sourceBuffer)

            // Muted sources still advance the timeline (their ring keeps accumulating real
            // capture — see docs/TASKS.md) but contribute silence to both the mix and the
            // per-source callback, so we simply never read their ring data here.
            if !state.muted {
                if let channelData = sourceBuffer.floatChannelData {
                    state.ring.read(into: channelData, frameCount: frameCount, startFrameIndex: start)
                }
                applyGain(state.gain, to: sourceBuffer)
            }

            updateLevel(for: source, state: state, buffer: sourceBuffer, blockFrameCount: frameCount)

            if let onSourceBuffer {
                emitSourceBuffer(sourceBuffer, source: source, presentationTime: presentationTime, callback: onSourceBuffer)
            }

            accumulate(sourceBuffer, into: mixBuffer)
        }

        SoftClipper.apply(to: mixBuffer)
        emittedFrameIndex = start + Int64(frameCount)

        if let onMixedBuffer {
            do {
                let sampleBuffer = try AudioBufferBridging.makeSampleBuffer(from: mixBuffer, presentationTime: presentationTime)
                onMixedBuffer(sampleBuffer)
            } catch {
                Log.audio.error("failed to build mixed CMSampleBuffer: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func emitSourceBuffer(_ buffer: AVAudioPCMBuffer, source: AudioSource, presentationTime: CMTime, callback: (AudioSource, CMSampleBuffer) -> Void) {
        do {
            let sampleBuffer = try AudioBufferBridging.makeSampleBuffer(from: buffer, presentationTime: presentationTime)
            callback(source, sampleBuffer)
        } catch {
            Log.audio.error("failed to build source CMSampleBuffer for \(source.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func zero(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        for channel in 0..<Int(buffer.format.channelCount) {
            data[channel].update(repeating: 0, count: frameCount)
        }
    }

    private func applyGain(_ gain: Float, to buffer: AVAudioPCMBuffer) {
        guard gain != 1, let data = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = data[channel]
            for i in 0..<frameCount {
                samples[i] *= gain
            }
        }
    }

    private func accumulate(_ source: AVAudioPCMBuffer, into mix: AVAudioPCMBuffer) {
        guard let sourceData = source.floatChannelData, let mixData = mix.floatChannelData else { return }
        let frameCount = Int(mix.frameLength)
        for channel in 0..<Int(mix.format.channelCount) {
            let s = sourceData[channel]
            let m = mixData[channel]
            for i in 0..<frameCount {
                m[i] += s[i]
            }
        }
    }

    // MARK: - Levels

    private func updateLevel(for source: AudioSource, state: MixerSourceState, buffer: AVAudioPCMBuffer, blockFrameCount: Int) {
        guard onLevels != nil, let data = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)

        var combined = [Float]()
        combined.reserveCapacity(blockFrameCount * channelCount)
        for channel in 0..<channelCount {
            combined.append(contentsOf: UnsafeBufferPointer(start: data[channel], count: blockFrameCount))
        }

        state.levelAccumulator.peak = max(state.levelAccumulator.peak, LevelMeter.peakAmplitude(combined))
        state.levelAccumulator.sumSquares += Double(LevelMeter.meanSquare(combined)) * Double(combined.count)
        state.levelAccumulator.frameCount += combined.count

        let windowThreshold = levelWindowFrames * channelCount
        guard state.levelAccumulator.frameCount >= windowThreshold else { return }

        let meanSquare = state.levelAccumulator.sumSquares / Double(state.levelAccumulator.frameCount)
        let level = AudioLevel(
            peak: LevelMeter.amplitudeToDecibels(state.levelAccumulator.peak),
            rms: LevelMeter.amplitudeToDecibels(Float(meanSquare.squareRoot()))
        )
        state.levelAccumulator.reset()
        onLevels?(source, level)
    }
}
