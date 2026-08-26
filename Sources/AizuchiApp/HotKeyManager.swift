import AppKit
import Carbon.HIToolbox
import AizuchiCore

/// Registers `RecordingSettings.startStopHotKey` as a system-wide shortcut using
/// the Carbon Event Manager — still, as of this writing, the only API that gives
/// a menu-bar-only app (no window, no Accessibility permission) a global hotkey.
///
/// NOTE(uncertain): this whole file is written from memory against Carbon APIs
/// that predate Swift and have not changed in a very long time, but there is no
/// local Swift toolchain to compile it against (see `docs/AGENT_GUIDE.md`).
/// Every failure path below logs and returns rather than throwing or crashing —
/// if registration is wrong, the shortcut silently does nothing instead of taking
/// down the app. Verify on the macOS 15 CI runner before relying on this.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    /// Four-char signature Carbon uses to namespace hotkey IDs; packed the way
    /// `FourCharCode` expects.
    private static let signature: OSType = {
        "Azch".utf8.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
    }()
    private static let hotKeyID = UInt32(1)

    deinit {
        unregister()
    }

    /// `binding` of `nil` disables the shortcut without treating that as an error.
    func register(binding: HotKeyBinding?, handler: @escaping () -> Void) {
        unregister()
        guard let binding else { return }
        self.handler = handler

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let userData, let eventRef else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var pressedID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedID
                )
                if status == noErr, pressedID.id == HotKeyManager.hotKeyID {
                    manager.handler?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard installStatus == noErr else {
            Log.app.error("グローバルショートカットのイベントハンドラを登録できませんでした (status: \(installStatus))")
            return
        }

        let carbonHotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        var reference: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            binding.keyCode,
            carbonModifiers(from: binding.modifierFlags),
            carbonHotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if registerStatus == noErr {
            hotKeyRef = reference
        } else {
            Log.app.error("グローバルショートカットを登録できませんでした (status: \(registerStatus))")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        handler = nil
    }

    /// `HotKeyBinding.modifierFlags` stores an `NSEvent.ModifierFlags` raw value;
    /// Carbon wants its own bit values (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    private func carbonModifiers(from nsFlags: UInt) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: nsFlags)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}
