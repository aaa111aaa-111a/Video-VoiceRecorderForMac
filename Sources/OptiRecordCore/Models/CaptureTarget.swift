import Foundation
import CoreGraphics

/// What the user chose to record.
public enum CaptureTarget: Hashable, Sendable, Codable {
    /// A whole display, including every app's audio on it.
    case display(id: UInt32)
    /// A single window. Audio follows the owning application.
    case window(id: UInt32)
    /// One application's windows on a given display, and only that app's audio.
    case application(bundleIdentifier: String, displayID: UInt32)

    public var displayID: UInt32? {
        switch self {
        case .display(let id): return id
        case .application(_, let displayID): return displayID
        case .window: return nil
        }
    }

    public var kind: Kind {
        switch self {
        case .display: return .display
        case .window: return .window
        case .application: return .application
        }
    }

    public enum Kind: String, Sendable, CaseIterable {
        case display, window, application

        public var localizedName: String {
            switch self {
            case .display: return "画面全体"
            case .window: return "ウインドウ"
            case .application: return "アプリケーション"
            }
        }
    }
}

/// A snapshot of what ScreenCaptureKit says is recordable right now.
public struct ShareableContentSnapshot: Sendable, Equatable {
    public struct Display: Sendable, Equatable, Identifiable {
        public let id: UInt32
        public let name: String
        public let width: Int
        public let height: Int
        public let scaleFactor: CGFloat
        public let isMain: Bool

        public init(id: UInt32, name: String, width: Int, height: Int, scaleFactor: CGFloat, isMain: Bool) {
            self.id = id
            self.name = name
            self.width = width
            self.height = height
            self.scaleFactor = scaleFactor
            self.isMain = isMain
        }
    }

    public struct Window: Sendable, Equatable, Identifiable {
        public let id: UInt32
        public let title: String
        public let applicationName: String
        public let bundleIdentifier: String?
        public let frame: CGRect
        public let isOnScreen: Bool

        public init(id: UInt32, title: String, applicationName: String, bundleIdentifier: String?, frame: CGRect, isOnScreen: Bool) {
            self.id = id
            self.title = title
            self.applicationName = applicationName
            self.bundleIdentifier = bundleIdentifier
            self.frame = frame
            self.isOnScreen = isOnScreen
        }
    }

    public struct Application: Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let processID: Int32
        public let windowCount: Int

        public init(id: String, name: String, processID: Int32, windowCount: Int) {
            self.id = id
            self.name = name
            self.processID = processID
            self.windowCount = windowCount
        }

        public var bundleIdentifier: String { id }
    }

    public let displays: [Display]
    public let windows: [Window]
    public let applications: [Application]

    public init(displays: [Display], windows: [Window], applications: [Application]) {
        self.displays = displays
        self.windows = windows
        self.applications = applications
    }

    public static let empty = ShareableContentSnapshot(displays: [], windows: [], applications: [])

    public var mainDisplay: Display? {
        displays.first(where: { $0.isMain }) ?? displays.first
    }

    /// Applications that look like a running meeting, best candidate first.
    public var meetingApplications: [Application] {
        applications
            .filter { MeetingAppCatalog.isMeetingApp(bundleIdentifier: $0.id) }
            .sorted { lhs, rhs in
                let l = MeetingAppCatalog.match(bundleIdentifier: lhs.id)?.priority ?? 99
                let r = MeetingAppCatalog.match(bundleIdentifier: rhs.id)?.priority ?? 99
                if l != r { return l < r }
                return lhs.name < rhs.name
            }
    }

    public func display(id: UInt32) -> Display? { displays.first { $0.id == id } }
    public func window(id: UInt32) -> Window? { windows.first { $0.id == id } }
    public func application(bundleIdentifier: String) -> Application? {
        applications.first { $0.id == bundleIdentifier }
    }

    /// Human readable label for a target, used in the UI and in file names.
    public func label(for target: CaptureTarget) -> String? {
        switch target {
        case .display(let id):
            return display(id: id).map { $0.name }
        case .window(let id):
            guard let window = window(id: id) else { return nil }
            return window.title.isEmpty ? window.applicationName : window.title
        case .application(let bundleIdentifier, _):
            return application(bundleIdentifier: bundleIdentifier)?.name ?? bundleIdentifier
        }
    }
}
