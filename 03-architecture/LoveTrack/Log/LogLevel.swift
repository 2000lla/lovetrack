import Foundation

/// 日志级别。
public enum LogLevel: String, Codable, Sendable {
    case debug
    case info
    case warn
    case error

    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info:  return "INFO"
        case .warn:  return "WARN"
        case .error: return "ERROR"
        }
    }
}