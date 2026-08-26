import AppKit
import OptiRecordCore

/// Turns a stored `HotKeyBinding` into the way macOS itself displays shortcuts,
/// e.g. "⌃⇧R". Modifier order follows the system convention: Control, Option,
/// Shift, Command.
enum HotKeyDisplay {
    static func string(for binding: HotKeyBinding) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: binding.modifierFlags)
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        result += keyName(for: binding.keyCode)
        return result
    }

    // NOTE(uncertain): hand-written table of Carbon `kVK_ANSI_*` / `kVK_*` virtual
    // key codes for a US ANSI keyboard layout (from Carbon.HIToolbox's Events.h).
    // Written from memory without a compiler to check it against; only the entries
    // actually reachable from `SettingsView`'s shortcut display are exercised, but
    // double-check this table on the macOS CI runner. Non-US layouts are not handled.
    private static let keyCodeNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    private static func keyName(for keyCode: UInt32) -> String {
        keyCodeNames[keyCode] ?? "Key\(keyCode)"
    }
}
