import OptiRecordUI

/// Bridges the SwiftUI `App` world and the `NSApplicationDelegate` world.
///
/// SwiftUI instantiates `AppDelegate` itself (via `NSApplicationDelegateAdaptor`)
/// with no way to inject dependencies into it, so the one shared piece of state
/// the delegate needs — the view model — is handed over through this single slot
/// instead of a full dependency-injection container. `OptiRecordMainApp.init()` sets
/// it before `AppDelegate.applicationDidFinishLaunching` can possibly run.
final class AppEnvironment {
    static let shared = AppEnvironment()
    private init() {}

    var viewModel: RecorderViewModel?
}
