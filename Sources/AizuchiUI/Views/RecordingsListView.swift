import SwiftUI
import AppKit
import AizuchiCore

/// Direct recent recordings, newest first, with the two things people actually
/// want after a meeting ends: reveal in Finder, and play it back.
public struct RecordingsListView: View {
    @ObservedObject var viewModel: RecorderViewModel

    public init(viewModel: RecorderViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            if viewModel.recentRecordings.isEmpty {
                emptyState
            } else {
                List(viewModel.recentRecordings) { recording in
                    RecordingRow(recording: recording)
                }
                .listStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "film")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("録画はまだありません")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct RecordingRow: View {
    let recording: RecordingResult

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "film.fill")
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.url.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(Formatters.duration(recording.duration))
                    Text(Formatters.fileSize(recording.fileSize))
                    if let label = recording.targetLabel {
                        Text(label)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !recording.sidecarAudioURLs.isEmpty {
                    Text("音声ファイル: " + recording.sidecarAudioURLs.keys.map(\.localizedName).sorted().joined(separator: "、"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([recording.url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Finder で表示")

            Button {
                NSWorkspace.shared.open(recording.url)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("再生")
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RecordingsListView(viewModel: RecorderViewModel(controller: PreviewRecordingController.idle))
        .frame(width: 360, height: 200)
}
