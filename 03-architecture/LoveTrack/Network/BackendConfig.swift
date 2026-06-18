import Foundation

/// 后端配置。
///
/// 修改后端地址：编辑此文件底部的 `serverURL`，⌘R 即可。不需要改 xcconfig 或 Xcode Scheme。
public struct BackendConfig {
    /// 后端地址。Debug 默认连云服务器，Release 用 HTTPS 生产域名。
    private static let serverURL: String = {
        #if DEBUG
        return "http://YOUR_SERVER_IP:3000"  // 占位符:首次运行时填入你的后端 IP/域名 (Secrets.xcconfig 也可覆盖)
        #else
        return "https://api.lovetrack.app"  // 上架前替换
        #endif
    }()

    public static let baseURL: URL = {
        // 环境变量覆盖（保留：真机临时切其他服务器时可用）
        if let env = ProcessInfo.processInfo.environment["LOVETRACK_BACKEND_URL"],
           let url = URL(string: env) {
            print("[BackendConfig] baseURL = \(url.absoluteString) (env override)")
            return url
        }
        let url = URL(string: serverURL)!
        print("[BackendConfig] baseURL = \(url.absoluteString) (default)")
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
