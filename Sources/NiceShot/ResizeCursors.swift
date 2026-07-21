import AppKit

/// 斜めリサイズカーソル。公開 API に無いため、AppKit の非公開カーソルを
/// 取得して使い、取れなければ縦横リサイズカーソルにフォールバックする。
enum ResizeCursors {
    /// ↖↘（左上⇔右下）
    static var nwse: NSCursor {
        privateCursor("_windowResizeNorthWestSouthEastCursor") ?? .resizeUpDown
    }
    /// ↗↙（右上⇔左下）
    static var nesw: NSCursor {
        privateCursor("_windowResizeNorthEastSouthWestCursor") ?? .resizeUpDown
    }

    private static func privateCursor(_ selectorName: String) -> NSCursor? {
        let selector = NSSelectorFromString(selectorName)
        let cursorClass: AnyObject = NSCursor.self
        guard cursorClass.responds(to: selector),
              let result = cursorClass.perform(selector)?.takeUnretainedValue() as? NSCursor
        else { return nil }
        return result
    }
}
