import AizuchiAudio
import AizuchiCapture
import AizuchiCore

/// The composition root: the one place where the concrete capture, mixing and writing
/// types are chosen and wired together.
///
/// Everything else in the app talks to protocols from `AizuchiCore`, which is what lets
/// the coordinator's whole state machine be tested with fakes. This file is where that
/// abstraction gets cashed in for real ScreenCaptureKit and AVFoundation objects.
public enum RecordingStack {
    @MainActor
    public static func makeCoordinator(settingsStore: SettingsStore = SettingsStore()) -> RecordingCoordinator {
        RecordingCoordinator(
            screenCapturer: SCStreamScreenCapturer(),
            microphoneCapturer: AVCaptureMicrophoneCapturer(),
            mixer: TimelineMixer(),
            permissions: SystemPermissionChecker(),
            settingsStore: settingsStore,
            makeWriter: { AssetWriterMediaWriter() }
        )
    }
}
