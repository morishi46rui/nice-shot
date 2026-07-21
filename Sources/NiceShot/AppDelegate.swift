import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var overlay: SelectionOverlayController?
    private var editors: [ObjectIdentifier: EditorWindowController] = [:]
    private var preferences: PreferencesWindowController?

    private var hotKeyConfig = HotKeyConfig.load()
    private var captureMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        HotKeyManager.shared.onCapture = { [weak self] in
            self?.startRegionCapture()
        }
        HotKeyManager.shared.apply(hotKeyConfig)
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregister()
    }

    // MARK: - メニューバー

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                     accessibilityDescription: "NiceShot")

        let menu = NSMenu()
        let capture = NSMenuItem(title: captureTitle(),
                                 action: #selector(captureRegionMenu), keyEquivalent: "")
        menu.addItem(capture)
        captureMenuItem = capture
        menu.addItem(.separator())
        menu.addItem(withTitle: "ショートカットを設定…",
                     action: #selector(openPreferences), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "NiceShot を終了", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }

        item.menu = menu
        statusItem = item
    }

    private func captureTitle() -> String {
        "範囲をキャプチャ  (\(hotKeyConfig.display))"
    }

    @objc private func captureRegionMenu() { startRegionCapture() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openPreferences() {
        if preferences == nil {
            let controller = PreferencesWindowController(config: hotKeyConfig)
            controller.onChange = { [weak self] newConfig in
                self?.applyHotKey(newConfig)
            }
            preferences = controller
        }
        preferences?.show()
    }

    private func applyHotKey(_ config: HotKeyConfig) {
        hotKeyConfig = config
        config.save()
        HotKeyManager.shared.apply(config)
        captureMenuItem?.title = captureTitle()
    }

    // MARK: - キャプチャ

    private func currentScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func startRegionCapture() {
        guard overlay == nil else { return }
        let screen = currentScreen()
        let controller = SelectionOverlayController(screen: screen) { [weak self] pointRect, displayID, _ in
            guard let self else { return }
            self.overlay = nil
            guard let pointRect else { return } // キャンセル
            self.performCapture(displayID: displayID, pointRect: pointRect)
        }
        overlay = controller
        controller.show()
    }

    private func performCapture(displayID: CGDirectDisplayID, pointRect: CGRect) {
        Task { @MainActor in
            do {
                let cg = try await ScreenCapture.capture(displayID: displayID, pointRect: pointRect)
                // 切り抜いた画像は選択範囲そのもの。表示・書き出しは選択のポイントサイズで行う。
                self.openEditor(cgImage: cg, pointSize: pointRect.size)
            } catch {
                self.showError(error)
            }
        }
    }

    // MARK: - エディタ

    private func openEditor(cgImage: CGImage, pointSize: NSSize) {
        let controller = EditorWindowController(cgImage: cgImage, pointSize: pointSize)
        let key = ObjectIdentifier(controller)
        controller.onClose = { [weak self] in
            self?.editors[key] = nil
        }
        editors[key] = controller
        controller.show()
    }

    // MARK: - エラー表示

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "キャプチャに失敗しました"
        alert.informativeText = """
        \(error.localizedDescription)

        画面収録の許可が必要な場合は、システム設定 > プライバシーとセキュリティ > 画面収録 で NiceShot を有効にしてください。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
