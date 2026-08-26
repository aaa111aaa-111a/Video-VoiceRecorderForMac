import CoreMedia
import Foundation
import OptiRecordCore

/// The sample-buffer path, deliberately kept off the main actor.
///
/// Capture callbacks arrive on ScreenCaptureKit's and AVCaptureSession's own queues, and
/// mixed audio arrives on the mixer's queue. None of that traffic is routed through the
/// main actor — `RecordingCoordinator` only ever receives state, levels and elapsed time.
/// Sample buffers go capture → mixer → writer directly.
final class RecordingPipeline: NSObject, ScreenCaptureDelegate, MicrophoneCaptureDelegate {
    private let mixer: AudioMixing
    private let lock = NSLock()

    private var writer: MediaWriting?
    private var offsetter = TimelineOffsetter()
    private var writesSeparateAudioFiles = false

    /// Called on the mixer's queue.
    var onLevels: ((AudioSource, AudioLevel) -> Void)?
    /// Called on whichever queue noticed the failure.
    var onFailure: ((RecorderError) -> Void)?

    init(mixer: AudioMixing) {
        self.mixer = mixer
        super.init()

        mixer.onMixedBuffer = { [weak self] buffer in
            self?.appendAudio(buffer, to: .mixed)
        }
        mixer.onSourceBuffer = { [weak self] source, buffer in
            guard let self, self.wantsSeparateAudioFiles else { return }
            self.appendAudio(buffer, to: source == .system ? .system : .microphone)
        }
        mixer.onLevels = { [weak self] source, level in
            self?.onLevels?(source, level)
        }
    }

    private var wantsSeparateAudioFiles: Bool {
        lock.lock()
        defer { lock.unlock() }
        return writesSeparateAudioFiles
    }

    // MARK: - Wiring

    /// `nil` puts the pipeline in monitoring mode: capture and mixing keep running (so the
    /// level meters move) but nothing is written to disk.
    func attach(writer: MediaWriting?, writesSeparateAudioFiles: Bool = false) {
        lock.lock()
        self.writer = writer
        self.writesSeparateAudioFiles = writesSeparateAudioFiles
        lock.unlock()
    }

    func resetTimeline() {
        lock.lock()
        offsetter.reset()
        lock.unlock()
    }

    func pause() {
        lock.lock()
        offsetter.pause(at: hostTime())
        lock.unlock()
    }

    func resume() {
        lock.lock()
        offsetter.resume(at: hostTime())
        lock.unlock()
    }

    var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return offsetter.isPaused
    }

    private func hostTime() -> CMTime {
        CMClockGetTime(CMClockGetHostTimeClock())
    }

    // MARK: - Sample buffer routing

    private func appendAudio(_ sampleBuffer: CMSampleBuffer, to track: AudioTrackKind) {
        lock.lock()
        let writer = self.writer
        let paused = offsetter.isPaused
        let adjusted = offsetter.adjust(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        lock.unlock()

        guard let writer, !paused else { return }
        guard let retimed = SampleBufferRetimer.retimed(sampleBuffer, to: adjusted) else { return }
        writer.appendAudio(retimed, to: track)
    }

    // MARK: - ScreenCaptureDelegate

    func screenCapturer(_ capturer: ScreenCapturing, didOutputVideo sampleBuffer: CMSampleBuffer) {
        lock.lock()
        let writer = self.writer
        let paused = offsetter.isPaused
        let adjusted = offsetter.adjust(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        lock.unlock()

        guard let writer, !paused else { return }
        guard let retimed = SampleBufferRetimer.retimed(sampleBuffer, to: adjusted) else { return }
        writer.appendVideo(retimed)
    }

    func screenCapturer(_ capturer: ScreenCapturing, didOutputSystemAudio sampleBuffer: CMSampleBuffer) {
        // Feeding the mixer while paused would fill its ring with audio nobody will write;
        // dropping here is what makes the pause seamless rather than leaving a silent gap.
        guard !isPaused else { return }
        mixer.append(sampleBuffer, from: .system)
    }

    func screenCapturer(_ capturer: ScreenCapturing, didOutputMicrophone sampleBuffer: CMSampleBuffer) {
        guard !isPaused else { return }
        mixer.append(sampleBuffer, from: .microphone)
    }

    func screenCapturer(_ capturer: ScreenCapturing, didStopWith error: RecorderError) {
        onFailure?(error)
    }

    // MARK: - MicrophoneCaptureDelegate

    func microphoneCapturer(_ capturer: MicrophoneCapturing, didOutput sampleBuffer: CMSampleBuffer) {
        guard !isPaused else { return }
        mixer.append(sampleBuffer, from: .microphone)
    }

    func microphoneCapturer(_ capturer: MicrophoneCapturing, didStopWith error: RecorderError) {
        onFailure?(error)
    }
}
