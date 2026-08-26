import Foundation
import ScreenCaptureKit
import CoreMedia
import AppKit
import os
import AizuchiCore

/// `ScreenCapturing` on top of ScreenCaptureKit: screen + system audio, and (macOS
/// 15+, when asked) the microphone.
///
/// `SCStreamConfiguration.capturesAudio` — no virtual audio driver required — is the
/// entire reason Aizuchi exists (see docs/ARCHITECTURE.md), so this type is the most
/// carefully-built one in the module.
public final class SCStreamScreenCapturer: NSObject, ScreenCapturing {
    public weak var delegate: ScreenCaptureDelegate?

    public var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return runningStream != nil
    }

    // Each SCStreamOutputType gets its own serial queue: callbacks are on the hot
    // recording path and must never block each other (a slow audio consumer must
    // never stall video delivery, and vice versa). Per docs/AGENT_GUIDE.md, none of
    // these callbacks may block.
    private let videoQueue = DispatchQueue(label: "app.aizuchi.capture.screen.video")
    private let audioQueue = DispatchQueue(label: "app.aizuchi.capture.screen.audio")
    private let microphoneQueue = DispatchQueue(label: "app.aizuchi.capture.screen.microphone")

    private let stateLock = NSLock()
    private var runningStream: SCStream?

    private var disappearanceObserver: NSObjectProtocol?
    private var watchedBundleIdentifier: String?

    public override init() {
        super.init()
    }

    deinit {
        if let disappearanceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(disappearanceObserver)
        }
    }

    public func availableContent() async throws -> ShareableContentSnapshot {
        do {
            return try await SCShareableContentAdapter.fetchSnapshot()
        } catch {
            throw ScreenCaptureErrorTranslator.translate(error, context: .availableContent)
        }
    }

    public func start(target: CaptureTarget, configuration: RecordingConfiguration) async throws {
        guard !isRunning else {
            throw RecorderError.alreadyRecording
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw ScreenCaptureErrorTranslator.translate(error, context: .availableContent)
        }

        let snapshot = SCShareableContentAdapter.snapshot(from: content)
        guard ContentFilterBuilder.targetExists(target, in: snapshot) else {
            throw RecorderError.captureTargetDisappeared
        }

        let filter: SCContentFilter
        do {
            filter = try ContentFilterBuilder.makeFilter(for: target, content: content, ownBundleIdentifier: Bundle.main.bundleIdentifier)
        } catch {
            throw ScreenCaptureErrorTranslator.translate(error, context: .startCapture)
        }

        let streamConfiguration = StreamConfigurationBuilder.makeConfiguration(
            from: configuration,
            // `nil` = system default input. A specific device selection is handled
            // by `AVCaptureMicrophoneCapturer` on macOS 14; wiring a chosen device
            // into SCStream's own mic capture on macOS 15+ is left for the
            // integration pass once `RecordingCoordinator` can supply the UID.
            microphoneDeviceID: nil
        )

        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
            if configuration.capturesSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            }
            if #available(macOS 15.0, *), configuration.capturesMicrophone {
                try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: microphoneQueue)
            }
        } catch {
            throw RecorderError.captureStartFailed(error.localizedDescription)
        }

        do {
            try await stream.startCapture()
        } catch {
            throw ScreenCaptureErrorTranslator.translate(error, context: .startCapture)
        }

        stateLock.lock()
        runningStream = stream
        stateLock.unlock()

        observeTargetDisappearance(for: target, in: snapshot)
    }

    public func stop() async {
        stateLock.lock()
        let streamToStop = runningStream
        runningStream = nil
        stateLock.unlock()

        removeDisappearanceObserver()

        guard let streamToStop else { return }
        do {
            try await streamToStop.stopCapture()
        } catch {
            Log.capture.error("SCStream.stopCapture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Target disappearance
    //
    // Two independent signals, per docs/TASKS.md ("SCStream 側のエラーでも検知できる
    // ので両方でよい"):
    //  1. The owning application terminates (`NSWorkspace` notification) — catches
    //     the case where the whole app quits.
    //  2. ScreenCaptureKit itself stops the stream when the captured window/app is
    //     gone (`SCStreamDelegate.stream(_:didStopWithError:)` below) — catches a
    //     single window closing while its app stays open.

    private func observeTargetDisappearance(for target: CaptureTarget, in snapshot: ShareableContentSnapshot) {
        removeDisappearanceObserver()
        guard let bundleIdentifier = TargetWatch.bundleIdentifierToWatch(for: target, in: snapshot) else { return }

        watchedBundleIdentifier = bundleIdentifier
        disappearanceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            guard let terminated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            guard terminated.bundleIdentifier == self.watchedBundleIdentifier else { return }
            self.handleTargetDisappeared()
        }
    }

    private func removeDisappearanceObserver() {
        if let disappearanceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(disappearanceObserver)
        }
        disappearanceObserver = nil
        watchedBundleIdentifier = nil
    }

    private func handleTargetDisappeared() {
        stateLock.lock()
        let streamToStop = runningStream
        runningStream = nil
        stateLock.unlock()
        guard streamToStop != nil else { return }

        removeDisappearanceObserver()
        delegate?.screenCapturer(self, didStopWith: .captureTargetDisappeared)

        Task {
            try? await streamToStop?.stopCapture()
        }
    }
}

// MARK: - SCStreamOutput

extension SCStreamScreenCapturer: SCStreamOutput {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }

        if type == .screen {
            // Discard everything but `.complete` frames (idle/blank/suspended) so the
            // writer never sees duplicated or stale video. See `FrameStatus`.
            guard FrameStatus.isComplete(sampleBuffer) else { return }
            delegate?.screenCapturer(self, didOutputVideo: sampleBuffer)
            return
        }
        if type == .audio {
            delegate?.screenCapturer(self, didOutputSystemAudio: sampleBuffer)
            return
        }
        if #available(macOS 15.0, *), type == .microphone {
            delegate?.screenCapturer(self, didOutputMicrophone: sampleBuffer)
            return
        }
        // Unknown/future SCStreamOutputType case: nothing to forward.
    }
}

// MARK: - SCStreamDelegate

extension SCStreamScreenCapturer: SCStreamDelegate {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        stateLock.lock()
        let wasRunning = runningStream != nil
        runningStream = nil
        stateLock.unlock()
        guard wasRunning else { return }

        removeDisappearanceObserver()
        let recorderError = ScreenCaptureErrorTranslator.translate(error, context: .streamStopped)
        delegate?.screenCapturer(self, didStopWith: recorderError)
    }
}
