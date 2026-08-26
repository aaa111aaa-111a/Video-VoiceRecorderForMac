import XCTest
import Foundation // for the free-functions sin/log10 (Darwin libm overlay) used below
@testable import OptiRecordAudio
import OptiRecordCore

final class LevelMeterTests: XCTestCase {
    /// 480 Hz at 48 kHz => an exact 100-sample period, so 4800 samples is exactly 48 whole
    /// periods and the discrete peak/RMS match the continuous sine's analytic values very
    /// precisely (no partial-period bias).
    func testSineWavePeakAndRMSMatchAnalyticValues() {
        let amplitude: Float = 0.5
        let sampleRate = 48_000.0
        let frequency = 480.0
        let frameCount = 4800
        let omega = 2.0 * Double.pi * frequency / sampleRate

        var samples = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            samples[i] = amplitude * Float(sin(omega * Double(i)))
        }

        let level = LevelMeter.level(of: samples)

        let expectedPeakDB = 20 * log10(amplitude)
        let expectedRMSDB = 20 * log10(amplitude / Float(2).squareRoot())

        XCTAssertEqual(level.peak, expectedPeakDB, accuracy: 0.1)
        XCTAssertEqual(level.rms, expectedRMSDB, accuracy: 0.1)
    }

    func testSilenceClampsToFloorNotInfinity() {
        let samples = [Float](repeating: 0, count: 1024)
        let level = LevelMeter.level(of: samples)

        XCTAssertEqual(level.peak, LevelMeter.silenceFloorDecibels)
        XCTAssertEqual(level.rms, LevelMeter.silenceFloorDecibels)
        XCTAssertTrue(level.peak.isFinite)
        XCTAssertTrue(level.rms.isFinite)
    }

    func testEmptyInputIsSilentNotNaN() {
        let level = LevelMeter.level(of: [])
        XCTAssertEqual(level.peak, LevelMeter.silenceFloorDecibels)
        XCTAssertEqual(level.rms, LevelMeter.silenceFloorDecibels)
    }

    func testFullScaleAmplitudeIsApproximatelyZeroDBFS() {
        let db = LevelMeter.amplitudeToDecibels(1.0)
        XCTAssertEqual(db, 0, accuracy: 0.001)
    }

    func testLouderSignalHasHigherLevelThanQuieterSignal() {
        let loud = LevelMeter.level(of: [Float](repeating: 0.8, count: 512))
        let quiet = LevelMeter.level(of: [Float](repeating: 0.1, count: 512))
        XCTAssertGreaterThan(loud.peak, quiet.peak)
        XCTAssertGreaterThan(loud.rms, quiet.rms)
    }
}
