import Accelerate
import Foundation // for the free-function log10/sqrt (Darwin libm overlay) used below
import AizuchiCore

/// Peak / RMS in dBFS from raw Float32 samples. Pure math, no CoreMedia/AVFoundation
/// dependency, so it is trivial to unit test with a synthetic sine wave.
public enum LevelMeter {
    /// Digital silence floor. `20 * log10(0)` is `-infinity`; callers never see that here.
    public static let silenceFloorDecibels: Float = -160

    /// Peak absolute sample value (linear, 0...1-ish; can exceed 1 before clipping).
    public static func peakAmplitude(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        return peak
    }

    /// Mean of the squared samples (linear). Take `sqrt` of this for linear RMS amplitude.
    public static func meanSquare(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var meanSquare: Float = 0
        vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(samples.count))
        return meanSquare
    }

    /// `20 * log10(amplitude)`, clamped to `silenceFloorDecibels` so silence (or anything
    /// non-finite) never produces `-infinity` or `NaN`.
    public static func amplitudeToDecibels(_ amplitude: Float) -> Float {
        guard amplitude.isFinite, amplitude > 0 else { return silenceFloorDecibels }
        return max(20 * log10(amplitude), silenceFloorDecibels)
    }

    /// Peak/RMS of one block of samples, in dBFS.
    public static func level(of samples: [Float]) -> AudioLevel {
        let rmsAmplitude = sqrt(meanSquare(samples))
        return AudioLevel(
            peak: amplitudeToDecibels(peakAmplitude(samples)),
            rms: amplitudeToDecibels(rmsAmplitude)
        )
    }
}
