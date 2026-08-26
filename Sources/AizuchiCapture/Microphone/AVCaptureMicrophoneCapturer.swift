import AVFoundation
import CoreMedia
import Foundation
import AizuchiCore

/// `MicrophoneCapturing` on top of `AVCaptureSession`. Used on macOS 14 (where
/// `SCStream` cannot capture the microphone at all) and whenever the user picks a
/// specific input device rather than leaving `SCStream`'s own macOS 15+ microphone
/// capture on the system default.
public final class AVCaptureMicrophoneCapturer: NSObject, MicrophoneCapturing {
    public weak var delegate: MicrophoneCaptureDelegate?

    public var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isRunning
    }

    private let session = AVCaptureSession()
    private let outputQueue = DispatchQueue(label: "app.aizuchi.capture.microphone.output")
    private let sessionQueue = DispatchQueue(label: "app.aizuchi.capture.microphone.session")

    private let stateLock = NSLock()
    private var _isRunning = false

    private var currentDeviceUID: String?
    private var disconnectObserver: NSObjectProtocol?

    public override init() {
        super.init()
    }

    deinit {
        if let disconnectObserver {
            NotificationCenter.default.removeObserver(disconnectObserver)
        }
    }

    public func availableDevices() -> [AudioInputDevice] {
        MicrophoneDeviceEnumerator.availableDevices()
    }

    public func start(deviceUID: String?) async throws {
        guard !isRunning else { return }

        let device: AVCaptureDevice
        if let deviceUID, let match = MicrophoneDeviceEnumerator.device(uid: deviceUID) {
            device = match
        } else if let defaultDevice = AVCaptureDevice.default(for: .audio) {
            device = defaultDevice
        } else {
            throw RecorderError.microphoneUnavailable("マイクが見つかりません")
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw RecorderError.microphoneUnavailable(error.localizedDescription)
        }

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: outputQueue)

        session.beginConfiguration()
        for existingInput in session.inputs {
            session.removeInput(existingInput)
        }
        for existingOutput in session.outputs {
            session.removeOutput(existingOutput)
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw RecorderError.microphoneUnavailable("マイクの入力を追加できません")
        }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw RecorderError.microphoneUnavailable("マイクの出力を追加できません")
        }
        session.addOutput(output)
        session.commitConfiguration()

        currentDeviceUID = device.uniqueID
        observeDisconnect(of: device)

        // `startRunning()` blocks the calling thread until the session is up, so it
        // must never run on the caller's (potentially main-actor) context.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [session] in
                session.startRunning()
                continuation.resume()
            }
        }

        stateLock.lock()
        _isRunning = true
        stateLock.unlock()
    }

    public func stop() async {
        guard isRunning else { return }
        stateLock.lock()
        _isRunning = false
        stateLock.unlock()

        removeDisconnectObserver()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [session] in
                session.stopRunning()
                continuation.resume()
            }
        }
        currentDeviceUID = nil
    }

    private func observeDisconnect(of device: AVCaptureDevice) {
        removeDisconnectObserver()
        // NOTE(uncertain): `.AVCaptureDeviceWasDisconnected` is AVFoundation's
        // long-standing (pre-Swift-concurrency-era) notification name, bridged from
        // the Objective-C `AVCaptureDeviceWasDisconnectedNotification` constant. The
        // exact Swift-side spelling is not something this module can verify without a
        // compiler; if it has since been renamed, this observer simply never fires
        // and disconnect is only surfaced indirectly (the session stops delivering
        // sample buffers).
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            guard let disconnected = notification.object as? AVCaptureDevice, disconnected.uniqueID == self.currentDeviceUID else { return }
            self.handleDisconnect()
        }
    }

    private func removeDisconnectObserver() {
        if let disconnectObserver {
            NotificationCenter.default.removeObserver(disconnectObserver)
        }
        disconnectObserver = nil
    }

    private func handleDisconnect() {
        stateLock.lock()
        let wasRunning = _isRunning
        _isRunning = false
        stateLock.unlock()
        guard wasRunning else { return }

        removeDisconnectObserver()
        delegate?.microphoneCapturer(self, didStopWith: .microphoneUnavailable("マイクが切断されました"))

        Task { [sessionQueue, session] in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                sessionQueue.async {
                    session.stopRunning()
                    continuation.resume()
                }
            }
        }
    }
}

extension AVCaptureMicrophoneCapturer: AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        delegate?.microphoneCapturer(self, didOutput: sampleBuffer)
    }
}
