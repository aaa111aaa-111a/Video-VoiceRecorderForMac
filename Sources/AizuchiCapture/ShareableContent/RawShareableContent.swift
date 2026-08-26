import Foundation
import CoreGraphics

/// Plain-value mirror of the `SCDisplay` fields `ShareableContentMapper` needs.
///
/// ScreenCaptureKit's real types (`SCDisplay`, `SCWindow`, `SCRunningApplication`)
/// cannot be constructed outside a live, TCC-authorized `SCShareableContent` fetch,
/// so there is no way to build one directly in a unit test. These `Raw*` types exist
/// purely so the *mapping rules* (which window counts as real, which app counts as
/// "has windows", display naming fallback, ...) can run under XCTest without
/// ScreenCaptureKit involved at all. See `SCShareableContentAdapter` for the (thin,
/// untestable) code that actually talks to ScreenCaptureKit and produces these.
struct RawDisplay: Equatable {
    let displayID: UInt32
    let width: Int
    let height: Int

    init(displayID: UInt32, width: Int, height: Int) {
        self.displayID = displayID
        self.width = width
        self.height = height
    }
}

struct RawWindow: Equatable {
    let windowID: UInt32
    let title: String?
    let applicationName: String?
    let bundleIdentifier: String?
    let frame: CGRect
    let isOnScreen: Bool

    init(windowID: UInt32, title: String?, applicationName: String?, bundleIdentifier: String?, frame: CGRect, isOnScreen: Bool) {
        self.windowID = windowID
        self.title = title
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.frame = frame
        self.isOnScreen = isOnScreen
    }
}

struct RawApplication: Equatable {
    let bundleIdentifier: String
    let applicationName: String
    let processID: Int32

    init(bundleIdentifier: String, applicationName: String, processID: Int32) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.processID = processID
    }
}
