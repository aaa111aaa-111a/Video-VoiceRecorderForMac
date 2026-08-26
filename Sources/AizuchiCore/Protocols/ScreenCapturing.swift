import Foundation
import CoreMedia

/// Screen + system audio capture. Implemented by `SCStreamScreenCapturer`
/// (AizuchiCapture) on top of ScreenCaptureKit; faked in tests.
///
/// Callbacks arrive on a private serial queue, **not** on the main thread. They are
/// on the hot path of a live recording: do not block them.
public protocol ScreenCapturing: AnyObject {
    var delegate: ScreenCaptureDelegate? { get set }
    var isRunning: Bool { get }

    /// Everything ScreenCaptureKit currently considers recordable.
    /// Throws `RecorderError.screenRecordingPermissionDenied` when TCC says no.
    func availableContent() async throws -> ShareableContentSnapshot

    func start(target: CaptureTarget, configuration: RecordingConfiguration) async throws
    func stop() async
}

public protocol ScreenCaptureDelegate: AnyObject {
    func screenCapturer(_ capturer: ScreenCapturing, didOutputVideo sampleBuffer: CMSampleBuffer)
    /// System audio: what the meeting app and every other app is playing.
    func screenCapturer(_ capturer: ScreenCapturing, didOutputSystemAudio sampleBuffer: CMSampleBuffer)
    /// Microphone delivered by ScreenCaptureKit itself (macOS 15+). On macOS 14 the
    /// mic arrives through `MicrophoneCapturing` instead and this is never called.
    func screenCapturer(_ capturer: ScreenCapturing, didOutputMicrophone sampleBuffer: CMSampleBuffer)
    func screenCapturer(_ capturer: ScreenCapturing, didStopWith error: RecorderError)
}

public extension ScreenCaptureDelegate {
    func screenCapturer(_ capturer: ScreenCapturing, didOutputMicrophone sampleBuffer: CMSampleBuffer) {}
}

/// Separate microphone capture, used on macOS 14 and whenever the user picks a
/// specific input device.
public protocol MicrophoneCapturing: AnyObject {
    var delegate: MicrophoneCaptureDelegate? { get set }
    var isRunning: Bool { get }

    /// Input devices, for the settings picker. First element is the system default.
    func availableDevices() -> [AudioInputDevice]

    /// `deviceUID` nil means "system default input".
    func start(deviceUID: String?) async throws
    func stop() async
}

public protocol MicrophoneCaptureDelegate: AnyObject {
    func microphoneCapturer(_ capturer: MicrophoneCapturing, didOutput sampleBuffer: CMSampleBuffer)
    func microphoneCapturer(_ capturer: MicrophoneCapturing, didStopWith error: RecorderError)
}

public struct AudioInputDevice: Sendable, Equatable, Identifiable, Hashable {
    /// `AVCaptureDevice.uniqueID`.
    public let id: String
    public let name: String
    public let isDefault: Bool

    public init(id: String, name: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

/// TCC permission state, kept behind a protocol so the UI can be previewed
/// in every combination of granted/denied.
public protocol PermissionChecking: AnyObject {
    func status(for kind: PermissionKind) -> PermissionStatus
    /// Triggers the system prompt when the status is `.notDetermined`.
    @discardableResult
    func request(_ kind: PermissionKind) async -> PermissionStatus
    /// Opens the relevant System Settings pane; the only fix once a permission is denied.
    func openSystemSettings(for kind: PermissionKind)
}
