import AppKit
import Carbon.HIToolbox

/// 撮影ホットキーの設定。UserDefaults に永続化する。
struct HotKeyConfig: Equatable {
    var keyCode: UInt32          // 仮想キーコード（kVK_*）
    var carbonModifiers: UInt32  // Carbon の修飾キー（cmdKey 等）
    var display: String          // 表示用（例: "⌥⇧4"）

    static let `default` = HotKeyConfig(keyCode: UInt32(kVK_ANSI_4),
                                        carbonModifiers: UInt32(optionKey | shiftKey),
                                        display: "⌥⇧4")

    private static let keyCodeKey = "hotkey.keyCode"
    private static let modifiersKey = "hotkey.carbonModifiers"
    private static let displayKey = "hotkey.display"

    static func load() -> HotKeyConfig {
        let d = UserDefaults.standard
        guard d.object(forKey: keyCodeKey) != nil else { return .default }
        return HotKeyConfig(keyCode: UInt32(d.integer(forKey: keyCodeKey)),
                            carbonModifiers: UInt32(d.integer(forKey: modifiersKey)),
                            display: d.string(forKey: displayKey) ?? "?")
    }

    func save() {
        let d = UserDefaults.standard
        d.set(Int(keyCode), forKey: Self.keyCodeKey)
        d.set(Int(carbonModifiers), forKey: Self.modifiersKey)
        d.set(display, forKey: Self.displayKey)
    }

    // MARK: - NSEvent からの生成

    /// キー入力イベントから設定を作る。修飾キーが1つも無い場合は nil（グローバルホットキーに不適）。
    static func from(event: NSEvent) -> HotKeyConfig? {
        let flags = event.modifierFlags
        // Shift 以外の修飾（⌘/⌥/⌃）を最低1つ要求する。
        let hasStrongModifier = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
        guard hasStrongModifier else { return nil }

        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }

        return HotKeyConfig(keyCode: UInt32(event.keyCode),
                            carbonModifiers: carbon,
                            display: displayString(flags: flags, event: event))
    }

    private static func displayString(flags: NSEvent.ModifierFlags, event: NSEvent) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        s += keyName(for: event)
        return s
    }

    private static func keyName(for event: NSEvent) -> String {
        let code = Int(event.keyCode)
        if let special = specialKeyNames[code] { return special }
        // キーコードから「キー本来の刻印」を引く（Shift の影響を受けさせない）。
        if let base = keyCodeLabels[code] { return base }
        let chars = event.charactersIgnoringModifiers ?? ""
        return chars.isEmpty ? "Key\(code)" : chars.uppercased()
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_Escape: "⎋",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// ANSI 配列の仮想キーコード → キー刻印（英字は大文字、数字/記号はそのまま）。
    private static let keyCodeLabels: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
        kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Grave: "`",
    ]
}
