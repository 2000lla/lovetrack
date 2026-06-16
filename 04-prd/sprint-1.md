# Sprint 1 计划 — MVP 第 1 周（地基 + 可跑通 Demo）

| 字段 | 值 |
| --- | --- |
| Sprint 编号 | Sprint 1（共 8 周，第 1/8 周） |
| Sprint 周期 | 2026-06-23（周一） ~ 2026-06-27（周五），5 个工作日 |
| 团队配置 | iOS 开发 ×1 / 后端开发 ×1 / 设计（半参与）/ PM ×1 |
| 关联文档 | `prd.md`、`data-model.md`、`../03-architecture/architecture.md` |

---

## 1. Sprint Goal（一句话）

> **本周五下午能拿出一个"双方都能看到彼此实时位置"的 iOS Demo：装在两台模拟器/真机上，打开 App、注册两个账号、配对、互相看到对方位置，轨迹采集已运行并能在 Demo 里回放当天的轨迹。**

---

## 2. 范围（In/Out）

### 2.1 本周 In Scope
- 工程骨架（SwiftUI + xcodegen）跑通编译
- CoreLocation 基础定位（前台）
- 后端 stub：Firebase Realtime Database 模拟节点、Cloud Functions 简单中转
- 注册 / 登录页（Mock 验证码）
- 邀请配对流（生成邀请码、输入邀请码）
- 实时定位主页（地图占位 + 双方位置 marker）
- 后台定位保活 PoC（demonstrate 而非完美）
- 隐私协议 + 权限引导双层弹窗
- Demo 数据准备（两个 mock 账号，济南/北京位置）

### 2.2 本周 Out of Scope（推迟到 Sprint 2+）
- 轨迹回放 UI（数据已采集，UI 用占位）
- 地理围栏提醒
- 隐身模式
- 精度档位设置
- 挚友关系类型
- 戳一戳 / 电量显示
- 后台被杀恢复的完整实现（先做基础版）
- App Store 审核准备

---

## 3. 团队与角色

| 角色 | 姓名（占位） | 本周核心职责 |
| --- | --- | --- |
| iOS 主程 | Dev-iOS | SwiftUI 工程、CoreLocation、UI 页面、地图集成 |
| 后端主程 | Dev-BE | Firebase 项目搭建、Auth/Realtime DB 接入、Cloud Functions |
| 设计（半参与） | Designer | 周二/周四参与 UI review，输出"开启定位"动效设计稿 |
| PM | PM | 每日 standup 主持、周五 demo 评审、阻塞升级 |

> 假设人手：1 iOS + 1 后端 + 0.5 设计 + 1 PM。Sprint 2 起建议增加 1 名 iOS 和 1 名 QA。

---

## 4. 五日任务分解（精确到半天）

> 格式：**上午**（9:30–12:30）/ **下午**（13:30–18:00）。每个半天产出 = 一个可验证物（commit、截图、链接、文档）。

### 📅 周一 Day 1 — 立项 + 工程跑通

| 时段 | 负责人 | 任务 | 产出 |
| --- | --- | --- | --- |
| 上午 | PM | Kick-off：PRD 宣讲、Sprint 计划评审、分工确认 | 会议纪要 + Slack 频道通告 |
| 上午 | Dev-iOS | 工程初始化：xcodegen 配 `LoveTrack/` 目录结构，SwiftUI App 入口能 `xcodebuild build` 通过 | commit `feat: scaffold LoveTrack xcodegen` |
| 上午 | Dev-BE | Firebase 项目创建，配置 iOS BundleID、Auth Provider（Phone）、Realtime DB 安全规则 | Firebase 控制台截图 + README |
| 下午 | Dev-iOS | Info.plist 三件套：`NSLocationWhenInUseUsageDescription` / `NSLocationAlwaysAndWhenInUseUsageDescription` / `NSLocationAlwaysUsageDescription` 文案定稿 | commit `feat: location permission keys` |
| 下午 | Dev-BE | Firebase iOS SDK 通过 SPM 接入（避开 Pod 国内网络坑），写最小 Auth 测试用例 | `FirebaseAuthTests.swift` 通过 |
| 下午 | PM + Designer | 确认 iOS 设计 token（颜色、字号、圆角），与 `02-ui-prototype/` 的 HTML 原型对齐 | 设计 token 文档 |

### 📅 周二 Day 2 — 注册 + 配对闭环

| 时段 | 负责人 | 任务 | 产出 |
| --- | --- | --- | --- |
| 上午 | Dev-iOS | 注册页 UI：手机号输入 + 验证码输入 + 60s 倒计时 + 校验逻辑 | commit + 真机截图 |
| 上午 | Dev-BE | Firebase Phone Auth 后端打通，验证码接口 mock（避免真发短信成本） | API endpoint + Postman 测试通过 |
| 下午 | Dev-iOS | 邀请码生成 + 输入页（6 位数字 + deep link），配对成功后写入 Realtime DB `relationships/{rid}/` | commit `feat: invite-pair flow` |
| 下午 | Dev-BE | Realtime DB 数据结构按 `data-model.md` 草案初始化（User / Relationship 节点 + 测试数据） | DB seed 脚本 |
| 下午 | Designer | "开启定位"开关动效 + 邀请页插画设计稿 | Figma 链接 |
| 晚上 | 全员 | 站会延长 30 分钟：注册+配对 demo（两台模拟器走一遍） | 录屏 |

### 📅 周三 Day 3 — 实时定位核心页

| 时段 | 负责人 | 任务 | 产出 |
| --- | --- | --- | --- |
| 上午 | Dev-iOS | 主页 UI：顶部（头像/昵称/距离/电量占位）+ 地图区（高德 SDK 接入）+ 底部"开启定位"开关 | commit + 截图 |
| 上午 | Dev-BE | `LocationPoint` 节点设计：`relationships/{rid}/locations/{uid}/latest` 实时同步 | Realtime DB 规则 + 文档 |
| 下午 | Dev-iOS | `LocationManager.swift`（actor 隔离）：前台定位 + 监听对方位置变化 | commit `feat: location manager v1` |
| 下午 | Dev-BE | Cloud Function：定时聚合昨天的 `LocationPoint` 写入 `TrackSegment`（仅 Sprint 1 demo 用，不要求生产级） | Function 部署成功 |
| 晚上 | Dev-iOS | 自测：两台模拟器互相看到位置，distance 数字刷新 | 录屏 |

### 📅 周四 Day 4 — 后台保活 PoC + 隐私弹窗

| 时段 | 负责人 | 任务 | 产出 |
| --- | --- | --- | --- |
| 上午 | Dev-iOS | 后台定位 PoC：`allowsBackgroundLocationUpdates = true` + Significant-Change Service 兜底 | commit + 真机锁屏 30 分钟位置日志 |
| 上午 | Dev-BE | 后台定位数据上报接口（POST `/locations`，含节流） | API 文档 + 测试用例 |
| 下午 | Dev-iOS | 隐私协议页 + 首次启动双层权限弹窗（WhenInUse → Always 引导） | commit + 流程截图 |
| 下午 | PM | 整理审核备注初稿（Always 权限解释、demo 视频脚本） | 文档 |
| 下午 | 全员 | Code review：互相 PR review，标记技术债 | review 记录 |
| 晚上 | Dev-iOS | 自测：杀掉 App 后再次打开，10 秒内恢复定位（满足 AC-F-011-1） | 录屏 |

### 📅 周五 Day 5 — 联调 + Demo 准备

| 时段 | 负责人 | 任务 | 产出 |
| --- | --- | --- | --- |
| 上午 | Dev-iOS + Dev-BE | 端到端联调：注册→配对→实时定位→后台保活→轨迹采集（基础） | 联调 checklist 全绿 |
| 上午 | PM | 准备 Demo 脚本（两台真机/模拟器，固定路线） | Demo runbook |
| 下午 | 全员 | **Sprint Review + Demo**：展示本周成果 | 录屏 + 评审意见 |
| 下午 | 全员 | Sprint Retrospective：3 亮点 + 3 改进 + 行动项 | Retrospective 文档 |
| 下午 | PM | 写 Sprint 1 总结报告，更新 board，预告 Sprint 2 候选 Backlog | 总结报告 |

---

## 5. 每日 Standup 模板

> 时间：每天 10:00，时长 ≤ 15 分钟。异步用 Slack 帖子，同步用飞书/Zoom。

```
【Sprint 1 Day X Standup】YYYY-MM-DD
🧑 Dev-iOS
  ✅ Yesterday: ...
  🎯 Today: ...
  🚧 Blockers: ...

🧑 Dev-BE
  ✅ Yesterday: ...
  🎯 Today: ...
  🚧 Blockers: ...

🧑 Designer
  ✅ Yesterday: ...
  🎯 Today: ...
  🚧 Blockers: ...

🧑 PM
  ✅ Yesterday: ...
  🎯 Today: ...
  🚧 Blockers: ...

📌 Notes / Decisions: ...
```

**规则**：
- 每个状态用 1-2 句话，不展开技术细节（细节走 Slack 私信或 PR 评论）
- Blockers 必须当场指派 owner + deadline
- 所有人必须 10:05 前发完，否则 PM 私聊提醒

---

## 6. 周五 Demo 节点（Definition of Demo）

### 6.1 Demo 形式
- **时间**：周五 16:00–17:00
- **受众**：全体团队 + 老板/投资人（如有）+ 设计
- **形式**：现场演示 + 录屏备份
- **时长**：20 分钟演示 + 20 分钟 Q&A + 20 分钟 Retro

### 6.2 Demo Runbook（PM 主导执行）

```
[0:00–0:02] PM 开场：本周目标回顾（Sprint Goal）
[0:02–0:06] Demo Part 1: 注册 + 配对
  - A 手机打开 App → 输手机号 → 验证码（mock 123456）→ 注册成功
  - A 邀请码展示（截图 6 位数字）
  - B 手机输同一邀请码 → 配对成功 → 跳主页
[0:06–0:12] Demo Part 2: 实时定位
  - 主页展示双方位置（济南/北京模拟位置）
  - 距离数字实时刷新
  - 手动滑动其中一个 marker → 对方主页 marker 平滑跟随
[0:12–0:16] Demo Part 3: 后台保活
  - 锁屏 30 秒 → 解锁 → 位置仍持续更新
  - 杀进程 → 重启 → 10 秒内恢复
[0:16–0:18] Demo Part 4: 隐私体验
  - 首次启动 → 隐私协议弹窗 → WhenInUse 弹窗 → Always 引导
[0:18–0:20] 收尾：本周 KPI（注册/配对成功率/崩溃率）
```

### 6.3 录屏要求
- 1080p 60fps
- 包含音频讲解
- 存到共享盘：`/Shared/Sprint-Recordings/sprint-1-demo.mp4`

### 6.4 Demo 必须达到的状态（Pass Criteria）
- [ ] 两个手机从注册到互相看到位置 ≤ 5 分钟
- [ ] 实时位置延迟 ≤ 3 秒
- [ ] 杀进程后自动恢复定位 ≤ 10 秒
- [ ] 隐私弹窗流程完整且不卡顿
- [ ] 无 P0 崩溃

---

## 7. 阻塞依赖项（Dependencies）

| ID | 依赖项 | 影响 | 负责人 | 解决日期 | 状态 |
| --- | --- | --- | --- | --- | --- |
| DEP-001 | 高德地图 SDK AppKey 申请 | Dev-iOS 集成阻塞 | PM | 周一 | ⚠️ 待申请 |
| DEP-002 | Firebase 项目创建 + 账单绑定 | 后端阻塞 | Dev-BE | 周一 | ⚠️ 待绑定信用卡 |
| DEP-003 | Apple Developer Team ID 配置 | xcodebuild 签名 | Dev-iOS | 周一 | 🟡 已有 |
| DEP-004 | 设计 token（颜色/字体）确认 | UI 开工 | Designer | 周一下午 | 🟢 周一交付 |
| DEP-005 | 两台测试真机到位（iPhone 14+） | 端到端测试 | PM | 周二 | ⚠️ 待协调 |
| DEP-006 | 短信验证码服务商选型（Mock vs 阿里云） | 注册流程 | Dev-BE | 周一 | 🟢 用 mock |
| DEP-007 | 高德 Info.plist key 与 Apple key 冲突测试 | 集成阻塞 | Dev-iOS | 周三 | 🟡 已知风险，看架构文档 |

**阻塞升级机制**：DEP 项标红 24 小时未推进 → PM 升级到总监。

---

## 8. Definition of Done（DoD）

每个 Story 完成必须满足：
- [ ] 代码合并到 `main` 分支并通过 CI
- [ ] 至少 1 名同事 code review approve
- [ ] 单元测试覆盖核心逻辑（LocationManager / Auth / RealtimeSync）
- [ ] 真机/模拟器上手动验证通过
- [ ] 关联 AC（验收标准）逐条勾选
- [ ] 文档同步更新（架构/数据模型如有变动）
- [ ] 无 P0/P1 已知 bug 未处理

---

## 9. 风险登记（Sprint 1 专属）

| ID | 风险 | 概率 | 影响 | 应对 |
| --- | --- | --- | --- | --- |
| S1-R-001 | Firebase 国内网络不稳，本周联调卡住 | 中 | 高 | 准备本地 mock server 兜底 |
| S1-R-002 | iOS 16 模拟器后台定位限制（模拟器不支持 always） | 高 | 中 | 用真机测试；模拟器只演示前台部分 |
| S1-R-003 | 高德 SDK 集成有兼容问题，周三才暴露 | 中 | 高 | 周二上午预研 PoC；不行就先用 MapKit 占位 |
| S1-R-004 | 1 个 iOS + 1 个后端人手吃紧，周五 demo 缩水 | 中 | 高 | 砍范围：轨迹回放 UI 推迟到 Sprint 2 |

---

## 10. Sprint Backlog（按 Story 拆分）

| Story ID | 标题 | 估时（人天） | Owner | 状态 |
| --- | --- | --- | --- | --- |
| SB-001 | 工程骨架跑通 | 0.5 | Dev-iOS | 📋 Todo |
| SB-002 | 注册/登录 | 1.0 | Dev-iOS + Dev-BE | 📋 Todo |
| SB-003 | 邀请配对 | 1.0 | Dev-iOS + Dev-BE | 📋 Todo |
| SB-004 | 实时定位主页（地图 + 双方位置） | 2.0 | Dev-iOS | 📋 Todo |
| SB-005 | LocationManager + 后台上报 | 1.5 | Dev-iOS + Dev-BE | 📋 Todo |
| SB-006 | 隐私协议 + 权限引导 | 0.5 | Dev-iOS | 📋 Todo |
| SB-007 | 轨迹采集（基础版，UI 推迟） | 1.0 | Dev-iOS + Dev-BE | 📋 Todo |
| SB-008 | 后台保活 PoC | 1.0 | Dev-iOS | 📋 Todo |
| SB-009 | Demo 数据准备 + 录屏 | 0.5 | Dev-BE + PM | 📋 Todo |

**总估时**：9.0 人天 × 2 人 = 18 人天，分布在 5 天 × 2 人 = 10 人天 → **容量紧绷，需砍范围**。已识别可砍项：轨迹 UI、围栏、隐身。

---

## 11. Sprint 2 预告（仅占位）

候选 Backlog（优先级排序）：
1. 轨迹回放 UI（拖动时间轴）
2. 地理围栏（家/公司预设）
3. 隐身模式
4. 后台被杀恢复完善
5. 精度档位 UI
6. App Store 审核准备

---

## 12. 文档版本

| 版本 | 日期 | 变更 | 作者 |
| --- | --- | --- | --- |
| v1.0 | 2026-06-16 | 初版 | requirement-agent |