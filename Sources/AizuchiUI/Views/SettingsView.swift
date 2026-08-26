import SwiftUI
import AppKit
import AizuchiCore

/// The `Settings { }` scene's root view. Owns a local, editable copy of
/// `RecordingSettings`; every change is written back through `SettingsStore` and
/// the controller is notified once via `RecorderViewModel.settingsDidChange()`.
public struct SettingsView: View {
    @ObservedObject var viewModel: RecorderViewModel
    @State private var settings: RecordingSettings

    public init(viewModel: RecorderViewModel) {
        self.viewModel = viewModel
        _settings = State(initialValue: viewModel.settingsStore.settings)
    }

    public var body: some View {
        TabView {
            GeneralSettingsTab(settings: $settings)
                .tabItem { Label("一般", systemImage: "gearshape") }

            VideoSettingsTab(settings: $settings)
                .tabItem { Label("映像", systemImage: "video") }

            AudioSettingsTab(settings: $settings, viewModel: viewModel)
                .tabItem { Label("音声", systemImage: "waveform") }

            OutputSettingsTab(settings: $settings)
                .tabItem { Label("保存先", systemImage: "folder") }
        }
        .frame(width: 480, height: 440)
        .onChange(of: settings) { _, newValue in
            viewModel.settingsStore.settings = newValue
            viewModel.settingsDidChange()
        }
        .onDisappear {
            // Pairs with `MenuBarContentView.openSettingsWindow()`, which flips the
            // app to `.regular` so a Dock-icon-less menu bar app can bring this
            // window to the front at all. Switch back once it closes.
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

#Preview {
    SettingsView(viewModel: RecorderViewModel(controller: PreviewRecordingController.idle))
}
