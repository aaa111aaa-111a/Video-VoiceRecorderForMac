import Foundation

public enum RecordingState: Equatable, Sendable {
    case idle
    /// Permissions checked, capture starting, writer being set up.
    case preparing
    case recording
    case paused
    /// Stop requested; the writer is flushing to disk.
    case finishing
    case failed(RecorderError)

    public var isBusy: Bool {
        switch self {
        case .preparing, .finishing: return true
        default: return false
        }
    }

    public var isActive: Bool {
        switch self {
        case .recording, .paused: return true
        default: return false
        }
    }

    public var canStart: Bool {
        switch self {
        case .idle, .failed: return true
        default: return false
        }
    }

    public var localizedDescription: String {
        switch self {
        case .idle: return "待機中"
        case .preparing: return "準備中…"
        case .recording: return "録画中"
        case .paused: return "一時停止中"
        case .finishing: return "書き出し中…"
        case .failed(let error): return "エラー: \(error.localizedDescription)"
        }
    }
}

/// Everything a finished recording produced.
public struct RecordingResult: Equatable, Sendable, Identifiable, Codable {
    public var id: UUID
    public var url: URL
    public var duration: TimeInterval
    public var fileSize: Int64
    public var startedAt: Date
    public var targetLabel: String?
    /// Optional stems, written when `RecordingSettings.writesSeparateAudioFiles` is on.
    public var sidecarAudioURLs: [AudioSource: URL]

    public init(id: UUID = UUID(), url: URL, duration: TimeInterval, fileSize: Int64, startedAt: Date, targetLabel: String? = nil, sidecarAudioURLs: [AudioSource: URL] = [:]) {
        self.id = id
        self.url = url
        self.duration = duration
        self.fileSize = fileSize
        self.startedAt = startedAt
        self.targetLabel = targetLabel
        self.sidecarAudioURLs = sidecarAudioURLs
    }
}
