import Foundation

/// What the UI talks to. `RecordingCoordinator` (AizuchiRecording) is the real
/// implementation; `PreviewRecordingController` (AizuchiUI) fakes it for SwiftUI previews.
///
/// Every member is main-actor isolated, and every callback fires on the main actor,
/// so view models never have to hop threads.
@MainActor
public protocol RecordingControlling: AnyObject {
    var state: RecordingState { get }
    /// Seconds of recorded material, excluding paused time.
    var elapsed: TimeInterval { get }
    var levels: [AudioSource: AudioLevel] { get }
    var currentTarget: CaptureTarget? { get }
    var lastResult: RecordingResult? { get }

    var onStateChange: ((RecordingState) -> Void)? { get set }
    var onElapsedChange: ((TimeInterval) -> Void)? { get set }
    var onLevelsChange: (([AudioSource: AudioLevel]) -> Void)? { get set }
    var onFinish: ((Result<RecordingResult, RecorderError>) -> Void)? { get set }

    func permissionStatus(for kind: PermissionKind) -> PermissionStatus
    @discardableResult
    func requestPermission(_ kind: PermissionKind) async -> PermissionStatus
    func openSystemSettings(for kind: PermissionKind)

    func refreshAvailableContent() async throws -> ShareableContentSnapshot
    func availableMicrophones() -> [AudioInputDevice]

    /// Opens the capture streams without writing anything, so the level meters
    /// show signal before the meeting starts. This is how the user checks that
    /// the other side's audio really is being picked up.
    func startMonitoring(target: CaptureTarget) async
    func stopMonitoring() async

    func start(target: CaptureTarget) async
    func pause()
    func resume()
    func stop() async

    func setGain(_ gain: Float, for source: AudioSource)
    func setEnabled(_ enabled: Bool, for source: AudioSource)
    /// Re-read `SettingsStore` after the settings window changed something.
    func settingsDidChange()
}
