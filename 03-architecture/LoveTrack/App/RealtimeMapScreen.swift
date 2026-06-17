import SwiftUI
import CoreLocation

/// 实时定位主页 — 复刻原型 love-location.html
/// 结构: Status bar → PartnerHero → 地图(高德真地图/MiniMap Canvas) → DistanceCard → PokeGrid → QuickCards → BottomNav
public struct RealtimeMapScreen: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var store: RelationshipStore

    @State private var locationEnabled: Bool = true
    @State private var toastMessage: String?
    @State private var toastIcon: String?

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            backgroundLayer
            contentScroll
            toastLayer
            // 底部导航由 AppTabView 统一管理
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    // MARK: - Layers

    private var backgroundLayer: some View {
        ZStack {
            Theme.bg
            LinearGradient(
                stops: [
                    .init(color: Color(red: 1.00, green: 0.84, blue: 0.91).opacity(0.55), location: 0.0),
                    .init(color: .clear, location: 0.5),
                    .init(color: Color(red: 0.91, green: 0.84, blue: 1.00).opacity(0.55), location: 1.0),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            backgroundStickers
        }
        .ignoresSafeArea()
    }

    private var backgroundStickers: some View {
        ZStack {
            Image(systemName: "heart.fill")
                .font(.system(size: 24))
                .foregroundColor(Theme.primary)
                .opacity(0.10)
                .offset(x: -140, y: -320)
            Image(systemName: "sparkle")
                .font(.system(size: 20))
                .foregroundColor(Theme.violet)
                .opacity(0.12)
                .offset(x: 140, y: -180)
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(Theme.primary)
                .opacity(0.10)
                .offset(x: -150, y: 80)
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundColor(Theme.violet)
                .opacity(0.12)
                .offset(x: 145, y: 220)
        }
    }

    private var contentScroll: some View {
        ScrollView {
            VStack(spacing: 14) {
                StatusBar()
                PartnerHero(
                    name: store.partner?.displayName ?? "小月亮",
                    avatar: "👧🏻",
                    distanceKm: store.distanceKmToPartner(myLocation: session.lastLocation),
                    isOnline: true,
                    deviceModel: "iPhone 15 Pro",
                    batteryPercent: Int(((store.lastKnownPartnerLocation?.battery?.level ?? 0.78) * 100).rounded()),
                    networkLabel: "5G · WiFi"
                )
                mapSection
                DistanceCard(
                    locationEnabled: $locationEnabled,
                    distanceMeters: distanceMeters,
                    partnerName: store.partner?.displayName ?? "小月亮"
                ) { newValue in
                    showToast(
                        newValue ? "已开启实时定位 · 共享位置给 TA" : "已关闭定位 · TA 将看不到你的位置",
                        icon: newValue ? "location.fill" : "moon.fill"
                    )
                }
                PokeGrid(partnerName: store.partner?.displayName ?? "小月亮") { item in
                    showToast("已发送给 TA：\(item.name)", icon: "paperplane.fill")
                }
                QuickCards { kind in
                    showToast("打开「\(kind.title)」", icon: kind.systemIcon)
                }
                Color.clear.frame(height: 100) // bottom nav 空间
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 地图区: 有 SDK 走真地图, 否则 Canvas 占位

    @ViewBuilder
    private var mapSection: some View {
        if AAMapBootstrap.isAvailable, let center = mapCenter {
            AAMapView(
                center: center,
                partner: mapPartner,
                me: mapMe
            )
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous))
            .softShadow(Theme.shadowMd)
        } else {
            MiniMap(
                partnerName: store.partner?.displayName ?? "小月亮",
                partnerAvatar: "👧🏻",
                lastUpdatedText: "1 分钟前更新"
            )
        }
    }

    // MARK: - Toast

    private var toastLayer: some View {
        VStack {
            Spacer()
            if let msg = toastMessage {
                HStack(spacing: 6) {
                    if let icon = toastIcon {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(msg)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color(red: 0.165, green: 0.078, blue: 0.188),
                                     Color(red: 0.227, green: 0.122, blue: 0.267)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                )
                .softShadow(Theme.shadowMd)
                .padding(.bottom, 110)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    /// 地图中心点: 优先用对方位置, 没有则用我自己的位置
    private var mapCenter: CLLocationCoordinate2D? {
        if let p = store.lastKnownPartnerLocation {
            return CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
        }
        if let me = session.lastLocation {
            return me.coordinate
        }
        return nil
    }

    private var mapPartner: MapPerson? {
        guard let p = store.lastKnownPartnerLocation else { return nil }
        return MapPerson(
            id: p.userId,
            name: store.partner?.displayName ?? "TA",
            coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
        )
    }

    private var mapMe: MapPerson? {
        guard let me = session.lastLocation else { return nil }
        return MapPerson(
            id: session.currentUser.id,
            name: "我",
            coordinate: me.coordinate
        )
    }

    private var distanceMeters: Int? {
        guard let km = store.distanceKmToPartner(myLocation: session.lastLocation) else {
            return store.lastKnownPartnerLocation != nil ? 1200 : nil
        }
        return Int((km * 1000).rounded())
    }

    private func showToast(_ message: String, icon: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            toastMessage = message
            toastIcon = icon
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeIn(duration: 0.25)) {
                toastMessage = nil
                toastIcon = nil
            }
        }
    }
}

#Preview {
    RealtimeMapScreen()
        .environmentObject(AppSession())
        .environmentObject(RelationshipStore(
            me: User(id: "u1", displayName: "我"),
            realtime: HTTPRealtimeSyncService(userId: "u1")
        ))
}
