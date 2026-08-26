import Foundation

/// Persists `RecordingSettings` as JSON in UserDefaults, and notifies observers.
public final class SettingsStore {
    public static let didChangeNotification = Notification.Name("app.aizuchi.settingsDidChange")
    private static let key = "recordingSettings"

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter

    public init(defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    public var settings: RecordingSettings {
        get { load() }
        set { save(newValue) }
    }

    public func load() -> RecordingSettings {
        guard let data = defaults.data(forKey: Self.key) else { return .default }
        do {
            return try JSONDecoder().decode(RecordingSettings.self, from: data)
        } catch {
            Log.app.error("設定の読み込みに失敗したため既定値を使います: \(String(describing: error), privacy: .public)")
            return .default
        }
    }

    public func save(_ settings: RecordingSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: Self.key)
            notificationCenter.post(name: Self.didChangeNotification, object: nil)
        } catch {
            Log.app.error("設定の保存に失敗しました: \(String(describing: error), privacy: .public)")
        }
    }

    /// Mutate in place: `store.update { $0.microphoneEnabled = false }`.
    @discardableResult
    public func update(_ mutate: (inout RecordingSettings) -> Void) -> RecordingSettings {
        var current = load()
        mutate(&current)
        save(current)
        return current
    }

    public func reset() {
        defaults.removeObject(forKey: Self.key)
        notificationCenter.post(name: Self.didChangeNotification, object: nil)
    }
}
