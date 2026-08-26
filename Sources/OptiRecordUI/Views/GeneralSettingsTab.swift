import SwiftUI
import OptiRecordCore

/// 「一般」タブ: ログイン時起動、グローバルショートカット表示、終了時の挙動。
struct GeneralSettingsTab: View {
    @Binding var settings: RecordingSettings

    var body: some View {
        Form {
            Section {
                Toggle("ログイン時に起動", isOn: $settings.launchAtLogin)

                LabeledContent("グローバルショートカット") {
                    Text(hotKeyDescription)
                        .foregroundStyle(.secondary)
                }
            }

            Section("終了時の挙動") {
                Toggle("録画が完了したら Finder で表示", isOn: $settings.revealsInFinderWhenDone)
                Toggle("録画中は自分のウインドウを除外する", isOn: $settings.excludesOwnWindows)
                Toggle("録画対象のアプリが終了したら自動で停止する", isOn: $settings.stopsWhenTargetDisappears)
            }

            Section("ディスク容量") {
                Stepper(value: $settings.minimumFreeDiskMegabytes, in: 256...10240, step: 256) {
                    Text("空き容量が \(settings.minimumFreeDiskMegabytes) MB を下回ったら録画を停止する")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var hotKeyDescription: String {
        guard let binding = settings.startStopHotKey else { return "未設定" }
        return HotKeyDisplay.string(for: binding)
    }
}

#Preview {
    GeneralSettingsTab(settings: .constant(.default))
        .frame(width: 480, height: 440)
}
