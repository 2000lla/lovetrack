import Foundation
import BackgroundTasks
import UIKit
import os.log

/// 后台保活策略。
///
/// 包含三件事：
/// 1. 注册 BGTask（iOS 给 ~30s 后台时间刷一次位置 / 上送）
/// 2. 监听 App lifecycle（前台 / 后台切换时切档）
/// 3. 处理 cold launch（系统 kill 后被 Significant-Change 唤醒）
public actor BackgroundKeepAlive {
    public static let shared = BackgroundKeepAlive()

    private let log = Logger(subsystem: "com.lovetrack.app", category: "BackgroundKeepAlive")
    private var lifecycleTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?
    private weak var locationManager: LocationManager?
    private var isRegistered = false

    /// 必须从 AppDelegate / App init 阶段同步调用（BGTaskScheduler.register 必须在 launch 完成前）。
    public nonisolated static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.lovetrack.app.refresh",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task {
                await BackgroundKeepAlive.shared.handleAppRefresh(task: refreshTask)
            }
        }
    }

    /// 启动保活（在 app 已获得 Always 权限后调用）。
    public func start(locationManager: LocationManager) async {
        self.locationManager = locationManager
        guard !isRegistered else { return }
        isRegistered = true

        // 1. 监听 lifecycle
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in
            await self?.observeAppLifecycle()
        }

        // 2. 监听定位事件
        locationTask?.cancel()
        locationTask = Task { [weak self] in
            guard let self = self else { return }
            let stream = await locationManager.events()
            for await event in stream {
                await self.handleLocationEvent(event)
            }
        }

        // 3. 调度下一次 BGTask
        scheduleNextAppRefresh()

        log.info("BackgroundKeepAlive started")
    }

    public func stop() {
        lifecycleTask?.cancel()
        locationTask?.cancel()
        lifecycleTask = nil
        locationTask = nil
        isRegistered = false
    }

    // MARK: - Private

    private func observeAppLifecycle() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification) {
                    await self?.handleEnterBackground()
                }
            }
            group.addTask { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: UIApplication.willEnterForegroundNotification) {
                    await self?.handleEnterForeground()
                }
            }
        }
    }

    private func handleEnterBackground() {
        log.info("App entered background")
        Task { [weak self] in
            guard let self = self else { return }
            let lm = await self.locationManager
            guard let lm = lm else { return }
            await lm.handleAppBackground()
            await self.scheduleNextAppRefresh()
        }
    }

    private func handleEnterForeground() {
        log.info("App will enter foreground")
        Task { [weak self] in
            guard let self = self else { return }
            let lm = await self.locationManager
            guard let lm = lm else { return }
            await lm.handleAppForeground()
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) async {
        log.info("BGAppRefreshTask fired")
        // 1. 调度下一次（无论本次成功失败都要调度）
        scheduleNextAppRefresh()

        // 2. 给系统 25s 时间做一次"轻量唤醒后上报"
        task.expirationHandler = {
            // 在 setTaskCompleted 前由系统处理
        }

        // 3. 触发一次位置更新（即便应用在后台也能拿到新的 location）
        if let lm = locationManager {
            try? await lm.start()
        }

        // 4. 等几秒让 location callback 触发
        try? await Task.sleep(nanoseconds: 5_000_000_000)

        task.setTaskCompleted(success: true)
    }

    private func handleLocationEvent(_ event: LocationManager.CLLocationEvent) async {
        // 节流后上送到 RealtimeSyncService
        // （具体实现见 RealtimeSyncService.uploadPoint(_:)）
        // 这里仅记录日志占位
        log.debug("Location event: mode=\(event.mode.rawValue) accuracy=\(event.location.horizontalAccuracy)")
    }

    private func scheduleNextAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.lovetrack.app.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)  // 至少 15 min 后
        do {
            try BGTaskScheduler.shared.submit(request)
            log.info("Scheduled next BGAppRefresh")
        } catch {
            log.error("Failed to schedule BGAppRefresh: \(error.localizedDescription, privacy: .public)")
        }
    }
}
