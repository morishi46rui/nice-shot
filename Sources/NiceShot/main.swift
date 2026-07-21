import AppKit

// メニューバー常駐アプリとして起動する。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Dock に出さず、メニューバーのみに常駐させる。
app.setActivationPolicy(.accessory)
app.run()
