import SwiftUI

/// 底部导航栏 — 自定义 4 tabs (守护 / 位置 / 消息 / 我的)
/// 对应原型 `.bottom-nav` 块
public struct LoveTrackBottomNav: View {
    @Binding public var selection: Tab
    public let onSelect: ((Tab) -> Void)?

    public init(selection: Binding<Tab>, onSelect: ((Tab) -> Void)? = nil) {
        self._selection = selection
        self.onSelect = onSelect
    }

    public enum Tab: String, CaseIterable, Identifiable {
        case protect, location, message, profile
        public var id: String { rawValue }

        var label: String {
            switch self {
            case .protect: return "守护"
            case .location: return "位置"
            case .message: return "消息"
            case .profile: return "我的"
            }
        }

        var icon: String {
            switch self {
            case .protect: return "heart.fill"
            case .location: return "mappin.and.ellipse"
            case .message: return "bubble.left.and.bubble.right.fill"
            case .profile: return "person.crop.circle.fill"
            }
        }
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                NavItem(
                    tab: tab,
                    isActive: tab == selection
                ) {
                    if selection != tab {
                        selection = tab
                        onSelect?(tab)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(Color.white.opacity(0.5))
            }
        )
        .overlay(
            Rectangle()
                .fill(Theme.border)
                .frame(height: 0.5),
            alignment: .top
        )
    }
}

private struct NavItem: View {
    let tab: LoveTrackBottomNav.Tab
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                ZStack(alignment: .top) {
                    if isActive {
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Theme.primary, Theme.violet],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: 18, height: 3)
                            .offset(y: -4)
                    }
                    Image(systemName: tab.icon)
                        .font(.system(size: 22, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? Theme.primary : Theme.textSubtle)
                        .padding(.top, 2)
                }
                Text(tab.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isActive ? Theme.primary : Theme.textSubtle)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    BottomNavPreview()
}

private struct BottomNavPreview: View {
    @State private var selection: LoveTrackBottomNav.Tab = .location
    var body: some View {
        VStack {
            Spacer()
            LoveTrackBottomNav(selection: $selection) { tab in
                print("switch: \(tab.label)")
            }
        }
        .background(Theme.bgGradient)
    }
}
