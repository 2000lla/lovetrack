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
    private var lastReportedLocation: CLLocation?
    private var lastReportedAt: Date?
    private let throttleInterval: TimeInterval = 5  // 同一坐标 5s 内不重复上送

    public static let shared = LocationManager()

    public init() {
        let m = CLLocationManager()
        self.cl = m
        self.delegate = LocationDelegate()
        self.cl.delegate = delegate
        self.cl.pausesLocationUpdatesAutomatically = true
        self.cl.showsBackgroundLocationIndicator = true
        self.cl.activityType = .otherNavigation
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

    /// 启动定位（自动选 mode）。
    public func start() throws {
        let auth = currentAuthState()
        guard auth == .whenInUse || auth == .always else {
            throw LocationError.permissionDenied
        }
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationError.serviceDisabled
        }
        sessionId = UUID().uuidString

        // 简化：默认前台高精度。CoreLocation 自身会根据授权类型适配后台
        // 不在 actor 内部调 MainActor.assumeIsolated（Swift 6 严格并发下会 crash）
        // V0.2 再做精确的前台/后台判定
        if auth == .always {
            applyMode(.background)
        } else {
            applyMode(.foreground)
        }
    }

    public func stop() {
        cl.stopUpdatingLocation()
        cl.stopMonitoringSignificantLocationChanges()
        mode = .off
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
            // 节流
            if let last = lastReportedLocation,
               let lastAt = lastReportedAt,
               loc.distance(from: last) < 10,
               Date().timeIntervalSince(lastAt) < throttleInterval {
                continue
            }
            lastReportedLocation = loc
            lastReportedAt = Date()

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
        switch newMode {
        case .off:
            cl.stopUpdatingLocation()
            cl.stopMonitoringSignificantLocationChanges()
        case .foreground:
            cl.stopMonitoringSignificantLocationChanges()
            cl.desiredAccuracy = kCLLocationAccuracyBest
            cl.distanceFilter = 5
            cl.allowsBackgroundLocationUpdates = false
            cl.startUpdatingLocation()
        case .background:
            cl.desiredAccuracy = kCLLocationAccuracyHundredMeters
            cl.distanceFilter = 50
            cl.allowsBackgroundLocationUpdates = true
            cl.startUpdatingLocation()
        case .significantChange:
            cl.stopUpdatingLocation()
            cl.allowsBackgroundLocationUpdates = true
            cl.startMonitoringSignificantLocationChanges()
        }
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
