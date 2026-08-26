import AVFoundation
import CoreMedia
import Foundation
import OptiRecordCore

/// `MediaWriting` on top of `AVAssetWriter`: H.264/HEVC video plus one AAC audio track
/// holding the mix, and optionally per-source sidecar files.
///
/// ## Threading
/// `appendVideo` and `appendAudio` are called from the capture queue and the mixer queue
/// respectively, and both append synchronously on the calling thread — deliberately.
/// Hopping to a private queue would mean retaining ScreenCaptureKit's pooled sample
/// buffers for longer than the pool's `queueDepth` allows, which starves capture. A lock
/// guards only the small amount of shared state (session start, counters, timestamps);
/// the `append` calls themselves go to two different `AVAssetWriterInput`s, which
/// AVFoundation allows from different threads.
public final class AssetWriterMediaWriter: MediaWriting {
    private let lock = NSLock()

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var mixedAudioInput: AVAssetWriterInput?
    private var sidecars: [AudioSource: SidecarAudioWriter] = [:]

    private var outputURL: URL?
    private var startedAt = Date()
    private var sessionStarted = false
    private var sessionStartTime: CMTime = .invalid
    private var lastVideoTime: CMTime = .invalid
    private var lastAudioTime: CMTime = .invalid
    private var finished = false

    private var droppedVideoFrames = 0
    private var droppedAudioBuffers = 0

    public init() {}

    public var isWriting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return writer != nil && !finished
    }

    // MARK: - Setup

    public func start(configuration: RecordingConfiguration, outputURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        guard writer == nil else { throw RecorderError.alreadyRecording }

        try? FileManager.default.removeItem(at: outputURL)

        let fileType: AVFileType = configuration.container == .mp4 ? .mp4 : .mov
        let assetWriter: AVAssetWriter
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
        } catch {
            throw RecorderError.writerSetupFailed(error.localizedDescription)
        }
        // A recording that crashes (or whose Mac loses power) mid-meeting is still
        // playable up to the last completed fragment. Cheap insurance.
        assetWriter.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 1)

        let video = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: Self.videoSettings(for: configuration)
        )
        video.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(video) else {
            throw RecorderError.writerSetupFailed("映像トラックを追加できません")
        }
        assetWriter.add(video)

        var audio: AVAssetWriterInput?
        if configuration.capturesAnyAudio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: Self.audioSettings(for: configuration)
            )
            input.expectsMediaDataInRealTime = true
            guard assetWriter.canAdd(input) else {
                throw RecorderError.writerSetupFailed("音声トラックを追加できません")
            }
            assetWriter.add(input)
            audio = input
        }

        guard assetWriter.startWriting() else {
            throw RecorderError.writerSetupFailed(assetWriter.error?.localizedDescription ?? "書き出しを開始できません")
        }

        if configuration.writesSeparateAudioFiles {
            let settings = Self.audioSettings(for: configuration)
            for source in AudioSource.allCases {
                let wanted = source == .system ? configuration.capturesSystemAudio : configuration.capturesMicrophone
                guard wanted else { continue }
                let url = OutputFileNaming.sidecarURL(for: outputURL, source: source)
                // A sidecar that cannot be created must not take the recording down with it.
                do {
                    sidecars[source] = try SidecarAudioWriter(source: source, url: url, audioSettings: settings)
                } catch {
                    Log.writer.error("sidecar writer for \(source.rawValue, privacy: .public) unavailable: \(String(describing: error), privacy: .public)")
                }
            }
        }

        self.writer = assetWriter
        self.videoInput = video
        self.mixedAudioInput = audio
        self.outputURL = outputURL
        self.startedAt = Date()
        self.sessionStarted = false
        self.finished = false
        self.droppedVideoFrames = 0
        self.droppedAudioBuffers = 0
        self.lastVideoTime = .invalid
        self.lastAudioTime = .invalid

        Log.writer.info("writer started: \(configuration.width, privacy: .public)x\(configuration.height, privacy: .public)@\(configuration.frameRate, privacy: .public)")
    }

    static func videoSettings(for configuration: RecordingConfiguration) -> [String: Any] {
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: configuration.videoBitrate,
            AVVideoExpectedSourceFrameRateKey: configuration.frameRate,
            // A keyframe every 2 seconds keeps seeking usable without bloating the file.
            AVVideoMaxKeyFrameIntervalDurationKey: 2.0,
            // Screen content has no motion to predict backwards from, and B-frames only
            // add encode latency to a live capture.
            AVVideoAllowFrameReorderingKey: false
        ]
        if configuration.codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        return [
            AVVideoCodecKey: configuration.codec == .h264 ? AVVideoCodecType.h264 : AVVideoCodecType.hevc,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: compression
        ]
    }

    static func audioSettings(for configuration: RecordingConfiguration) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: configuration.audioFormat.sampleRate,
            AVNumberOfChannelsKey: configuration.audioFormat.channelCount,
            AVEncoderBitRateKey: 192_000
        ]
    }

    // MARK: - Appending

    public func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid else { return }

        lock.lock()
        guard let writer, let videoInput, !finished, writer.status == .writing else {
            lock.unlock()
            return
        }
        if !sessionStarted {
            // The first video frame defines time zero for the whole file; audio that
            // arrived before it has nowhere to go.
            writer.startSession(atSourceTime: presentationTime)
            sessionStarted = true
            sessionStartTime = presentationTime
        }
        if lastVideoTime.isValid, presentationTime <= lastVideoTime {
            lock.unlock()
            return
        }
        guard videoInput.isReadyForMoreMediaData else {
            droppedVideoFrames += 1
            lock.unlock()
            return
        }
        lastVideoTime = presentationTime
        lock.unlock()

        if !videoInput.append(sampleBuffer) {
            Log.writer.error("video append failed: \(String(describing: writer.error), privacy: .public)")
        }
    }

    public func appendAudio(_ sampleBuffer: CMSampleBuffer, to track: AudioTrackKind) {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid else { return }

        switch track {
        case .mixed:
            appendMixedAudio(sampleBuffer, presentationTime: presentationTime)
        case .system, .microphone:
            guard let source = track.source else { return }
            // Sidecars are secondary output; appending under the lock keeps their
            // single-threaded contract without a second queue.
            lock.lock()
            defer { lock.unlock() }
            guard sessionStarted, !finished, let sidecar = sidecars[source] else { return }
            sidecar.append(sampleBuffer)
        }
    }

    private func appendMixedAudio(_ sampleBuffer: CMSampleBuffer, presentationTime: CMTime) {
        lock.lock()
        guard let writer, let mixedAudioInput, !finished, writer.status == .writing else {
            lock.unlock()
            return
        }
        // Audio before the first video frame has no session to land in.
        guard sessionStarted else {
            lock.unlock()
            return
        }
        if lastAudioTime.isValid, presentationTime <= lastAudioTime {
            lock.unlock()
            return
        }
        guard mixedAudioInput.isReadyForMoreMediaData else {
            droppedAudioBuffers += 1
            lock.unlock()
            return
        }
        lastAudioTime = presentationTime
        lock.unlock()

        if !mixedAudioInput.append(sampleBuffer) {
            Log.writer.error("audio append failed: \(String(describing: writer.error), privacy: .public)")
        }
    }

    // MARK: - Finishing

    public func finish() async throws -> RecordingResult {
        lock.lock()
        guard let writer, let url = outputURL, !finished else {
            lock.unlock()
            throw RecorderError.notRecording
        }
        finished = true
        let videoInput = self.videoInput
        let audioInput = self.mixedAudioInput
        let sidecarWriters = Array(sidecars.values)
        let started = startedAt
        let sessionStart = sessionStartTime
        let lastVideo = lastVideoTime
        let droppedVideo = droppedVideoFrames
        let droppedAudio = droppedAudioBuffers
        let didStartSession = sessionStarted
        lock.unlock()

        if droppedVideo > 0 || droppedAudio > 0 {
            Log.writer.notice("dropped \(droppedVideo, privacy: .public) video frames and \(droppedAudio, privacy: .public) audio buffers (encoder not keeping up)")
        }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        for sidecar in sidecarWriters {
            await sidecar.finish()
        }

        guard didStartSession else {
            // Not a single frame made it: there is nothing to save.
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw RecorderError.writerFailed("録画されたフレームがありません")
        }

        await writer.finishWriting()

        if writer.status == .failed {
            throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "不明なエラー")
        }

        let duration = lastVideo.isValid && sessionStart.isValid
            ? max(0, CMTimeGetSeconds(CMTimeSubtract(lastVideo, sessionStart)))
            : 0
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0

        var sidecarURLs: [AudioSource: URL] = [:]
        for sidecar in sidecarWriters where FileManager.default.fileExists(atPath: sidecar.url.path) {
            sidecarURLs[sidecar.source] = sidecar.url
        }

        return RecordingResult(
            url: url,
            duration: duration,
            fileSize: size,
            startedAt: started,
            sidecarAudioURLs: sidecarURLs
        )
    }

    public func cancel() async {
        lock.lock()
        guard let writer, !finished else {
            lock.unlock()
            return
        }
        finished = true
        let url = outputURL
        let sidecarWriters = Array(sidecars.values)
        lock.unlock()

        for sidecar in sidecarWriters {
            sidecar.cancel()
        }
        writer.cancelWriting()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
