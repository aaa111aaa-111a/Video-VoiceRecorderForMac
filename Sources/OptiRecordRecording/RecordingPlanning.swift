import CoreGraphics
import Foundation
import OptiRecordCore

/// Where the microphone comes from. Two sources exist and picking between them is a real
/// decision, so it is a named, tested function rather than an `if` buried in the coordinator.
public enum MicrophoneStrategy: String, Equatable, Sendable {
    /// Microphone recording is off.
    case none
    /// macOS 15+ with the system default input: ScreenCaptureKit delivers the microphone
    /// on the same clock as system audio, which is the best case for staying in sync.
    case screenCaptureKit
    /// macOS 14, or the user picked a specific input device: a separate `AVCaptureSession`.
    case avCapture

    public var usesSeparateCapturer: Bool { self == .avCapture }
}

public enum RecordingPlanner {
    public static func microphoneStrategy(
        capturesMicrophone: Bool,
        deviceUID: String?,
        supportsStreamMicrophone: Bool
    ) -> MicrophoneStrategy {
        guard capturesMicrophone else { return .none }
        // ScreenCaptureKit's own microphone capture always uses the system default input,
        // so an explicit device choice has to go through AVCaptureSession.
        if supportsStreamMicrophone && deviceUID == nil { return .screenCaptureKit }
        return .avCapture
    }

    /// True on the macOS versions where `SCStream` can capture the microphone itself.
    public static var systemSupportsStreamMicrophone: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }
}

/// Pixel geometry of whatever the user chose to record, so `RecordingConfiguration.resolve`
/// has something concrete to scale down from.
public struct SourceGeometry: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let scale: CGFloat

    public init(width: Int, height: Int, scale: CGFloat) {
        self.width = width
        self.height = height
        self.scale = scale
    }

    public static func resolve(target: CaptureTarget, snapshot: ShareableContentSnapshot) -> SourceGeometry? {
        switch target {
        case .display(let id):
            guard let display = snapshot.display(id: id) else { return nil }
            return SourceGeometry(width: display.width, height: display.height, scale: display.scaleFactor)

        case .application(_, let displayID):
            guard let display = snapshot.display(id: displayID) else { return nil }
            return SourceGeometry(width: display.width, height: display.height, scale: display.scaleFactor)

        case .window(let id):
            guard let window = snapshot.window(id: id) else { return nil }
            let width = Int(window.frame.width.rounded())
            let height = Int(window.frame.height.rounded())
            guard width > 0, height > 0 else { return nil }
            // A window has no scale factor of its own; use the display it is most likely on.
            let scale = snapshot.mainDisplay?.scaleFactor ?? 1
            return SourceGeometry(width: width, height: height, scale: scale)
        }
    }
}

/// Resolving the output folder, creating it, and refusing to start a recording that would
/// fill the disk halfway through a meeting.
public enum OutputLocation {
    public enum Failure: Error, Equatable {
        case directoryUnavailable(String)
        case diskSpaceLow(availableBytes: Int64)
    }

    /// Resolves the user's chosen folder from its bookmark, falling back to `~/Movies/OptiRecord`.
    /// Also starts security-scoped access when the bookmark carries it.
    public static func directory(from bookmark: Data?, fileManager: FileManager = .default) -> URL {
        guard let bookmark else { return OutputFileNaming.defaultDirectory }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            _ = url.startAccessingSecurityScopedResource()
            if isStale {
                Log.writer.notice("output folder bookmark is stale; the user may need to pick the folder again")
            }
            return url
        } catch {
            Log.writer.error("could not resolve the output folder bookmark, falling back to the default: \(String(describing: error), privacy: .public)")
            return OutputFileNaming.defaultDirectory
        }
    }

    public static func prepare(
        directory: URL,
        minimumFreeMegabytes: Int,
        fileManager: FileManager = .default
    ) throws -> URL {
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw Failure.directoryUnavailable(error.localizedDescription)
            }
        }
        guard fileManager.isWritableFile(atPath: directory.path) else {
            throw Failure.directoryUnavailable("書き込み権限がありません")
        }
        if let available = DiskSpace.availableBytes(at: directory) {
            let minimum = Int64(minimumFreeMegabytes) * 1_048_576
            if available < minimum {
                throw Failure.diskSpaceLow(availableBytes: available)
            }
        }
        return directory
    }

    public static func outputURL(
        directory: URL,
        settings: RecordingSettings,
        targetLabel: String?,
        date: Date = Date(),
        fileManager: FileManager = .default
    ) -> URL {
        let name = OutputFileNaming.fileName(
            template: settings.fileNameTemplate,
            sourceLabel: targetLabel,
            date: date
        )
        return OutputFileNaming.uniqueURL(
            directory: directory,
            fileName: name,
            fileExtension: settings.container.fileExtension
        ) { fileManager.fileExists(atPath: $0.path) }
    }
}
