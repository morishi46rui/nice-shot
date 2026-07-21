import AppKit

/// スクリーンショットと注釈を描画・編集するキャンバス。
/// 座標系はビュー（＝画像ポイント）・左下原点。
final class CanvasView: NSView, NSTextFieldDelegate {
    let baseCGImage: CGImage
    private let baseImage: NSImage
    private let blurredImage: NSImage
    private let pointSize: NSSize

    var currentTool: ToolKind = .arrow
    var currentColor: NSColor = .systemRed
    var currentWidth: CGFloat = 4

    /// 図形を描き終えて選択ツールへ自動切り替えしたときに呼ばれる（ツールバー表示更新用）。
    var onFinishDrawing: (() -> Void)?

    private(set) var annotations: [Annotation] = []
    private var draft: Annotation?

    private var selectedIndex: Int?
    private var dragLastPoint: CGPoint?

    private enum DragMode {
        case none
        case move
        case resize(handle: Int)
    }
    private var dragMode: DragMode = .none
    private var resizeSnapshot: Annotation?         // リサイズ開始時の注釈スナップショット

    private let handleRadius: CGFloat = 5
    private let handleHitTolerance: CGFloat = 10

    /// 外接矩形のどの辺が動くか。
    enum Edge { case none, min, max }
    /// ハンドル1つ分の情報（位置と、動かす辺）。
    struct HandleInfo { let point: CGPoint; let xEdge: Edge; let yEdge: Edge }

    private var activeTextField: NSTextField?
    private var activeTextOrigin: CGPoint = .zero

    private var currentFontSize: CGFloat { 12 + currentWidth * 4 }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    init(cgImage: CGImage, pointSize: NSSize) {
        self.baseCGImage = cgImage
        self.pointSize = pointSize
        self.baseImage = NSImage(cgImage: cgImage, size: pointSize)
        self.blurredImage = CanvasView.makeBlurred(cgImage, pointSize: pointSize)
        super.init(frame: NSRect(origin: .zero, size: pointSize))
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - カーソル

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.activeInKeyWindow, .inVisibleRect, .cursorUpdate, .mouseMoved],
                                owner: self, userInfo: nil)
        addTrackingArea(ta)
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor(at: convert(event.locationInWindow, from: nil)).set()
    }

    /// ツールと、カーソル位置（ハンドル/図形の上か）に応じたカーソルを返す。
    private func cursor(at p: CGPoint) -> NSCursor {
        switch currentTool {
        case .text:
            return .iBeam
        case .select:
            if let h = handleHitTest(at: p), let idx = selectedIndex {
                return cursorForHandle(h, ann: annotations[idx])
            }
            if hitTest(at: p) != nil { return .openHand }
            return .arrow
        default:
            return .crosshair
        }
    }

    private func cursorForHandle(_ index: Int, ann: Annotation) -> NSCursor {
        if ann.kind == .line || ann.kind == .arrow { return .crosshair }
        let handles = handleDescriptors(for: ann)
        guard handles.indices.contains(index) else { return .arrow }
        let d = handles[index]
        switch (d.xEdge, d.yEdge) {
        case (.none, _):
            return .resizeUpDown          // 上下辺
        case (_, .none):
            return .resizeLeftRight       // 左右辺
        default:
            // 角: TL/BR は NWSE、BL/TR は NESW。
            let nwse = (d.xEdge == .min && d.yEdge == .max) || (d.xEdge == .max && d.yEdge == .min)
            return nwse ? ResizeCursors.nwse : ResizeCursors.nesw
        }
    }

    // MARK: - 描画

    override func draw(_ dirtyRect: NSRect) {
        drawScene(in: bounds, showSelection: true)
    }

    private func drawScene(in rect: CGRect, showSelection: Bool) {
        baseImage.draw(in: rect)
        for ann in annotations { drawAnnotation(ann) }
        if let draft { drawAnnotation(draft) }
        if showSelection, currentTool == .select,
           let idx = selectedIndex, annotations.indices.contains(idx) {
            drawSelectionIndicator(for: annotations[idx])
        }
    }

    private func drawAnnotation(_ ann: Annotation) {
        ann.color.setStroke()
        ann.color.setFill()

        switch ann.kind {
        case .rectangle:
            let path = NSBezierPath(rect: normalizedRect(ann))
            path.lineWidth = ann.lineWidth
            path.stroke()
        case .ellipse:
            let path = NSBezierPath(ovalIn: normalizedRect(ann))
            path.lineWidth = ann.lineWidth
            path.stroke()
        case .line:
            let path = NSBezierPath()
            path.move(to: ann.start)
            path.line(to: ann.end)
            path.lineWidth = ann.lineWidth
            path.lineCapStyle = .round
            path.stroke()
        case .arrow:
            drawArrow(from: ann.start, to: ann.end, width: ann.lineWidth)
        case .pen:
            guard ann.points.count > 1 else { break }
            let path = NSBezierPath()
            path.move(to: ann.points[0])
            for p in ann.points.dropFirst() { path.line(to: p) }
            path.lineWidth = ann.lineWidth
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()
        case .text:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: ann.fontSize, weight: .semibold),
                .foregroundColor: ann.color
            ]
            (ann.text as NSString).draw(at: ann.start, withAttributes: attrs)
        case .blur:
            let r = normalizedRect(ann)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: r).addClip()
            blurredImage.draw(in: bounds)
            NSGraphicsContext.restoreGraphicsState()
        case .select:
            break // 注釈として保存されることはない
        }
    }

    /// 選択中の注釈の周りに破線の枠とハンドルを描く。
    private func drawSelectionIndicator(for ann: Annotation) {
        let box = boundingBox(of: ann).insetBy(dx: -6, dy: -6)

        let path = NSBezierPath(rect: box)
        path.lineWidth = 1
        path.setLineDash([5, 3], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()

        for handle in handleDescriptors(for: ann) {
            let c = handle.point
            let r = CGRect(x: c.x - handleRadius, y: c.y - handleRadius,
                           width: handleRadius * 2, height: handleRadius * 2)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: r).fill()
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(ovalIn: r)
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }

    /// リサイズ用ハンドル。直線/矢印は両端点、それ以外は外接矩形の4隅＋4辺中央（計8個）。
    private func handleDescriptors(for ann: Annotation) -> [HandleInfo] {
        switch ann.kind {
        case .line, .arrow:
            return [HandleInfo(point: ann.start, xEdge: .none, yEdge: .none),
                    HandleInfo(point: ann.end,   xEdge: .none, yEdge: .none)]
        default:
            let b = boundingBox(of: ann)
            let midX = b.midX, midY = b.midY
            return [
                HandleInfo(point: CGPoint(x: b.minX, y: b.minY), xEdge: .min, yEdge: .min), // 左下
                HandleInfo(point: CGPoint(x: b.maxX, y: b.minY), xEdge: .max, yEdge: .min), // 右下
                HandleInfo(point: CGPoint(x: b.minX, y: b.maxY), xEdge: .min, yEdge: .max), // 左上
                HandleInfo(point: CGPoint(x: b.maxX, y: b.maxY), xEdge: .max, yEdge: .max), // 右上
                HandleInfo(point: CGPoint(x: midX,  y: b.minY), xEdge: .none, yEdge: .min), // 下辺
                HandleInfo(point: CGPoint(x: midX,  y: b.maxY), xEdge: .none, yEdge: .max), // 上辺
                HandleInfo(point: CGPoint(x: b.minX, y: midY),  xEdge: .min, yEdge: .none), // 左辺
                HandleInfo(point: CGPoint(x: b.maxX, y: midY),  xEdge: .max, yEdge: .none), // 右辺
            ]
        }
    }

    /// 選択中注釈のハンドルに当たっていればその index を返す。
    private func handleHitTest(at p: CGPoint) -> Int? {
        guard let idx = selectedIndex, annotations.indices.contains(idx) else { return nil }
        let handles = handleDescriptors(for: annotations[idx])
        for (i, h) in handles.enumerated() where hypot(p.x - h.point.x, p.y - h.point.y) <= handleHitTolerance {
            return i
        }
        return nil
    }

    private func normalizedRect(_ ann: Annotation) -> CGRect {
        CGRect(x: min(ann.start.x, ann.end.x),
               y: min(ann.start.y, ann.end.y),
               width: abs(ann.end.x - ann.start.x),
               height: abs(ann.end.y - ann.start.y))
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, width: CGFloat) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(12, width * 3.2)
        let headAngle = CGFloat.pi / 7

        // 軸（矢じり分だけ手前で止める）。
        let shaftEnd = CGPoint(x: end.x - cos(angle) * headLength * 0.6,
                               y: end.y - sin(angle) * headLength * 0.6)
        let shaft = NSBezierPath()
        shaft.move(to: start)
        shaft.line(to: shaftEnd)
        shaft.lineWidth = width
        shaft.lineCapStyle = .round
        shaft.stroke()

        // 矢じり（塗りつぶし三角形）。
        let p1 = CGPoint(x: end.x - headLength * cos(angle - headAngle),
                         y: end.y - headLength * sin(angle - headAngle))
        let p2 = CGPoint(x: end.x - headLength * cos(angle + headAngle),
                         y: end.y - headLength * sin(angle + headAngle))
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: p1)
        head.line(to: p2)
        head.close()
        head.fill()
    }

    // MARK: - マウス操作

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        if currentTool == .select {
            window?.makeFirstResponder(self)

            // まず選択中図形のハンドル（リサイズ）を判定。
            if let handle = handleHitTest(at: p), let idx = selectedIndex {
                resizeSnapshot = annotations[idx]
                dragMode = .resize(handle: handle)
                return
            }

            // 図形本体なら選択して移動。
            selectedIndex = hitTest(at: p)
            if selectedIndex != nil {
                dragMode = .move
                dragLastPoint = p
            } else {
                dragMode = .none
                dragLastPoint = nil
            }
            needsDisplay = true
            return
        }

        if currentTool == .text {
            commitActiveText()
            beginTextEditing(at: p)
            return
        }
        commitActiveText()
        selectedIndex = nil

        var ann = Annotation(kind: currentTool, color: currentColor,
                             lineWidth: currentWidth, start: p, end: p)
        if currentTool == .pen { ann.points = [p] }
        draft = ann
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        if currentTool == .select {
            guard let idx = selectedIndex, annotations.indices.contains(idx) else { return }
            switch dragMode {
            case .move:
                guard let last = dragLastPoint else { return }
                translate(&annotations[idx], dx: p.x - last.x, dy: p.y - last.y)
                dragLastPoint = p
                needsDisplay = true
            case .resize(let handle):
                if let snap = resizeSnapshot {
                    let shift = event.modifierFlags.contains(.shift)
                    annotations[idx] = resized(snap, handle: handle, to: p, shift: shift)
                    needsDisplay = true
                }
            case .none:
                break
            }
            return
        }

        guard var ann = draft else { return }
        ann.end = p
        if ann.kind == .pen { ann.points.append(p) }
        draft = ann
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if currentTool == .select {
            dragLastPoint = nil
            dragMode = .none
            resizeSnapshot = nil
            return
        }
        guard let ann = draft else { return }
        draft = nil
        // 極小のドラッグは無視。
        let dx = abs(ann.end.x - ann.start.x)
        let dy = abs(ann.end.y - ann.start.y)
        var appended = false
        if ann.kind == .pen {
            if ann.points.count > 1 { annotations.append(ann); appended = true }
        } else if dx >= 3 || dy >= 3 {
            annotations.append(ann); appended = true
        }
        if appended { switchToSelect(selecting: annotations.count - 1) }
        needsDisplay = true
    }

    /// 描き終えた図形を選択状態にして選択ツールへ切り替える。
    private func switchToSelect(selecting index: Int) {
        currentTool = .select
        selectedIndex = index
        onFinishDrawing?()
    }

    override func keyDown(with event: NSEvent) {
        // Delete / Backspace で選択中の注釈を削除。
        if currentTool == .select, event.keyCode == 51 || event.keyCode == 117,
           let idx = selectedIndex, annotations.indices.contains(idx) {
            annotations.remove(at: idx)
            selectedIndex = nil
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - ヒットテスト・移動

    /// 最前面（配列末尾）から順に、点がどの注釈に当たるか調べる。
    private func hitTest(at p: CGPoint) -> Int? {
        for idx in annotations.indices.reversed() {
            if isHit(annotations[idx], at: p) { return idx }
        }
        return nil
    }

    private func isHit(_ ann: Annotation, at p: CGPoint) -> Bool {
        let tol = max(8, ann.lineWidth)
        switch ann.kind {
        case .rectangle, .ellipse, .blur, .text:
            return boundingBox(of: ann).insetBy(dx: -tol / 2, dy: -tol / 2).contains(p)
        case .line, .arrow:
            return distanceToSegment(p, a: ann.start, b: ann.end) <= tol
        case .pen:
            guard ann.points.count > 1 else { return false }
            for i in 0..<(ann.points.count - 1) {
                if distanceToSegment(p, a: ann.points[i], b: ann.points[i + 1]) <= tol {
                    return true
                }
            }
            return false
        case .select:
            return false
        }
    }

    /// スナップショットを基準に、ハンドルを点 p へ動かしたリサイズ結果を返す。
    /// - Parameter shift: 縦横比固定（角）／角度スナップ（直線・矢印）。
    private func resized(_ snapshot: Annotation, handle: Int, to p: CGPoint, shift: Bool) -> Annotation {
        // 直線・矢印は端点を直接移動。Shift で 45° 単位にスナップ。
        if snapshot.kind == .line || snapshot.kind == .arrow {
            var ann = snapshot
            let fixed = handle == 0 ? snapshot.end : snapshot.start
            let moved = shift ? snapAngle(from: fixed, to: p) : p
            if handle == 0 { ann.start = moved } else { ann.end = moved }
            return ann
        }

        let orig = boundingBox(of: snapshot)
        guard orig.width > 0.5, orig.height > 0.5 else { return snapshot }
        let handles = handleDescriptors(for: snapshot)
        guard handles.indices.contains(handle) else { return snapshot }
        let d = handles[handle]

        var minX = orig.minX, maxX = orig.maxX
        var minY = orig.minY, maxY = orig.maxY

        if shift, d.xEdge != .none, d.yEdge != .none {
            // 角＋縦横比固定：対角を固定して元比率を保つ。
            let anchorX = d.xEdge == .min ? orig.maxX : orig.minX
            let anchorY = d.yEdge == .min ? orig.maxY : orig.minY
            let scale = max(abs(p.x - anchorX) / orig.width, abs(p.y - anchorY) / orig.height)
            let signX: CGFloat = p.x >= anchorX ? 1 : -1
            let signY: CGFloat = p.y >= anchorY ? 1 : -1
            let movingX = anchorX + signX * orig.width * scale
            let movingY = anchorY + signY * orig.height * scale
            minX = min(anchorX, movingX); maxX = max(anchorX, movingX)
            minY = min(anchorY, movingY); maxY = max(anchorY, movingY)
        } else {
            if d.xEdge == .min { minX = p.x } else if d.xEdge == .max { maxX = p.x }
            if d.yEdge == .min { minY = p.y } else if d.yEdge == .max { maxY = p.y }
        }

        let newBox = CGRect(x: min(minX, maxX), y: min(minY, maxY),
                            width: max(abs(maxX - minX), 1), height: max(abs(maxY - minY), 1))
        return remap(snapshot, from: orig, to: newBox)
    }

    /// 外接矩形 orig を newBox に写すように注釈の形状を作り直す。
    private func remap(_ snapshot: Annotation, from orig: CGRect, to newBox: CGRect) -> Annotation {
        var ann = snapshot
        switch ann.kind {
        case .rectangle, .ellipse, .blur:
            ann.start = CGPoint(x: newBox.minX, y: newBox.minY)
            ann.end = CGPoint(x: newBox.maxX, y: newBox.maxY)
        case .pen:
            ann.points = snapshot.points.map { mapPoint($0, from: orig, to: newBox) }
        case .text:
            ann.start = mapPoint(snapshot.start, from: orig, to: newBox)
            ann.fontSize = max(6, snapshot.fontSize * (newBox.height / orig.height))
        default:
            break
        }
        return ann
    }

    private func mapPoint(_ pt: CGPoint, from orig: CGRect, to newBox: CGRect) -> CGPoint {
        CGPoint(x: newBox.minX + (pt.x - orig.minX) / orig.width * newBox.width,
                y: newBox.minY + (pt.y - orig.minY) / orig.height * newBox.height)
    }

    /// fixed からの角度を 45° 単位にスナップした点を返す。
    private func snapAngle(from fixed: CGPoint, to p: CGPoint) -> CGPoint {
        let dx = p.x - fixed.x, dy = p.y - fixed.y
        let len = hypot(dx, dy)
        let step = CGFloat.pi / 4
        let snapped = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: fixed.x + cos(snapped) * len, y: fixed.y + sin(snapped) * len)
    }

    private func translate(_ ann: inout Annotation, dx: CGFloat, dy: CGFloat) {
        ann.start.x += dx; ann.start.y += dy
        ann.end.x += dx;   ann.end.y += dy
        if !ann.points.isEmpty {
            ann.points = ann.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        }
    }

    private func boundingBox(of ann: Annotation) -> CGRect {
        switch ann.kind {
        case .pen:
            guard let first = ann.points.first else { return normalizedRect(ann) }
            var rect = CGRect(origin: first, size: .zero)
            for p in ann.points { rect = rect.union(CGRect(origin: p, size: .zero)) }
            return rect
        case .text:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: ann.fontSize, weight: .semibold)
            ]
            let size = (ann.text as NSString).size(withAttributes: attrs)
            return CGRect(origin: ann.start, size: size)
        default:
            return normalizedRect(ann)
        }
    }

    private func distanceToSegment(_ p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq
        t = max(0, min(1, t))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }

    // MARK: - テキスト編集

    private func beginTextEditing(at point: CGPoint) {
        let tf = NSTextField(frame: CGRect(x: point.x, y: point.y,
                                           width: 240, height: currentFontSize + 8))
        tf.font = .systemFont(ofSize: currentFontSize, weight: .semibold)
        tf.textColor = currentColor
        tf.drawsBackground = false
        tf.isBordered = false
        tf.focusRingType = .none
        tf.placeholderString = "テキストを入力"
        tf.delegate = self
        addSubview(tf)
        window?.makeFirstResponder(tf)
        activeTextField = tf
        activeTextOrigin = point
    }

    /// 編集中テキストがあれば確定して注釈化する。確定した場合 true。
    @discardableResult
    func commitActiveText() -> Bool {
        guard let tf = activeTextField else { return false }
        let text = tf.stringValue
        activeTextField = nil
        tf.removeFromSuperview()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        var ann = Annotation(kind: .text, color: tf.textColor ?? currentColor,
                             lineWidth: currentWidth,
                             start: activeTextOrigin, end: activeTextOrigin)
        ann.text = text
        ann.fontSize = currentFontSize
        annotations.append(ann)
        needsDisplay = true
        return true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // テキスト確定後も選択ツールへ自動切り替え。
        if commitActiveText() {
            switchToSelect(selecting: annotations.count - 1)
        }
    }

    // MARK: - 編集操作

    func undo() {
        commitActiveText()
        if !annotations.isEmpty {
            annotations.removeLast()
            selectedIndex = nil
            needsDisplay = true
        }
    }

    // MARK: - 書き出し

    /// 注釈を焼き込んだ最終画像（ピクセル解像度）を返す。
    func renderImage() -> NSImage {
        commitActiveText()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: baseCGImage.width,
                                         pixelsHigh: baseCGImage.height,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            return baseImage
        }
        rep.size = pointSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        drawScene(in: bounds, showSelection: false) // 選択枠は焼き込まない
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: pointSize)
        img.addRepresentation(rep)
        return img
    }

    // MARK: - ぼかし画像生成

    private static func makeBlurred(_ cg: CGImage, pointSize: NSSize) -> NSImage {
        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIPixellate") else {
            return NSImage(cgImage: cg, size: pointSize)
        }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(max(10, CGFloat(cg.width) / 60), forKey: kCIInputScaleKey)
        let ctx = CIContext()
        guard let out = filter.outputImage?.cropped(to: ci.extent),
              let outCG = ctx.createCGImage(out, from: ci.extent) else {
            return NSImage(cgImage: cg, size: pointSize)
        }
        return NSImage(cgImage: outCG, size: pointSize)
    }
}
