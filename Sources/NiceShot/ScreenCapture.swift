import AppKit
import ScreenCaptureKit

enum ScreenCaptureError: Error, LocalizedError {
    case displayNotFound
    case emptyRegion

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "対象ディスプレイが見つかりませんでした。"
        case .emptyRegion: return "選択範囲が空です。"
        }
    }
}

/// ScreenCaptureKit を使ったスクリーンキャプチャ。
enum ScreenCapture {
    /// 指定ディスプレイをキャプチャし、`pointRect`（そのディスプレイ内・左上原点・ポイント単位）で切り抜く。
    /// `pointRect` は選択オーバーレイと同じ NSScreen のポイント座標。切り抜き倍率も
    /// SCDisplay ではなく NSScreen のポイントサイズから求めるため、HiDPI スケーリングや
    /// マルチモニタ混在でもズレない。
    /// - Returns: 切り抜いた CGImage（ピクセル解像度）。
    static func capture(displayID: CGDirectDisplayID, pointRect: CGRect) async throws -> CGImage {
        guard pointRect.width >= 1, pointRect.height >= 1 else {
            throw ScreenCaptureError.emptyRegion
        }

        let content = try await SCShareableContent.current
        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureError.displayNotFound
        }

        // 選択座標の基準となる NSScreen のポイントサイズ。
        let screen = NSScreen.screens.first { screenDisplayID($0) == displayID }
        let scale = screen?.backingScaleFactor ?? 2.0
        let pointW = screen?.frame.width ?? CGFloat(scDisplay.width)
        let pointH = screen?.frame.height ?? CGFloat(scDisplay.height)

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(pointW * scale)
        config.height = Int(pointH * scale)
        config.showsCursor = false
        config.captureResolution = .best

        let full = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        // 実際のキャプチャ画素数 ÷ NSScreen ポイントサイズ＝実効倍率（選択座標と同じ土俵）。
        let effX = CGFloat(full.width) / pointW
        let effY = CGFloat(full.height) / pointH
        let pixelRect = CGRect(x: floor(pointRect.minX * effX),
                               y: floor(pointRect.minY * effY),
                               width: ceil(pointRect.width * effX),
                               height: ceil(pointRect.height * effY))
            .intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))

        guard pixelRect.width >= 1, pixelRect.height >= 1,
              let cropped = full.cropping(to: pixelRect) else {
            throw ScreenCaptureError.emptyRegion
        }
        return cropped
    }

    static func screenDisplayID(_ screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}
