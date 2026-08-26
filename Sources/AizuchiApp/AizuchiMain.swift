import AppKit
import SwiftUI
import AizuchiCore

/// Entry point. Workstream D replaces the body with the real menu bar UI;
/// this placeholder keeps the executable target compiling in the meantime.
@main
struct AizuchiMainApp: App {
    var body: some Scene {
        MenuBarExtra(AppInfo.name, systemImage: "record.circle") {
            Text("\(AppInfo.name) \(AppInfo.version)")
            Divider()
            Button("終了") { NSApplication.shared.terminate(nil) }
        }
    }
}
