import AppKit

/// キーになれる borderless ウィンドウ（Esc 受信のため）。
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// ドラッグで矩形選択させるビュー。
final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?

    private var startPoint: CGPoint?
    private var currentRect: CGRect?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        // 全体を暗くする。
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        guard let rect = currentRect else { return }

        // 選択範囲だけ元の映像を見せる（暗幕を透明に戻してくり抜く）。
        rect.fill(using: .clear)

        // 枠線。
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1.5
        border.stroke()

        // 寸法ラベル。
        let label = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        var labelOrigin = CGPoint(x: rect.minX, y: rect.minY - size.height - 6)
        if labelOrigin.y < 4 { labelOrigin.y = rect.maxY + 6 }
        let bg = CGRect(x: labelOrigin.x - 4, y: labelOrigin.y - 2,
                        width: size.width + 8, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        (label as NSString).draw(at: labelOrigin, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        currentRect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                             width: abs(p.x - start.x), height: abs(p.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { startPoint = nil }
        guard let rect = currentRect, rect.width >= 3, rect.height >= 3 else {
            onFinish?(nil)
            return
        }
        onFinish?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onFinish?(nil)
        }
    }
}

/// 範囲選択オーバーレイの表示を管理する。
final class SelectionOverlayController {
    private var window: OverlayWindow?
    private let screen: NSScreen
    private let completion: (_ pointRect: CGRect?, _ displayID: CGDirectDisplayID, _ scale: CGFloat) -> Void

    init(screen: NSScreen,
         completion: @escaping (_ pointRect: CGRect?, _ displayID: CGDirectDisplayID, _ scale: CGFloat) -> Void) {
        self.screen = screen
        self.completion = completion
    }

    func show() {
        let win = OverlayWindow(contentRect: screen.frame,
                                styleMask: .borderless,
                                backing: .buffered,
                                defer: false)
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = false
        win.setFrame(screen.frame, display: true)

        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self] rect in
            self?.finish(viewRect: rect, viewHeight: view.bounds.height)
        }
        win.contentView = view

        self.window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(view)
    }

    private func finish(viewRect: CGRect?, viewHeight: CGFloat) {
        let displayID = ScreenCapture.screenDisplayID(screen)
        let scale = screen.backingScaleFactor

        window?.orderOut(nil)
        window = nil

        guard let viewRect else {
            completion(nil, displayID, scale)
            return
        }
        // ビュー座標（左下原点）→ ディスプレイ内・左上原点のポイント矩形へ変換。
        let pointRect = CGRect(x: viewRect.minX,
                               y: viewHeight - viewRect.maxY,
                               width: viewRect.width,
                               height: viewRect.height)
        completion(pointRect, displayID, scale)
    }
}
