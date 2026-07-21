import AppKit

/// キャプチャ画像を画面上にフローティング表示する（ピン留め）。
final class PinWindowController: NSObject, NSWindowDelegate {
    /// 閉じられるまで自身を保持しておくための集合。
    private static var living: Set<PinWindowController> = []

    private let panel: NSPanel

    static func present(image: NSImage) {
        let controller = PinWindowController(image: image)
        living.insert(controller)
        controller.show()
    }

    private init(image: NSImage) {
        let size = image.size
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let imageView = ClickThroughImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor(white: 1, alpha: 0.25).cgColor
        panel.contentView = imageView

        super.init()
        panel.delegate = self
        imageView.onDoubleClick = { [weak self] in self?.panel.close() }
        imageView.onCopy = { [weak self] in self?.copy(image: image) }
    }

    private func show() {
        // マウス位置付近に少しずらして表示。
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(CGPoint(x: mouse.x + 12, y: mouse.y - panel.frame.height - 12))
        panel.orderFrontRegardless()
    }

    private func copy(image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    func windowWillClose(_ notification: Notification) {
        PinWindowController.living.remove(self)
    }
}

/// ドラッグで移動、ダブルクリックで閉じ、⌘C でコピーできる画像ビュー。
private final class ClickThroughImageView: NSImageView {
    var onDoubleClick: (() -> Void)?
    var onCopy: (() -> Void)?

    private var dragOrigin: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount >= 2 {
            onDoubleClick?()
            return
        }
        // ウィンドウ移動のため、画面座標での基点を記録。
        if let win = window {
            let mouseInWindow = event.locationInWindow
            dragOrigin = CGPoint(x: mouseInWindow.x, y: mouseInWindow.y)
            _ = win
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let win = window, let origin = dragOrigin else { return }
        let screenPoint = NSEvent.mouseLocation
        win.setFrameOrigin(CGPoint(x: screenPoint.x - origin.x,
                                   y: screenPoint.y - origin.y))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.keyCode == 51 { // Esc / Delete
            window?.close()
        } else if event.charactersIgnoringModifiers == "c",
                  event.modifierFlags.contains(.command) {
            onCopy?()
        } else {
            super.keyDown(with: event)
        }
    }
}
