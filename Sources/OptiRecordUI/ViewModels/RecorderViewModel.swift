import Foundation
import OptiRecordCore

/// Bridges a `RecordingControlling` implementation (`RecordingCoordinator` in
/// production, `PreviewRecordingController` in previews/tests) into SwiftUI.
///
/// This is the only place the UI touches the recording layer: every view reads
/// `@Published` state from here rather than talking to the controller directly,
/// so views stay dumb and this type stays unit-testable without a real capture
/// pipeline. See `Tests/OptiRecordUITests/RecorderViewModelTests.swift`.
@MainActor
public final class RecorderViewModel: ObservableObject {
    @Published public private(set) var state: RecordingState
    @Published public private(set) var elapsed: TimeInterval
    @Published public private(set) var levels: [AudioSource: AudioLevel]
    @Published public private(set) var availableContent: ShareableContentSnapshot = .empty
    @Published public var selectedTarget: CaptureTarget? {
        didSet { persistSelectedTarget() }
    }
    @Published public private(set) var permissionStates: [PermissionKind: PermissionStatus] = [:]
    @Published public private(set) var recentRecordings: [RecordingResult]
    @Published public var errorMessage: String?
    /// Sources that have been silent (per `AudioLevel.isSilent`) for at least
    /// `silenceThreshold` seconds while enabled. Drives the "音声が検出されていません"
    /// warning in `LevelMeterView` — the last line of defense against a recording
    /// that finishes with no audio in it.
    @Published public private(set) var silentSources: Set<AudioSource> = []

    public let controller: RecordingControlling
    public let settingsStore: SettingsStore

    /// Extra hook for app-level side effects (e.g. a "recording finished" system
    /// notification) that don't belong in the view model itself. Called after
    /// `recentRecordings` / `errorMessage` have already been updated.
    public var onRecordingFinished: ((Result<RecordingResult, RecorderError>) -> Void)?

    private let defaults: UserDefaults
    private let silenceThreshold: TimeInterval
    private let now: () -> Date
    private var silenceSince: [AudioSource: Date] = [:]
    private var cachedSettings: RecordingSettings

    private static let selectedTargetKey = "app.optirecord.selectedCaptureTarget.v1"
    private static let recentRecordingsKey = "app.optirecord.recentRecordings.v1"
    private static let maxRecentRecordings = 20

    public init(
        controller: RecordingControlling,
        settingsStore: SettingsStore = SettingsStore(),
        defaults: UserDefaults = .standard,
        silenceThreshold: TimeInterval = 5,
        now: @escaping () -> Date = Date.init
    ) {
        self.controller = controller
        self.settingsStore = settingsStore
        self.defaults = defaults
        self.silenceThreshold = silenceThreshold
        self.now = now
        self.cachedSettings = settingsStore.settings

        self.state = controller.state
        self.elapsed = controller.elapsed
        self.levels = controller.levels
        self.recentRecordings = Self.loadRecentRecordings(from: defaults)
        self.selectedTarget = Self.loadSelectedTarget(from: defaults)

        wireCallbacks()
        refreshPermissionStates()
    }

    // MARK: Derived UI state

    /// Screen recording is a hard requirement (it is how both video and system
    /// audio are captured), so recording cannot start without it.
    public var canStartRecording: Bool {
        state.canStart && (permissionStates[.screenRecording] ?? .notDetermined).isAuthorized
    }
    public var canPause: Bool { state == .recording }
    public var canResume: Bool { state == .paused }
    public var canStop: Bool { state.isActive }
    public var elapsedDisplay: String { Formatters.duration(elapsed) }

    // MARK: Actions

    public func start() async {
        guard let target = selectedTarget else {
            errorMessage = "録画対象を選択してください"
            return
        }
        errorMessage = nil
        await controller.start(target: target)
    }

    public func stop() async {
        await controller.stop()
    }

    public func pause() {
        controller.pause()
    }

    public func resume() {
        controller.resume()
    }

    public func startMonitoring() async {
        guard let target = selectedTarget else { return }
        await controller.startMonitoring(target: target)
    }

    public func stopMonitoring() async {
        await controller.stopMonitoring()
    }

    public func refreshAvailableContent() async {
        do {
            let snapshot = try await controller.refreshAvailableContent()
            availableContent = snapshot
            applyDefaultSelectionIfNeeded(snapshot)
        } catch let error as RecorderError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func availableMicrophones() -> [AudioInputDevice] {
        controller.availableMicrophones()
    }

    public func refreshPermissionStates() {
        for kind in PermissionKind.allCases {
            permissionStates[kind] = controller.permissionStatus(for: kind)
        }
    }

    @discardableResult
    public func requestPermission(_ kind: PermissionKind) async -> PermissionStatus {
        let status = await controller.requestPermission(kind)
        permissionStates[kind] = status
        return status
    }

    public func openSystemSettings(for kind: PermissionKind) {
        controller.openSystemSettings(for: kind)
    }

    public func setGain(_ gain: Float, for source: AudioSource) {
        controller.setGain(gain, for: source)
    }

    public func setEnabled(_ enabled: Bool, for source: AudioSource) {
        controller.setEnabled(enabled, for: source)
    }

    /// Call after `settingsStore.settings` was written to (typically from
    /// `SettingsView`) so both the controller and this view model's cached copy
    /// pick the change up.
    public func settingsDidChange() {
        cachedSettings = settingsStore.settings
        controller.settingsDidChange()
    }

    // MARK: Callback wiring

    private func wireCallbacks() {
        controller.onStateChange = { [weak self] newState in
            self?.state = newState
        }
        controller.onElapsedChange = { [weak self] elapsed in
            self?.elapsed = elapsed
        }
        controller.onLevelsChange = { [weak self] levels in
            self?.handleLevelsChange(levels)
        }
        controller.onFinish = { [weak self] result in
            self?.handleFinish(result)
        }
    }

    private func handleLevelsChange(_ levels: [AudioSource: AudioLevel]) {
        self.levels = levels
        updateSilenceTracking(levels)
    }

    private func handleFinish(_ result: Result<RecordingResult, RecorderError>) {
        switch result {
        case .success(let recording):
            addRecentRecording(recording)
            errorMessage = nil
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
        onRecordingFinished?(result)
    }

    // MARK: Silence detection

    private func updateSilenceTracking(_ levels: [AudioSource: AudioLevel]) {
        var updated = silentSources
        let currentTime = now()

        for source in AudioSource.allCases {
            guard cachedSettings.isEnabled(source) else {
                silenceSince[source] = nil
                updated.remove(source)
                continue
            }
            guard let level = levels[source] else { continue }

            if level.isSilent {
                let since = silenceSince[source] ?? currentTime
                if silenceSince[source] == nil { silenceSince[source] = since }
                if currentTime.timeIntervalSince(since) >= silenceThreshold {
                    updated.insert(source)
                }
            } else {
                silenceSince[source] = nil
                updated.remove(source)
            }
        }

        if updated != silentSources {
            silentSources = updated
        }
    }

    // MARK: Capture target selection

    private func applyDefaultSelectionIfNeeded(_ snapshot: ShareableContentSnapshot) {
        if let target = selectedTarget, isValid(target, in: snapshot) {
            return
        }
        if let firstMeeting = snapshot.meetingApplications.first {
            selectedTarget = .application(bundleIdentifier: firstMeeting.id, displayID: snapshot.mainDisplay?.id ?? 0)
        } else if let display = snapshot.mainDisplay {
            selectedTarget = .display(id: display.id)
        }
        // An empty snapshot (e.g. before the permission is granted) leaves the
        // previous selection alone rather than clearing it.
    }

    private func isValid(_ target: CaptureTarget, in snapshot: ShareableContentSnapshot) -> Bool {
        switch target {
        case .display(let id): return snapshot.display(id: id) != nil
        case .window(let id): return snapshot.window(id: id) != nil
        case .application(let bundleIdentifier, _): return snapshot.application(bundleIdentifier: bundleIdentifier) != nil
        }
    }

    private func persistSelectedTarget() {
        guard let target = selectedTarget, let data = try? JSONEncoder().encode(target) else {
            defaults.removeObject(forKey: Self.selectedTargetKey)
            return
        }
        defaults.set(data, forKey: Self.selectedTargetKey)
    }

    private static func loadSelectedTarget(from defaults: UserDefaults) -> CaptureTarget? {
        guard let data = defaults.data(forKey: selectedTargetKey) else { return nil }
        return try? JSONDecoder().decode(CaptureTarget.self, from: data)
    }

    // MARK: Recent recordings

    private func addRecentRecording(_ result: RecordingResult) {
        var updated = recentRecordings
        updated.insert(result, at: 0)
        if updated.count > Self.maxRecentRecordings {
            updated.removeLast(updated.count - Self.maxRecentRecordings)
        }
        recentRecordings = updated
        saveRecentRecordings()
    }

    private func saveRecentRecordings() {
        guard let data = try? JSONEncoder().encode(recentRecordings) else { return }
        defaults.set(data, forKey: Self.recentRecordingsKey)
    }

    private static func loadRecentRecordings(from defaults: UserDefaults) -> [RecordingResult] {
        guard let data = defaults.data(forKey: recentRecordingsKey) else { return [] }
        return (try? JSONDecoder().decode([RecordingResult].self, from: data)) ?? []
    }
}
