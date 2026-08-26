import Foundation
import AizuchiCore

/// The app's one stateful object: turns "the user pressed record" into permissions,
/// capture, mixing, and a file on disk — and back again.
///
/// Everything here runs on the main actor. Sample buffers never touch it: those go
/// capture → mixer → writer through `RecordingPipeline`, and only state, levels and
/// elapsed time are hopped back to main. Concrete capture/mix/write types are injected,
/// so the whole state machine is testable with fakes.
@MainActor
public final class RecordingCoordinator: RecordingControlling {

    // MARK: - Observable state

    public private(set) var state: RecordingState = .idle {
        didSet {
            guard oldValue != state else { return }
            onStateChange?(state)
        }
    }
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var levels: [AudioSource: AudioLevel] = [:]
    public private(set) var currentTarget: CaptureTarget?
    public private(set) var lastResult: RecordingResult?

    public var onStateChange: ((RecordingState) -> Void)?
    public var onElapsedChange: ((TimeInterval) -> Void)?
    public var onLevelsChange: (([AudioSource: AudioLevel]) -> Void)?
    public var onFinish: ((Result<RecordingResult, RecorderError>) -> Void)?

    // MARK: - Dependencies

    private let screenCapturer: ScreenCapturing
    private let microphoneCapturer: MicrophoneCapturing
    private let mixer: AudioMixing
    private let permissions: PermissionChecking
    private let settingsStore: SettingsStore
    private let makeWriter: () -> MediaWriting
    private let resolveDirectory: (RecordingSettings) -> URL
    private let pipeline: RecordingPipeline
    private let clock: () -> Date

    // MARK: - Session state

    private var settings: RecordingSettings
    private var writer: MediaWriting?
    private var isMonitoring = false
    private var microphoneStrategy: MicrophoneStrategy = .none
    private var snapshot: ShareableContentSnapshot = .empty
    private var outputDirectory: URL?
    private var elapsedTimer: Timer?
    private var diskTimer: Timer?
    private var segmentStart: Date?
    private var accumulatedElapsed: TimeInterval = 0

    public init(
        screenCapturer: ScreenCapturing,
        microphoneCapturer: MicrophoneCapturing,
        mixer: AudioMixing,
        permissions: PermissionChecking,
        settingsStore: SettingsStore = SettingsStore(),
        makeWriter: @escaping () -> MediaWriting = { AssetWriterMediaWriter() },
        resolveDirectory: @escaping (RecordingSettings) -> URL = { OutputLocation.directory(from: $0.outputDirectoryBookmark) },
        clock: @escaping () -> Date = Date.init
    ) {
        self.screenCapturer = screenCapturer
        self.microphoneCapturer = microphoneCapturer
        self.mixer = mixer
        self.permissions = permissions
        self.settingsStore = settingsStore
        self.makeWriter = makeWriter
        self.resolveDirectory = resolveDirectory
        self.clock = clock
        self.settings = settingsStore.load()
        self.pipeline = RecordingPipeline(mixer: mixer)

        screenCapturer.delegate = pipeline
        microphoneCapturer.delegate = pipeline

        // Both arrive on capture/mixer queues; the hop to main is the only main-actor
        // traffic in the whole sample path.
        pipeline.onLevels = { [weak self] source, level in
            Task { @MainActor in
                self?.handleLevel(source, level)
            }
        }
        pipeline.onFailure = { [weak self] error in
            Task { @MainActor in
                await self?.handleCaptureFailure(error)
            }
        }
    }

    // MARK: - Permissions

    public func permissionStatus(for kind: PermissionKind) -> PermissionStatus {
        permissions.status(for: kind)
    }

    @discardableResult
    public func requestPermission(_ kind: PermissionKind) async -> PermissionStatus {
        await permissions.request(kind)
    }

    public func openSystemSettings(for kind: PermissionKind) {
        permissions.openSystemSettings(for: kind)
    }

    // MARK: - Sources

    public func refreshAvailableContent() async throws -> ShareableContentSnapshot {
        let content = try await screenCapturer.availableContent()
        snapshot = content
        return content
    }

    public func availableMicrophones() -> [AudioInputDevice] {
        microphoneCapturer.availableDevices()
    }

    // MARK: - Monitoring
    //
    // Recording a meeting and only then discovering the other side's audio was missing is
    // the failure this whole app exists to prevent, so the meters have to move *before*
    // the user commits. Monitoring runs the full capture and mix path with no writer.

    public func startMonitoring(target: CaptureTarget) async {
        guard state.canStart, !isMonitoring else { return }
        settings = settingsStore.load()
        do {
            snapshot = try await screenCapturer.availableContent()
            let configuration = try currentConfiguration(for: target)
            try await beginCapture(target: target, configuration: configuration)
            isMonitoring = true
            currentTarget = target
        } catch let error as RecorderError {
            await teardownCapture()
            state = .failed(error)
        } catch {
            await teardownCapture()
            state = .failed(.captureStartFailed(error.localizedDescription))
        }
    }

    public func stopMonitoring() async {
        guard isMonitoring, !state.isActive else { return }
        isMonitoring = false
        await teardownCapture()
        levels = [:]
        onLevelsChange?(levels)
    }

    // MARK: - Recording

    public func start(target: CaptureTarget) async {
        guard state.canStart else { return }
        settings = settingsStore.load()
        state = .preparing

        guard permissions.status(for: .screenRecording).isAuthorized else {
            state = .failed(.screenRecordingPermissionDenied)
            onFinish?(.failure(.screenRecordingPermissionDenied))
            return
        }

        do {
            // Work out geometry and check the disk *before* touching capture: there is no
            // reason to make the user grant screen recording only to fail on free space.
            let reuseWarmSession = isMonitoring && currentTarget == target
            if !reuseWarmSession {
                snapshot = try await screenCapturer.availableContent()
            }
            let configuration = try currentConfiguration(for: target)

            let directory = try prepareOutputDirectory()
            let label = snapshot.label(for: target)
            let url = OutputLocation.outputURL(
                directory: directory,
                settings: settings,
                targetLabel: label,
                date: clock()
            )

            // Reusing a monitoring session keeps the capture streams warm, so recording
            // starts instantly and without a second permission prompt.
            if !reuseWarmSession {
                if isMonitoring {
                    await teardownCapture()
                    isMonitoring = false
                }
                try await beginCapture(target: target, configuration: configuration)
            }

            let newWriter = makeWriter()
            try newWriter.start(configuration: configuration, outputURL: url)
            writer = newWriter
            pipeline.resetTimeline()
            pipeline.attach(writer: newWriter, writesSeparateAudioFiles: configuration.writesSeparateAudioFiles)

            isMonitoring = false
            currentTarget = target
            accumulatedElapsed = 0
            segmentStart = clock()
            elapsed = 0
            onElapsedChange?(0)
            startTimers()
            state = .recording
            Log.app.info("recording started -> \(url.lastPathComponent, privacy: .public)")
        } catch let error as RecorderError {
            await abort(with: error)
        } catch let failure as OutputLocation.Failure {
            await abort(with: Self.recorderError(from: failure))
        } catch {
            await abort(with: .captureStartFailed(error.localizedDescription))
        }
    }

    public func pause() {
        guard state == .recording else { return }
        pipeline.pause()
        accumulatedElapsed += currentSegmentDuration()
        segmentStart = nil
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        pipeline.resume()
        segmentStart = clock()
        state = .recording
    }

    public func stop() async {
        guard state.isActive else { return }
        state = .finishing
        stopTimers()
        accumulatedElapsed += currentSegmentDuration()
        segmentStart = nil

        await teardownCapture()

        guard let writer else {
            state = .idle
            return
        }
        self.writer = nil

        do {
            var result = try await writer.finish()
            result.targetLabel = currentTarget.flatMap { snapshot.label(for: $0) }
            lastResult = result
            state = .idle
            elapsed = 0
            onElapsedChange?(0)
            onFinish?(.success(result))
            Log.app.info("recording finished: \(result.url.lastPathComponent, privacy: .public) (\(Int(result.duration), privacy: .public)s)")
        } catch let error as RecorderError {
            state = .failed(error)
            onFinish?(.failure(error))
        } catch {
            let wrapped = RecorderError.writerFailed(error.localizedDescription)
            state = .failed(wrapped)
            onFinish?(.failure(wrapped))
        }
    }

    // MARK: - Audio controls

    public func setGain(_ gain: Float, for source: AudioSource) {
        mixer.setGain(gain, for: source)
        settingsStore.update { stored in
            switch source {
            case .system: stored.systemAudioGain = gain
            case .microphone: stored.microphoneGain = gain
            }
        }
        settings = settingsStore.load()
    }

    public func setEnabled(_ enabled: Bool, for source: AudioSource) {
        mixer.setMuted(!enabled, for: source)
        settingsStore.update { stored in
            switch source {
            case .system: stored.systemAudioEnabled = enabled
            case .microphone: stored.microphoneEnabled = enabled
            }
        }
        settings = settingsStore.load()
    }

    public func settingsDidChange() {
        settings = settingsStore.load()
        mixer.setGain(settings.systemAudioGain, for: .system)
        mixer.setGain(settings.microphoneGain, for: .microphone)
        mixer.setMuted(!settings.systemAudioEnabled, for: .system)
        mixer.setMuted(!settings.microphoneEnabled, for: .microphone)
    }

    // MARK: - Capture lifecycle

    /// Starts screen capture (and, when needed, the separate microphone capturer) and
    /// prepares the mixer. Shared by monitoring and recording.
    private func beginCapture(target: CaptureTarget, configuration: RecordingConfiguration) async throws {
        // The mixer's timeline anchor must live on the host clock, because that is the
        // clock both capture paths timestamp against and the one the mixer polls to decide
        // when a block's deadline has passed.
        let timeline = AudioTimeline(anchor: HostClock.now(), sampleRate: configuration.audioFormat.sampleRate)
        var sources: Set<AudioSource> = []
        if configuration.capturesSystemAudio { sources.insert(.system) }
        if configuration.capturesMicrophone { sources.insert(.microphone) }
        try mixer.prepare(timeline: timeline, sources: sources, format: configuration.audioFormat)
        mixer.setGain(settings.systemAudioGain, for: .system)
        mixer.setGain(settings.microphoneGain, for: .microphone)

        try await screenCapturer.start(target: target, configuration: configuration)

        microphoneStrategy = RecordingPlanner.microphoneStrategy(
            capturesMicrophone: configuration.capturesMicrophone,
            deviceUID: settings.microphoneDeviceUID,
            supportsStreamMicrophone: RecordingPlanner.systemSupportsStreamMicrophone
        )
        if microphoneStrategy.usesSeparateCapturer {
            do {
                try await microphoneCapturer.start(deviceUID: settings.microphoneDeviceUID)
            } catch {
                // A missing microphone must never cost the user the meeting recording:
                // carry on with system audio only and let the UI show the mic as silent.
                microphoneStrategy = .none
                Log.capture.error("microphone unavailable, continuing without it: \(String(describing: error), privacy: .public)")
            }
        }

        currentTarget = target
    }

    private func teardownCapture() async {
        await screenCapturer.stop()
        if microphoneStrategy.usesSeparateCapturer {
            await microphoneCapturer.stop()
        }
        microphoneStrategy = .none
        // Flush trailing audio into the writer (if any) before detaching it.
        mixer.drain()
        pipeline.attach(writer: nil)
        mixer.reset()
    }

    private func currentConfiguration(for target: CaptureTarget) throws -> RecordingConfiguration {
        guard let geometry = SourceGeometry.resolve(target: target, snapshot: snapshot) else {
            throw RecorderError.captureTargetDisappeared
        }
        return RecordingConfiguration.resolve(
            settings: settings,
            sourceWidth: geometry.width,
            sourceHeight: geometry.height,
            sourceScale: geometry.scale
        )
    }

    private func prepareOutputDirectory() throws -> URL {
        let directory = resolveDirectory(settings)
        let prepared = try OutputLocation.prepare(
            directory: directory,
            minimumFreeMegabytes: settings.minimumFreeDiskMegabytes
        )
        outputDirectory = prepared
        return prepared
    }

    private static func recorderError(from failure: OutputLocation.Failure) -> RecorderError {
        switch failure {
        case .directoryUnavailable(let detail): return .outputDirectoryUnavailable(detail)
        case .diskSpaceLow(let bytes): return .diskSpaceLow(availableBytes: bytes)
        }
    }

    /// Something went wrong before recording really began: leave nothing behind.
    private func abort(with error: RecorderError) async {
        if let writer {
            await writer.cancel()
            self.writer = nil
        }
        await teardownCapture()
        isMonitoring = false
        stopTimers()
        state = .failed(error)
        onFinish?(.failure(error))
    }

    // MARK: - Failures during a recording

    private func handleCaptureFailure(_ error: RecorderError) async {
        guard state.isActive || isMonitoring else { return }
        Log.app.error("capture failure: \(String(describing: error), privacy: .public)")

        guard state.isActive else {
            isMonitoring = false
            await teardownCapture()
            state = .failed(error)
            return
        }
        // Whatever broke, the minutes already recorded are the user's meeting: save them.
        await stop()
        state = .failed(error)
    }

    // MARK: - Timers

    private func startTimers() {
        stopTimers()
        let elapsedTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickElapsed() }
        }
        RunLoop.main.add(elapsedTimer, forMode: .common)
        self.elapsedTimer = elapsedTimer

        let diskTimer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.checkDiskSpace() }
        }
        RunLoop.main.add(diskTimer, forMode: .common)
        self.diskTimer = diskTimer
    }

    private func stopTimers() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        diskTimer?.invalidate()
        diskTimer = nil
    }

    private func currentSegmentDuration() -> TimeInterval {
        guard let segmentStart else { return 0 }
        return max(0, clock().timeIntervalSince(segmentStart))
    }

    private func tickElapsed() {
        guard state == .recording else { return }
        elapsed = accumulatedElapsed + currentSegmentDuration()
        onElapsedChange?(elapsed)
    }

    private func checkDiskSpace() async {
        guard state.isActive, let directory = outputDirectory else { return }
        guard let available = DiskSpace.availableBytes(at: directory) else { return }
        let minimum = Int64(settings.minimumFreeDiskMegabytes) * 1_048_576
        guard available < minimum else { return }

        Log.app.error("disk space exhausted mid-recording; stopping and keeping what we have")
        await stop()
        state = .failed(.diskSpaceLow(availableBytes: available))
    }

    private func handleLevel(_ source: AudioSource, _ level: AudioLevel) {
        levels[source] = level
        onLevelsChange?(levels)
    }
}
