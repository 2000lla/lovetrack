import SwiftUI

/// 快捷信息卡 — 守护模式 / 低电提醒 / 常去地点 / 紧急求助
/// 对应原型 `.quick-row` 块
public struct QuickCards: View {
    public let onTap: ((QuickCardKind) -> Void)?

    public init(onTap: ((QuickCardKind) -> Void)? = nil) {
        self.onTap = onTap
    }

    private let cards: [QuickCardKind] = [
        .protect, .lowBattery, .frequentPlaces, .sos
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    public var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(cards) { kind in
                QuickCard(kind: kind) {
                    onTap?(kind)
                }
            }
        }
    }
}

public enum QuickCardKind: String, CaseIterable, Identifiable {
    case protect
    case lowBattery
    case frequentPlaces
    case sos

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .protect: return "守护模式"
        case .lowBattery: return "低电提醒"
        case .frequentPlaces: return "常去地点"
        case .sos: return "紧急求助"
        }
    }

    var subtitle: String {
        switch self {
        case .protect: return "已开启 · 24h"
        case .lowBattery: return "<20% 通知你"
        case .frequentPlaces: return "家 · 公司"
        case .sos: return "一键联系"
        }
    }

    var systemIcon: String {
        switch self {
        case .protect: return "shield.fill"
        case .lowBattery: return "battery.25"
        case .frequentPlaces: return "mappin.and.ellipse"
        case .sos: return "exclamationmark.triangle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .protect: return Theme.violetSoft
        case .lowBattery: return Theme.primarySoft
        case .frequentPlaces: return Color(red: 1.00, green: 0.94, blue: 0.88)
        case .sos: return Color(red: 0.92, green: 0.99, blue: 0.96)
        }
    }

    var iconTint: Color {
        switch self {
        case .protect: return Theme.violet
        case .lowBattery: return Theme.primary
        case .frequentPlaces: return Color(red: 0.95, green: 0.59, blue: 0.27)
        case .sos: return Theme.success
        }
    }
}

private struct QuickCard: View {
    let kind: QuickCardKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                        .fill(kind.iconColor)
                        .frame(width: 36, height: 36)
                    Image(systemName: kind.systemIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(kind.iconTint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    Text(kind.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1.5)
            )
            .softShadow(Theme.shadowXs)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    QuickCards { kind in
        print("tap: \(kind.title)")
    }
    .padding()
    .background(Theme.bgGradient)
}
