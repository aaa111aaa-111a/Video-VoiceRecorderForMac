import Foundation
import CoreGraphics
import AizuchiCore

/// A fake `RecordingControlling` for SwiftUI previews and `RecorderViewModel` unit
/// tests. Nothing here touches ScreenCaptureKit, AVFoundation, or the filesystem.
///
/// Two ways to drive it:
/// - `start(target:)` / `pause()` / `resume()` / `stop()` behave like the real
///   thing (with short artificial delays) and animate elapsed time + levels on
///   their own via background `Task`s.
/// - `simulateState(_:)` / `simulateElapsed(_:)` / `simulateLevels(_:)` push a
///   value directly, with no timers involved — the deterministic path tests use.
@MainActor
public final class PreviewRecordingController: RecordingControlling {
    public private(set) var state: RecordingState {
        didSet { if oldValue != state { onStateChange?(state) } }
    }
    public private(set) var elapsed: TimeInterval = 0 {
        didSet { onElapsedChange?(elapsed) }
    }
    public private(set) var levels: [AudioSource: AudioLevel] = [:] {
        didSet { onLevelsChange?(levels) }
    }
    public private(set) var currentTarget: CaptureTarget?
    public private(set) var lastResult: RecordingResult?

    public var onStateChange: ((RecordingState) -> Void)?
    public var onElapsedChange: ((TimeInterval) -> Void)?
    public var onLevelsChange: (([AudioSource: AudioLevel]) -> Void)?
    public var onFinish: ((Result<RecordingResult, RecorderError>) -> Void)?

    private var permissions: [PermissionKind: PermissionStatus]
    private let snapshot: ShareableContentSnapshot
    private let microphones: [AudioInputDevice]
    private var gains: [AudioSource: Float] = [.system: 1.0, .microphone: 1.0]
    private var enabledSources: [AudioSource: Bool]

    private var elapsedTask: Task<Void, Never>?
    private var levelsTask: Task<Void, Never>?

    public init(
        initialState: RecordingState = .idle,
        permissions: [PermissionKind: PermissionStatus] = [.screenRecording: .authorized, .microphone: .authorized],
        snapshot: ShareableContentSnapshot = PreviewRecordingController.previewSnapshot,
        microphones: [AudioInputDevice] = PreviewRecordingController.previewMicrophones,
        mutedSources: Set<AudioSource> = []
    ) {
        self.state = initialState
        self.permissions = permissions
        self.snapshot = snapshot
        self.microphones = microphones
        var enabled: [AudioSource: Bool] = [:]
        for source in AudioSource.allCases { enabled[source] = !mutedSources.contains(source) }
        self.enabledSources = enabled
    }

    deinit {
        elapsedTask?.cancel()
        levelsTask?.cancel()
    }

    // MARK: RecordingControlling

    public func permissionStatus(for kind: PermissionKind) -> PermissionStatus {
        permissions[kind] ?? .notDetermined
    }

    @discardableResult
    public func requestPermission(_ kind: PermissionKind) async -> PermissionStatus {
        permissions[kind] = .authorized
        return .authorized
    }

    public func openSystemSettings(for kind: PermissionKind) {
        // No-op: there is no System Settings to open from a preview or a test.
    }

    public func refreshAvailableContent() async throws -> ShareableContentSnapshot {
        guard permissions[.screenRecording] == .authorized else {
            throw RecorderError.screenRecordingPermissionDenied
        }
        return snapshot
    }

    public func availableMicrophones() -> [AudioInputDevice] {
        microphones
    }

    public func startMonitoring(target: CaptureTarget) async {
        currentTarget = target
        startLevelSimulation()
    }

    public func stopMonitoring() async {
        stopLevelSimulation()
    }

    public func start(target: CaptureTarget) async {
        currentTarget = target
        state = .preparing
        try? await Task.sleep(nanoseconds: 150_000_000)
        state = .recording
        startElapsedTimer()
        startLevelSimulation()
    }

    public func pause() {
        guard state == .recording else { return }
        state = .paused
        stopElapsedTimer()
    }

    public func resume() {
        guard state == .paused else { return }
        state = .recording
        startElapsedTimer()
    }

    public func stop() async {
        guard state.isActive else { return }
        state = .finishing
        try? await Task.sleep(nanoseconds: 150_000_000)
        stopElapsedTimer()
        stopLevelSimulation()

        let result = RecordingResult(
            url: URL(fileURLWithPath: "/tmp/aizuchi-preview-\(Int(Date().timeIntervalSince1970)).mp4"),
            duration: elapsed,
            fileSize: Int64(max(elapsed, 1) * 450_000),
            startedAt: Date().addingTimeInterval(-elapsed),
            targetLabel: currentTarget.flatMap { snapshot.label(for: $0) }
        )
        lastResult = result
        elapsed = 0
        levels = [:]
        state = .idle
        onFinish?(.success(result))
    }

    public func setGain(_ gain: Float, for source: AudioSource) {
        gains[source] = gain
    }

    public func setEnabled(_ enabled: Bool, for source: AudioSource) {
        enabledSources[source] = enabled
    }

    public func settingsDidChange() {
        // Nothing persisted here for the fake controller to reload.
    }

    // MARK: Test / preview hooks

    /// Pushes a state without going through `start`/`pause`/`resume`/`stop`.
    public func simulateState(_ newState: RecordingState) {
        state = newState
    }

    public func simulateElapsed(_ value: TimeInterval) {
        elapsed = value
    }

    public func simulateLevels(_ newLevels: [AudioSource: AudioLevel]) {
        levels = newLevels
    }

    // MARK: Animation

    private func startElapsedTimer() {
        elapsedTask?.cancel()
        elapsedTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                self.elapsed += 0.2
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTask?.cancel()
        elapsedTask = nil
    }

    private func startLevelSimulation() {
        levelsTask?.cancel()
        let start = Date()
        levelsTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 50_000_000) // ~20 Hz, matching AudioMixing.onLevels
                if Task.isCancelled { return }
                guard let self else { return }
                let t = Date().timeIntervalSince(start)
                self.levels = Self.simulatedLevels(at: t, enabled: self.enabledSources)
            }
        }
    }

    private func stopLevelSimulation() {
        levelsTask?.cancel()
        levelsTask = nil
    }

    /// Sine waves at different frequencies/phases so the two meters do not move
    /// in lockstep, which reads as obviously fake in a preview.
    private static func simulatedLevels(at t: TimeInterval, enabled: [AudioSource: Bool]) -> [AudioSource: AudioLevel] {
        func level(phase: Double, frequency: Double) -> AudioLevel {
            let wave = (sin(t * frequency + phase) + 1) / 2 // 0...1
            let peakDb = Float(-38 + wave * 34) // roughly -38...-4 dBFS
            let rmsDb = peakDb - 6
            return AudioLevel(peak: peakDb, rms: rmsDb)
        }
        return [
            .system: (enabled[.system] ?? true) ? level(phase: 0, frequency: 1.3) : .silence,
            .microphone: (enabled[.microphone] ?? true) ? level(phase: 1.7, frequency: 0.9) : .silence
        ]
    }
}

// MARK: - Scenarios

extension PreviewRecordingController {
    public static var idle: PreviewRecordingController {
        PreviewRecordingController(initialState: .idle)
    }

    public static var recording: PreviewRecordingController {
        let controller = PreviewRecordingController(initialState: .recording)
        controller.elapsed = 754
        controller.startElapsedTimer()
        controller.startLevelSimulation()
        return controller
    }

    public static var paused: PreviewRecordingController {
        let controller = PreviewRecordingController(initialState: .paused)
        controller.elapsed = 312
        controller.levels = [.system: .silence, .microphone: .silence]
        return controller
    }

    public static var failed: PreviewRecordingController {
        PreviewRecordingController(initialState: .failed(.diskSpaceLow(availableBytes: 64 * 1_048_576)))
    }

    public static var permissionsNeeded: PreviewRecordingController {
        PreviewRecordingController(initialState: .idle, permissions: [.screenRecording: .denied, .microphone: .notDetermined])
    }

    /// System audio is fine but the microphone never produces signal — the
    /// scenario `LevelMeterView`'s silence warning exists for.
    public static var silentMicrophone: PreviewRecordingController {
        let controller = PreviewRecordingController(initialState: .recording, mutedSources: [.microphone])
        controller.elapsed = 120
        controller.startElapsedTimer()
        controller.startLevelSimulation()
        return controller
    }
}

// MARK: - Sample data

extension PreviewRecordingController {
    public static let previewSnapshot = ShareableContentSnapshot(
        displays: [
            .init(id: 1, name: "内蔵ディスプレイ", width: 2560, height: 1440, scaleFactor: 2, isMain: true),
            .init(id: 2, name: "外部ディスプレイ", width: 1920, height: 1080, scaleFactor: 1, isMain: false)
        ],
        windows: [
            .init(id: 101, title: "週次定例", applicationName: "Zoom", bundleIdentifier: "us.zoom.xos", frame: CGRect(x: 0, y: 0, width: 1280, height: 720), isOnScreen: true),
            .init(id: 102, title: "Keynote", applicationName: "Keynote", bundleIdentifier: "com.apple.iWork.Keynote", frame: CGRect(x: 0, y: 0, width: 1024, height: 768), isOnScreen: true)
        ],
        applications: [
            .init(id: "us.zoom.xos", name: "Zoom", processID: 111, windowCount: 1),
            .init(id: "com.google.Chrome", name: "Google Chrome", processID: 222, windowCount: 3),
            .init(id: "com.apple.finder", name: "Finder", processID: 1, windowCount: 2)
        ]
    )

    public static let previewMicrophones: [AudioInputDevice] = [
        .init(id: "default", name: "MacBook Pro のマイク", isDefault: true),
        .init(id: "usb-mic", name: "USB マイク", isDefault: false)
    ]
}
