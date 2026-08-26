import AVFoundation
import AizuchiCore

/// Lists usable audio input devices for the settings picker.
enum MicrophoneDeviceEnumerator {
    /// `.microphone` is the macOS 14+ audio input device type. The deployment
    /// target is already macOS 14, so there is no older branch to keep; the fallback
    /// to `devices(for:)` only covers a discovery session that finds nothing.
    private static func discoveredDevices() -> [AVCaptureDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        let discovered = session.devices
        return discovered.isEmpty ? AVCaptureDevice.devices(for: .audio) : discovered
    }

    /// First element is the system default input, per the
    /// `MicrophoneCapturing.availableDevices()` contract.
    static func availableDevices() -> [AudioInputDevice] {
        let defaultDevice = AVCaptureDevice.default(for: .audio)
        let mapped = discoveredDevices().map { device in
            AudioInputDevice(id: device.uniqueID, name: device.localizedName, isDefault: device.uniqueID == defaultDevice?.uniqueID)
        }
        return mapped.sorted { $0.isDefault && !$1.isDefault }
    }

    static func device(uid: String) -> AVCaptureDevice? {
        AVCaptureDevice(uniqueID: uid)
    }
}
