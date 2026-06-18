import Foundation

/// 单条日志记录。
public struct LogEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let module: String
    public let message: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        module: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.module = module
        self.message = message
    }

    /// UI 显示用：`[21:34:05.123][INFO ][AppSession] 上传位置: 22.82, 108.27`
    public var formatted: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        let ts = f.string(from: timestamp)
        return "[\(ts)][\(level.label.padding(toLength: 5, withPad: " ", startingAt: 0))][\(module)] \(message)"
    }

    /// 文件落盘 + 复制粘贴用（带日期，方便 grep）。
    public var fullLine: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "[\(f.string(from: timestamp))][\(level.label)][\(module)] \(message)"
    }
}