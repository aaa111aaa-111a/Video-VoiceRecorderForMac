import SwiftUI
import OptiRecordCore

/// Shown automatically on first launch (and whenever screen recording is not yet
/// authorized) so the user grants both permissions before they hit "録画開始"
/// and discover it silently doesn't work.
public struct PermissionOnboardingView: View {
    @ObservedObject var viewModel: RecorderViewModel
    var onContinue: (() -> Void)?

    public init(viewModel: RecorderViewModel, onContinue: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(AppInfo.name) を使うには権限が必要です")
                    .font(.title2.bold())
                Text("録画を始める前に、以下の権限を許可してください。")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(PermissionKind.allCases) { kind in
                    permissionRow(kind)
                }
            }

            HStack {
                Spacer()
                Button("続ける") { onContinue?() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!screenRecordingAuthorized)
            }
        }
        .padding(24)
        .frame(width: 420)
        .task { viewModel.refreshPermissionStates() }
    }

    private var screenRecordingAuthorized: Bool {
        (viewModel.permissionStates[.screenRecording] ?? .notDetermined).isAuthorized
    }

    @ViewBuilder
    private func permissionRow(_ kind: PermissionKind) -> some View {
        let status = viewModel.permissionStates[kind] ?? .notDetermined
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName(for: kind))
                .font(.title2)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(kind.localizedName).font(.headline)
                    statusBadge(status)
                }
                Text(kind.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            actionControl(kind, status)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func symbolName(for kind: PermissionKind) -> String {
        switch kind {
        case .screenRecording: return "display"
        case .microphone: return "mic.fill"
        }
    }

    private func statusBadge(_ status: PermissionStatus) -> some View {
        Text(status.localizedName)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor(status).opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor(status))
    }

    private func badgeColor(_ status: PermissionStatus) -> Color {
        switch status {
        case .authorized: return .green
        case .denied, .restricted: return .red
        case .notDetermined: return .secondary
        }
    }

    @ViewBuilder
    private func actionControl(_ kind: PermissionKind, _ status: PermissionStatus) -> some View {
        switch status {
        case .authorized:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .notDetermined:
            Button("許可する") { Task { await viewModel.requestPermission(kind) } }
        case .denied, .restricted:
            Button("システム設定を開く") { viewModel.openSystemSettings(for: kind) }
        }
    }
}

#Preview("未許可") {
    PermissionOnboardingView(viewModel: RecorderViewModel(controller: PreviewRecordingController.permissionsNeeded))
}

#Preview("許可済み") {
    PermissionOnboardingView(viewModel: RecorderViewModel(controller: PreviewRecordingController.idle))
}
