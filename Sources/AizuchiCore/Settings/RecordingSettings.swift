import Foundation
import CoreGraphics

public enum VideoQualityPreset: String, Codable, CaseIterable, Sendable, Identifiable {
    case p720, p1080, p1440, native

    public var id: String { rawValue }

    /// Long-edge cap in points. `nil` keeps the source resolution.
    public var maximumHeight: Int? {
        switch self {
        case .p720: return 720
        case .p1080: return 1080
        case .p1440: return 1440
        case .native: return nil
        }
    }

    public var localizedName: String {
        switch self {
        case .p720: return "720p（軽量）"
        case .p1080: return "1080p（推奨）"
        case .p1440: return "1440p"
        case .native: return "元の解像度"
        }
    }
}

public enum VideoCodecPreference: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Widest compatibility, larger files.
    case h264
    /// Roughly 30% smaller at the same quality; hardware encoded on Apple Silicon.
    case hevc

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .h264: return "H.264（互換性重視）"
        case .hevc: return "HEVC / H.265（容量重視）"
        }
    }
}

public enum ContainerFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    case mp4, mov

    public var id: String { rawValue }
    public var fileExtension: String { rawValue }

    public var localizedName: String {
        switch self {
        case .mp4: return "MP4"
        case .mov: return "QuickTime (MOV)"
        }
    }
}

public enum FrameRatePreset: Int, Codable, CaseIterable, Sendable, Identifiable {
    case fps10 = 10
    case fps15 = 15
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60

    public var id: Int { rawValue }
    public var fps: Int { rawValue }

    public var localizedName: String {
        switch self {
        case .fps15: return "15 fps（会議に十分）"
        case .fps30: return "30 fps（推奨）"
        default: return "\(rawValue) fps"
        }
    }
}

/// Everything the user can configure. Codable so it round-trips through UserDefaults.
public struct RecordingSettings: Codable, Equatable, Sendable {
    // MARK: Video
    public var quality: VideoQualityPreset
    public var frameRate: FrameRatePreset
    public var codec: VideoCodecPreference
    public var container: ContainerFormat
    /// nil = derive from resolution and frame rate.
    public var manualVideoBitrate: Int?
    public var showsCursor: Bool

    // MARK: Audio
    public var systemAudioEnabled: Bool
    public var microphoneEnabled: Bool
    /// `AVCaptureDevice.uniqueID`. nil = system default input.
    public var microphoneDeviceUID: String?
    /// Linear gain, 0...4 (0 dB == 1.0).
    public var microphoneGain: Float
    public var systemAudioGain: Float
    /// Write mic-only and system-only m4a files next to the video, for transcription.
    public var writesSeparateAudioFiles: Bool
    /// Keep our own alert sounds out of the recording.
    public var excludesOwnAudio: Bool

    // MARK: Output
    /// Security-scoped bookmark for the chosen folder; nil = ~/Movies/Aizuchi.
    public var outputDirectoryBookmark: Data?
    public var fileNameTemplate: String

    // MARK: Behaviour
    public var launchAtLogin: Bool
    /// Hide our own windows from the capture so the recording does not show the recorder.
    public var excludesOwnWindows: Bool
    /// Stop automatically when the recorded meeting app quits.
    public var stopsWhenTargetDisappears: Bool
    /// Reveal the finished file in Finder.
    public var revealsInFinderWhenDone: Bool
    /// Warn (and stop) below this many megabytes of free disk space.
    public var minimumFreeDiskMegabytes: Int
    /// Carbon key code + modifier flags for the global start/stop shortcut.
    public var startStopHotKey: HotKeyBinding?

    public init(
        quality: VideoQualityPreset = .p1080,
        frameRate: FrameRatePreset = .fps30,
        codec: VideoCodecPreference = .h264,
        container: ContainerFormat = .mp4,
        manualVideoBitrate: Int? = nil,
        showsCursor: Bool = true,
        systemAudioEnabled: Bool = true,
        microphoneEnabled: Bool = true,
        microphoneDeviceUID: String? = nil,
        microphoneGain: Float = 1.0,
        systemAudioGain: Float = 1.0,
        writesSeparateAudioFiles: Bool = false,
        excludesOwnAudio: Bool = true,
        outputDirectoryBookmark: Data? = nil,
        fileNameTemplate: String = OutputFileNaming.defaultTemplate,
        launchAtLogin: Bool = false,
        excludesOwnWindows: Bool = true,
        stopsWhenTargetDisappears: Bool = true,
        revealsInFinderWhenDone: Bool = true,
        minimumFreeDiskMegabytes: Int = 1024,
        startStopHotKey: HotKeyBinding? = .defaultStartStop
    ) {
        self.quality = quality
        self.frameRate = frameRate
        self.codec = codec
        self.container = container
        self.manualVideoBitrate = manualVideoBitrate
        self.showsCursor = showsCursor
        self.systemAudioEnabled = systemAudioEnabled
        self.microphoneEnabled = microphoneEnabled
        self.microphoneDeviceUID = microphoneDeviceUID
        self.microphoneGain = microphoneGain
        self.systemAudioGain = systemAudioGain
        self.writesSeparateAudioFiles = writesSeparateAudioFiles
        self.excludesOwnAudio = excludesOwnAudio
        self.outputDirectoryBookmark = outputDirectoryBookmark
        self.fileNameTemplate = fileNameTemplate
        self.launchAtLogin = launchAtLogin
        self.excludesOwnWindows = excludesOwnWindows
        self.stopsWhenTargetDisappears = stopsWhenTargetDisappears
        self.revealsInFinderWhenDone = revealsInFinderWhenDone
        self.minimumFreeDiskMegabytes = minimumFreeDiskMegabytes
        self.startStopHotKey = startStopHotKey
    }

    public static let `default` = RecordingSettings()

    public func gain(for source: AudioSource) -> Float {
        switch source {
        case .system: return systemAudioGain
        case .microphone: return microphoneGain
        }
    }

    public func isEnabled(_ source: AudioSource) -> Bool {
        switch source {
        case .system: return systemAudioEnabled
        case .microphone: return microphoneEnabled
        }
    }

    public var enabledAudioSources: [AudioSource] {
        AudioSource.allCases.filter { isEnabled($0) }
    }

    public enum CodingKeys: String, CodingKey {
        case quality, frameRate, codec, container, manualVideoBitrate, showsCursor
        case systemAudioEnabled, microphoneEnabled, microphoneDeviceUID, microphoneGain, systemAudioGain
        case writesSeparateAudioFiles, excludesOwnAudio
        case outputDirectoryBookmark, fileNameTemplate
        case launchAtLogin, excludesOwnWindows, stopsWhenTargetDisappears, revealsInFinderWhenDone
        case minimumFreeDiskMegabytes, startStopHotKey
    }

    /// Decoding tolerates missing keys so a settings file written by an older build still loads.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = RecordingSettings.default

        func decode<T: Decodable>(_ key: CodingKeys, _ defaultValue: T) -> T {
            guard let decoded = try? values.decodeIfPresent(T.self, forKey: key) else { return defaultValue }
            return decoded ?? defaultValue
        }
        func decodeOptional<T: Decodable>(_ key: CodingKeys, _ type: T.Type) -> T? {
            guard let decoded = try? values.decodeIfPresent(T.self, forKey: key) else { return nil }
            return decoded
        }

        quality = decode(.quality, fallback.quality)
        frameRate = decode(.frameRate, fallback.frameRate)
        codec = decode(.codec, fallback.codec)
        container = decode(.container, fallback.container)
        manualVideoBitrate = decodeOptional(.manualVideoBitrate, Int.self)
        showsCursor = decode(.showsCursor, fallback.showsCursor)
        systemAudioEnabled = decode(.systemAudioEnabled, fallback.systemAudioEnabled)
        microphoneEnabled = decode(.microphoneEnabled, fallback.microphoneEnabled)
        microphoneDeviceUID = decodeOptional(.microphoneDeviceUID, String.self)
        microphoneGain = decode(.microphoneGain, fallback.microphoneGain)
        systemAudioGain = decode(.systemAudioGain, fallback.systemAudioGain)
        writesSeparateAudioFiles = decode(.writesSeparateAudioFiles, fallback.writesSeparateAudioFiles)
        excludesOwnAudio = decode(.excludesOwnAudio, fallback.excludesOwnAudio)
        outputDirectoryBookmark = decodeOptional(.outputDirectoryBookmark, Data.self)
        fileNameTemplate = decode(.fileNameTemplate, fallback.fileNameTemplate)
        launchAtLogin = decode(.launchAtLogin, fallback.launchAtLogin)
        excludesOwnWindows = decode(.excludesOwnWindows, fallback.excludesOwnWindows)
        stopsWhenTargetDisappears = decode(.stopsWhenTargetDisappears, fallback.stopsWhenTargetDisappears)
        revealsInFinderWhenDone = decode(.revealsInFinderWhenDone, fallback.revealsInFinderWhenDone)
        minimumFreeDiskMegabytes = decode(.minimumFreeDiskMegabytes, fallback.minimumFreeDiskMegabytes)
        startStopHotKey = decodeOptional(.startStopHotKey, HotKeyBinding.self)
    }
}

/// A global shortcut, stored as a Carbon key code plus `NSEvent.ModifierFlags` raw value.
public struct HotKeyBinding: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifierFlags: UInt

    public init(keyCode: UInt32, modifierFlags: UInt) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    /// ⌃⇧R — `kVK_ANSI_R` is 15; control (1 << 18) + shift (1 << 17).
    public static let defaultStartStop = HotKeyBinding(keyCode: 15, modifierFlags: (1 << 18) | (1 << 17))
}
