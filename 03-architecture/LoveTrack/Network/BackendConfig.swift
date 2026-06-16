import Foundation

/// 后端配置。
///
/// 真机调试时，把 baseURL 改成你的电脑 IP（如 http://192.168.1.100:3000），
/// iPhone 和 Mac 必须在同一个 WiFi。
public struct BackendConfig {
    /// HTTP + WebSocket 基础地址。
    /// - 模拟器：`http://localhost:3000`（共享 Mac localhost）
    /// - 真机：Mac 的局域网 IP（如 http://192.168.10.43:3000）
    public static let baseURL: URL = {
        if let env = ProcessInfo.processInfo.environment["LOVETRACK_BACKEND_URL"],
           let url = URL(string: env) {
            return url
        }
        // 你的 Mac IP（iPhone 真机调试用）
        return URL(string: "http://192.168.10.43:3000")!
    }()

    /// WebSocket URL（http:// → ws://, https:// → wss://）
    public static let wsURL: URL = {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        comps.scheme = comps.scheme == "https" ? "wss" : "ws"
        comps.path = "/sync"
        return comps.url!
    }()
}