import XCTest
@testable import OptiRecordUI
@testable import OptiRecordCore

/// Exercises `RecorderViewModel` against `PreviewRecordingController`, without a
/// real capture pipeline. Each test gets its own `UserDefaults` suite so the
/// persistence tests (selected target, recent recordings) do not leak state
/// between runs.
@MainActor
final class RecorderViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "app.optirecord.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeSettingsStore() -> SettingsStore {
        SettingsStore(defaults: defaults, notificationCenter: NotificationCenter())
    }

    /// `controller` is optional rather than defaulted to a fresh instance: default
    /// argument expressions are evaluated in a nonisolated context, and
    /// `PreviewRecordingController` is main-actor isolated.
    private func makeViewModel(
        controller: PreviewRecordingController? = nil,
        silenceThreshold: TimeInterval = 5,
        now: @escaping () -> Date = Date.init
    ) -> RecorderViewModel {
        RecorderViewModel(
            controller: controller ?? PreviewRecordingController(initialState: .idle),
            settingsStore: makeSettingsStore(),
            defaults: defaults,
            silenceThreshold: silenceThreshold,
            now: now
        )
    }

    // MARK: Callback bridging

    func testControllerCallbacksReflectIntoPublishedProperties() {
        let controller = PreviewRecordingController(initialState: .idle)
        let viewModel = makeViewModel(controller: controller)

        controller.simulateState(.recording)
        XCTAssertEqual(viewModel.state, .recording)

        controller.simulateElapsed(42)
        XCTAssertEqual(viewModel.elapsed, 42)

        let levels: [AudioSource: AudioLevel] = [
            .system: AudioLevel(peak: -10, rms: -14),
            .microphone: AudioLevel(peak: -30, rms: -34)
        ]
        controller.simulateLevels(levels)
        XCTAssertEqual(viewModel.levels, levels)

        var finishedResult: Result<RecordingResult, RecorderError>?
        viewModel.onRecordingFinished = { finishedResult = $0 }
        let recording = RecordingResult(url: URL(fileURLWithPath: "/tmp/a.mp4"), duration: 10, fileSize: 100, startedAt: Date())
        controller.onFinish?(.success(recording))

        XCTAssertEqual(viewModel.recentRecordings.first, recording)
        // `Result` is not `Equatable` in the standard library, so unwrap by hand.
        guard case .success(let notifiedRecording) = finishedResult else {
            return XCTFail("Expected onRecordingFinished to be called with a success result")
        }
        XCTAssertEqual(notifiedRecording, recording)
    }

    // MARK: Start / stop availability

    func testStartIsDisabledWhileRecordingAndStopIsEnabled() {
        let controller = PreviewRecordingController(initialState: .idle)
        let viewModel = makeViewModel(controller: controller)

        XCTAssertTrue(viewModel.canStartRecording)
        XCTAssertFalse(viewModel.canStop)

        controller.simulateState(.recording)

        XCTAssertFalse(viewModel.canStartRecording)
        XCTAssertTrue(viewModel.canStop)
        XCTAssertTrue(viewModel.canPause)
        XCTAssertFalse(viewModel.canResume)
    }

    func testStartIsDisabledWithoutScreenRecordingPermission() {
        let controller = PreviewRecordingController(
            initialState: .idle,
            permissions: [.screenRecording: .denied, .microphone: .authorized]
        )
        let viewModel = makeViewModel(controller: controller)

        XCTAssertFalse(viewModel.canStartRecording)
    }

    // MARK: Elapsed display

    func testElapsedDisplayFormatsHoursMinutesSeconds() {
        let controller = PreviewRecordingController(initialState: .idle)
        let viewModel = makeViewModel(controller: controller)

        controller.simulateElapsed(65)
        XCTAssertEqual(viewModel.elapsedDisplay, "01:05")

        controller.simulateElapsed(3725)
        XCTAssertEqual(viewModel.elapsedDisplay, "1:02:05")
    }

    // MARK: Silence warning

    func testSilenceWarningRaisesAfterThresholdAndClearsWhenAudioReturns() {
        var now = Date()
        let controller = PreviewRecordingController(initialState: .recording)
        let viewModel = makeViewModel(controller: controller, silenceThreshold: 5, now: { now })

        let silence = AudioLevel(peak: -80, rms: -80)
        let loud = AudioLevel(peak: -10, rms: -12)

        controller.simulateLevels([.system: loud, .microphone: silence])
        XCTAssertFalse(viewModel.silentSources.contains(.microphone), "無音になった直後は警告しない")

        now = now.addingTimeInterval(3)
        controller.simulateLevels([.system: loud, .microphone: silence])
        XCTAssertFalse(viewModel.silentSources.contains(.microphone), "3秒ではまだ閾値未満")

        now = now.addingTimeInterval(2.5)
        controller.simulateLevels([.system: loud, .microphone: silence])
        XCTAssertTrue(viewModel.silentSources.contains(.microphone), "5秒を超えたら警告する")
        XCTAssertFalse(viewModel.silentSources.contains(.system), "音があるソースは警告しない")

        controller.simulateLevels([.system: loud, .microphone: loud])
        XCTAssertFalse(viewModel.silentSources.contains(.microphone), "音が戻ったら警告は消える")
    }

    func testSilenceWarningIgnoresDisabledSources() {
        let store = makeSettingsStore()
        store.update { $0.microphoneEnabled = false }
        var now = Date()
        let controller = PreviewRecordingController(initialState: .recording)
        let viewModel = RecorderViewModel(controller: controller, settingsStore: store, defaults: defaults, silenceThreshold: 5, now: { now })

        let silence = AudioLevel(peak: -80, rms: -80)
        controller.simulateLevels([.system: silence, .microphone: silence])
        now = now.addingTimeInterval(6)
        controller.simulateLevels([.system: silence, .microphone: silence])

        XCTAssertTrue(viewModel.silentSources.contains(.system))
        XCTAssertFalse(viewModel.silentSources.contains(.microphone), "無効化されたソースでは警告しない")
    }

    // MARK: Recent recordings cap

    func testRecentRecordingsAreCappedAtTwenty() {
        let controller = PreviewRecordingController(initialState: .idle)
        let viewModel = makeViewModel(controller: controller)

        for index in 0..<25 {
            let result = RecordingResult(
                url: URL(fileURLWithPath: "/tmp/recording-\(index).mp4"),
                duration: 60,
                fileSize: 1_000_000,
                startedAt: Date()
            )
            controller.onFinish?(.success(result))
        }

        XCTAssertEqual(viewModel.recentRecordings.count, 20)
        // Newest first: the very last one appended should be at the front.
        XCTAssertEqual(viewModel.recentRecordings.first?.url.lastPathComponent, "recording-24.mp4")
    }

    // MARK: Selected capture target persistence

    func testSelectedCaptureTargetIsPersistedAcrossViewModels() {
        let controllerA = PreviewRecordingController(initialState: .idle)
        let viewModelA = makeViewModel(controller: controllerA)
        viewModelA.selectedTarget = .application(bundleIdentifier: "us.zoom.xos", displayID: 1)

        let controllerB = PreviewRecordingController(initialState: .idle)
        let viewModelB = makeViewModel(controller: controllerB)

        XCTAssertEqual(viewModelB.selectedTarget, .application(bundleIdentifier: "us.zoom.xos", displayID: 1))
    }
}
