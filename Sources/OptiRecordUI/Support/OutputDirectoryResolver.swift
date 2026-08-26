import Foundation
import AppKit
import OptiRecordCore

/// Resolves `RecordingSettings.outputDirectoryBookmark` (a security-scoped
/// bookmark) back into a usable `URL`, and creates fresh bookmarks when the user
/// picks a new folder in `SettingsView`.
///
/// The app is not sandboxed today (see `Resources/OptiRecord.entitlements`), so a
/// plain `URL` would already work — bookmarks are used anyway because the task
/// contract calls for them and because it costs nothing to be ready for a future
/// sandboxed build.
enum OutputDirectoryResolver {
    static func resolve(from settings: RecordingSettings) -> URL {
        guard let bookmark = settings.outputDirectoryBookmark else {
            return OutputFileNaming.defaultDirectory
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return OutputFileNaming.defaultDirectory
        }
        return url
    }

    /// Bookmark data suitable for `RecordingSettings.outputDirectoryBookmark`.
    static func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Reveals the resolved output folder in Finder, creating it first if this is
    /// the very first recording and nobody has written to it yet.
    static func openInFinder(settings: RecordingSettings) {
        let url = resolve(from: settings)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
        NSWorkspace.shared.open(url)
    }
}
