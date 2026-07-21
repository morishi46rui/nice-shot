import AppKit

/// 環境設定ウィンドウ（撮影ショートカット・起動設定）。
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let recorder: ShortcutRecorderView
    private let loginToggle = NSButton(checkboxWithTitle: "ログイン時に起動", target: nil, action: nil)

    /// ショートカットが変更されたときに呼ばれる。
    var onChange: ((HotKeyConfig) -> Void)?

    init(config: HotKeyConfig) {
        recorder = ShortcutRecorderView(config: config)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 350),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        window.title = "NiceShot 設定"
        window.isReleasedWhenClosed = false

        super.init()
        window.delegate = self
        buildContent()
        window.center()

        recorder.onChange = { [weak self] newConfig in
            self?.onChange?(newConfig)
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        let contentWidth: CGFloat = 480 - 56 // 左右 padding 28

        let title = label("撮影ショートカット", font: .systemFont(ofSize: 15, weight: .semibold))
        let subtitle = label("キャプチャを開始するキーの組み合わせを登録します。",
                             font: .systemFont(ofSize: 12))
        subtitle.textColor = .secondaryLabelColor

        // 記録フィールド＋ヒント。
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(equalToConstant: 220).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let hint = label("フィールドをクリックしてキーを押す（Esc で取消）",
                         font: .systemFont(ofSize: 11))
        hint.textColor = .tertiaryLabelColor

        let recorderColumn = NSStackView(views: [recorder, hint])
        recorderColumn.orientation = .vertical
        recorderColumn.alignment = .leading
        recorderColumn.spacing = 6

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        // システムショートカットとの競合に関する注意書き。
        let note = label(
            "⌘⇧4 など macOS 標準のスクリーンショットと重なるキーを使う場合は、"
            + "システム設定 →「キーボード」→「キーボードショートカット」→「スクリーンショット」"
            + "で同じショートカットをオフにしてください。",
            font: .systemFont(ofSize: 11))
        note.textColor = .secondaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false
        note.preferredMaxLayoutWidth = contentWidth
        note.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        let divider2 = NSBox()
        divider2.boxType = .separator
        divider2.translatesAutoresizingMaskIntoConstraints = false
        divider2.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        // 起動設定。
        let startupTitle = label("起動", font: .systemFont(ofSize: 15, weight: .semibold))
        loginToggle.target = self
        loginToggle.action = #selector(toggleLoginItem(_:))
        loginToggle.state = LoginItem.isEnabled ? .on : .off
        let startupHint = label("Mac のログイン時に NiceShot を自動的に起動します。",
                                font: .systemFont(ofSize: 11))
        startupHint.textColor = .tertiaryLabelColor

        let startupColumn = NSStackView(views: [startupTitle, loginToggle, startupHint])
        startupColumn.orientation = .vertical
        startupColumn.alignment = .leading
        startupColumn.spacing = 8

        let stack = NSStackView(views: [title, subtitle, recorderColumn, divider, note,
                                        divider2, startupColumn])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(20, after: recorderColumn)
        stack.setCustomSpacing(20, after: note)
        stack.setCustomSpacing(6, after: title)
        stack.setCustomSpacing(18, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
        ])
        window.contentView = container
    }

    @objc private func toggleLoginItem(_ sender: NSButton) {
        let ok = LoginItem.setEnabled(sender.state == .on)
        if !ok {
            // 失敗したら実際の状態に戻し、理由を伝える。
            sender.state = LoginItem.isEnabled ? .on : .off
            let alert = NSAlert()
            alert.messageText = "ログイン項目を変更できませんでした"
            alert.informativeText = "システム設定 → 一般 → ログイン項目 から手動で追加することもできます。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window)
        }
    }

    private func label(_ text: String, font: NSFont = .systemFont(ofSize: 13)) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font
        l.lineBreakMode = .byWordWrapping
        l.maximumNumberOfLines = 0
        return l
    }
}
