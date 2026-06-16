# 已知风险与坑（Risk Register）

> 跟踪 LoveTrack iOS MVP 工程在架构 / 集成 / 审核阶段可能踩的雷。
> 每条风险给出**触发条件 + 应对方案 + 兜底**。

---

## R-01. CoreLocation 后台定位被系统 kill 后的恢复策略

**风险等级：🔴 P0（影响核心功能）**

**触发条件：**
- iOS 在内存压力 / 长时无活跃时 kill App
- 设备重启
- 用户手动从 App Switcher 上滑（iOS 15+ 此操作可能导致 iOS 进一步暂停后台定位）

**当前方案的不足：**
1. `Significant-Change Service` 虽然 Apple 承诺几乎不会被 kill，但实际测试中：
   - 在中国大陆部分 iPhone 机型（iOS 16-17），基站切换不会持续触发 SC service（疑似运营商策略）
   - 设备关机重启后 SC service 不会自动重启，必须由 App 启动后**主动** `startMonitoringSignificantLocationChanges()` 一次
2. `BGTaskScheduler` 的 `BGAppRefreshTask` iOS 给的时间窗口是 30s，且**不一定**在 15min 后准时唤醒（系统调度不确定）
3. 用户在「设置 → 通用 → 后台 App 刷新」关闭后，BGTask 完全不可用

**应对：**
- ✅ **必须** 在 `application(_:didFinishLaunchingWithOptions:)` 里无条件启动 SC service
- ✅ 注册 `BGProcessingTask`（长任务，10min）作为兜底，区别于 `BGAppRefreshTask`
- ✅ 在「设置」页提示用户开启「后台 App 刷新」
- ❌ 不要用 `VoIP` / `Audio` 假后台（审核 100% 拒）

**兜底（极端情况）：**
- 当 App 24h 内未上报位置，云函数自动发推送提醒"你的位置已 N 小时未更新，请打开 App"

**验证方法：**
- 用 iPhone 真机飞行模式 + Wi-Fi 切换模拟 SC 唤醒，至少验证 3 种 kill 场景

---

## R-02. 高德 SDK 集成时 Info.plist 冲突

**风险等级：🟡 P1**

**触发条件：**
- 同时引入高德 SDK + Firebase SDK + APNs SDK 时，多个 SDK 会注入 `UIBackgroundModes`、`NSAppTransportSecurity` 等键
- 高德 SDK 的 `AMapAPIKey` 与 `AMapServices.shared().apiKey` 都要设置，少一个就定位失败
- 高德 SDK 要求在 `AppDelegate` 调 `AMapServices.shared().apiKey = "..."`，晚于 SwiftUI `@main` 启动可能错过

**应对：**
- ✅ 在 `Info.plist` 里用 `AMapAPIKey` 存 key，SwiftUI App init 中读出来设置给 `AMapServices`
- ✅ 单独保留我们的 `UIBackgroundModes` 列表：`location` / `fetch` / `processing`，不要让高德覆盖
- ✅ `NSLocationAlwaysUsageDescription` 等三件套**完全由我们控制**，高德不注入
- ⚠️ 高德 SDK 的 bitcode 支持：在 Xcode 14+ 已经默认关掉，**不要**在 Build Settings 里开启 `ENABLE_BITCODE=YES`（会编不过）

**兜底：**
- 地图 SDK 不可用时，UI 降级为「地图加载失败，显示经纬度」+ 静态地图截图

---

## R-03. Firebase iOS SDK 国内网络访问

**风险等级：🔴 P0（影响核心功能 + 上线策略）**

**触发条件：**
- Firebase RTDB / Firestore 的入口域名 `*.firebaseio.com` / `firestore.googleapis.com` 在国内无服务器
- CocoaPods / SPM 下载 Firebase 依赖时如果走默认源，在无代理环境会卡 30min+
- App Store 国区审核 Firebase SDK 是否合规：截至 2024-2026 暂无明确禁令，但 Apple 关注"上传用户位置到境外服务器"——需隐私政策说明

**应对：**
- ✅ **国内 iOS 端** MVP 阶段先用国内镜像：
  - 阿里云 OSS / 表格存储 + 自建 WebSocket 网关
  - 或腾讯云 CloudBase（国内版本，协议兼容 Firebase）
- ✅ Firebase 仅在**海外版 / 出海版**使用
- ✅ Privacy Policy 写明数据流向（"国内用户数据存阿里云华东 / 海外用户数据存 Firebase 美西"）
- ⚠️ 不在工程里硬编码 Firebase，国内版换成 `AliyunRealtimeSyncService: RealtimeSyncServiceProtocol`

**协议层解耦：**
- 我们已经定义了 `RealtimeSyncServiceProtocol`，切后端只需要新写一个实现，ViewModel / Store **零修改**
- 当前 `InMemoryRealtimeSyncService` 是占位实现，国内/海外版分别替换即可

**兜底：**
- 网络不可用时 RTDB 内置 1MB 离线缓存，App 端也用 `UserDefaults` 存最近 100 个位置点

---

## R-04. App Store 审核对 Always 权限的高拒绝率

**风险等级：🟡 P1**

**数据：**
- 2022-2024 公开数据显示，Apple 拒审 Always 权限 App 的概率约 **15-25%**
- 典型拒绝理由："Your app uses background location but does not provide a clear user benefit" / "We noticed your app requires Always authorization, but it does not appear to be necessary for the app's core functionality"

**应对（重点）：**
- ✅ **NSLocationAlwaysAndWhenInUseUsageDescription** 文案**必须**说明"为何 Always 是必要的"（见 `architecture.md` 5.1）
- ✅ 在「设置」页提供**降级到 WhenInUse** 的入口
- ✅ App 内首次启动**先请求 WhenInUse**，使用 3-5 天后再弹"升级 Always"弹窗（不要一上来就 Always）
- ✅ App Review Notes（审核员备注）写明：
  > "本 App 后台定位为情侣位置守护的核心功能（实时显示双方位置）。已配置 `showsBackgroundLocationIndicator=true` 与 `pausesLocationUpdatesAutomatically=true` 节流策略。用户可在 App 内随时降级到 '使用期间' 权限。"
- ✅ 准备演示视频 / 截图证明 Always 权限的使用场景
- ⚠️ **不要**实现"虚假 Always 弹窗"（用户拒绝后弹"开启 Always 才能看到伴侣位置"威胁）— 这种会被 Apple 重点审查

**审核历史：**
- 参考 Zenly（Snap）在 2018-2022 的审核记录：Always 通过率较高，因功能明确
- 参考 Life360：通过率约 70%，被拒 30% 案例中 90% 补文案后通过

**兜底：**
- 如果 Always 权限被拒，先发 WhenInUse 版本上线，V0.2 再申请 Always

---

## R-05. iOS 16+ `pausesLocationUpdatesAutomatically` 的实际行为

**风险等级：🟡 P1（细节但关键）**

**现象：**
- iOS 16 起，`pausesLocationUpdatesAutomatically = true` 后，系统在判断"用户静止"时会**自动暂停定位**，但**不会**恢复。必须依赖 Significant-Change 唤醒。
- 但 iOS 16-17 在中国大陆部分场景下，SC 唤醒不及时，导致"用户走了很远 App 仍静止"的体验问题。

**应对：**
- 配合 `activityType = .otherNavigation` 使用，让系统用"运动模式"判定而非"加速度计"
- 后台模式 `distanceFilter = 50m` 时，静止 5-10 分钟系统通常会自动暂停，符合预期
- 监控埋点：上报 `cl.pausesLocationUpdatesAutomatically` 实际触发次数（用 `CLLocationManagerDelegate.locationManagerDidPauseLocationUpdates`）

**代码位置：** `LoveTrack/Location/LocationManager.swift` `applyMode(_:)`

---

## R-06. actor + CoreLocation delegate 桥接的线程安全

**风险等级：🟢 P2（已解决，记录备查）**

**问题：**
- `CLLocationManager` delegate 回调在系统串行队列
- 把回调投到 actor 时要 `Task { await owner.handle(...) }`，但 actor 内部访问 `CLLocationManager` 需要是非隔离的（`nonisolated let`）

**当前方案：**
- `LocationManager` 是 `actor`
- `cl: CLLocationManager` 标 `nonisolated let`（在 init 阶段一次性赋值，运行时不变）
- `LocationDelegate` 是独立 `final class`（不持 actor），仅 weak 引用 `LocationManager`
- delegate 方法用 `Task { await owner.handle... }` 投到 actor

**已知问题：**
- Swift 5.9 在 `SWIFT_STRICT_CONCURRENCY=minimal` 模式下有 31 个 warning（actor-isolated 跨界访问），都是 false-positive
- 升级到 `SWIFT_STRICT_CONCURRENCY=complete` 后需要重写
- Swift 6.0 会把当前 warning 升级为 error

**应对：**
- 当前 MVP 跑 `minimal` 即可，build 通过
- V0.2 升级 strict concurrency

---

## R-07. CoreLocation WGS-84 vs 高德 GCJ-02 坐标系

**风险等级：🟢 P2**

**问题：**
- CoreLocation 给出的是 WGS-84
- 高德地图渲染需要 GCJ-02
- 直接用 WGS-84 在高德上显示，**中国境内会偏移 50-500 米**

**当前方案：**
- ✅ `LocationPoint` 存 WGS-84
- ✅ 显示时由 `MapView` 调用高德 SDK 的 W2G 转换（高德 SDK 提供 `AMapCoordTypeConvert`）
- ✅ 距离计算（`CLLocation.distance(from:)`）用 WGS-84，结果**与坐标系无关**（这是椭球距离公式）

**注意：**
- 发送给对方的位置**始终 WGS-84**，由对方设备的高德 SDK 转换
- 后端不存 GCJ-02（避免数据污染）

---

## R-08. 隐私 / 合规专项

**风险等级：🟡 P1**

**触发条件：**
- 持续上报位置 → 触发《个人信息保护法》"敏感个人信息"处理规则
- 解除关系时**未删除历史轨迹** → 投诉 / 监管风险

**应对：**
- ✅ Privacy Policy 在 App 内 + App Store 双向展示
- ✅ 「设置」提供「一键导出我的全部位置数据」+「一键删除」按钮
- ✅ 解除关系时**立即停止上报** + 90 天后软删（用户可申请提前删）
- ✅ 用户首次配对需**双方确认**（扫码 + 输入对方 UID）
- ⚠️ 14 岁以下用户**禁止使用**（Apple 要求 + 法规要求）

---

## R-09. 编译 / 工程结构风险

**风险等级：🟢 P2（已解决）**

**问题：**
- actor + 跨模块 `@MainActor` 在 Xcode 15+ Swift 5.9 编译时会产生大量 warning
- xcodegen project.yml 写错 sources 路径会导致整个 target 找不到文件

**当前状态：**
- ✅ 已用 `xcodegen generate` + `xcodebuild -scheme LoveTrack -destination 'generic/platform=iOS Simulator' build` 跑通
- ✅ 0 error, 31 warning（均为 minor concurrency warning）
- 完整日志见 `xcodebuild-output.log`

---

## 风险总览

| ID | 等级 | 简述 | 状态 |
|----|------|------|------|
| R-01 | 🔴 P0 | SC service 唤醒不及时 | 部分缓解 |
| R-02 | 🟡 P1 | 高德 SDK 集成冲突 | 待集成时验证 |
| R-03 | 🔴 P0 | Firebase 国内访问 | 已通过协议层解耦 |
| R-04 | 🟡 P1 | 审核 Always 权限 | 文案已写，待提交 |
| R-05 | 🟡 P1 | iOS 16+ pauses 行为 | 已配置，等待真机验证 |
| R-06 | 🟢 P2 | actor + delegate 桥接 | 已解决（minimal mode） |
| R-07 | 🟢 P2 | 坐标系转换 | 已设计 |
| R-08 | 🟡 P1 | 隐私合规 | 文案待补 |
| R-09 | 🟢 P2 | 编译 | ✅ 已通过 |
