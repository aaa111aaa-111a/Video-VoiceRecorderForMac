import Foundation
import os

/// One logger per subsystem area. `log stream --predicate 'subsystem == "app.aizuchi.Aizuchi"'`
/// in Terminal shows everything while debugging a recording.
public enum Log {
    public static let subsystem = AppInfo.bundleIdentifier

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let audio = Logger(subsystem: subsystem, category: "audio")
    public static let writer = Logger(subsystem: subsystem, category: "writer")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
    public static let permissions = Logger(subsystem: subsystem, category: "permissions")
}
