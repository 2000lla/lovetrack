# LoveTrack iOS Architecture（v0.1 — MVP）

> 对标「爱合」的情侣位置守护 App。MVP 范围：**实时定位 + 轨迹回放**。
> 砍掉：纪念日 / 睡眠监测 / 心情贴纸等所有非定位功能。

---

## 1. 模块图（Layered MVVM + Actor）

```
┌──────────────────────────────────────────────────────────────────────┐
│                              App 入口层                                │
│  LoveTrackApp.swift  ──  ScenePhase / BG Task / Push handler          │
└──────────────┬───────────────────────────────────────────────────────┘
               │ @main / Scene
               ▼
┌──────────────────────────────────────────────────────────────────────┐
│                            UI Layer (SwiftUI)                         │
│  ┌────────────────────┐  ┌────────────────────┐  ┌────────────────┐   │
│  │ RealtimeMapView    │  │ TrackPlaybackView  │  │ PairingView    │   │
│  │ (高德 SwiftUI)     │  │ (时间轴 + 地图)    │  │ (扫码配对)     │   │
│  └─────────┬──────────┘  └─────────┬──────────┘  └───────┬────────┘   │
│            │ @StateObject / .task                      │            │
└────────────┼──────────────────────────────────────────┼─────────────┘
             │                                          │
             ▼                                          ▼
┌──────────────────────────────────────────────────────────────────────┐
│                         ViewModel Layer (Combine)                     │
│  ┌─────────────────────────┐    ┌──────────────────────────────┐      │
│  │ RealtimeLocationVM      │    │ TrackPlaybackVM              │      │
│  │ @Published 位置 / 距离  │    │ @Published 轨迹点 / 播放头   │      │
│  └─────────────┬───────────┘    └────────────┬─────────────────┘      │
│                │ @MainActor                   │                       │
└────────────────┼──────────────────────────────┼───────────────────────┘
                 │                              │
                 ▼                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     Service Layer (业务编排)                          │
│  ┌────────────────────────┐  ┌──────────────────────────┐             │
│  │ LocationService        │  │ RelationshipService      │             │
│  │ (前台 / 后台策略路由)  │  │ (配对 / 解除 / 拉取对方) │             │
│  └────────────┬───────────┘  └────────────┬─────────────┘             │
│               │                           │                           │
│               │ delegates                 │ subscribe                 │
│               ▼                           ▼                           │
│  ┌────────────────────────┐  ┌──────────────────────────┐             │
│  │ LocationManager  actor │  │ RealtimeSyncService      │             │
│  │ (CoreLocation 封装)    │  │ (Firebase RTDB 抽象)     │             │
│  └────────────┬───────────┘  └────────────┬─────────────┘             │
│               │ CLLocationManager         │ WebSocket / FDB          │
│               ▼                           ▼                           │
│        CoreLocation Framework      Firebase iOS SDK                   │
└──────────────────────────────────────────────────────────────────────┘
               │                           │
               ▼                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                       Infrastructure / Platform                       │
│  CoreLocation · 高德地图 SDK · Firebase RTDB · URLSession · Keychain  │
└──────────────────────────────────────────────────────────────────────┘
```

**层级职责：**
- **UI Layer**：只负责渲染和用户输入，不持有业务逻辑。所有副作用走 `task { await vm.xxx() }`。
- **ViewModel Layer**：`@MainActor` 隔离，发布 `@Published` 状态；纯 Swift 值，不直接 import `CoreLocation` / `Firebase`。
- **Service Layer**：跨 ViewModel 共享的业务规则（节流、配对校验、电量感知）。允许是 `actor`。
- **Manager Layer**：与系统 SDK 直接对话的薄壳。`actor` + `AsyncStream` 输出事件，绝不在主线程持有 `CLLocationManager`。
- **基础设施**：第三方 SDK、Keychain、APNs。

---

## 2. 数据模型

```swift
// Models/User.swift
/// 单个用户（包含"我"和"伴侣"两端都用此结构）。
public struct User: Codable, Identifiable, Equatable, Sendable {
    public let id: String              // Firebase UID
    public var displayName: String
    public var avatarURL: URL?
    public var deviceModel: String     // 上报用于显示
    public var createdAt: Date
    public var updatedAt: Date
}

// Models/Relationship.swift
/// 情侣/亲密关系绑定关系。
public struct Relationship: Codable, Identifiable, Equatable, Sendable {
    public let id: String              // 关系 ID
    public var userA: String           // User.id
    public var userB: String           // User.id
    public var status: Status          // pending / active / dissolved
    public var pairedAt: Date
    public var dissolvedAt: Date?

    public enum Status: String, Codable, Sendable { case pending, active, dissolved }
}

// Models/LocationPoint.swift
/// 单个定位点（实时 + 轨迹共用）。
public struct LocationPoint: Codable, Equatable, Sendable, Hashable {
    public let userId: String
    public let lat: Double             // WGS-84（CoreLocation 原生）
    public let lon: Double
    public let altitude: Double?       // 海拔（可空，多数场景 GPS 无 altitude）
    public let horizontalAccuracy: Double
    public let verticalAccuracy: Double?
    public let speed: Double?          // m/s
    public let course: Double?         // 方向 0-360
    public let timestamp: Date         // 设备采集时间
    public let receivedAt: Date        // 服务端落库时间
    public let battery: BatteryInfo?   // 上报时的电量/状态
    public let source: Source          // gps / wifi / cell / significant
    public let sessionId: String       // 用于分段轨迹
}

public struct BatteryInfo: Codable, Equatable, Sendable {
    public let level: Double           // 0.0 ~ 1.0
    public let isCharging: Bool
    public let isLowPower: Bool        // iOS 低电量模式
}

public enum Source: String, Codable, Sendable {
    case gps, wifi, cell, significantChange
}

// Models/TrackSegment.swift
/// 一段连续轨迹（一次"出门 - 回家"或一天）。
public struct TrackSegment: Codable, Identifiable, Equatable, Sendable {
    public let id: String              // UUID
    public let userId: String
    public let startedAt: Date
    public let endedAt: Date
    public var points: [LocationPoint] // 按时间升序
    public var summary: Summary

    public struct Summary: Codable, Equatable, Sendable {
        public let distanceMeters: Double
        public let topSpeed: Double
        public let avgSpeed: Double
        public let polylineEncoded: String  // Google polyline 算法，压缩存储
    }
}
```

**实体关系（ASCII ER）：**

```
User (1) ─────< (N) LocationPoint
  │                      │
  │                      │ N
  │                      ▼
  └── (1,1) Relationship (userA, userB)        TrackSegment (1) ──< (N) LocationPoint
                  (1,1)    (1,1)                       │
                    │       │                          │ N
                    ▼       ▼                          ▼
                  UserA   UserB                   LocationPoint
```

---

## 3. 关键决策与理由

### 3.1 为什么 SwiftUI（不用 UIKit）

| 维度 | SwiftUI | UIKit | 决定 |
|------|---------|-------|------|
| 学习曲线 | 状态驱动，声明式 | 命令式 + lifecycle | **SwiftUI** |
| 实时数据绑定 | `@Published` + `$vm.foo` 一行 | 手动 KVO/Notification | **SwiftUI** |
| 后台 / 系统扩展 | 受限 | 几乎无限制 | 持平（都要 bridge 到 CoreLocation） |
| iOS 16+ 覆盖率 | ≥ 92%（国内 iPhone 6s 之后均可） | 100% | 风险可接受 |
| 团队效率 | 1 屏 ≈ 50 行 | 1 屏 ≈ 200 行 | **SwiftUI** |

> 唯一例外：`CLLocationManager` 仍需在 SwiftUI 中用 `UIViewControllerRepresentable` 或直接由 `actor` 持有（我们选后者，避免 UIKit 污染）。高德地图 SDK 已有 SwiftUI 包装（`AMapView` SwiftUI extension），无需 UIKit bridge。

### 3.2 为什么 Firebase（不自建后端）

1. **WebSocket 免维护** — Realtime Database 自带，断线重连 / 顺序保证 / 离线缓存都内置。
2. **Auth / 推送** — 一套 SDK 解决配对码生成和"对方上线"通知。
3. **Cloud Functions** — 1 周内可上线"超 24h 无定位"告警。
4. **国内访问** — 这是风险点（见 `risk.md` 第 3 条），MVP 阶段在 iOS 端走 `https://` 通用 443，多数情况可用。

### 3.3 为什么 Actor（不是 singleton + lock）

`CLLocationManager` 必须在固定线程的 run loop 上 `delegate` 回调。用 `actor` 隔离后：

- `CLLocationManager` 仅在 actor 内部持有，外部无法直接访问。
- 业务调用走 `await locManager.start()`，编译器保证线程安全。
- 通过 `AsyncStream<CLLocation>` 对外广播，ViewModel 用 `for await loc in stream { }` 消费。

### 3.4 为什么高德 + CoreLocation 双栈

- CoreLocation 是定位数据源（标准 API、合规可控）。
- 高德只负责**地图渲染 + 坐标系转换**（GCJ-02 ↔ WGS-84）。
- 这样**定位逻辑**与**地图 UI** 解耦，未来可换 MapKit / Google Maps 不影响业务。

---

## 4. CoreLocation 后台保活策略（核心）

### 4.1 三层架构

```
┌───────────────────────────────────────────────────────────────────┐
│  Layer 1: Foreground (Active Session)                             │
│  ─────────────────────────────────                                  │
│  desiredAccuracy: kCLLocationAccuracyBest                         │
│  distanceFilter: 5m                                                 │
│  pausesLocationUpdatesAutomatically = false                        │
│  activityType: .otherNavigation (恋爱关系 → 步行/出行混合)         │
│  触发条件: app.active == true                                       │
└───────────────────────────────────────────────────────────────────┘
                              ▼ app 退到后台
┌───────────────────────────────────────────────────────────────────┐
│  Layer 2: Background (Continuous)                                  │
│  ─────────────────────────────────                                  │
│  allowsBackgroundLocationUpdates = true   ★ 必须打 ★              │
│  desiredAccuracy: kCLLocationAccuracyHundredMeters (省电)         │
│  distanceFilter: 50m                                                │
│  pausesLocationUpdatesAutomatically = true   ← 关键: 让系统帮我们   │
│                                                 降级而不是 kill    │
│  showsBackgroundLocationIndicator = true  (顶部蓝条/蓝点)         │
│  触发条件: Authorization == .authorizedAlways + bg mode 已配置    │
└───────────────────────────────────────────────────────────────────┘
                              ▼ 系统判定长时间静止 / 触发 Pause
┌───────────────────────────────────────────────────────────────────┐
│  Layer 3: Significant-Change Service (兜底唤醒)                    │
│  ─────────────────────────────────                                  │
│  startMonitoringSignificantLocationChanges()                       │
│  用途: iOS 在几乎所有情况下都会保留这个 service (Apple 文档明确)  │
│  行为: 基站 / 可见 Wi-Fi 切换时唤醒 app,触发 didFinishLaunching  │
│  唤醒后: 检测"我是否仍在配对中" → 是则立刻重启 Layer 2              │
│  ★ 这是"被系统 kill 后恢复"的核心机制 ★                            │
└───────────────────────────────────────────────────────────────────┘
```

### 4.2 `allowsBackgroundLocationUpdates` 的正确用法

**何时开：**
```swift
// 必须 .authorizedAlways 才能设为 true，否则系统忽略
if authorization == .authorizedAlways {
    manager.allowsBackgroundLocationUpdates = true
    manager.showsBackgroundLocationIndicator = true
}
```

**何时关：**
- 用户在 App 内手动**关闭**定位权限
- 关系 `status == .dissolved`
- 进入「省电模式」白名单（用户主动勾选"省电时停报"）

**坑：**
- 即便 Info.plist 加了 `UIBackgroundModes: location`，**Always 权限被拒** 仍不会上报。
- 用户在系统设置里把 App 设成「仅使用一次」时，Pauses 后**不会**自动恢复 — 必须在前台请求升级权限。

### 4.3 静止判定与节流（节流后端流量 + 省电）

```swift
// 简化的"是否在移动"判断（用于切档 + 节流上报）
let isMoving = location.speed > 0.5  // > 0.5 m/s ≈ 1.8 km/h 步行起步
if isMoving {
    // → 切回 Layer 1 精度
} else {
    // → 切到 Layer 2 + 节流: 5 分钟内同样位置不重复上送
}
```

### 4.4 被系统 kill 后的恢复策略

iOS 在以下场景可能 kill App：
1. 用户从 App Switcher 上滑
2. 内存压力
3. 长时间后台 + 无 Significant-Change 唤醒

**我们的恢复链路：**

```
系统 kill App
    ↓
系统仍保留: Significant-Change Service（不依赖 App 进程）
    ↓
基站 / Wi-Fi 切换触发 (几百米 ~ 几公里)
    ↓
系统自动启动 App → didFinishLaunchingWithOptions
    ↓
LoveTrackApp.swift 检查:
  ├─ 关系 status == .active ? 继续
  ├─ 定位权限 == .authorizedAlways ? 继续
  └─ 启动 Significant-Change → 收到首个 callback → 切回 Layer 2 连续定位
    ↓
后台 AsyncTask 上送"我醒过来了"事件 + 当前坐标
```

**工程实现要点：**
- `Info.plist` 必须有 `UIBackgroundModes: location` + `fetch` + `processing`（冗余提高保活）
- `BGTaskScheduler` 注册一个 `com.lovetrack.refresh` task 兜底（iOS 给约 30s 后台时间刷一次）
- **不要**尝试 `Audio` / `VoIP` 后台保活（审核 100% 拒绝，详见 5.2）

### 4.5 关键代码骨架（见 `LoveTrack/Location/LocationManager.swift`）

```swift
public actor LocationManager {
    private let cl: CLLocationManager
    private var continuations: [UUID: AsyncStream<CLLocation>.Continuation] = [:]

    public func observe() -> AsyncStream<CLLocation> {
        AsyncStream { cont in
            let id = UUID()
            continuations[id] = cont
            cont.onTermination = { [weak self] _ in
                Task { await self?.remove(id) }
            }
        }
    }
    // ... 见代码
}
```

---

## 5. App Store 审核合规

### 5.1 Info.plist 文案（iOS 16+ 三件套）

> 完整文案见 `LoveTrack/Info.plist`。下面是**逐字段**的撰写理由，审核员看到任一字段都会挑战。

#### `NSLocationWhenInUseUsageDescription`
> **"我们需要在 App 打开时获取你的位置，用于显示你与伴侣的实时距离。位置数据仅在 App 运行时使用，不会用于广告。"**
- 必须说明**具体用途**（"显示距离"），不能写"改善体验"这类模糊话术。
- 强调"App 运行时使用"对应 WhenInUse 权限范围。

#### `NSLocationAlwaysAndWhenInUseUsageDescription`
> **"开启'始终'权限后，即便 App 在后台或锁屏，我们也能持续为你和伴侣更新位置，守护彼此安全。我们采用 Apple 推荐的 CoreLocation 后台服务模式，仅在位置发生显著变化时上报，不会持续高频采集。"**
- 必须解释**为什么 Always** 而不是 WhenInUse。
- 明确"何时不上报"（"显著变化时"）以安抚用户对耗电的担忧。

#### `NSLocationAlwaysUsageDescription`（iOS 10 兼容保留）
> **"保留此字段以兼容 iOS 10 设备。"**
- 实际上 iOS 16+ 不再单独请求，但 Apple 仍要求三件套齐全。

### 5.2 审核员可能 challenge 与答复

| # | 审核员 challenge | 我们答复 |
|---|------------------|----------|
| 1 | "你的 App 在前台关闭后仍在使用位置，是否必要？" | 是的。情侣双方需要对方在锁屏 / 后台时也能看到当前位置。我们已配置 `showsBackgroundLocationIndicator = true` 让用户随时知道 App 在使用位置。 |
| 2 | "为什么不用 Push 通知代替常驻定位？" | Push 通知只能触发"提示"，不能持续获取**对方**的位置；我们既要获取**自己**也要获取**对方**的位置数据，故必须常驻定位。 |
| 3 | "后台定位耗电严重，你们如何优化？" | 1) `pausesLocationUpdatesAutomatically = true` 让系统在用户静止时自动暂停；2) `distanceFilter: 50m` 避免无效上报；3) 后台时切到 `kCLLocationAccuracyHundredMeters` 省电；4) 我们已在 Privacy 页列出"耗电估算"和"省电模式开关"。 |
| 4 | "是否声明了 `UIBackgroundModes: location`？" | 是的，且仅声明 `location` + `fetch` + `processing` 三个 background mode，未使用 VoIP / Audio 等被 Apple 严格限制的方式。 |
| 5 | "伴侣未同意也持续上报，涉嫌隐私违规？" | 配对流程需双方**扫码确认**；解除关系时**立即停止上报**并从服务端删除全部轨迹（90 天保留期可由用户申请提前删除）。我们在 App 内提供"一键导出 + 一键删除"功能。 |
| 6 | "App 内是否提供关闭'始终'的入口？" | 是的。设置 → 隐私 → 定位服务 → 一键降级到 WhenInUse，并提示用户降级后伴侣将看不到你的实时位置。 |

### 5.3 提交审核前自检清单

- [x] `NSLocationWhenInUseUsageDescription` 有具体用途
- [x] `NSLocationAlwaysAndWhenInUseUsageDescription` 解释为何 Always
- [x] `NSLocationAlwaysUsageDescription` 保留字段
- [x] `UIBackgroundModes` 只声明必要项（location / fetch / processing）
- [x] App 内有"降级到 WhenInUse"入口
- [x] 隐私政策 URL 在 App Store Connect 已填
- [x] 审核备注（App Review Notes）写明："本 App 后台定位为产品核心功能，已配置合理节流策略，用户可在 App 内随时降级权限"

---

## 6. 错误处理与降级

| 错误 | 表现 | 降级 |
|------|------|------|
| `kCLErrorDenied` | 定位权限被拒 | 引导到系统设置；伴侣看到"对方未开启定位" |
| `kCLErrorLocationUnknown` | 30s 内无定位 | 继续等待；超 60s 切到 Significant-Change |
| Firebase 离线 | 网络抖动 | RTDB 内置 1MB 离线缓存；联网后增量同步 |
| Firebase 被墙 | 国内网络 | 见 risk.md 第 3 条，建议在 Cloud Functions 侧加腾讯云 / 阿里云镜像 |

---

## 7. 测试策略（MVP 阶段）

- **单元测试**：`LocationManager` 的节流逻辑 / 坐标系转换 / 距离计算
- **集成测试**：`RealtimeSyncService` 接到 mock Firebase 后的双向同步
- **UI 测试**：配对流程 / 定位开关切换 / 轨迹拖动
- **手动测试**：飞行模式 → Wi-Fi → 4G 切换下的恢复链路

---

## 8. 版本演进路线（v0.1 → v1.0）

| 版本 | 范围 | 关键依赖 |
|------|------|----------|
| v0.1 (MVP) | 实时定位 + 轨迹回放 | CoreLocation + 高德 + Firebase RTDB |
| v0.2 | 地理围栏 + 到达/离开通知 | CLCircularRegion + APNs |
| v0.3 | 低功耗模式 + 桌面小组件 | WidgetKit + App Groups |
| v1.0 | 完整关系网（家人 / 朋友） | 自建后端 + 用户关系图 |
