import AppKit
import UniformTypeIdentifiers

/// 注釈エディタのウィンドウ。ツールバー ＋ キャンバスを持つ。
final class EditorWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let canvas: CanvasView
    private var toolButtons: [ToolKind: NSButton] = [:]

    /// ウィンドウが閉じたときに呼ばれる（AppDelegate が参照を解放するため）。
    var onClose: (() -> Void)?

    init(cgImage: CGImage, pointSize: NSSize) {
        canvas = CanvasView(cgImage: cgImage, pointSize: pointSize)

        let toolbarHeight: CGFloat = 46
        // 画面に収まるサイズへ制限。
        let visible = (NSScreen.main?.visibleFrame.size) ?? NSSize(width: 1200, height: 800)
        let maxW = visible.width - 80
        let maxH = visible.height - 80 - toolbarHeight
        let contentW = min(canvas.frame.width, maxW)
        let contentH = min(canvas.frame.height, maxH)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentW, height: contentH + toolbarHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "NiceShot — 編集"
        window.isReleasedWhenClosed = false

        super.init()

        window.delegate = self
        buildContent(toolbarHeight: toolbarHeight)
        selectTool(currentTool: .arrow)
        window.center()

        // 図形を描き終えたら選択ツールへ自動切り替え（ツールバー表示も同期）。
        canvas.onFinishDrawing = { [weak self] in
            self?.selectTool(currentTool: .select)
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - レイアウト構築

    private func buildContent(toolbarHeight: CGFloat) {
        let container = NSView()

        let toolbar = makeToolbar()
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(white: 0.12, alpha: 1)
        scroll.documentView = canvas

        container.addSubview(toolbar)
        container.addSubview(scroll)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: toolbarHeight),

            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        window.contentView = container
    }

    private func makeToolbar() -> NSView {
        let bar = NSView()
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // 描画ツール。
        for tool in ToolKind.allCases {
            let b = iconButton(symbol: tool.symbolName, tooltip: tool.tooltip,
                               action: #selector(toolButtonTapped(_:)))
            b.tag = ToolKind.allCases.firstIndex(of: tool)!
            toolButtons[tool] = b
            stack.addArrangedSubview(b)
        }

        stack.addArrangedSubview(separator())

        // 色。
        let colorWell = NSColorWell()
        colorWell.color = canvas.currentColor
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 40).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 28).isActive = true
        colorWell.toolTip = "色"
        stack.addArrangedSubview(colorWell)

        // 線幅。
        let slider = NSSlider(value: Double(canvas.currentWidth), minValue: 1, maxValue: 20,
                              target: self, action: #selector(widthChanged(_:)))
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 90).isActive = true
        slider.toolTip = "線の太さ"
        stack.addArrangedSubview(slider)

        stack.addArrangedSubview(separator())

        // 操作。
        let undo = iconButton(symbol: "arrow.uturn.backward", tooltip: "元に戻す (⌘Z)",
                              action: #selector(undoTapped))
        undo.keyEquivalent = "z"; undo.keyEquivalentModifierMask = .command
        stack.addArrangedSubview(undo)

        stack.addArrangedSubview(NSView()) // spacer 代わり（末尾を右寄せしないので単純に間隔）

        let copy = textButton(title: "コピー", tooltip: "クリップボードへコピー (⌘C)",
                              action: #selector(copyTapped))
        copy.keyEquivalent = "c"; copy.keyEquivalentModifierMask = .command
        stack.addArrangedSubview(copy)

        let pin = textButton(title: "ピン留め", tooltip: "画面に固定 (⌘P)",
                             action: #selector(pinTapped))
        pin.keyEquivalent = "p"; pin.keyEquivalentModifierMask = .command
        stack.addArrangedSubview(pin)

        let save = textButton(title: "保存…", tooltip: "PNG で保存 (⌘S)",
                              action: #selector(saveTapped))
        save.keyEquivalent = "s"; save.keyEquivalentModifierMask = .command
        stack.addArrangedSubview(save)

        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    private func iconButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let b = NSButton()
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        b.bezelStyle = .texturedRounded
        b.setButtonType(.momentaryPushIn)
        b.imagePosition = .imageOnly
        b.target = self
        b.action = action
        b.toolTip = tooltip
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 34).isActive = true
        return b
    }

    private func textButton(title: String, tooltip: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.toolTip = tooltip
        return b
    }

    private func separator() -> NSView {
        let v = NSBox()
        v.boxType = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return v
    }

    // MARK: - アクション

    @objc private func toolButtonTapped(_ sender: NSButton) {
        let tool = ToolKind.allCases[sender.tag]
        selectTool(currentTool: tool)
    }

    private func selectTool(currentTool tool: ToolKind) {
        canvas.currentTool = tool
        for (kind, button) in toolButtons {
            button.contentTintColor = (kind == tool) ? .controlAccentColor : nil
            button.state = (kind == tool) ? .on : .off
        }
        window.invalidateCursorRects(for: canvas)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        canvas.currentColor = sender.color
    }

    @objc private func widthChanged(_ sender: NSSlider) {
        canvas.currentWidth = CGFloat(sender.doubleValue)
    }

    @objc private func undoTapped() {
        canvas.undo()
    }

    @objc private func copyTapped() {
        let image = canvas.renderImage()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        window.close()
    }

    @objc private func pinTapped() {
        let image = canvas.renderImage()
        PinWindowController.present(image: image)
        window.close()
    }

    @objc private func saveTapped() {
        let image = canvas.renderImage()
        guard let png = pngData(from: image) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "NiceShot.png"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            try? png.write(to: url)
            self?.window.close() // 保存が成立したときだけ閉じる
        }
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
