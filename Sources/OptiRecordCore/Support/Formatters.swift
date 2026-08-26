import Foundation

public enum Formatters {
    /// `01:23:45` while recording, `23:45` under an hour.
    public static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    public static func fileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(bytes, 0))
    }

    public static func bitrate(_ bitsPerSecond: Int) -> String {
        let mbps = Double(bitsPerSecond) / 1_000_000
        return String(format: "%.1f Mbps", mbps)
    }

    /// "1080p30 · H.264 · 5.0 Mbps" for the settings summary line.
    public static func configurationSummary(_ configuration: RecordingConfiguration) -> String {
        let codec = configuration.codec == .h264 ? "H.264" : "HEVC"
        return "\(configuration.width)×\(configuration.height)@\(configuration.frameRate)fps · \(codec) · \(bitrate(configuration.videoBitrate))"
    }
}

/// Free space on the volume that holds a directory, used to refuse a recording
/// that would fill the disk halfway through a meeting.
public enum DiskSpace {
    /// `url` must be a directory that exists; the key is only reported for real volumes.
    public static func availableBytes(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return capacity
    }

    /// Seconds of recording the remaining space allows at the configured bitrate.
    public static func estimatedRemainingSeconds(availableBytes: Int64, configuration: RecordingConfiguration) -> TimeInterval {
        let perSecond = max(configuration.estimatedBytesPerSecond, 1)
        return TimeInterval(availableBytes) / TimeInterval(perSecond)
    }
}
