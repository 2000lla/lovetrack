import SwiftUI

/// 守护状态横幅（主页顶栏下方，显示当前守护模式 + 暂停状态）。
/// Apple 审核要求：后台定位必须有"明显 UI 指示"。
public struct GuardBanner: View {
    @ObservedObject var settings: GuardSettings

    public init(settings: GuardSettings) {
        self.settings = settings
    }

    public var body: some View {
        HStack(spacing: 10) {
            iconView
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detailText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var iconView: some View {
        let image = Image(systemName: iconName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(iconColor)
        if #available(iOS 17.0, *) {
            image.symbolEffect(.pulse, options: .repeating, isActive: isActivelySharing)
        } else {
            image
        }
    }

    // MARK: - Computed

    private var isActivelySharing: Bool { settings.isActivelySharing }

    private var iconName: String {
        if settings.isPaused { return "pause.circle.fill" }
        return settings.mode.icon
    }

    private var iconColor: Color {
        if settings.isPaused { return .orange }
        return settings.mode.accentColor
    }

    private var backgroundColor: Color {
        if settings.isPaused { return Color.orange.opacity(0.10) }
        switch settings.mode {
        case .off:       return Color.gray.opacity(0.10)
        case .standard:  return Color.blue.opacity(0.08)
        case .realtime:  return Color.pink.opacity(0.08)
        }
    }

    private var borderColor: Color {
        if settings.isPaused { return Color.orange.opacity(0.3) }
        switch settings.mode {
        case .off:       return Color.gray.opacity(0.2)
        case .standard:  return Color.blue.opacity(0.25)
        case .realtime:  return Color.pink.opacity(0.3)
        }
    }

    private var titleText: String {
        if settings.isPaused { return "位置共享已暂停" }
        switch settings.mode {
        case .off:       return "未开启守护"
        case .standard:  return "标准守护中"
        case .realtime:  return "实时守护中"
        }
    }

    private var detailText: String {
        if let until = settings.pausedUntil, settings.isPaused {
            return "将在 \(formattedTime(until)) 自动恢复"
        }
        switch settings.mode {
        case .off:
            return "你和 TA 互相看不到位置"
        case .standard:
            return "TA 可以看到你的大致位置（5 min 心跳）"
        case .realtime:
            return "TA 可以看到你的实时位置（1 min 心跳）"
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    VStack(spacing: 12) {
        GuardBanner(settings: {
            let s = GuardSettings()
            return s
        }())
        GuardBanner(settings: {
            let s = GuardSettings()
            s.mode = .standard
            return s
        }())
        GuardBanner(settings: {
            let s = GuardSettings()
            s.mode = .realtime
            return s
        }())
        GuardBanner(settings: {
            let s = GuardSettings()
            s.mode = .standard
            s.pauseForOneHour()
            return s
        }())
    }
    .padding()
    .background(Theme.bg)
}