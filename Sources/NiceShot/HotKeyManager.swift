import AppKit
import Carbon.HIToolbox

/// Carbon の RegisterEventHotKey を使ったグローバルホットキー管理。
/// アクセシビリティ権限を必要とせずに動作する。
final class HotKeyManager {
    static let shared = HotKeyManager()

    /// ホットキー押下時に呼ばれるハンドラ。
    var onCapture: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private init() {}

    /// 設定を適用する（既存のホットキーは解除して再登録）。
    func apply(_ config: HotKeyConfig) {
        installHandlerIfNeeded()

        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4E534854), id: 1) // 'NSHT'
        RegisterEventHotKey(config.keyCode, config.carbonModifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        // C 関数ポインタなのでコンテキストをキャプチャできない。シングルトン経由でハンドラを呼ぶ。
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            HotKeyManager.shared.onCapture?()
            return noErr
        }, 1, &eventType, nil, &eventHandler)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKeyRef = nil
        eventHandler = nil
    }
}
