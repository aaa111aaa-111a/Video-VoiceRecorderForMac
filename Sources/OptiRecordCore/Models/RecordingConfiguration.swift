import Foundation
import CoreGraphics

/// Settings resolved against a concrete capture source. This is what the capture
/// layer and the writer both consume, so they can never disagree about geometry.
public struct RecordingConfiguration: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var frameRate: Int
    public var codec: VideoCodecPreference
    public var videoBitrate: Int
    public var container: ContainerFormat
    public var showsCursor: Bool

    public var capturesSystemAudio: Bool
    public var capturesMicrophone: Bool
    public var excludesOwnAudio: Bool
    /// Keep OptiRecord's own windows out of a whole-display recording, so the video
    /// does not show the recorder that made it.
    public var excludesOwnWindows: Bool
    public var audioFormat: AudioStreamFormat
    public var writesSeparateAudioFiles: Bool

    public init(
        width: Int,
        height: Int,
        frameRate: Int,
        codec: VideoCodecPreference,
        videoBitrate: Int,
        container: ContainerFormat,
        showsCursor: Bool,
        capturesSystemAudio: Bool,
        capturesMicrophone: Bool,
        excludesOwnAudio: Bool,
        excludesOwnWindows: Bool = true,
        audioFormat: AudioStreamFormat = .canonical,
        writesSeparateAudioFiles: Bool = false
    ) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.codec = codec
        self.videoBitrate = videoBitrate
        self.container = container
        self.showsCursor = showsCursor
        self.capturesSystemAudio = capturesSystemAudio
        self.capturesMicrophone = capturesMicrophone
        self.excludesOwnAudio = excludesOwnAudio
        self.excludesOwnWindows = excludesOwnWindows
        self.audioFormat = audioFormat
        self.writesSeparateAudioFiles = writesSeparateAudioFiles
    }

    public var capturesAnyAudio: Bool { capturesSystemAudio || capturesMicrophone }

    /// Rough size estimate for the UI, in bytes per second.
    public var estimatedBytesPerSecond: Int {
        let audioBits = capturesAnyAudio ? 192_000 : 0
        return (videoBitrate + audioBits) / 8
    }

    /// Build a configuration for a source of the given pixel size.
    /// The result is always even-sized: H.264/HEVC encoders reject odd dimensions.
    public static func resolve(settings: RecordingSettings, sourceWidth: Int, sourceHeight: Int, sourceScale: CGFloat = 1) -> RecordingConfiguration {
        let scaledWidth = max(2, Int((CGFloat(sourceWidth) * sourceScale).rounded()))
        let scaledHeight = max(2, Int((CGFloat(sourceHeight) * sourceScale).rounded()))

        var width = scaledWidth
        var height = scaledHeight
        if let cap = settings.quality.maximumHeight, scaledHeight > cap {
            let ratio = CGFloat(cap) / CGFloat(scaledHeight)
            height = cap
            width = max(2, Int((CGFloat(scaledWidth) * ratio).rounded()))
        }
        width = evenClamped(width)
        height = evenClamped(height)

        let fps = settings.frameRate.fps
        let bitrate = settings.manualVideoBitrate
            ?? BitrateCalculator.recommendedBitrate(width: width, height: height, frameRate: fps, codec: settings.codec)

        return RecordingConfiguration(
            width: width,
            height: height,
            frameRate: fps,
            codec: settings.codec,
            videoBitrate: bitrate,
            container: settings.container,
            showsCursor: settings.showsCursor,
            capturesSystemAudio: settings.systemAudioEnabled,
            capturesMicrophone: settings.microphoneEnabled,
            excludesOwnAudio: settings.excludesOwnAudio,
            excludesOwnWindows: settings.excludesOwnWindows,
            audioFormat: .canonical,
            writesSeparateAudioFiles: settings.writesSeparateAudioFiles
        )
    }

    private static func evenClamped(_ value: Int) -> Int {
        let clamped = min(max(value, 2), 7680)
        return clamped % 2 == 0 ? clamped : clamped - 1
    }
}

/// Screen content compresses far better than camera footage, so the usual
/// bits-per-pixel tables are wasteful here. These numbers target "text stays sharp"
/// rather than "film grain survives".
public enum BitrateCalculator {
    public static let minimumBitrate = 1_000_000
    public static let maximumBitrate = 24_000_000

    public static func recommendedBitrate(width: Int, height: Int, frameRate: Int, codec: VideoCodecPreference) -> Int {
        let pixels = Double(width * height)
        let bitsPerPixelPerFrame: Double
        switch codec {
        case .h264: bitsPerPixelPerFrame = 0.055
        case .hevc: bitsPerPixelPerFrame = 0.038
        }
        // Frame rate helps sublinearly: a 60 fps screen recording is not twice the
        // information of a 30 fps one, because most frames barely change.
        let frameRateFactor = pow(Double(max(frameRate, 1)) / 30.0, 0.65)
        let raw = pixels * bitsPerPixelPerFrame * 30.0 * frameRateFactor
        let rounded = (raw / 100_000).rounded() * 100_000
        return min(max(Int(rounded), minimumBitrate), maximumBitrate)
    }
}
