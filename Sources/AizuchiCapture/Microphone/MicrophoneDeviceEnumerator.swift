import AVFoundation
import AizuchiCore

/// Lists usable audio input devices for the settings picker.
enum MicrophoneDeviceEnumerator {
    // NOTE(uncertain): `AVCaptureDevice.DeviceType.microphone` is recalled as the
    // modern (macOS 14+ / iOS 17+) catch-all audio input device type introduced
    // alongside camera device-type unification; `.builtInMicrophone` is its
    // pre-macOS-14 equivalent. Both names carry some memory uncertainty — this
    // module's minimum deployment target is already macOS 14, so the `#available`
    // branch below is largely defensive, but the fallback to
    // `AVCaptureDevice.devices(for: .audio)` (a much older, solid API) is what
    // actually keeps this safe if either device-type name is wrong or a discovery
    // session yields nothing.
    private static func discoveredDevices() -> [AVCaptureDevice] {
        let deviceTypes: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            deviceTypes = [.microphone]
        } else {
            deviceTypes = [.builtInMicrophone]
        }
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .audio, position: .unspecified)
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
