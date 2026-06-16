import SwiftUI
import BackgroundTasks
import CoreLocation

@main
struct LoveTrackApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = AppSession()

    init() {
        // 必须在 launch 完成前注册 BGTask
        BackgroundKeepAlive.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(session.relationshipStore)
                .task {
                    // 兜底：bootstrap 失败不能导致 App 崩
                    do {
                        try await session.bootstrap()
                    } catch {
                        print("[LoveTrackApp] bootstrap failed: \(error)")
                    }
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                session.handleEnterBackground()
            case .active:
                session.handleEnterForeground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}

/// App 全局依赖容器。
@MainActor
final class AppSession: ObservableObject {
    let realtime: RealtimeSyncServiceProtocol
    let locationManager: LocationManager
    let relationshipStore: RelationshipStore

    @Published var currentUser: User
    @Published var authState: LocationManager.AuthState = .notDetermined
    @Published var lastLocation: CLLocation?
    @Published var isReady: Bool = false
    @Published var isPaired: Bool = false
    @Published var currentRelationship: Relationship?

    private var locationTask: Task<Void, Never>?
    private var partnerLocationTask: Task<Void, Never>?

    init() {
        // 用稳定的 userId（生产应该用 Apple ID / UUID 持久化到 Keychain）
        let storedId = UserDefaults.standard.string(forKey: "lovetrack.userId") ?? UUID().uuidString
        UserDefaults.standard.set(storedId, forKey: "lovetrack.userId")
        let me = User(id: storedId, displayName: "我")
        self.currentUser = me
        let lm = LocationManager.shared
        self.locationManager = lm
        // 用 HTTP 后端版（对接 05-backend Node.js）
        let sync: RealtimeSyncServiceProtocol = HTTPRealtimeSyncService(userId: storedId)
        self.realtime = sync
        self.relationshipStore = RelationshipStore(me: me, realtime: sync)
        // 监听 WebSocket 推送的 pair_success：对方加入 → 自动跳转主页
        if let http = sync as? HTTPRealtimeSyncService {
            http.onPairSuccess = { [weak self] inviteeId in
                Task { @MainActor in
                    guard let self else { return }
                    self.isPaired = true
                    self.relationshipStore.partner = User(id: inviteeId, displayName: "伴侣")
                    self.relationshipStore.isPaired = true
                    print("[AppSession] pair_success → auto-transitioning to main")
                }
            }
        }
    }

    @MainActor
    func completePairing(relationship: Relationship? = nil) {
        isPaired = true
        if let rel = relationship {
            currentRelationship = rel
        }
        print("[AppSession] completePairing called, isPaired=\(isPaired)")
    }

    func bootstrap() async {
        // 1. 注册定位
        authState = await locationManager.requestAuthorization()
        // 2. 启动后台保活
        await BackgroundKeepAlive.shared.start(locationManager: locationManager)
        // 3. 提前连接 WebSocket（即使还没配对也连，位置才能流出去；后端会忽略 partner 推送）
        if let http = realtime as? HTTPRealtimeSyncService {
            await http.bootstrapConnect()
        }
        // 4. 订阅定位 → 同步到云
        locationTask?.cancel()
        locationTask = Task { [weak self] in
            guard let self = self else { return }
            let stream = await self.locationManager.events()
            for await event in stream {
                let point = LocationPoint(
                    userId: self.currentUser.id,
                    lat: event.location.coordinate.latitude,
                    lon: event.location.coordinate.longitude,
                    altitude: event.location.altitude,
                    horizontalAccuracy: event.location.horizontalAccuracy,
                    verticalAccuracy: event.location.verticalAccuracy,
                    speed: event.location.speed,
                    course: event.location.course,
                    timestamp: event.location.timestamp,
                    battery: event.battery,
                    source: mapSource(event.mode),
                    sessionId: event.sessionId
                )
                try? await self.realtime.uploadPoint(point)
                self.lastLocation = event.location
            }
        }
        // 5. 启动定位
        try? await locationManager.start()
        // 6. 订阅 partner 位置流（把对方位置更新到 store）
        startObservingPartnerLocation()
        isReady = true
    }

    /// 订阅对方位置 → 推到 RelationshipStore
    private func startObservingPartnerLocation() {
        partnerLocationTask?.cancel()
        partnerLocationTask = Task { [weak self] in
            guard let self = self else { return }
            for await point in self.realtime.observePartnerLocation(userId: "partner") {
                await MainActor.run {
                    // 通过 store 更新对方位置（store 内部已经维护 lastKnownPartnerLocation）
                    // 这里直接 refresh 触发 store 内的订阅
                    self.relationshipStore.refreshPartnerLocation(point)
                }
            }
        }
    }

    func handleEnterForeground() {
        Task { await locationManager.handleAppForeground() }
    }

    func handleEnterBackground() {
        Task { await locationManager.handleAppBackground() }
    }

    private func mapSource(_ mode: LocationManager.TrackingMode) -> Source {
        switch mode {
        case .foreground, .background: return .gps
        case .significantChange: return .significantChange
        case .off: return .gps
        }
    }
}

/// 根视图（极简占位）。
struct RootView: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var store: RelationshipStore

    var body: some View {
        if session.isPaired || store.isPaired {
            mainTabs
        } else {
            PairScreen()
        }
    }

    private var mainTabs: some View {
        TabView {
            RealtimeMapScreen()
                .tabItem { Label("定位", systemImage: "location.fill") }
            TrackPlaybackScreen()
                .tabItem { Label("轨迹", systemImage: "map.fill") }
            SettingsScreen()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(.purple)
    }
}

struct RealtimeMapScreen: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var store: RelationshipStore

    var body: some View {
        let center = session.lastLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 36.6512, longitude: 117.1201)
        let partner = store.lastKnownPartnerLocation
        var annotations: [MapView.Annotation] = []
        if let p = partner {
            annotations.append(.init(
                id: "partner",
                coordinate: .init(latitude: p.lat, longitude: p.lon),
                title: store.partner?.displayName ?? "伴侣",
                iconSystemName: "heart.circle.fill"
            ))
        }
        return VStack(spacing: 0) {
            partnerHeader
            MapView(center: center, annotations: annotations, showsUserLocation: true)
        }
    }

    @ViewBuilder
    private var partnerHeader: some View {
        if let partner = store.partner,
           let p = store.lastKnownPartnerLocation {
            let dist = store.distanceKmToPartner(myLocation: session.lastLocation)
            HStack {
                VStack(alignment: .leading) {
                    Text(partner.displayName).font(.headline)
                    Text(String(format: "距离 %.2f km", dist ?? 0))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "电量 %.0f%%", (p.battery?.level ?? 1) * 100))
                    .font(.caption.monospacedDigit())
            }
            .padding(16)
        } else {
            HStack {
                Text("未配对")
                    .font(.headline)
                Spacer()
            }
            .padding(16)
        }
    }
}

struct TrackPlaybackScreen: View {
    @EnvironmentObject var session: AppSession

    var body: some View {
        let vm = TrackPlaybackViewModel(sync: session.realtime)
        return TrackPlaybackView(viewModel: vm)
    }
}

struct SettingsScreen: View {
    @EnvironmentObject var session: AppSession

    var body: some View {
        Form {
            Section("权限") {
                Text("定位权限: \(authLabel)")
                Button("请求 Always 权限") {
                    Task { _ = await session.locationManager.requestAuthorization() }
                }
            }
            Section("关系") {
                if session.relationshipStore.isPaired {
                    Button("解除关系", role: .destructive) {
                        Task {
                            try? await session.relationshipStore.dissolve()
                            session.isPaired = false
                        }
                    }
                } else {
                    Text("尚未配对")
                }
            }
            Section("调试") {
                Text("userId: \(session.currentUser.id)")
                    .font(.caption.monospaced())
                Text("后端: \(BackendConfig.baseURL.absoluteString)")
                    .font(.caption.monospaced())
            }
        }
    }

    private var authLabel: String {
        switch session.authState {
        case .notDetermined: return "未决定"
        case .denied: return "已拒绝"
        case .restricted: return "受限"
        case .whenInUse: return "使用期间"
        case .always: return "始终"
        }
    }
}
