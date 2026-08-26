import XCTest
@testable import OptiRecordCore
@testable import OptiRecordRecording

@MainActor
final class RecordingCoordinatorTests: XCTestCase {
    private var capturer: FakeScreenCapturer!
    private var microphone: FakeMicrophoneCapturer!
    private var mixer: FakeMixer!
    private var writer: FakeWriter!
    private var permissions: FakePermissionChecker!
    private var store: SettingsStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var directory: URL!
    private var states: [RecordingState] = []

    private let target = CaptureTarget.display(id: 1)

    override func setUp() async throws {
        try await super.setUp()
        capturer = FakeScreenCapturer()
        microphone = FakeMicrophoneCapturer()
        mixer = FakeMixer()
        writer = FakeWriter()
        permissions = FakePermissionChecker()
        suiteName = "app.optirecord.recording.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = SettingsStore(defaults: defaults)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("optirecord-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        states = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    private func makeCoordinator() -> RecordingCoordinator {
        let coordinator = RecordingCoordinator(
            screenCapturer: capturer,
            microphoneCapturer: microphone,
            mixer: mixer,
            permissions: permissions,
            settingsStore: store,
            makeWriter: { [writer] in writer! },
            resolveDirectory: { [directory] _ in directory! }
        )
        coordinator.onStateChange = { [weak self] state in self?.states.append(state) }
        return coordinator
    }

    /// Drives the main-actor queue until `condition` holds, so tests never guess at timing.
    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 2) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return condition()
    }

    // MARK: - Permissions

    func testRecordingIsRefusedWithoutScreenRecordingPermission() async {
        permissions.statuses[.screenRecording] = .denied
        let coordinator = makeCoordinator()

        await coordinator.start(target: target)

        XCTAssertEqual(coordinator.state, .failed(.screenRecordingPermissionDenied))
        XCTAssertEqual(capturer.startCount, 0)
        XCTAssertEqual(writer.startCount, 0)
    }

    func testAMissingMicrophoneDoesNotCostTheRecording() async {
        // Force the separate-capturer path by choosing a specific device, then break it.
        store.update { $0.microphoneDeviceUID = "usb-mic" }
        microphone.startError = RecorderError.microphoneUnavailable("抜かれています")
        let coordinator = makeCoordinator()

        await coordinator.start(target: target)

        XCTAssertEqual(coordinator.state, .recording)
        XCTAssertEqual(writer.startCount, 1)
    }

    // MARK: - State machine

    func testHappyPathStateSequence() async {
        let coordinator = makeCoordinator()

        await coordinator.start(target: target)
        XCTAssertEqual(coordinator.state, .recording)
        await coordinator.stop()

        XCTAssertEqual(states, [.preparing, .recording, .finishing, .idle])
        XCTAssertEqual(capturer.startCount, 1)
        XCTAssertEqual(capturer.stopCount, 1)
        XCTAssertEqual(writer.finishCount, 1)
        XCTAssertEqual(mixer.drainCount, 1)
    }

    func testStartIsIgnoredWhileAlreadyRecording() async {
        let coordinator = makeCoordinator()
        await coordinator.start(target: target)
        await coordinator.start(target: target)

        XCTAssertEqual(capturer.startCount, 1)
        XCTAssertEqual(writer.startCount, 1)
    }

    func testStopReportsTheResult() async {
        writer.result = RecordingResult(
            url: directory.appendingPathComponent("Zoom.mp4"),
            duration: 42,
            fileSize: 1_234_567,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )
        let coordinator = makeCoordinator()
        var finished: RecordingResult?
        coordinator.onFinish = { result in
            if case .success(let value) = result { finished = value }
        }

        await coordinator.start(target: target)
        await coordinator.stop()

        XCTAssertEqual(finished?.duration, 42)
        XCTAssertEqual(coordinator.lastResult?.fileSize, 1_234_567)
        XCTAssertEqual(finished?.targetLabel, "内蔵ディスプレイ")
    }

    func testWriterFailureSurfacesAsFailedState() async {
        writer.finishError = RecorderError.writerFailed("ディスクが外れました")
        let coordinator = makeCoordinator()
        var failure: RecorderError?
        coordinator.onFinish = { result in
            if case .failure(let error) = result { failure = error }
        }

        await coordinator.start(target: target)
        await coordinator.stop()

        XCTAssertEqual(failure, .writerFailed("ディスクが外れました"))
        XCTAssertEqual(coordinator.state, .failed(.writerFailed("ディスクが外れました")))
    }

    // MARK: - Pause

    func testElapsedDoesNotAdvanceWhilePaused() async {
        var now = Date(timeIntervalSince1970: 0)
        let coordinator = RecordingCoordinator(
            screenCapturer: capturer,
            microphoneCapturer: microphone,
            mixer: mixer,
            permissions: permissions,
            settingsStore: store,
            makeWriter: { [writer] in writer! },
            resolveDirectory: { [directory] _ in directory! },
            clock: { now }
        )
        // This test builds its own coordinator for the injected clock, so it has to
        // subscribe the way `makeCoordinator()` does.
        coordinator.onStateChange = { [weak self] state in self?.states.append(state) }

        await coordinator.start(target: target)
        now = now.addingTimeInterval(10)
        coordinator.pause()
        XCTAssertEqual(coordinator.state, .paused)

        // 30 seconds pass while paused; none of it should count.
        now = now.addingTimeInterval(30)
        coordinator.resume()
        now = now.addingTimeInterval(5)
        await coordinator.stop()

        XCTAssertEqual(coordinator.elapsed, 0, "stopping resets the displayed timer")
        XCTAssertEqual(states, [.preparing, .recording, .paused, .recording, .finishing, .idle])
    }

    func testPauseIsIgnoredWhenNotRecording() async {
        let coordinator = makeCoordinator()
        coordinator.pause()
        XCTAssertEqual(coordinator.state, .idle)
        coordinator.resume()
        XCTAssertEqual(coordinator.state, .idle)
    }

    // MARK: - Monitoring

    func testMonitoringMovesTheMetersWithoutWritingAFile() async {
        let coordinator = makeCoordinator()

        await coordinator.startMonitoring(target: target)

        XCTAssertEqual(capturer.startCount, 1)
        XCTAssertEqual(writer.startCount, 0, "monitoring must never create a file")
        XCTAssertEqual(mixer.prepareCount, 1)
        XCTAssertEqual(coordinator.state, .idle)

        mixer.emitLevel(AudioLevel(peak: -6, rms: -12), for: .system)
        let arrived = await waitUntil { coordinator.levels[.system] != nil }
        XCTAssertTrue(arrived)
        XCTAssertEqual(coordinator.levels[.system]?.peak, -6)
    }

    func testRecordingReusesAWarmMonitoringSession() async {
        let coordinator = makeCoordinator()

        await coordinator.startMonitoring(target: target)
        await coordinator.start(target: target)

        // The capture streams were already running: no restart, no second TCC prompt.
        XCTAssertEqual(capturer.startCount, 1)
        XCTAssertEqual(capturer.stopCount, 0)
        XCTAssertEqual(writer.startCount, 1)
        XCTAssertEqual(coordinator.state, .recording)
    }

    func testMonitoringADifferentTargetRestartsCapture() async {
        let coordinator = makeCoordinator()

        await coordinator.startMonitoring(target: target)
        await coordinator.start(target: .window(id: 10))

        XCTAssertEqual(capturer.startCount, 2)
        XCTAssertEqual(capturer.stopCount, 1)
        XCTAssertEqual(coordinator.state, .recording)
    }

    // MARK: - Failures mid-recording

    func testCaptureFailureStopsAndKeepsWhatWasRecorded() async {
        let coordinator = makeCoordinator()
        await coordinator.start(target: target)

        capturer.fail(with: .captureTargetDisappeared)

        let settled = await waitUntil { coordinator.state == .failed(.captureTargetDisappeared) }
        XCTAssertTrue(settled, "state was \(coordinator.state)")
        XCTAssertEqual(writer.finishCount, 1, "the recording so far must be saved, not discarded")
        XCTAssertEqual(writer.cancelCount, 0)
    }

    func testDiskSpaceIsCheckedBeforeStarting() async {
        // Ten terabytes free is a bar no CI runner clears.
        store.update { $0.minimumFreeDiskMegabytes = 10_000_000 }
        let coordinator = makeCoordinator()

        await coordinator.start(target: target)

        guard case .failed(let error) = coordinator.state else {
            return XCTFail("expected a failure, got \(coordinator.state)")
        }
        guard case .diskSpaceLow = error else {
            return XCTFail("expected diskSpaceLow, got \(error)")
        }
        XCTAssertEqual(writer.startCount, 0)
    }

    func testTargetThatDisappearedBeforeStarting() async {
        capturer.snapshot = .empty
        let coordinator = makeCoordinator()

        await coordinator.start(target: target)

        XCTAssertEqual(coordinator.state, .failed(.captureTargetDisappeared))
        XCTAssertEqual(writer.startCount, 0)
    }

    // MARK: - Configuration and audio controls

    func testConfigurationFollowsTheDisplayGeometry() async {
        store.update { $0.quality = .p1080 }
        let coordinator = makeCoordinator()

        await coordinator.start(target: target)

        // 1512x982 @2x -> 3024x1964, capped to 1080 tall.
        XCTAssertEqual(writer.configuration?.height, 1080)
        XCTAssertEqual(writer.configuration?.width, 1662)
        XCTAssertEqual(capturer.lastConfiguration?.height, 1080)
    }

    func testGainAndMuteReachTheMixerAndPersist() async {
        let coordinator = makeCoordinator()
        coordinator.setGain(1.8, for: .microphone)
        coordinator.setEnabled(false, for: .system)

        XCTAssertEqual(mixer.gains[.microphone], 1.8)
        XCTAssertEqual(mixer.muted[.system], true)
        XCTAssertEqual(store.load().microphoneGain, 1.8)
        XCTAssertFalse(store.load().systemAudioEnabled)
    }

    func testOnlyEnabledSourcesArePrepared() async {
        store.update { $0.microphoneEnabled = false }
        let coordinator = makeCoordinator()

        await coordinator.start(target: target)

        XCTAssertEqual(mixer.preparedSources, [.system])
        XCTAssertEqual(microphone.startCount, 0)
    }
}
