import Foundation
import ServiceManagement

/// ログイン時の自動起動（ログイン項目）の管理。macOS 13+ の SMAppService を使う。
enum LoginItem {
    /// 現在ログイン項目として有効か。
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 自動起動の有効/無効を切り替える。成功したら true。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("[NiceShot] ログイン項目の切り替えに失敗: \(error.localizedDescription)")
            return false
        }
    }
}
