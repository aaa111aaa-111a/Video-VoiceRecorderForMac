import Foundation

/// A conferencing app we know about, so the UI can preselect it and file names read nicely.
public struct MeetingApp: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let bundleIdentifiers: [String]
    /// Prefix match, for Chrome/Edge PWAs such as `com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan`.
    public let bundleIdentifierPrefixes: [String]
    /// Meet runs in a browser, so "record this app" also records other tabs' audio.
    public let isBrowser: Bool
    /// Lower sorts first when several meeting apps are running.
    public let priority: Int

    public init(id: String, name: String, bundleIdentifiers: [String], bundleIdentifierPrefixes: [String] = [], isBrowser: Bool = false, priority: Int) {
        self.id = id
        self.name = name
        self.bundleIdentifiers = bundleIdentifiers
        self.bundleIdentifierPrefixes = bundleIdentifierPrefixes
        self.isBrowser = isBrowser
        self.priority = priority
    }

    public func matches(bundleIdentifier: String) -> Bool {
        if bundleIdentifiers.contains(bundleIdentifier) { return true }
        return bundleIdentifierPrefixes.contains { bundleIdentifier.hasPrefix($0) }
    }
}

public enum MeetingAppCatalog {
    public static let zoom = MeetingApp(
        id: "zoom", name: "Zoom",
        bundleIdentifiers: ["us.zoom.xos"], priority: 0)

    public static let teams = MeetingApp(
        id: "teams", name: "Microsoft Teams",
        bundleIdentifiers: ["com.microsoft.teams", "com.microsoft.teams2"], priority: 1)

    public static let webex = MeetingApp(
        id: "webex", name: "Webex",
        bundleIdentifiers: ["Cisco-Systems.Spark", "com.webex.meetingmanager"], priority: 2)

    public static let slack = MeetingApp(
        id: "slack", name: "Slack",
        bundleIdentifiers: ["com.tinyspeck.slackmacgap"], priority: 3)

    public static let discord = MeetingApp(
        id: "discord", name: "Discord",
        bundleIdentifiers: ["com.hnc.Discord"], priority: 4)

    /// Google Meet has no native app: it lives in a browser tab or an installed PWA.
    public static let chrome = MeetingApp(
        id: "chrome", name: "Google Chrome",
        bundleIdentifiers: ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary"],
        bundleIdentifierPrefixes: ["com.google.Chrome.app."], isBrowser: true, priority: 5)

    public static let edge = MeetingApp(
        id: "edge", name: "Microsoft Edge",
        bundleIdentifiers: ["com.microsoft.edgemac"],
        bundleIdentifierPrefixes: ["com.microsoft.edgemac.app."], isBrowser: true, priority: 6)

    public static let safari = MeetingApp(
        id: "safari", name: "Safari",
        bundleIdentifiers: ["com.apple.Safari"], isBrowser: true, priority: 7)

    public static let arc = MeetingApp(
        id: "arc", name: "Arc",
        bundleIdentifiers: ["company.thebrowser.Browser"], isBrowser: true, priority: 8)

    public static let firefox = MeetingApp(
        id: "firefox", name: "Firefox",
        bundleIdentifiers: ["org.mozilla.firefox"], isBrowser: true, priority: 9)

    public static let all: [MeetingApp] = [zoom, teams, webex, slack, discord, chrome, edge, safari, arc, firefox]

    public static func match(bundleIdentifier: String) -> MeetingApp? {
        all.first { $0.matches(bundleIdentifier: bundleIdentifier) }
    }

    public static func isMeetingApp(bundleIdentifier: String) -> Bool {
        match(bundleIdentifier: bundleIdentifier) != nil
    }

    /// Short token used in generated file names, e.g. "Zoom" -> `Zoom_2026-08-26_14-03.mp4`.
    public static func shortName(bundleIdentifier: String) -> String? {
        match(bundleIdentifier: bundleIdentifier)?.name
    }
}
