import AppKit
import UserNotifications
import ServiceManagement
import AizuchiCore
import AizuchiUI

/// `NSApplicationDelegate` side of the app: things SwiftUI's `App`/`Scene` world
/// does not cover on its own — quit confirmation while recording, the login item,
/// the "recording finished" notification, and the global start/stop shortcut.
/// AppKit calls every delegate method on the main thread, and everything this
/// touches — the view model, its settings store — is main-actor isolated, so the
/// whole class is declared that way rather than sprinkling hops through it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyManager: HotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestNotificationAuthorizationIfNeeded()
        syncLoginItem()
        observeRecordingFinish()
        installHotKey()
    }

    /// Recording keeps running when the menu bar popover closes, so this is the
    /// only place left to make sure a quit does not silently throw the in-progress
    /// recording away.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewModel = AppEnvironment.shared.viewModel, viewModel.state.isActive else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "録画中です"
        alert.informativeText = "終了すると録画を停止して保存します。よろしいですか?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "録画を停止して終了")
        alert.addButton(withTitle: "キャンセル")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return .terminateCancel
        }

        Task { @MainActor in
            await viewModel.stop()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: Login item

    private func syncLoginItem() {
        guard let viewModel = AppEnvironment.shared.viewModel else { return }
        applyLoginItem(enabled: viewModel.settingsStore.settings.launchAtLogin)
    }

    /// NOTE(uncertain): `SMAppService` requires the app to be a signed, bundled
    /// `.app` (which is how `Scripts/build-app.sh` ships it, but not how `swift
    /// run` launches it) — every path here is best-effort so a bare executable, or
    /// an unsigned build, never crashes the app over this.
    func applyLoginItem(enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("ログイン項目の設定に失敗しました: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Notifications

    private func requestNotificationAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                Log.app.error("通知の許可取得に失敗しました: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func observeRecordingFinish() {
        AppEnvironment.shared.viewModel?.onRecordingFinished = { result in
            AppDelegate.notifyFinished(result)
        }
    }

    private static func notifyFinished(_ result: Result<RecordingResult, RecorderError>) {
        let content = UNMutableNotificationContent()
        switch result {
        case .success(let recording):
            content.title = "\(AppInfo.name): 録画が完了しました"
            content.body = "\(recording.url.lastPathComponent) ・ \(Formatters.duration(recording.duration))"
        case .failure(let error):
            content.title = "\(AppInfo.name): 録画でエラーが発生しました"
            content.body = error.localizedDescription
        }
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.app.error("通知の送信に失敗しました: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: Global shortcut

    private func installHotKey() {
        guard let viewModel = AppEnvironment.shared.viewModel else { return }
        let manager = HotKeyManager()
        hotKeyManager = manager
        manager.register(binding: viewModel.settingsStore.settings.startStopHotKey) {
            Task { @MainActor in
                await AppDelegate.toggleRecording()
            }
        }
    }

    @MainActor
    private static func toggleRecording() async {
        guard let viewModel = AppEnvironment.shared.viewModel else { return }
        if viewModel.state.isActive {
            await viewModel.stop()
        } else if viewModel.canStartRecording {
            await viewModel.start()
        }
    }
}
