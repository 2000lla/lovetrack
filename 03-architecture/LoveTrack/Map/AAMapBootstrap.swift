import Foundation
import CoreLocation

#if canImport(MAMapKit)
import AMapFoundationKit
import MAMapKit
#endif

/// 高德 iOS SDK 启动初始化。
///
/// **调用时机**：必须在 App 启动早期调用一次（`LoveTrackApp.init` 里）。
/// **作用**：把 `Secrets.xcconfig` 里的 `AMAP_API_KEY` 通过 Info.plist 注入 `AMapServices`，
/// 启用 HTTPS（生产环境必须）。
///
/// **隐私合规两行**（`MAMapView.updatePrivacyShow / updatePrivacyAgree`）
/// 由 `AAMapView.makeUIView` 在地图首次创建前调用，无需在此处重复。
///
/// **安全**：
/// - Key 从 `Info.plist` 的 `AMapAPIKey` 字段读取
/// - Info.plist 的值由 `xcconfig` 注入，xcconfig 已 `.gitignore`，不进 git 历史
/// - 生产构建应把 key 替换成更严格的鉴权方案（设备绑定 / 后端代理）
public enum AAMapBootstrap {
    /// 启动时一次性初始化。SDK 不可用时静默跳过（编译期 canImport 决定）。
    public static func bootstrap() {
        #if canImport(MAMapKit)
        guard let key = apiKey else {
            print("[AAMap] ⚠️ AMapAPIKey 缺失, 高德地图将无法加载")
            print("[AAMap]    请检查 Secrets.xcconfig 是否有 AMAP_API_KEY = ...")
            return
        }
        AMapServices.shared().apiKey = key
        AMapServices.shared().enableHTTPS = true
        print("[AAMap] ✅ 初始化完成, key 前缀: \(key.prefix(6))…")
        #else
        print("[AAMap] ⏭️ 高德 SDK 未链接, 跳过 bootstrap (MapView 会走 fallback)")
        #endif
    }

    /// 当前 key（供 debug UI 展示，不要在 release 显示完整 key）
    public static var apiKey: String? {
        (Bundle.main.infoDictionary?["AMapAPIKey"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty()
    }

    /// SDK 是否可用（编译期 + 运行时 key 检查）
    public static var isAvailable: Bool {
        #if canImport(MAMapKit)
        return apiKey != nil
        #else
        return false
        #endif
    }
}

private extension String {
    func nilIfEmpty() -> String? { isEmpty ? nil : self }
}

