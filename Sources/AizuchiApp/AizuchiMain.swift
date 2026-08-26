import SwiftUI
import AppKit
import AizuchiCore
import AizuchiRecording
import AizuchiUI

@main
struct AizuchiMainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel: RecorderViewModel

    init() {
        // The only place the app names concrete capture/mix/write types; every view
        // below talks to `RecordingControlling` from AizuchiCore.
        let settingsStore = SettingsStore()
        let controller = RecordingStack.makeCoordinator(settingsStore: settingsStore)
        let viewModel = RecorderViewModel(controller: controller, settingsStore: settingsStore)
        _viewModel = StateObject(wrappedValue: viewModel)
        // AppDelegate is instantiated by NSApplicationDelegateAdaptor with no
        // initializer arguments, so this is how it learns about the view model —
        // see AppEnvironment.swift.
        AppEnvironment.shared.viewModel = viewModel
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(viewModel: viewModel)
        } label: {
            MenuBarIconLabel(state: viewModel.state)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
