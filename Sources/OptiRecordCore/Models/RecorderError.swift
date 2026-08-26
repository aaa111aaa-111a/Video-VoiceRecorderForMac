import Foundation

/// Every failure the user can hit, with a Japanese message and a concrete next step.
public enum RecorderError: LocalizedError, Equatable, Sendable, Codable {
    case screenRecordingPermissionDenied
    case microphonePermissionDenied
    case noCaptureTargetAvailable
    case captureTargetDisappeared
    case captureStartFailed(String)
    case captureStopped(String)
    case microphoneUnavailable(String)
    case audioConversionFailed(String)
    case writerSetupFailed(String)
    case writerFailed(String)
    case outputDirectoryUnavailable(String)
    case diskSpaceLow(availableBytes: Int64)
    case alreadyRecording
    case notRecording
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionDenied:
            return "画面収録の権限がありません"
        case .microphonePermissionDenied:
            return "マイクの権限がありません"
        case .noCaptureTargetAvailable:
            return "録画できる画面・ウインドウが見つかりません"
        case .captureTargetDisappeared:
            return "録画対象のウインドウが閉じられました"
        case .captureStartFailed(let detail):
            return "画面キャプチャを開始できません: \(detail)"
        case .captureStopped(let detail):
            return "画面キャプチャが停止しました: \(detail)"
        case .microphoneUnavailable(let detail):
            return "マイクを使用できません: \(detail)"
        case .audioConversionFailed(let detail):
            return "音声の変換に失敗しました: \(detail)"
        case .writerSetupFailed(let detail):
            return "録画ファイルを準備できません: \(detail)"
        case .writerFailed(let detail):
            return "録画ファイルの書き込みに失敗しました: \(detail)"
        case .outputDirectoryUnavailable(let detail):
            return "保存先フォルダを使用できません: \(detail)"
        case .diskSpaceLow(let availableBytes):
            let mb = availableBytes / 1_048_576
            return "ディスクの空き容量が不足しています（残り \(mb) MB）"
        case .alreadyRecording:
            return "すでに録画中です"
        case .notRecording:
            return "録画していません"
        case .cancelled:
            return "録画をキャンセルしました"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .screenRecordingPermissionDenied:
            return "システム設定 > プライバシーとセキュリティ > 画面収録 で \(AppInfo.name) を許可してください。"
        case .microphonePermissionDenied:
            return "システム設定 > プライバシーとセキュリティ > マイク で \(AppInfo.name) を許可してください。"
        case .captureTargetDisappeared, .noCaptureTargetAvailable:
            return "録画対象を選び直してください。"
        case .microphoneUnavailable:
            return "別の入力デバイスを選ぶか、マイク録音をオフにしてください。"
        case .diskSpaceLow:
            return "不要なファイルを削除するか、保存先を空き容量のあるディスクに変更してください。"
        case .outputDirectoryUnavailable:
            return "設定から保存先フォルダを選び直してください。"
        default:
            return nil
        }
    }

    /// Failures where the recording in progress cannot continue.
    public var isFatalDuringRecording: Bool {
        switch self {
        case .writerFailed, .captureStopped, .diskSpaceLow, .captureTargetDisappeared:
            return true
        default:
            return false
        }
    }
}
