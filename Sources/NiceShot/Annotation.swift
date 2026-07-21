import AppKit

enum ToolKind: CaseIterable {
    case select, arrow, rectangle, ellipse, line, pen, text, blur

    var symbolName: String {
        switch self {
        case .select:    return "cursorarrow"
        case .arrow:     return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse:   return "circle"
        case .line:      return "line.diagonal"
        case .pen:       return "pencil.tip"
        case .text:      return "textformat"
        case .blur:      return "drop.fill"
        }
    }

    var tooltip: String {
        switch self {
        case .select:    return "選択・移動"
        case .arrow:     return "矢印"
        case .rectangle: return "四角"
        case .ellipse:   return "楕円"
        case .line:      return "直線"
        case .pen:       return "フリーハンド"
        case .text:      return "テキスト"
        case .blur:      return "ぼかし"
        }
    }
}

/// 1 つの注釈。座標はキャンバス（＝画像ポイント）座標系・左下原点。
struct Annotation {
    let id = UUID()
    var kind: ToolKind
    var color: NSColor
    var lineWidth: CGFloat
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint] = []   // pen 用
    var text: String = ""
    var fontSize: CGFloat = 24
}
