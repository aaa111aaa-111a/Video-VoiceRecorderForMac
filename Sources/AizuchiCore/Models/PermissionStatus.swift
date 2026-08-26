import Foundation

public enum PermissionStatus: String, Sendable, Equatable, Codable {
    case notDetermined
    case denied
    case restricted
    case authorized

    public var isAuthorized: Bool { self == .authorized }

    public var localizedName: String {
        switch self {
        case .notDetermined: return "未確認"
        case .denied: return "拒否されています"
        case .restricted: return "制限されています"
        case .authorized: return "許可済み"
        }
    }
}

public enum PermissionKind: String, Sendable, CaseIterable, Identifiable {
    case screenRecording
    case microphone

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .screenRecording: return "画面収録"
        case .microphone: return "マイク"
        }
    }

    /// Deep link into the right pane of System Settings.
    public var settingsURLString: String {
        switch self {
        case .screenRecording:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .microphone:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        }
    }

    public var explanation: String {
        switch self {
        case .screenRecording:
            return "画面とシステム音声（相手の声）の録音に必要です。"
        case .microphone:
            return "自分の声の録音に必要です。オフにすれば無しでも録画できます。"
        }
    }
}
