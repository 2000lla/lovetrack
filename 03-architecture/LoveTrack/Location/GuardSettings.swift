import Foundation
import SwiftUI

/// 守护模式（位置共享策略）。
///
/// 设计原则：**默认保守档，高频是用户的主动选择**。
/// - 关闭：完全停采（用户主动停了）
/// - 标准：保守档（默认，电池友好，符合 App Store 审核默认行为）
/// - 实时：高频档（用户主动开启，体验优先）
public enum GuardMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case off
    case standard
    case realtime

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off:      return "已暂停"
        case .standard: return "标准守护"
        case .realtime: return "实时守护"
        }
    }

    public var description: String {
        switch self {
        case .off:
            return "你和 TA 互相看不到对方位置"
        case .standard:
            return "后台静止 5 分钟心跳一次，移动时 15-30 秒。电池友好。"
        case .realtime:
            return "后台静止 1 分钟心跳，移动时 3-10 秒。耗电增加约 15%。"
        }
    }

    public var icon: String {
        switch self {
        case .off:      return "moon.fill"
        case .standard: return "shield.lefthalf.filled"
        case .realtime: return "shield.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .off:      return .gray
        case .standard: return .blue
        case .realtime: return .pink
        }
    }
}

/// 用户的守护设置（持久化到 UserDefaults）。
///
/// **默认**：`.standard`（保守档）—— 用户首次进入 App 就走保守档，
/// 不主动采集任何高频数据，符合 App Store "user control + necessary" 原则。
@MainActor
public final class GuardSettings: ObservableObject {
    @Published public var mode: GuardMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode) }
    }

    /// 是否暂停共享（任意模式下都可一键暂停）。
    @Published public var isPaused: Bool {
        didSet { UserDefaults.standard.set(isPaused, forKey: Keys.isPaused) }
    }

    /// 暂停到期时间（nil = 未暂停或已恢复）。
    @Published public var pausedUntil: Date? {
        didSet {
            if let date = pausedUntil {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Keys.pausedUntil)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.pausedUntil)
            }
        }
    }

    public init() {
        let raw = UserDefaults.standard.string(forKey: Keys.mode) ?? GuardMode.standard.rawValue
        self.mode = GuardMode(rawValue: raw) ?? .standard
        self.isPaused = UserDefaults.standard.bool(forKey: Keys.isPaused)

        let ts = UserDefaults.standard.double(forKey: Keys.pausedUntil)
        if ts > 0 {
            let date = Date(timeIntervalSince1970: ts)
            self.pausedUntil = date > Date() ? date : nil
            if self.pausedUntil == nil {
                self.isPaused = false
            }
        } else {
            self.pausedUntil = nil
        }
    }

    /// 当前是否真的在采集位置。
    /// - mode == .off → false
    /// - mode != .off && isPaused → false
    /// - 否则 → true
    public var isActivelySharing: Bool {
        if mode == .off { return false }
        if isPaused { return false }
        return true
    }

    /// 暂停 1 小时。
    public func pauseForOneHour() {
        isPaused = true
        pausedUntil = Date().addingTimeInterval(3600)
    }

    /// 暂停到明天早上 8 点。
    public func pauseUntilMorning() {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 8
        components.minute = 0
        let target = calendar.date(from: components) ?? Date().addingTimeInterval(8 * 3600)
        let safeTarget = target > Date() ? target : target.addingTimeInterval(24 * 3600)
        isPaused = true
        pausedUntil = safeTarget
    }

    /// 立即恢复共享。
    public func resume() {
        isPaused = false
        pausedUntil = nil
    }

    /// 检查暂停是否到期，到期自动恢复。
    @discardableResult
    public func checkPauseExpiry() -> Bool {
        guard isPaused, let until = pausedUntil else { return false }
        if until <= Date() {
            resume()
            return true
        }
        return false
    }

    private enum Keys {
        static let mode = "lovetrack.guardMode"
        static let isPaused = "lovetrack.isPaused"
        static let pausedUntil = "lovetrack.pausedUntil"
    }
}