import ScreenCaptureKit
import Foundation
import AizuchiCore

/// Turns a `CaptureTarget` into the `SCContentFilter` ScreenCaptureKit actually
/// captures.
///
/// Building the real filter needs a live `SCShareableContent` fetch to resolve our
/// plain IDs (`UInt32` display/window IDs, bundle identifier strings) into
/// ScreenCaptureKit's own display/window/application handles, so `makeFilter` itself
/// cannot be unit tested. The pieces that *can* be tested without ScreenCaptureKit —
/// which apps get excluded from a display capture, whether a target still exists —
/// are pure functions below, covered by `ContentFilterBuilderTests`.
enum ContentFilterBuilder {
    enum FilterError: Error, Equatable {
        case displayNotFound
        case windowNotFound
        case applicationNotFound
    }

    static func makeFilter(for target: CaptureTarget, content: SCShareableContent, ownBundleIdentifier: String?) throws -> SCContentFilter {
        switch target {
        case .display(let id):
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw FilterError.displayNotFound
            }
            // The caller passes a nil identifier when the user turned the
            // "exclude my own windows" setting off.
            let excludeIDs = bundleIdentifiersToExcludeFromDisplay(
                allBundleIdentifiers: content.applications.map(\.bundleIdentifier),
                ownBundleIdentifier: ownBundleIdentifier
            )
            let excludedApplications = content.applications.filter { excludeIDs.contains($0.bundleIdentifier) }
            return SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: [])

        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw FilterError.windowNotFound
            }
            return SCContentFilter(desktopIndependentWindow: window)

        case .application(let bundleIdentifier, let displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw FilterError.displayNotFound
            }
            guard let application = content.applications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
                throw FilterError.applicationNotFound
            }
            // Filtering by `including:` also scopes *audio* to just this
            // application's windows — this is what makes "record only Zoom, not the
            // Slack notification sound next to it" possible.
            return SCContentFilter(display: display, including: [application], exceptingWindows: [])
        }
    }

    /// Pure: which of the currently-running apps' windows should be excluded from a
    /// whole-display recording. Today that is only Aizuchi itself, matched by bundle
    /// identifier so this never depends on window titles or z-ordering.
    static func bundleIdentifiersToExcludeFromDisplay(allBundleIdentifiers: [String], ownBundleIdentifier: String?) -> Set<String> {
        guard let ownBundleIdentifier, allBundleIdentifiers.contains(ownBundleIdentifier) else { return [] }
        return [ownBundleIdentifier]
    }

    /// Pure: whether `target` still refers to something present in `snapshot`. Used
    /// as a cheap pre-check before resolving ScreenCaptureKit's own handles, so a
    /// stale target (window closed between the user picking it and pressing record)
    /// becomes `RecorderError.captureTargetDisappeared` instead of a raw, less
    /// meaningful `FilterError`.
    static func targetExists(_ target: CaptureTarget, in snapshot: ShareableContentSnapshot) -> Bool {
        switch target {
        case .display(let id):
            return snapshot.display(id: id) != nil
        case .window(let id):
            return snapshot.window(id: id) != nil
        case .application(let bundleIdentifier, let displayID):
            return snapshot.application(bundleIdentifier: bundleIdentifier) != nil && snapshot.display(id: displayID) != nil
        }
    }
}
