import Foundation

/// The two things we record. Kept separate all the way to the mixer so the user
/// can mute one, ride its gain, and (optionally) get a per-source audio file.
public enum AudioSource: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Everything the Mac plays: the other participants' voices, shared videos, alerts.
    case system
    /// The local microphone: the user's own voice.
    case microphone

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .system: return "システム音声"
        case .microphone: return "マイク"
        }
    }

    public var symbolName: String {
        switch self {
        case .system: return "speaker.wave.2.fill"
        case .microphone: return "mic.fill"
        }
    }
}

/// Which track a buffer belongs to in the output file.
public enum AudioTrackKind: String, Codable, Sendable, CaseIterable {
    /// System + mic summed. Always written; this is what a normal player plays.
    case mixed
    /// System only, written to a sidecar file when the user wants clean stems.
    case system
    /// Mic only, written to a sidecar file.
    case microphone

    public var source: AudioSource? {
        switch self {
        case .mixed: return nil
        case .system: return .system
        case .microphone: return .microphone
        }
    }
}

/// Peak / RMS in dBFS. `-160` means digital silence.
public struct AudioLevel: Equatable, Sendable {
    public var peak: Float
    public var rms: Float

    public init(peak: Float, rms: Float) {
        self.peak = peak
        self.rms = rms
    }

    public static let silence = AudioLevel(peak: -160, rms: -160)

    public var isSilent: Bool { peak <= -60 }
    /// True once the signal is loud enough to clip.
    public var isClipping: Bool { peak >= -0.5 }

    /// 0...1 for a meter, with `floor` dBFS mapped to 0.
    public static func normalize(_ decibels: Float, floor: Float = -60) -> Float {
        guard decibels.isFinite else { return 0 }
        if decibels <= floor { return 0 }
        if decibels >= 0 { return 1 }
        return (decibels - floor) / -floor
    }

    public var normalizedPeak: Float { AudioLevel.normalize(peak) }
    public var normalizedRMS: Float { AudioLevel.normalize(rms) }

    /// Meters look jittery if they follow the signal exactly: rise fast, fall slowly.
    public func smoothed(towards new: AudioLevel, attack: Float = 1.0, release: Float = 0.2) -> AudioLevel {
        func blend(_ old: Float, _ next: Float) -> Float {
            let coefficient = next > old ? attack : release
            return old + (next - old) * coefficient
        }
        return AudioLevel(peak: blend(peak, new.peak), rms: blend(rms, new.rms))
    }
}

/// The canonical PCM format everything is converted to before mixing.
public struct AudioStreamFormat: Equatable, Sendable {
    public var sampleRate: Double
    public var channelCount: Int

    public init(sampleRate: Double, channelCount: Int) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    /// 48 kHz stereo float — what ScreenCaptureKit hands us, so it is the cheapest common ground.
    public static let canonical = AudioStreamFormat(sampleRate: 48_000, channelCount: 2)

    /// Frames per mix block. 1024 frames @ 48 kHz ≈ 21 ms.
    public static let mixBlockFrames = 1024
}
