import Foundation
import CoreGraphics
import OptiRecordCore

/// Turns raw, plain-value shareable content (`RawDisplay` / `RawWindow` /
/// `RawApplication`) into the `ShareableContentSnapshot` the rest of the app
/// consumes.
///
/// Kept free of ScreenCaptureKit and AppKit so every rule here — which windows are
/// worth showing to the user, which apps count as "has windows" — is a plain,
/// directly unit-testable function. `SCShareableContentAdapter` is the (thin, real)
/// glue that feeds this from an actual `SCShareableContent` fetch.
enum ShareableContentMapper {
    /// Windows narrower or shorter than this are capture debris (menu extras, 1x1
    /// shadow/helper windows) rather than something a user would ever choose to
    /// record.
    static let minimumWindowDimension: CGFloat = 40

    /// Per-display info we cannot know without AppKit (`NSScreen`) — kept as an
    /// injectable dependency so `mapDisplays`/`snapshot` stay pure and testable.
    struct DisplayMetadata {
        let name: String?
        let scaleFactor: CGFloat?

        init(name: String? = nil, scaleFactor: CGFloat? = nil) {
            self.name = name
            self.scaleFactor = scaleFactor
        }

        static let unknown = DisplayMetadata()
    }

    /// A window with no title, or with either dimension under
    /// `minimumWindowDimension`, is excluded from the picker.
    static func shouldInclude(window: RawWindow) -> Bool {
        guard let title = window.title, !title.isEmpty else { return false }
        guard window.frame.width >= minimumWindowDimension, window.frame.height >= minimumWindowDimension else { return false }
        return true
    }

    static func mapWindows(_ rawWindows: [RawWindow]) -> [ShareableContentSnapshot.Window] {
        rawWindows.filter(shouldInclude).map { window in
            ShareableContentSnapshot.Window(
                id: window.windowID,
                title: window.title ?? "",
                applicationName: window.applicationName ?? "",
                bundleIdentifier: window.bundleIdentifier,
                frame: window.frame,
                isOnScreen: window.isOnScreen
            )
        }
    }

    /// Apps that own none of `includedWindows` are excluded: a background/menu-bar
    /// agent with no shareable surface is not something a user can meaningfully pick
    /// from the "record this application" list.
    static func mapApplications(_ rawApplications: [RawApplication], includedWindows: [ShareableContentSnapshot.Window]) -> [ShareableContentSnapshot.Application] {
        rawApplications.compactMap { application in
            let windowCount = includedWindows.filter { $0.bundleIdentifier == application.bundleIdentifier }.count
            guard windowCount > 0 else { return nil }
            return ShareableContentSnapshot.Application(
                id: application.bundleIdentifier,
                name: application.applicationName,
                processID: application.processID,
                windowCount: windowCount
            )
        }
    }

    static func mapDisplays(
        _ rawDisplays: [RawDisplay],
        mainDisplayID: UInt32,
        metadataProvider: (UInt32) -> DisplayMetadata = { _ in .unknown }
    ) -> [ShareableContentSnapshot.Display] {
        rawDisplays.enumerated().map { index, display in
            let metadata = metadataProvider(display.displayID)
            return ShareableContentSnapshot.Display(
                id: display.displayID,
                name: metadata.name ?? "Display \(index + 1)",
                width: display.width,
                height: display.height,
                scaleFactor: metadata.scaleFactor ?? 1,
                isMain: display.displayID == mainDisplayID
            )
        }
    }

    static func snapshot(
        rawDisplays: [RawDisplay],
        rawWindows: [RawWindow],
        rawApplications: [RawApplication],
        mainDisplayID: UInt32,
        metadataProvider: (UInt32) -> DisplayMetadata = { _ in .unknown }
    ) -> ShareableContentSnapshot {
        let windows = mapWindows(rawWindows)
        let applications = mapApplications(rawApplications, includedWindows: windows)
        let displays = mapDisplays(rawDisplays, mainDisplayID: mainDisplayID, metadataProvider: metadataProvider)
        return ShareableContentSnapshot(displays: displays, windows: windows, applications: applications)
    }
}
