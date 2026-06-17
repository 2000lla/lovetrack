import SwiftUI
import CoreLocation

/// App 主壳 — 4 tabs 切换 (守护 / 位置 / 消息 / 我的)
/// 复刻原型 love-location.html 的 bottom-nav + 内容区结构
public struct AppTabView: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var store: RelationshipStore

    @State private var selectedTab: AppTab = .location

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            // 内容区
            Group {
                switch selectedTab {
                case .guard_:     GuardScreen()
                case .location:   RealtimeMapScreen()
                case .message:    MessageScreen()
                case .profile:    ProfileScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            // 自定义底部导航
            LoveTrackBottomNav(selection: tabBinding)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var tabBinding: Binding<LoveTrackBottomNav.Tab> {
        Binding(
            get: {
                switch selectedTab {
                case .guard_:   return .protect
                case .location: return .location
                case .message:  return .message
                case .profile:  return .profile
                }
            },
            set: { newTab in
                withAnimation(.easeInOut(duration: 0.2)) {
                    switch newTab {
                    case .protect:  selectedTab = .guard_
                    case .location: selectedTab = .location
                    case .message:  selectedTab = .message
                    case .profile:  selectedTab = .profile
                    }
                }
            }
        )
    }
}

public enum AppTab: String, CaseIterable, Identifiable {
    case guard_ = "guard"
    case location, message, profile

    public var id: String { rawValue }
}

#Preview {
    AppTabView()
        .environmentObject(AppSession())
        .environmentObject(RelationshipStore(
            me: User(id: "u1", displayName: "我"),
            realtime: HTTPRealtimeSyncService(userId: "u1")
        ))
}
