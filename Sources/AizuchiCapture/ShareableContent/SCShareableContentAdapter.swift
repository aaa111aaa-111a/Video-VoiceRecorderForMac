import ScreenCaptureKit
import AppKit
import CoreGraphics
import AizuchiCore

/// The only place in this module that touches real `SCShareableContent`. Fetches it
/// and flattens ScreenCaptureKit's own types into the plain `Raw*` values
/// `ShareableContentMapper` understands, so all the actual filtering/naming rules
/// live in one testable place.
enum SCShareableContentAdapter {
    /// `excludingDesktopWindows: false` leaves the Desktop picture/icons window in
    /// the result (harmless: it fails our own title/size filter anyway).
    /// `onScreenWindowsOnly: true` is the one that matters here — only windows
    /// actually visible right now are worth offering in the picker.
    static func fetchSnapshot() async throws -> ShareableContentSnapshot {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return snapshot(from: content)
    }

    static func snapshot(from content: SCShareableContent) -> ShareableContentSnapshot {
        let rawDisplays = content.displays.map { display in
            RawDisplay(displayID: display.displayID, width: display.width, height: display.height)
        }
        let rawWindows = content.windows.map { window in
            RawWindow(
                windowID: window.windowID,
                title: window.title,
                applicationName: window.owningApplication?.applicationName,
                bundleIdentifier: window.owningApplication?.bundleIdentifier,
                frame: window.frame,
                isOnScreen: window.isOnScreen
            )
        }
        let rawApplications = content.applications.map { application in
            RawApplication(
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.applicationName,
                processID: application.processID
            )
        }
        return ShareableContentMapper.snapshot(
            rawDisplays: rawDisplays,
            rawWindows: rawWindows,
            rawApplications: rawApplications,
            mainDisplayID: CGMainDisplayID(),
            metadataProvider: displayMetadata(for:)
        )
    }

    private static func displayMetadata(for displayID: UInt32) -> ShareableContentMapper.DisplayMetadata {
        guard let screen = NSScreen.screens.first(where: { screenDisplayID($0) == displayID }) else {
            return .unknown
        }
        return ShareableContentMapper.DisplayMetadata(name: screen.localizedName, scaleFactor: screen.backingScaleFactor)
    }

    // NOTE(uncertain): reading a display's CGDirectDisplayID back off an `NSScreen`
    // means digging into `deviceDescription`; the literal key string "NSScreenNumber"
    // is long-standing (used throughout Apple sample code and third-party projects)
    // but is not exposed as a typed Swift constant, so this is a string literal I
    // cannot verify compiles/behaves correctly without a compiler at hand. If it ever
    // fails to resolve, `ShareableContentMapper.mapDisplays`'s "Display N" fallback
    // name and the default 1x scale factor keep the rest of the feature working.
    private static func screenDisplayID(_ screen: NSScreen) -> UInt32? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return number.uint32Value
    }
}
