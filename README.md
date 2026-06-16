# LoveTrack — 情侣守护 App MVP

用科技守护亲密，让关心时刻在线。

## 📁 项目结构

```
├── 01-research/         # 竞品调研（爱合/微爱/恋爱记/Zenly/Life360）
├── 02-ui-prototype/     # 高保真 HTML 原型（实时定位 + 轨迹回放）
├── 03-architecture/     # iOS 工程骨架 + 架构文档
│   └── LoveTrack/       # SwiftUI Xcode 工程（MVVM + Actor）
├── 04-prd/              # 产品需求文档 + Sprint 1 计划 + 数据模型
└── 05-backend/          # Node.js 后端（Express + WebSocket + Docker）
```

## 🚀 技术栈

- **iOS**: SwiftUI + CoreLocation + MVVM + Actor（iOS 16+）
- **后端**: Node.js 20 + Express + WebSocket（ws）
- **部署**: Docker + docker-compose（Ubuntu 22.04）
- **设计**: 粉紫渐变 + 圆角卡片 + 表情贴纸（对标爱合）

## 🔌 快速启动

### 后端
```bash
cd 05-backend
npm install
npm start
# → http://localhost:3000
# → ws://localhost:3000/sync?userId=YOUR_ID
```

### iOS
```bash
cd 03-architecture/LoveTrack
xcodegen generate
open LoveTrack.xcodeproj
# Signing & Capabilities → 登录 Apple ID → ⌘R
```

### Docker 部署
```bash
cd 05-backend
docker compose up -d
```

## 📡 API

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/bind` | 创建邀请码（返回 6 位 code） |
| POST | `/pair` | 用邀请码绑定 |
| GET | `/healthz` | 健康检查 |
| WS | `/sync?userId=xxx` | 实时位置同步 |

## 📋 Sprint 1 目标

周五拿出双方实时位置 Demo。
