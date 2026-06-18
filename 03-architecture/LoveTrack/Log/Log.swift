import Foundation
import os

/// 全局日志入口。
///
/// 用法：
/// ```swift
/// Log.info("AppSession", "定位已启动 (profile=standard)")
/// Log.warn("HTTPRealtime", "请求超时, retry #3")
/// Log.error("LocationManager", "permission denied")
/// Log.debug("Network", "payload=\\(body)")  // 默认关, 用户在设置里打开
/// ```
///
/// 同时输出到：
/// - Xcode console（`print`，原有行为不变）
/// - `LogStore.shared` 内存环形 buffer → UI 展示
/// - `Documents/dev.log` 文件 → 可分享 / 导出
///
/// 所有方法都是 `nonisolated`，可以从任意 actor / 线程调用（包括 CLLocationManagerDelegate
/// 回调、后台 Task 等）。开关检查直接走 UserDefaults，绕开 LogStore 的 @MainActor 隔离。
public enum Log {
    /// 模块名前缀（保持和原来 `print("[Module] ...")` 的风格一致）。
    public static func debug(_ module: String, _ message: @autoclosure () -> String) {
        guard UserDefaults.standard.bool(forKey: Keys.debugEnabled) else { return }
        emit(level: .debug, module: module, message: message())
    }

    public static func info(_ module: String, _ message: @autoclosure () -> String) {
        emit(level: .info, module: module, message: message())
    }

    public static func warn(_ module: String, _ message: @autoclosure () -> String) {
        emit(level: .warn, module: module, message: message())
    }

    public static func error(_ module: String, _ message: @autoclosure () -> String) {
        emit(level: .error, module: module, message: message())
    }

    private static func emit(level: LogLevel, module: String, message: String) {
        let entry = LogEntry(level: level, module: module, message: message)
        LogStore.shared.append(entry)
    }

    /// 与 LogStore.swift 里的 Keys 保持同步 —— Log.* 在 nonisolated context 调用,
    /// 不能读 main-actor 隔离的 store 属性, 所以这里直接读 UserDefaults。
    enum Keys {
        static let debugEnabled = "lovetrack.log.debugEnabled"
    }
}