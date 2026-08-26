import SwiftUI
import AizuchiCore

/// 「音声」タブ: マイクデバイス選択、各ソースのゲイン、サイドカー m4a 出力。
struct AudioSettingsTab: View {
    @Binding var settings: RecordingSettings
    @ObservedObject var viewModel: RecorderViewModel

    var body: some View {
        Form {
            Section("マイク") {
                Toggle("マイクを録音する", isOn: $settings.microphoneEnabled)

                Picker("入力デバイス", selection: $settings.microphoneDeviceUID) {
                    Text("システム既定").tag(String?.none)
                    ForEach(viewModel.availableMicrophones()) { device in
                        Text(device.name).tag(String?.some(device.id))
                    }
                }
                .disabled(!settings.microphoneEnabled)

                gainRow(title: "マイクのゲイン", value: $settings.microphoneGain)
                    .disabled(!settings.microphoneEnabled)
            }

            Section("システム音声") {
                Toggle("システム音声を録音する", isOn: $settings.systemAudioEnabled)
                gainRow(title: "システム音声のゲイン", value: $settings.systemAudioGain)
                    .disabled(!settings.systemAudioEnabled)
                Toggle("自分自身の再生音を除外する", isOn: $settings.excludesOwnAudio)
            }

            Section("個別ファイル出力") {
                Toggle("音声を個別ファイル（m4a）でも書き出す", isOn: $settings.writesSeparateAudioFiles)
                Text("文字起こしに使うなら有効に。システム音声とマイクをそれぞれ別ファイルとして、映像とは別に保存します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func gainRow(title: String, value: Binding<Float>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: 0...2)
            Text(String(format: "%.1f×", value.wrappedValue))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

#Preview {
    AudioSettingsTab(settings: .constant(.default), viewModel: RecorderViewModel(controller: PreviewRecordingController.idle))
        .frame(width: 480, height: 440)
}
