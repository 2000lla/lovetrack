import Foundation
import CoreLocation
import UIKit

/// 核心定位管理器（actor 隔离）。
///
/// 设计要点：
/// - `CLLocationManager` 必须在有 run loop 的线程上持有（系统要求）。
///   用 `actor` 隔离后，外部只能通过 `await` 访问。
/// - 通过 `AsyncStream<CLLocationEvent>` 对外广播，避免回调地狱。
/// - 自动适配前台 / 后台 / Significant-Change 三层策略（见 `BackgroundKeepAlive`）。
public actor LocationManager {
    public enum AuthState: Sendable, Equatable {
        case notDetermined
        case denied
        case restricted
        case whenInUse
        case always
    }

    public enum TrackingMode: String, Sendable, Equatable {
        case off
        case foreground        // 高精度
        case background        // 中精度
        case significantChange // 兜底
    }

    /// 三档守护模式对应的定位策略。
    /// 与 GuardMode 一一映射，但放在 LocationManager 里以便测试时单独使用。
    public enum GuardProfile: String, Sendable, Equatable {
        case off       // 完全停采
        case standard  // 保守档：静止 5 min 心跳 / 移动 15-30 s
        case realtime  // 高频档：静止 1 min 心跳 / 移动 3-10 s

        public var foregroundAccuracy: CLLocationAccuracy {
            switch self {
            case .off:       return kCLLocationAccuracyThreeKilometers
            case .standard: return kCLLocationAccuracyHundredMeters
            case .realtime: return kCLLocationAccuracyBestForNavigation
            }
        }

        public var backgroundAccuracy: CLLocationAccuracy {
            switch self {
            case .off:       return kCLLocationAccuracyThreeKilometers
            case .standard: return kCLLocationAccuracyHundredMeters
            case .realtime: return kCLLocationAccuracyNearestTenMeters
            }
        }

        /// 距离过滤（米）
        public var distanceFilter: CLLocationDistance {
            switch self {
            case .off:       return kCLDistanceFilterNone
            case .standard:  return 50
            case .realtime:  return kCLDistanceFilterNone
            }
        }

        /// 静止心跳间隔（秒）—— 即使坐标不变也强制刷新一次
        public var heartbeatInterval: TimeInterval {
            switch self {
            case .off:       return .infinity
            case .standard:  return 300   // 5 min
            case .realtime:  return 60    // 1 min
            }
        }

        /// 移动时最大上报间隔（秒）—— 即使没到 distanceFilter 也强制刷一次
        public var maxMovingReportInterval: TimeInterval {
            switch self {
            case .off:       return .infinity
            case .standard:  return 30
            case .realtime:  return 10
            }
        }

        public var allowsBackgroundUpdates: Bool {
            self != .off
        }

        public var pausesLocationUpdatesAutomatically: Bool {
            // realtime 需要关掉（不然静止时系统会停采），standard 让系统自己判断
            self == .realtime ? false : true
        }
    }

    public struct CLLocationEvent: Sendable, Equatable {
        public let location: CLLocation
        public let mode: TrackingMode
        public let battery: BatteryInfo
        public let sessionId: String

        public init(location: CLLocation, mode: TrackingMode, battery: BatteryInfo, sessionId: String) {
            self.location = location
            self.mode = mode
            self.battery = battery
            self.sessionId = sessionId
        }
    }

    public enum LocationError: Error, Sendable {
        case permissionDenied
        case serviceDisabled
        case unknown
    }

    // MARK: - State

    nonisolated let cl: CLLocationManager
    nonisolated let delegate: LocationDelegate
    private var continuations: [UUID: AsyncStream<CLLocationEvent>.Continuation] = [:]
    private var authContinuations: [UUID: AsyncStream<AuthState>.Continuation] = [:]
    private var sessionId: String = UUID().uuidString
    private var mode: TrackingMode = .off
    private var profile: GuardProfile = .standard
    private var lastReportedLocation: CLLocation?
    private var lastReportedAt: Date?
    private var lastMovementAt: Date?
    private let throttleInterval: TimeInterval = 2  // 同一坐标 2s 内不重复上送
    private var heartbeatTask: Task<Void, Never>?

    public static let shared = LocationManager()

    public init() {
        let m = CLLocationManager()
        self.cl = m
        self.delegate = LocationDelegate()
        self.cl.delegate = delegate
        self.cl.showsBackgroundLocationIndicator = true
        self.cl.activityType = .otherNavigation
        // pausesLocationUpdatesAutomatically 由 profile 动态控制
        self.cl.pausesLocationUpdatesAutomatically = true  // standard 模式默认值
        self.delegate.owner = self
    }

    // MARK: - Public API

    /// 请求位置权限（先 WhenInUse，再升级 Always）。
    public func requestAuthorization() async -> AuthState {
        var current = currentAuthState()
        if current == .notDetermined {
            cl.requestWhenInUseAuthorization()
            current = await waitForAuthChange()
        }
        if current == .whenInUse {
            // 必须等用户在"升级弹窗"点确认后，状态才会变成 .always
            cl.requestAlwaysAuthorization()
            current = await waitForAuthChange(timeout: 60)
        }
        return current
    }

    public nonisolated func currentAuthState() -> AuthState {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = cl.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorizedWhenInUse: return .whenInUse
        case .authorizedAlways: return .always
        @unknown default: return .notDetermined
        }
    }

    /// 启动定位（按 profile 自动选 mode）。
    public func start() throws {
        try start(profile: profile)
    }

    /// 启动定位并指定守护档位。
    public func start(profile newProfile: GuardProfile) throws {
        let auth = currentAuthState()
        guard auth == .whenInUse || auth == .always else {
            throw LocationError.permissionDenied
        }
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationError.serviceDisabled
        }

        // off 档：完全停采
        if newProfile == .off {
            self.profile = .off
            stop()
            heartbeatTask?.cancel()
            heartbeatTask = nil
            return
        }

        // 必须先停掉旧的，再切换（不然 pause/resume 切换档位不生效）
        cl.stopUpdatingLocation()
        cl.stopMonitoringSignificantLocationChanges()

        self.profile = newProfile
        sessionId = UUID().uuidString
        lastMovementAt = Date()

        if auth == .always {
            applyMode(.background)
        } else {
            applyMode(.foreground)
        }
        startHeartbeatLoop()
    }

    /// 切换守护档位（不重启 App，运行时切换）。
    public func switchProfile(to newProfile: GuardProfile) {
        guard newProfile != self.profile else { return }
        print("[LocationManager] switchProfile: \(self.profile.rawValue) → \(newProfile.rawValue)")
        try? start(profile: newProfile)
    }

    /// 暂停 / 恢复采集（不解绑 WS）。
    public func pause() {
        print("[LocationManager] pause")
        cl.stopUpdatingLocation()
        cl.stopMonitoringSignificantLocationChanges()
        heartbeatTask?.cancel()
        heartbeatTask = nil
        mode = .off
    }

    public func resume() {
        print("[LocationManager] resume")
        try? start()
    }

    public func stop() {
        cl.stopUpdatingLocation()
        cl.stopMonitoringSignificantLocationChanges()
        heartbeatTask?.cancel()
        heartbeatTask = nil
        mode = .off
    }

    // MARK: - Heartbeat

    /// 启动心跳 loop：到点强制 yield 一个 lastLocation（即使坐标没变）。
    /// 让静止场景也能定期上报（standard 5 min / realtime 1 min）。
    private func startHeartbeatLoop() {
        heartbeatTask?.cancel()
        let interval = profile.heartbeatInterval
        guard interval.isFinite, interval > 0 else { return }
        heartbeatTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                await self.fireHeartbeat()
            }
        }
        print("[LocationManager] heartbeat loop started: every \(Int(interval))s (profile=\(profile.rawValue))")
    }

    private func fireHeartbeat() {
        // 没定位过就不发
        guard let last = lastReportedLocation else { return }
        let event = CLLocationEvent(
            location: last,
            mode: mode,
            battery: currentBatteryInfoSync(),
            sessionId: sessionId
        )
        print("[LocationManager] 💓 heartbeat fired (last=\(last.coordinate.latitude), \(last.coordinate.longitude))")
        for cont in continuations.values {
            cont.yield(event)
        }
        lastReportedAt = Date()
    }

    /// 订阅定位事件（多个订阅者允许共存）。
    public func events() -> AsyncStream<CLLocationEvent> {
        AsyncStream { cont in
            let id = UUID()
            self.addContinuation(id: id, cont: cont)
            cont.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id: id) }
            }
        }
    }

    /// 订阅权限变更。
    public func authEvents() -> AsyncStream<AuthState> {
        AsyncStream { cont in
            let id = UUID()
            self.addAuthContinuation(id: id, cont: cont)
            cont.onTermination = { [weak self] _ in
                Task { await self?.removeAuthContinuation(id: id) }
            }
        }
    }

    /// 处理 App 进入前台（供 AppSession 调用）。
    public func handleAppForeground() {
        if mode == .background {
            applyMode(.foreground)
        }
    }

    /// 处理 App 进入后台（供 AppSession 调用）。
    public func handleAppBackground() {
        let auth = currentAuthState()
        if auth == .always, mode != .significantChange {
            applyMode(.background)
        }
    }

    // MARK: - Internal (called by delegate)

    fileprivate func handleLocations(_ locations: [CLLocation]) {
        for loc in locations {
            let now = Date()

            // 节流：同坐标 2s 内不重复
            if let last = lastReportedLocation,
               let lastAt = lastReportedAt,
               loc.distance(from: last) < 5,
               now.timeIntervalSince(lastAt) < throttleInterval {
                continue
            }

            // 移动检测：记录最近一次移动
            let isMoving = lastReportedLocation.map { loc.distance(from: $0) > profile.distanceFilter } ?? false
            if isMoving {
                lastMovementAt = now
            }

            // 强制上报节流：移动模式下，超过 maxMovingReportInterval 必须报一次
            let sinceLastReport = lastReportedAt.map { now.timeIntervalSince($0) } ?? .infinity
            let forceReport = isMoving && sinceLastReport > profile.maxMovingReportInterval

            if !isMoving && !forceReport && lastReportedLocation != nil {
                // 没移动 + 没到强制时间 + 之前报过 → 跳过（心跳由 fireHeartbeat 兜底）
                continue
            }

            lastReportedLocation = loc
            lastReportedAt = now

            let event = CLLocationEvent(
                location: loc,
                mode: mode,
                battery: currentBatteryInfoSync(),
                sessionId: sessionId
            )
            for cont in continuations.values {
                cont.yield(event)
            }
        }
    }

    fileprivate func handleAuthChange(_ status: CLAuthorizationStatus) {
        let state: AuthState
        switch status {
        case .notDetermined: state = .notDetermined
        case .denied: state = .denied
        case .restricted: state = .restricted
        case .authorizedWhenInUse: state = .whenInUse
        case .authorizedAlways: state = .always
        @unknown default: state = .notDetermined
        }
        for cont in authContinuations.values {
            cont.yield(state)
        }
    }

    // MARK: - Private

    private func applyMode(_ newMode: TrackingMode) {
        mode = newMode
        // 关键：先把 allowsBackgroundLocationUpdates 关掉（切 foreground 时），否则会 crash
        // iOS 16+ 会校验：当前不是 background mode 但 allowsBackgroundLocationUpdates=true 就崩
        switch newMode {
        case .off:
            cl.stopUpdatingLocation()
            cl.stopMonitoringSignificantLocationChanges()
            cl.allowsBackgroundLocationUpdates = false

        case .foreground:
            cl.stopMonitoringSignificantLocationChanges()
            cl.allowsBackgroundLocationUpdates = false
            cl.desiredAccuracy = profile.foregroundAccuracy
            cl.distanceFilter = profile.distanceFilter
            cl.pausesLocationUpdatesAutomatically = profile.pausesLocationUpdatesAutomatically
            cl.startUpdatingLocation()

        case .background:
            cl.desiredAccuracy = profile.backgroundAccuracy
            cl.distanceFilter = profile.distanceFilter
            cl.allowsBackgroundLocationUpdates = profile.allowsBackgroundUpdates
            cl.pausesLocationUpdatesAutomatically = profile.pausesLocationUpdatesAutomatically
            cl.startUpdatingLocation()

        case .significantChange:
            cl.stopUpdatingLocation()
            cl.allowsBackgroundLocationUpdates = true
            cl.startMonitoringSignificantLocationChanges()
        }
        print("[LocationManager] applyMode(\(newMode.rawValue)) profile=\(profile.rawValue) accuracy=\(cl.desiredAccuracy) filter=\(cl.distanceFilter)")
    }

    private func waitForAuthChange(timeout: TimeInterval = 30) async -> AuthState {
        await withCheckedContinuation { (cont: CheckedContinuation<AuthState, Never>) in
            let sub = self.authEvents()
            Task { @Sendable in
                var iterator = sub.makeAsyncIterator()
                let start = Date()
                while let state = await iterator.next() {
                    if state != .notDetermined {
                        cont.resume(returning: state)
                        return
                    }
                    if Date().timeIntervalSince(start) > timeout {
                        cont.resume(returning: state)
                        return
                    }
                }
                cont.resume(returning: .notDetermined)
            }
        }
    }

    private func addContinuation(id: UUID, cont: AsyncStream<CLLocationEvent>.Continuation) {
        continuations[id] = cont
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func addAuthContinuation(id: UUID, cont: AsyncStream<AuthState>.Continuation) {
        authContinuations[id] = cont
    }

    private func removeAuthContinuation(id: UUID) {
        authContinuations.removeValue(forKey: id)
    }

    /// 在 actor 内部同步读取电量信息。
    /// 简化版：跳到 MainActor 拿 UIDevice 状态（避免 Swift 6 严格并发 crash）。
    private func currentBatteryInfoSync() -> BatteryInfo {
        // 直接读系统 API —— UIDevice 读电量在 background thread 也安全（Apple 文档）
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = Double(UIDevice.current.batteryLevel)
        let charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        return BatteryInfo(
            level: level >= 0 ? level : 1.0,
            isCharging: charging,
            isLowPower: lowPower
        )
    }
}

/// `CLLocationManagerDelegate` 桥接。
///
/// CLLocationManager 的 delegate 回调在系统指定的串行队列上，
/// 所以这里用 `Task { await owner.handle... }` 投到 actor。
final class LocationDelegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    weak var owner: LocationManager?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let owner = owner else { return }
        Task { await owner.handleLocations(locations) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 错误交给上层：业务侧可订阅 errors 流（MVP 暂不实现）
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let owner = owner else { return }
        let status: CLAuthorizationStatus = manager.authorizationStatus
        Task { await owner.handleAuthChange(status) }
    }
}
