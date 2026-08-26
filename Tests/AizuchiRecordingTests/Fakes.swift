import Foundation
import CoreMedia
@testable import AizuchiCore
@testable import AizuchiRecording

/// The whole point of injecting protocols: the coordinator's state machine can be driven
/// end to end with no screen, no microphone, and no TCC permission — which is exactly
/// what CI has.

final class FakeScreenCapturer: ScreenCapturing {
    weak var delegate: ScreenCaptureDelegate?
    var isRunning = false

    var snapshot: ShareableContentSnapshot = .oneDisplay
    var availableContentError: Error?
    var startError: Error?

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastConfiguration: RecordingConfiguration?

    func availableContent() async throws -> ShareableContentSnapshot {
        if let availableContentError { throw availableContentError }
        return snapshot
    }

    func start(target: CaptureTarget, configuration: RecordingConfiguration) async throws {
        if let startError { throw startError }
        startCount += 1
        lastConfiguration = configuration
        isRunning = true
    }

    func stop() async {
        stopCount += 1
        isRunning = false
    }

    /// Simulates ScreenCaptureKit tearing the stream down mid-recording.
    func fail(with error: RecorderError) {
        isRunning = false
        delegate?.screenCapturer(self, didStopWith: error)
    }
}

final class FakeMicrophoneCapturer: MicrophoneCapturing {
    weak var delegate: MicrophoneCaptureDelegate?
    var isRunning = false

    var devices: [AudioInputDevice] = [AudioInputDevice(id: "builtin", name: "MacBook Pro のマイク", isDefault: true)]
    var startError: Error?

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastDeviceUID: String?

    func availableDevices() -> [AudioInputDevice] { devices }

    func start(deviceUID: String?) async throws {
        if let startError { throw startError }
        startCount += 1
        lastDeviceUID = deviceUID
        isRunning = true
    }

    func stop() async {
        stopCount += 1
        isRunning = false
    }
}

final class FakeMixer: AudioMixing {
    var onMixedBuffer: ((CMSampleBuffer) -> Void)?
    var onLevels: ((AudioSource, AudioLevel) -> Void)?
    var onSourceBuffer: ((AudioSource, CMSampleBuffer) -> Void)?

    private(set) var prepareCount = 0
    private(set) var drainCount = 0
    private(set) var resetCount = 0
    private(set) var preparedSources: Set<AudioSource> = []
    private(set) var gains: [AudioSource: Float] = [:]
    private(set) var muted: [AudioSource: Bool] = [:]
    var prepareError: Error?

    func prepare(timeline: AudioTimeline, sources: Set<AudioSource>, format: AudioStreamFormat) throws {
        if let prepareError { throw prepareError }
        prepareCount += 1
        preparedSources = sources
    }

    func append(_ sampleBuffer: CMSampleBuffer, from source: AudioSource) {}
    func setGain(_ gain: Float, for source: AudioSource) { gains[source] = gain }
    func setMuted(_ muted: Bool, for source: AudioSource) { self.muted[source] = muted }
    func drain() { drainCount += 1 }
    func reset() { resetCount += 1 }

    /// Pushes a level through the same path the real mixer uses.
    func emitLevel(_ level: AudioLevel, for source: AudioSource) {
        onLevels?(source, level)
    }
}

final class FakeWriter: MediaWriting {
    var isWriting = false

    var startError: Error?
    var finishError: Error?
    var result: RecordingResult?

    private(set) var startCount = 0
    private(set) var finishCount = 0
    private(set) var cancelCount = 0
    private(set) var outputURL: URL?
    private(set) var configuration: RecordingConfiguration?

    func start(configuration: RecordingConfiguration, outputURL: URL) throws {
        if let startError { throw startError }
        startCount += 1
        self.configuration = configuration
        self.outputURL = outputURL
        isWriting = true
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {}
    func appendAudio(_ sampleBuffer: CMSampleBuffer, to track: AudioTrackKind) {}

    func finish() async throws -> RecordingResult {
        finishCount += 1
        isWriting = false
        if let finishError { throw finishError }
        return result ?? RecordingResult(
            url: outputURL ?? URL(fileURLWithPath: "/tmp/fake.mp4"),
            duration: 12,
            fileSize: 3_400_000,
            startedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func cancel() async {
        cancelCount += 1
        isWriting = false
    }
}

final class FakePermissionChecker: PermissionChecking {
    var statuses: [PermissionKind: PermissionStatus] = [
        .screenRecording: .authorized,
        .microphone: .authorized
    ]
    private(set) var requested: [PermissionKind] = []
    private(set) var openedSettings: [PermissionKind] = []

    func status(for kind: PermissionKind) -> PermissionStatus {
        statuses[kind] ?? .notDetermined
    }

    @discardableResult
    func request(_ kind: PermissionKind) async -> PermissionStatus {
        requested.append(kind)
        return status(for: kind)
    }

    func openSystemSettings(for kind: PermissionKind) {
        openedSettings.append(kind)
    }
}

extension ShareableContentSnapshot {
    /// A single 1512x982@2x display with Zoom running on it — the shape of a real
    /// "record my meeting" session.
    static var oneDisplay: ShareableContentSnapshot {
        ShareableContentSnapshot(
            displays: [
                .init(id: 1, name: "内蔵ディスプレイ", width: 1512, height: 982, scaleFactor: 2, isMain: true)
            ],
            windows: [
                .init(id: 10, title: "Zoom ミーティング", applicationName: "Zoom", bundleIdentifier: "us.zoom.xos",
                      frame: CGRect(x: 0, y: 0, width: 1280, height: 720), isOnScreen: true)
            ],
            applications: [
                .init(id: "us.zoom.xos", name: "Zoom", processID: 501, windowCount: 1)
            ]
        )
    }
}
