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
        // DEBUG 编译：默认走 PairScreen（用户能看见配对页）
        //   输任意 6 位数字 + 绑定 → DevMock 触发配对成功进主页
        //   设环境变量 LOVETRACK_SKIP_PAIR=1 → 跳过配对直接进主页
        // Release 编译：必须走完真配对才能进主页
        #if DEBUG
        if ProcessInfo.processInfo.environment["LOVETRACK_SKIP_PAIR"] == "1" {
            mainTabs
                .onAppear {
                    DevMock.bootstrapIfNeeded(session: session, store: store)
                }
        } else {
            if session.isPaired || store.isPaired {
                mainTabs
            } else {
                PairScreen()
            }
        }
        #else
        if session.isPaired || store.isPaired {
            mainTabs
        } else {
            PairScreen()
        }
        #endif
    }

    private var mainTabs: some View {
        // 4 tabs 完整 UI（守护 / 位置 / 消息 / 我的）
        AppTabView()
    }
}

/// 开发期 mock — 在 DEBUG 编译、且没配对时,自动给一份假伴侣+假位置,方便看 UI
enum DevMock {
    @MainActor
    static func bootstrapIfNeeded(session: AppSession, store: RelationshipStore) {
        guard !session.isPaired, !store.isPaired else { return }

        // 1. 标记配对完成
        session.isPaired = true

        // 2. 注入 mock 伴侣
        let mockPartnerId = "mock-partner-001"
        let mockPartner = User(
            id: mockPartnerId,
            displayName: "小月亮",
            avatarURL: nil
        )

        // 3. 注入 mock 位置（济南历城区 — 跟原型地图一致）
        let mockLocation = LocationPoint(
            userId: mockPartnerId,
            lat: 36.6512,          // 历城区
            lon: 117.1201,
            altitude: nil,
            horizontalAccuracy: 5.0,
            verticalAccuracy: nil,
            speed: 0,
            course: 0,
            timestamp: Date().addingTimeInterval(-60), // 1 分钟前
            receivedAt: Date(),
            battery: BatteryInfo(level: 0.78, isCharging: false, isLowPower: false),
            source: .gps,
            sessionId: "mock-session"
        )

        // 4. 注入"我"的当前位置（山大科技产业园 — 跟伴侣距离 1.2km）
        let myLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 36.6640, longitude: 117.1280),
            altitude: 0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: -1,
            course: 0,
            speed: 0,
            timestamp: Date()
        )

        store.partner = mockPartner
        store.isPaired = true
        store.lastKnownPartnerLocation = mockLocation
        session.lastLocation = myLocation

        print("[DevMock] ✅ mock 伴侣 + 位置已注入,直接进主页调试")
    }
}

// RealtimeMapScreen 已在 App/RealtimeMapScreen.swift 定义（高保真复刻原型）

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
