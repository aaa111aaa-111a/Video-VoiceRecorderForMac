import XCTest
@testable import AizuchiCore

final class FormattersTests: XCTestCase {
    func testDurationUnderAnHourOmitsHours() {
        XCTAssertEqual(Formatters.duration(0), "00:00")
        XCTAssertEqual(Formatters.duration(59), "00:59")
        XCTAssertEqual(Formatters.duration(75), "01:15")
    }

    func testDurationOverAnHourShowsHours() {
        XCTAssertEqual(Formatters.duration(3661), "1:01:01")
    }

    func testDurationRejectsGarbage() {
        XCTAssertEqual(Formatters.duration(-5), "00:00")
        XCTAssertEqual(Formatters.duration(.nan), "00:00")
        XCTAssertEqual(Formatters.duration(.infinity), "00:00")
    }
}

final class AudioLevelTests: XCTestCase {
    func testSilenceNormalizesToZero() {
        XCTAssertEqual(AudioLevel.silence.normalizedPeak, 0)
        XCTAssertTrue(AudioLevel.silence.isSilent)
    }

    func testFullScaleNormalizesToOne() {
        XCTAssertEqual(AudioLevel(peak: 0, rms: 0).normalizedPeak, 1)
        XCTAssertTrue(AudioLevel(peak: 0, rms: -3).isClipping)
    }

    func testMidLevelSitsInTheMiddle() {
        XCTAssertEqual(AudioLevel.normalize(-30), 0.5, accuracy: 0.0001)
    }

    func testMetersFallSlowerThanTheyRise() {
        let quiet = AudioLevel(peak: -60, rms: -60)
        let loud = AudioLevel(peak: -10, rms: -10)
        // Rising snaps straight to the new value.
        XCTAssertEqual(quiet.smoothed(towards: loud).peak, -10, accuracy: 0.0001)
        // Falling only travels part of the way.
        XCTAssertEqual(loud.smoothed(towards: quiet).peak, -20, accuracy: 0.0001)
    }
}

final class MeetingAppCatalogTests: XCTestCase {
    func testKnownMeetingApps() {
        XCTAssertEqual(MeetingAppCatalog.match(bundleIdentifier: "us.zoom.xos")?.name, "Zoom")
        XCTAssertEqual(MeetingAppCatalog.match(bundleIdentifier: "com.microsoft.teams2")?.name, "Microsoft Teams")
    }

    func testChromePWAsMatchByPrefix() {
        // Google Meet installed as a PWA gets a hashed bundle identifier.
        XCTAssertTrue(MeetingAppCatalog.isMeetingApp(bundleIdentifier: "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"))
    }

    func testUnrelatedAppsAreNotMeetings() {
        XCTAssertFalse(MeetingAppCatalog.isMeetingApp(bundleIdentifier: "com.apple.finder"))
    }

    func testMeetingAppsSortWithZoomFirst() {
        let snapshot = ShareableContentSnapshot(
            displays: [],
            windows: [],
            applications: [
                .init(id: "com.apple.Safari", name: "Safari", processID: 3, windowCount: 1),
                .init(id: "us.zoom.xos", name: "Zoom", processID: 1, windowCount: 2),
                .init(id: "com.apple.finder", name: "Finder", processID: 2, windowCount: 1)
            ]
        )
        XCTAssertEqual(snapshot.meetingApplications.map(\.name), ["Zoom", "Safari"])
    }
}

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "app.aizuchi.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testEmptyStoreReturnsDefaults() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), .default)
    }

    func testSettingsRoundTrip() {
        let store = SettingsStore(defaults: defaults)
        store.update {
            $0.microphoneEnabled = false
            $0.microphoneGain = 2.5
            $0.codec = .hevc
        }
        let loaded = store.load()
        XCTAssertFalse(loaded.microphoneEnabled)
        XCTAssertEqual(loaded.microphoneGain, 2.5)
        XCTAssertEqual(loaded.codec, .hevc)
    }

    func testSettingsFromAnOlderBuildStillLoad() throws {
        // Only two keys, as if written before the rest of the fields existed.
        let partial = #"{"microphoneEnabled":false,"codec":"hevc"}"#.data(using: .utf8)!
        defaults.set(partial, forKey: "recordingSettings")
        let loaded = SettingsStore(defaults: defaults).load()
        XCTAssertFalse(loaded.microphoneEnabled)
        XCTAssertEqual(loaded.codec, .hevc)
        XCTAssertEqual(loaded.quality, RecordingSettings.default.quality)
        XCTAssertEqual(loaded.fileNameTemplate, OutputFileNaming.defaultTemplate)
    }

    func testCorruptSettingsFallBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: "recordingSettings")
        XCTAssertEqual(SettingsStore(defaults: defaults).load(), .default)
    }

    func testResetClearsStoredSettings() {
        let store = SettingsStore(defaults: defaults)
        store.update { $0.systemAudioEnabled = false }
        store.reset()
        XCTAssertEqual(store.load(), .default)
    }
}
