import SwiftUI
import AizuchiCore

/// 「映像」タブ: 画質・fps・コーデック・カーソル。選んだ組み合わせのビットレートと
/// 想定ファイルサイズをその場で見積もって表示する。
struct VideoSettingsTab: View {
    @Binding var settings: RecordingSettings

    var body: some View {
        Form {
            Section {
                Picker("画質", selection: $settings.quality) {
                    ForEach(VideoQualityPreset.allCases) { preset in
                        Text(preset.localizedName).tag(preset)
                    }
                }
                Picker("フレームレート", selection: $settings.frameRate) {
                    ForEach(FrameRatePreset.allCases) { fps in
                        Text(fps.localizedName).tag(fps)
                    }
                }
                Picker("コーデック", selection: $settings.codec) {
                    ForEach(VideoCodecPreference.allCases) { codec in
                        Text(codec.localizedName).tag(codec)
                    }
                }
                Picker("コンテナ形式", selection: $settings.container) {
                    ForEach(ContainerFormat.allCases) { container in
                        Text(container.localizedName).tag(container)
                    }
                }
                Toggle("マウスカーソルを含める", isOn: $settings.showsCursor)
            }

            Section("見積り") {
                Text(estimateSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// The estimate is computed against a 1080p canvas as a stand-in — the real
    /// size depends on whichever screen/window the user ends up recording, which
    /// this tab does not know about.
    private var estimateSummary: String {
        let configuration = RecordingConfiguration.resolve(settings: settings, sourceWidth: 1920, sourceHeight: 1080)
        let summary = Formatters.configurationSummary(configuration)
        let bytesPerHour = Int64(configuration.estimatedBytesPerSecond) * 3600
        return "\(summary) / 1時間あたり約 \(Formatters.fileSize(bytesPerHour))"
    }
}

#Preview {
    VideoSettingsTab(settings: .constant(.default))
        .frame(width: 480, height: 440)
}
