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
        // MapKit 不需要手动初始化,系统自带
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
                        Log.error("LoveTrackApp", "bootstrap failed: \(error)")
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
    let guardSettings: GuardSettings

    @Published var currentUser: User
    @Published var authState: LocationManager.AuthState = .notDetermined
    @Published var lastLocation: CLLocation?
    @Published var isReady: Bool = false
    @Published var isPaired: Bool = false
    @Published var currentRelationship: Relationship?

    private var locationTask: Task<Void, Never>?
    private var partnerLocationTask: Task<Void, Never>?
    private var partnerHttpPollTask: Task<Void, Never>?
    private var pauseCheckTask: Task<Void, Never>?

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
        self.guardSettings = GuardSettings()
        // 监听 WebSocket 推送的 pair_success：对方加入 → 自动跳转主页
        if let http = sync as? HTTPRealtimeSyncService {
            http.onPairSuccess = { [weak self] inviteeId in
                Task { @MainActor in
                    guard let self else { return }
                    self.isPaired = true
                    self.relationshipStore.partner = User(id: inviteeId, displayName: "伴侣")
                    self.relationshipStore.isPaired = true
                    Log.info("AppSession", "pair_success → auto-transitioning to main, inviteeId=\(inviteeId)")
                    // 配对成功后立即拉一次对方位置（不等 15s 轮询）
                    Task { await self.pollPartnerLocationOnce() }
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
        Log.info("AppSession", "completePairing called, isPaired=\(isPaired)")
    }

    func bootstrap() async {
        // 0. 检查暂停是否到期
        _ = guardSettings.checkPauseExpiry()

        // 1. 注册定位
        authState = await locationManager.requestAuthorization()
        // 2. 启动后台保活
        await BackgroundKeepAlive.shared.start(locationManager: locationManager)
        // 3. 提前连接 WebSocket（即使还没配对也连，位置才能流出去；后端会忽略 partner 推送）
        if let http = realtime as? HTTPRealtimeSyncService {
            await http.bootstrapConnect()
        }
        // 4. 订阅定位 → 同步到云（不管 mode 是什么都要订阅，因为 mode=off 时会 stop，事件不会来）
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
                Log.info("AppSession", "📍 上传位置: \(point.lat), \(point.lon) (mode=\(event.mode.rawValue), hp=\(Int(point.horizontalAccuracy))m)")
            }
        }
        // 5. 按用户选的档位启动定位
        applyGuardMode()
        // 6. 订阅 partner 位置流（把对方位置更新到 store）
        startObservingPartnerLocation()
        // 7. HTTP 兜底轮询：WebSocket 断了也能拉
        startPartnerHttpPolling()
        // 8. 暂停到期检查（每分钟跑一次）
        startPauseCheckLoop()
        isReady = true
    }

    /// 根据 guardSettings 把 LocationManager 切到对应档位。
    func applyGuardMode() {
        let profile = locationProfile(for: guardSettings.mode)
        if guardSettings.isPaused || guardSettings.mode == .off {
            Task { await locationManager.pause() }
            Log.info("AppSession", "🛑 定位已暂停 (mode=\(guardSettings.mode.rawValue), isPaused=\(guardSettings.isPaused))")
        } else {
            Task { await locationManager.switchProfile(to: profile) }
            Log.info("AppSession", "▶️ 定位已启动 (profile=\(profile.rawValue))")
        }
    }

    private func locationProfile(for mode: GuardMode) -> LocationManager.GuardProfile {
        switch mode {
        case .off:       return .off
        case .standard:  return .standard
        case .realtime:  return .realtime
        }
    }

    /// 用户从设置页切换档位 / 暂停 / 恢复时调用。
    func handleGuardChange() {
        Log.info("AppSession", "守护设置变更: mode=\(guardSettings.mode.rawValue), isPaused=\(guardSettings.isPaused)")
        applyGuardMode()
    }

    private func startPauseCheckLoop() {
        pauseCheckTask?.cancel()
        pauseCheckTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)  // 60s
                let expired = await MainActor.run { self.guardSettings.checkPauseExpiry() }
                if expired {
                    Log.info("AppSession", "暂停到期，自动恢复共享")
                    await MainActor.run { self.applyGuardMode() }
                }
            }
        }
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

    /// HTTP 轮询兜底：前台每 15s 拉一次对方位置（WebSocket 断了也能拿到）。
    /// 关键场景：App 从后台切回前台、WebSocket 重连中、首次启动对方还没上报。
    private func startPartnerHttpPolling() {
        partnerHttpPollTask?.cancel()
        partnerHttpPollTask = Task { [weak self] in
            guard let self = self else { return }
            // 启动先等 2s 让 pairing 先稳定（避免循环依赖）
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            while !Task.isCancelled {
                await self.pollPartnerLocationOnce()
                try? await Task.sleep(nanoseconds: 15_000_000_000)  // 15s
            }
        }
        Log.info("AppSession", "partner HTTP 轮询启动 (15s/次)")
    }

    @MainActor
    private func pollPartnerLocationOnce() async {
        guard let store = self.relationshipStore.relationship,
              let http = self.realtime as? HTTPRealtimeSyncService else {
            // 还没配对，不拉
            return
        }
        // 拿对方的 userId
        let partnerId: String
        if store.userA == self.currentUser.id {
            partnerId = store.userB
        } else if store.userB == self.currentUser.id {
            partnerId = store.userA
        } else {
            // pending 关系 / 异常
            return
        }
        guard !partnerId.isEmpty else { return }

        // HTTP 拉（service 内部会更新缓存 + 推给订阅者，触发 store.refreshPartnerLocation）
        do {
            _ = try await http.fetchPartnerLocation(userId: partnerId)
        } catch {
            Log.warn("AppSession", "HTTP 拉取对方位置失败: \(error)")
        }
    }

    func handleEnterForeground() {
        Task { await locationManager.handleAppForeground() }
        // 切回前台立即拉一次对方位置（不等 15s 轮询）
        Task { await pollPartnerLocationOnce() }
        // 确保轮询在跑
        if partnerHttpPollTask == nil || partnerHttpPollTask?.isCancelled == true {
            startPartnerHttpPolling()
        }
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

        Log.info("DevMock", "✅ mock 伴侣 + 位置已注入,直接进主页调试")
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
            // MARK: - 守护模式
            Section {
                ForEach(GuardMode.allCases) { mode in
                    Button {
                        guardSettings.mode = mode
                        session.handleGuardChange()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.icon)
                                .font(.title2)
                                .foregroundStyle(mode.accentColor)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if guardSettings.mode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(mode.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("守护模式")
            } footer: {
                Text("默认「标准守护」是保守档：后台静止时 5 分钟心跳一次。开启「实时守护」会增加约 15% 的电量消耗。")
            }

            // MARK: - 一键暂停
            if !guardSettings.isPaused && guardSettings.mode != .off {
                Section {
                    Button(role: .destructive) {
                        guardSettings.pauseForOneHour()
                        session.handleGuardChange()
                    } label: {
                        Label("暂停共享 1 小时", systemImage: "pause.circle")
                    }
                    Button(role: .destructive) {
                        guardSettings.pauseUntilMorning()
                        session.handleGuardChange()
                    } label: {
                        Label("暂停到明早 8 点", systemImage: "moon.stars")
                    }
                } header: {
                    Text("暂停共享")
                } footer: {
                    Text("暂停期间你看不到 TA，TA 也看不到你。后台定位会停止，电量恢复正常。")
                }
            } else if let until = guardSettings.pausedUntil {
                Section {
                    HStack {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                        Text("已暂停到 \(formatted(until))")
                        Spacer()
                    }
                    Button("立即恢复") {
                        guardSettings.resume()
                        session.handleGuardChange()
                    }
                } header: {
                    Text("暂停中")
                }
            }

            // MARK: - 权限
            Section("权限") {
                Text("定位权限: \(authLabel)")
                Button("请求 Always 权限") {
                    Task { _ = await session.locationManager.requestAuthorization() }
                }
            }

            // MARK: - 关系
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

            // MARK: - 调试
            Section("调试") {
                LabeledContent("userId") {
                    Text(session.currentUser.id)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("后端") {
                    Text(BackendConfig.baseURL.absoluteString)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("当前 profile") {
                    Text(currentProfileLabel)
                        .font(.caption.monospaced())
                }
            }
        }
        .navigationTitle("设置")
    }

    private var guardSettings: GuardSettings { session.guardSettings }

    private var authLabel: String {
        switch session.authState {
        case .notDetermined: return "未决定"
        case .denied: return "已拒绝"
        case .restricted: return "受限"
        case .whenInUse: return "使用期间"
        case .always: return "始终"
        }
    }

    private var currentProfileLabel: String {
        if guardSettings.isPaused { return "已暂停" }
        if guardSettings.mode == .off { return "off" }
        if guardSettings.mode == .standard { return "standard" }
        return "realtime"
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}
