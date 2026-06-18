import Foundation
import Combine

/// 全局日志 store（单例）。
///
/// 设计：
/// - 内存里维护一个环形 buffer，最多 `capacity` 条，超出自动 drop oldest
/// - 同时异步追加到 `Documents/dev.log`（方便用户分享/导出）
/// - 通过 `@Published var entries` 推到 UI（Settings → 开发者日志 页面）
/// - 所有写入都在 background queue，UI 读取走 main actor
@MainActor
public final class LogStore: ObservableObject {
    public static let shared = LogStore()

    /// UI 订阅的日志条目（最近 N 条，按时间倒序：最新在前）。
    @Published public private(set) var entries: [LogEntry] = []

    /// 用户开关：是否记录到文件（默认开）
    @Published public var isFileLoggingEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isFileLoggingEnabled, forKey: Keys.fileEnabled) }
    }

    /// 用户开关：是否在 Xcode console 打印（默认开）
    @Published public var isConsoleLoggingEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isConsoleLoggingEnabled, forKey: Keys.consoleEnabled) }
    }

    /// 用户开关：UI 是否记录 debug 级别（默认关，调试时打开）
    @Published public var isDebugEnabled: Bool = false {
        didSet { UserDefaults.standard.set(isDebugEnabled, forKey: Keys.debugEnabled) }
    }

    public let capacity: Int = 1000

    private let fileURL: URL?
    private let writeQueue = DispatchQueue(label: "com.lovetrack.log.write", qos: .utility)
    private let dateFormatter: ISO8601DateFormatter

    private enum Keys {
        static let fileEnabled = "lovetrack.log.fileEnabled"
        static let consoleEnabled = "lovetrack.log.consoleEnabled"
        static let debugEnabled = "lovetrack.log.debugEnabled"
    }

    public init() {
        self.isFileLoggingEnabled = UserDefaults.standard.object(forKey: Keys.fileEnabled) as? Bool ?? true
        self.isConsoleLoggingEnabled = UserDefaults.standard.object(forKey: Keys.consoleEnabled) as? Bool ?? true
        self.isDebugEnabled = UserDefaults.standard.bool(forKey: Keys.debugEnabled)

        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.dateFormatter = f

        if let docs = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            self.fileURL = docs.appendingPathComponent("dev.log")
        } else {
            self.fileURL = nil
        }
    }

    /// 追加一条日志（所有 Log.* 入口最终都走这里）。
    nonisolated public func append(_ entry: LogEntry) {
        // 1) Xcode console
        if UserDefaults.standard.object(forKey: Keys.consoleEnabled) as? Bool ?? true {
            print(entry.formatted)
        }

        // 2) 文件落盘（后台线程）
        if UserDefaults.standard.object(forKey: Keys.fileEnabled) as? Bool ?? true {
            let line = entry.fullLine + "\n"
            let url = self.fileURL  // 在 actor 外抓出来
            self.writeQueue.async {
                guard let url = url else { return }
                if let data = line.data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: url.path) {
                        if let handle = try? FileHandle(forWritingTo: url) {
                            try? handle.seekToEnd()
                            try? handle.write(contentsOf: data)
                            try? handle.close()
                        }
                    } else {
                        try? data.write(to: url, options: .atomic)
                    }
                }
            }
        }

        // 3) UI buffer（main actor）
        Task { @MainActor in
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.capacity {
                self.entries.removeLast(self.entries.count - self.capacity)
            }
        }
    }

    /// 清空 UI buffer（不删文件 —— 文件可手动重置）。
    public func clearBuffer() {
        entries.removeAll()
    }

    /// 返回日志文件路径（用于 UI 展示 / 分享）。
    public var logFileURL: URL? { fileURL }

    /// 清空磁盘日志文件。
    public func clearFile() {
        guard let url = fileURL else { return }
        writeQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }
}