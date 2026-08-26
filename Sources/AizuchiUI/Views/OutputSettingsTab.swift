import SwiftUI
import AppKit
import AizuchiCore

/// 「保存先」タブ: 保存フォルダ（security-scoped bookmark）とファイル名テンプレート。
struct OutputSettingsTab: View {
    @Binding var settings: RecordingSettings
    @State private var resolvedDirectoryPath: String = ""

    var body: some View {
        Form {
            Section("保存先フォルダ") {
                HStack {
                    Text(resolvedDirectoryPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("変更…") { chooseFolder() }
                }
            }

            Section("ファイル名テンプレート") {
                TextField("テンプレート", text: $settings.fileNameTemplate)
                Text("プレビュー: \(previewFileName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(OutputFileNaming.availableTokens, id: \.token) { entry in
                        HStack(spacing: 4) {
                            Text(entry.token)
                                .font(.caption2.monospaced())
                            Text("— \(entry.description)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { updateResolvedDirectoryPath() }
        .onChange(of: settings.outputDirectoryBookmark) { _, _ in updateResolvedDirectoryPath() }
    }

    private var previewFileName: String {
        let base = OutputFileNaming.fileName(template: settings.fileNameTemplate, sourceLabel: "Zoom", date: Date())
        return "\(base).\(settings.container.fileExtension)"
    }

    private func updateResolvedDirectoryPath() {
        resolvedDirectoryPath = OutputDirectoryResolver.resolve(from: settings).path
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        panel.directoryURL = OutputDirectoryResolver.resolve(from: settings)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.outputDirectoryBookmark = OutputDirectoryResolver.makeBookmark(for: url)
        updateResolvedDirectoryPath()
    }
}

#Preview {
    OutputSettingsTab(settings: .constant(.default))
        .frame(width: 480, height: 440)
}
