import Foundation

/// 后端配置。
///
/// `baseURL` 解析顺序（从高到低）：
/// 1. **环境变量 `LOVETRACK_BACKEND_URL`** —— Xcode scheme 临时切其他服务器；适合 debug
/// 2. **编译默认 `http://YOUR_SERVER_IP:3000`** —— 占位符，必须替换或用环境变量覆盖
///
/// ⚠️ 不能用 Info.plist 注入 URL：Xcode 处理 Info.plist 时会把 `http://` 的 `//`
/// 误识别为嵌套 keypath, 截断成 `http:`。所以 backend 地址走代码常量 + 环境变量。
///
/// 修改后端地址（开发期）：
/// - 在 Xcode scheme 里设置环境变量 `LOVETRACK_BACKEND_URL=http://你的IP:3000`（推荐）
/// - 或者编辑 `Secrets.xcconfig` 后用 launch argument 注入（gitignored）
/// - 直接改下面的 `defaultBackendURL` 会污染 git 历史，**不要这么做**
///
/// 上线 HTTPS：换成 `https://api.lovetrack.app`。
public struct BackendConfig {
    /// 编译默认后端地址占位符。Release 时改成 `https://api.lovetrack.app`。
    /// ⚠️ 提交前保持占位符，不要把真实 IP 写在这里。
    private static let defaultBackendURL = "http://YOUR_SERVER_IP:3000"

    public static let baseURL: URL = {
        // 1. 环境变量（Xcode scheme 临时切, 优先级最高）
        if let env = ProcessInfo.processInfo.environment["LOVETRACK_BACKEND_URL"],
           !env.isEmpty,
           let url = URL(string: env) {
            Log.info("BackendConfig", "baseURL = \(url.absoluteString) (env override)")
            return url
        }
        // 2. 编译默认
        let url = URL(string: defaultBackendURL)!
        Log.info("BackendConfig", "baseURL = \(url.absoluteString) (default)")
        return url
    }()

    /// WebSocket URL（http:// → ws://, https:// → wss://）
    public static var wsURL: URL {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        comps.scheme = comps.scheme == "https" ? "wss" : "ws"
        comps.path = "/sync"
        return comps.url!
    }
}