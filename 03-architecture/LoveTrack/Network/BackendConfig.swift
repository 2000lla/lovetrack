import Foundation

/// 后端配置。
///
/// **三步配置**（按使用场景）：
///
/// | 场景 | 启动 baseURL |
/// |------|---|
/// | 模拟器调试 | 默认走 `http://localhost:3000`（共享 Mac localhost） |
/// | 真机调试 | **必须**设环境变量 `LOVETRACK_BACKEND_URL=http://192.168.x.x:3000`（Xcode Scheme → Run → Arguments → Environment Variables） |
/// | 生产云服务器 | 部署后用 `LOVETRACK_BACKEND_URL=https://api.your-domain.com` |
///
/// **诊断**：启动时 `AppSession.bootstrap()` 会把实际 baseURL 打到 console，
/// 启动卡死时第一时间看 Xcode console 的 `[BackendConfig] baseURL = ...`。
public struct BackendConfig {
    /// HTTP + WebSocket 基础地址
    public static let baseURL: URL = {
        // 1. 最高优先级: 环境变量
        if let env = ProcessInfo.processInfo.environment["LOVETRACK_BACKEND_URL"],
           let url = URL(string: env) {
            print("[BackendConfig] baseURL = \(url.absoluteString) (env)")
            return url
        }

        // 2. 模拟器默认走 Mac localhost
        #if targetEnvironment(simulator)
        let url = URL(string: "http://localhost:3000")!
        print("[BackendConfig] baseURL = \(url.absoluteString) (simulator default)")
        return url
        #else
        // 3. 真机没设环境变量时: 给一个明确告警, 而不是错的占位 IP
        // 真机用 localhost 会连手机自己, 用 192.168.10.43 是占位猜的, 都不对
        print("[BackendConfig] ⚠️ LOVETRACK_BACKEND_URL 未设置 (真机环境)")
        print("[BackendConfig]    请在 Xcode Scheme → Run → Arguments → Environment Variables 添加:")
        print("[BackendConfig]    LOVETRACK_BACKEND_URL = http://YOUR_MAC_IP:3000")
        print("[BackendConfig]    查 Mac IP:  ifconfig en0 | grep 'inet '")
        print("[BackendConfig]    当前 fallback: 192.168.10.43:3000 (大概率不通, app 会卡)")
        return URL(string: "http://192.168.10.43:3000")!
        #endif
    }()

    /// WebSocket URL（http:// → ws://, https:// → wss://）
    public static var wsURL: URL {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        comps.scheme = comps.scheme == "https" ? "wss" : "ws"
        comps.path = "/sync"
        return comps.url!
    }
}
