import SwiftUI
import AppKit
import AizuchiCore

/// The content of the menu bar popover (`MenuBarExtra(...).menuBarExtraStyle(.window)`).
/// Deliberately compact and quiet — this sits open in the corner of the screen
/// during a meeting, so nothing here should compete for attention except the
/// level meters and, when something is wrong, the recording state itself.
public struct MenuBarContentView: View {
    @ObservedObject var viewModel: RecorderViewModel

    // NOTE(uncertain): `EnvironmentValues.openSettings` is the SwiftUI-native way to
    // open the `Settings { }` scene, added alongside macOS 14 (our minimum target).
    // Written from memory; verify it resolves on the macOS 15 CI runner.
    @Environment(\.openSettings) private var openSettings
    @AppStorage("app.aizuchi.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showingSourcePicker = false
    @State private var showingRecordings = false
    @State private var showingOnboarding = false

    public init(viewModel: RecorderViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            targetSummary
            Divider()
            LevelMeterView(viewModel: viewModel)
            Divider()
            controls

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(16)
        .frame(width: 340)
        .task {
            await viewModel.refreshAvailableContent()
            viewModel.refreshPermissionStates()
            let screenRecordingOK = (viewModel.permissionStates[.screenRecording] ?? .notDetermined).isAuthorized
            if !hasCompletedOnboarding || !screenRecordingOK {
                showingOnboarding = true
            }
        }
        .sheet(isPresented: $showingOnboarding) {
            PermissionOnboardingView(viewModel: viewModel) {
                hasCompletedOnboarding = true
                showingOnboarding = false
            }
        }
        .sheet(isPresented: $showingSourcePicker) {
            VStack(alignment: .trailing, spacing: 8) {
                SourcePickerView(viewModel: viewModel)
                Button("閉じる") { showingSourcePicker = false }
            }
            .padding(16)
            .frame(width: 360)
        }
        .sheet(isPresented: $showingRecordings) {
            VStack(alignment: .leading, spacing: 8) {
                Text("最近の録画").font(.headline)
                RecordingsListView(viewModel: viewModel)
                HStack {
                    Spacer()
                    Button("閉じる") { showingRecordings = false }
                }
            }
            .padding(16)
            .frame(width: 380, height: 320)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(badgeColor)
                .frame(width: 8, height: 8)
            Text(viewModel.state.localizedDescription)
                .font(.headline)
            Spacer()
            Text(viewModel.elapsedDisplay)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var badgeColor: Color {
        switch viewModel.state {
        case .recording: return .red
        case .paused: return .orange
        case .preparing, .finishing: return .blue
        case .idle: return .secondary
        case .failed: return .red
        }
    }

    // MARK: Target summary

    private var targetSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: "target")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("録画対象").font(.caption2).foregroundStyle(.secondary)
                Text(targetLabel).font(.callout).lineLimit(1)
            }
            Spacer()
            Button("変更…") { showingSourcePicker = true }
                .buttonStyle(.link)
                .disabled(viewModel.state.isActive)
        }
    }

    private var targetLabel: String {
        guard let target = viewModel.selectedTarget else { return "未選択" }
        return viewModel.availableContent.label(for: target) ?? "選択済み"
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                Task { await viewModel.start() }
            } label: {
                Label("開始", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!viewModel.canStartRecording)

            Button {
                if viewModel.canResume {
                    viewModel.resume()
                } else {
                    viewModel.pause()
                }
            } label: {
                Label(viewModel.canResume ? "再開" : "一時停止", systemImage: viewModel.canResume ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!(viewModel.canPause || viewModel.canResume))

            Button(role: .destructive) {
                Task { await viewModel.stop() }
            } label: {
                Label("停止", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!viewModel.canStop)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider()
            Button("最近の録画") { showingRecordings = true }
                .buttonStyle(.borderless)
            Button("設定…") { openSettingsWindow() }
                .buttonStyle(.borderless)
            Button("録画フォルダを開く") { openRecordingsFolder() }
                .buttonStyle(.borderless)
            Divider()
            Button("終了") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openRecordingsFolder() {
        OutputDirectoryResolver.openInFinder(settings: viewModel.settingsStore.settings)
    }

    // NOTE(uncertain): a menu-bar-only app (`LSUIElement`, no Dock icon) runs with
    // `NSApplication.ActivationPolicy.accessory`, under which `openSettings()` can
    // fail to bring the Settings window to the front — macOS won't key a window
    // for an app with no Dock icon. Switching to `.regular` first is the commonly
    // used fix; `SettingsView` switches back to `.accessory` when it disappears.
    // Written without a way to test it against a real menu bar popover — verify
    // on a real build. If it still misbehaves, the more thorough fix is a hidden
    // 1x1 `Window` scene declared before `Settings { }` purely to give
    // `openSettings()` a live SwiftUI render tree to call from.
    private func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}

#Preview("待機中") {
    MenuBarContentView(viewModel: RecorderViewModel(controller: PreviewRecordingController.idle))
}

#Preview("録画中") {
    MenuBarContentView(viewModel: RecorderViewModel(controller: PreviewRecordingController.recording))
}

#Preview("権限未許可") {
    MenuBarContentView(viewModel: RecorderViewModel(controller: PreviewRecordingController.permissionsNeeded))
}
