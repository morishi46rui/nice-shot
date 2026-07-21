import AppKit

/// クリックするとキー入力待ちになり、押されたショートカットを記録するコントロール。
final class ShortcutRecorderView: NSView {
    /// 新しいショートカットが確定したときに呼ばれる。
    var onChange: ((HotKeyConfig) -> Void)?

    private(set) var config: HotKeyConfig {
        didSet { needsDisplay = true }
    }
    private var isRecording = false {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    init(config: HotKeyConfig) {
        self.config = config
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 36))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 220, height: 36) }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8)

        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.14)
                     : NSColor.textBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text: String
        let color: NSColor
        let font: NSFont
        if isRecording {
            text = "キーを入力…"
            color = .secondaryLabelColor
            font = .systemFont(ofSize: 13, weight: .regular)
        } else {
            text = config.display
            color = .labelColor
            font = .systemFont(ofSize: 16, weight: .semibold)
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = CGPoint(x: (bounds.width - size.width) / 2,
                             y: (bounds.height - size.height) / 2)
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        isRecording.toggle()
        if isRecording { window?.makeFirstResponder(self) }
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        if event.keyCode == 53 { // Esc: キャンセル
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }

        if let newConfig = HotKeyConfig.from(event: event) {
            config = newConfig
            isRecording = false
            window?.makeFirstResponder(nil)
            onChange?(newConfig)
        } else {
            // 修飾キー無しなど不適な入力は軽く弾く。
            NSSound.beep()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // 記録中は ⌘系のショートカットも横取りして記録対象にする。
        if isRecording, HotKeyConfig.from(event: event) != nil {
            keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
