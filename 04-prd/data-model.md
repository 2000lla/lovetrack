# 数据模型草案 — LoveTrack MVP

| 字段 | 值 |
| --- | --- |
| 文档版本 | v1.0（2026-06-16） |
| 范围 | MVP（实时定位 + 轨迹回放） |
| 存储选型 | Firebase Realtime Database（主）+ Cloud Firestore（聚合数据） |
| 客户端缓存 | SwiftData / SQLite（本地轨迹缓存） |
| 关联文档 | `prd.md`、`sprint-1.md`、`../03-architecture/architecture.md` |

---

## 1. 设计原则

1. **关系驱动**：所有数据围绕"一对关系（Relationship）"展开，单个用户可同时存在于多个关系中。
2. **实时优先**：`LocationPoint` 走 Realtime DB（毫秒级同步）；`TrackSegment` 走 Firestore（聚合查询）。
3. **时序数据降采样**：原始点位保留 30 天，超过 30 天聚合为小时级。
4. **本地优先**：客户端必须能离线查看当天轨迹，因此 `LocationPoint` 在本地保留至少 7 天。
5. **坐标统一**：服务端统一存储 **WGS-84** 坐标系，高德 SDK 内部转换 GCJ-02 显示。
6. **隐私隔离**：每个 Relationship 是独立子树，RTDB Security Rules 强制 A、B 双方各自只能读写自己参与的关系。

---

## 2. 实体清单

MVP 共 5 个核心实体：

| # | 实体 | 主用途 | 存储位置 |
| --- | --- | --- | --- |
| 1 | **User** | 用户账号、资料、隐私设置 | RTDB `users/{uid}` |
| 2 | **Relationship** | 关系（A–B 配对） | RTDB `relationships/{rid}` |
| 3 | **LocationPoint** | 实时位置点（最新 + 短期历史） | RTDB `relationships/{rid}/locations/{uid}/latest` + `points/{ts}` |
| 4 | **TrackSegment** | 一天聚合后的轨迹段 + 停留点 | Firestore `relationships/{rid}/tracks/{uid}/{date}` |
| 5 | **DeviceStatus** | 设备状态（电量、网络、定位模式） | RTDB `users/{uid}/device` |

---

## 3. 实体字段定义

### 3.1 User

| 字段 | 类型 | 必填 | 注释 |
| --- | --- | --- | --- |
| `uid` | string | ✅ | Firebase Auth UID，主键 |
| `phone` | string | ✅ | 手机号（E.164 格式，如 +8613800138000） |
| `nickname` | string | ✅ | 昵称（默认取手机号后 4 位，可改） |
| `avatarUrl` | string | ❌ | 头像 CDN 地址；为空时用默认卡通头像 |
| `gender` | enum | ❌ | `male` / `female` / `unknown`，影响 UI 默认皮肤 |
| `birthYear` | int | ❌ | 仅用于年龄区间统计，不展示具体生日 |
| `createdAt` | timestamp | ✅ | 注册时间（服务端写） |
| `updatedAt` | timestamp | ✅ | 资料最后修改时间 |
| `privacySettings` | object | ✅ | 见下方子结构 |
| `device` | object | ✅ | 见 `DeviceStatus` 实体（冗余存一份便于查询） |

**`privacySettings` 子结构**：
| 字段 | 类型 | 默认 | 注释 |
| --- | --- | --- | --- |
| `shareLocationByDefault` | bool | `true` | 新建关系时默认共享位置 |
| `ghostMode` | bool | `false` | 全局隐身开关 |
| `ghostModeExpiresAt` | timestamp | `null` | 隐身到期时间 |
| `precisionLevel` | enum | `smart` | `high` / `balanced` / `low` / `smart` |
| `dataRetentionDays` | int | `30` | 服务端保留原始点位天数 |

---

### 3.2 Relationship

| 字段 | 类型 | 必填 | 注释 |
| --- | --- | --- | --- |
| `rid` | string | ✅ | 关系 ID（UUID v4） |
| `type` | enum | ✅ | `couple` / `close_friend`，MVP 仅 couple 启用，close_friend Sprint 2 |
| `status` | enum | ✅ | `pending_a` / `pending_b` / `active` / `ended` |
| `createdAt` | timestamp | ✅ | 创建时间（邀请发起时间） |
| `activatedAt` | timestamp | ❌ | 双方均接受时间 |
| `endedAt` | timestamp | ❌ | 解除时间 |
| `participants` | map | ✅ | `{uid_a: {...}, uid_b: {...}}`，详见子结构 |
| `settings` | object | ✅ | 关系级设置（围栏列表等） |
| `metadata` | object | ✅ | `{inviteCode, inviteCodeExpiresAt, sourceLink}` |

**`participants` 子结构**（以 A 视角）：
| 字段 | 类型 | 注释 |
| --- | --- | --- |
| `uid_a` | string | 创建邀请的用户 UID |
| `nickname_a` | string | A 在此关系中的昵称（默认 = user.nickname，可独立设置） |
| `joinedAt_a` | timestamp | A 加入时间 |
| `status_a` | enum | `pending` / `active` / `left` |
| `uid_b` | string | 受邀用户 UID，配对前可为空字符串 |
| `nickname_b` | string | 同上 |
| `joinedAt_b` | timestamp | — |
| `status_b` | enum | — |

**`settings` 子结构**：
| 字段 | 类型 | 注释 |
| --- | --- | --- |
| `geofences` | array | 围栏列表，元素见 `Geofence` |
| `ghostModeAllowed` | bool | 是否允许关系内使用隐身（默认 true） |

**`Geofence` 子结构**：
| 字段 | 类型 | 注释 |
| --- | --- | --- |
| `id` | string | UUID |
| `label` | string | "家"、"公司"等 |
| `lat` | double | WGS-84 中心点纬度 |
| `lon` | double | WGS-84 中心点经度 |
| `radius` | int | 半径（米），默认 200 |
| `trigger` | enum | `enter` / `leave` / `both` |
| `enabled` | bool | 是否启用 |

**`metadata` 子结构**：
| 字段 | 类型 | 注释 |
| --- | --- | --- |
| `inviteCode` | string | 6 位数字邀请码 |
| `inviteCodeExpiresAt` | timestamp | 7 天后过期 |
| `sourceLink` | string | `lovetrack://invite/{inviteCode}` 形式 deep link |

---

### 3.3 LocationPoint

> 时序数据。最新点位用 `latest` 节点方便实时同步；历史点位按时间戳分片存 `points/{ts}`。

| 字段 | 类型 | 必填 | 注释 |
| --- | --- | --- | --- |
| `uid` | string | ✅ | 上报用户 UID |
| `rid` | string | ✅ | 所属关系 |
| `ts` | long (ms) | ✅ | 上报时间戳（服务端校准，避免客户端时钟漂移） |
| `lat` | double | ✅ | WGS-84 纬度 |
| `lon` | double | ✅ | WGS-84 经度 |
| `accuracy` | float | ✅ | 水平精度（米），如 5.0 |
| `altitude` | double | ❌ | 海拔（米） |
| `speed` | float | ❌ | 速度（m/s） |
| `heading` | float | ❌ | 朝向（0–360 度） |
| `source` | enum | ✅ | `gps` / `wifi` / `cell` / `fused` |
| `battery` | int | ❌ | 上报时手机电量 0–100 |
| `isMoving` | bool | ✅ | 是否在运动（用于回放和聚合） |
| `clientId` | string | ✅ | 客户端生成的 UUID，用于去重 |
| `precisionLevel` | enum | ✅ | 上报时的精度档位 |

**`latest` 节点**：只保留 1 个最新点位（用 RTDB `set` 覆盖），便于实时订阅。
**`points/{ts}` 节点**：按时间戳分片，保留 30 天。30 天后由 Cloud Function 聚合到 `TrackSegment` 并删除原始点。

---

### 3.4 TrackSegment

> 一对关系中、某个用户、某一天的聚合轨迹。每天一份。

| 字段 | 类型 | 必填 | 注释 |
| --- | --- | --- | --- |
| `rid` | string | ✅ | 关系 ID |
| `uid` | string | ✅ | 用户 UID |
| `date` | string | ✅ | 日期 `YYYY-MM-DD`（按用户时区） |
| `summary` | object | ✅ | 当天统计摘要 |
| `path` | array | ✅ | 降采样后的轨迹点数组（最多 500 点） |
| `stayPoints` | array | ✅ | 停留点数组（停留 ≥ 10 分钟的位置） |
| `createdAt` | timestamp | ✅ | 生成时间 |
| `updatedAt` | timestamp | ✅ | 最后更新时间 |

**`summary` 子结构**：
| 字段 | 类型 | 注释 |
| --- | --- | --- |
| `totalDistance` | int | 总移动距离（米） |
| `startAt` | long | 首个定位点时间戳 |
| `endAt` | long | 末个定位点时间戳 |
| `pointCount` | int | 原始点位数（聚合前） |
| `movingDuration` | int | 移动时长（秒） |
| `stationaryDuration` | int | 静止时长（秒） |

**`path` 元素结构**（每点）：
```json
{
  "ts": 1719182400000,
  "lat": 36.6512,
  "lon": 117.1201,
  "speed": 1.2,
  "isMoving": true
}
```

**`stayPoints` 元素结构**：
```json
{
  "centerLat": 36.6512,
  "centerLon": 117.1201,
  "radius": 35,
  "arrivedAt": 1719182400000,
  "leftAt": 1719185400000,
  "durationSec": 3000,
  "label": "公司"     // 反向地理编码，可选
}
```

---

### 3.5 DeviceStatus

> 客户端状态汇总，便于对方主页展示。上报频率低（每 5 分钟或状态变更时）。

| 字段 | 类型 | 必填 | 注释 |
| --- | --- | --- | --- |
| `uid` | string | ✅ | 用户 UID |
| `battery` | int | ✅ | 0–100 |
| `batteryCharging` | bool | ✅ | 是否在充电 |
| `network` | enum | ✅ | `none` / `wifi` / `cellular_4g` / `cellular_5g` |
| `appForeground` | bool | ✅ | App 是否在前台（前台定位精度更高） |
| `precisionLevel` | enum | ✅ | 当前精度档位 |
| `locationPermission` | enum | ✅ | `denied` / `whenInUse` / `always` |
| `ghostModeActive` | bool | ✅ | 是否隐身中 |
| `lastHeartbeatAt` | long | ✅ | 最后心跳时间戳（用于判断是否"在线"） |
| `updatedAt` | timestamp | ✅ | 服务端写入时间 |

---

## 4. 实体关系图（ER Diagram）

```
                ┌──────────────────┐
                │      User        │
                │  (uid, phone,    │
                │   nickname, ...) │
                └──────┬───────────┘
                       │
                       │ 1
                       │
                       │ N
              ┌────────▼─────────┐
              │  Relationship    │           N
              │ (rid, type,      │◄─────────┐
              │  status,         │          │
              │  participants{}, │          │
              │  settings{})    │          │
              └────┬─────────────┘          │
                   │                        │
        ┌──────────┼──────────┐             │
        │ N        │ N        │ 1           │
        │          │          │             │
        ▼          ▼          ▼             │
  ┌─────────┐ ┌─────────┐ ┌──────────┐     │
  │Location-│ │ Track-  │ │   Geo-   │     │
  │ Point   │ │ Segment │ │  fence   │     │
  │(uid,    │ │(uid,    │ │(id,label,│     │
  │ rid, ts,│ │ date,   │ │ lat,lon, │     │
  │ lat,lon)│ │ path[], │ │ radius,..│     │
  └────┬────┘ │ stayPts)│ └──────────┘     │
       │      └─────────┘                   │
       │                                    │
       │ 1                                  │
       ▼                                    │
  ┌──────────────┐                          │
  │ DeviceStatus │  ◄────────────────────────┘
  │(uid, battery,│      每个 User 1 份
  │ network, ...)│
  └──────────────┘
```

**关系摘要**：
- `User` 1—N `Relationship`（一个用户可有多段关系：情侣 + 闺蜜）
- `Relationship` 1—N `LocationPoint`（关系内每个参与者的所有点位）
- `Relationship` 1—N `TrackSegment`（每天每用户一份）
- `Relationship` 1—N `Geofence`（嵌套在 settings.geofences）
- `User` 1—1 `DeviceStatus`

---

## 5. 关键字段示例（Real JSON Sample）

### 5.1 User
```json
{
  "uid": "u_8f3k2a91",
  "phone": "+8613800138000",
  "nickname": "小鹿",
  "avatarUrl": "https://cdn.lovetrack.app/avatars/u_8f3k2a91.jpg",
  "gender": "female",
  "birthYear": 2001,
  "createdAt": 1719129600000,
  "updatedAt": 1719129600000,
  "privacySettings": {
    "shareLocationByDefault": true,
    "ghostMode": false,
    "ghostModeExpiresAt": null,
    "precisionLevel": "smart",
    "dataRetentionDays": 30
  }
}
```

### 5.2 Relationship
```json
{
  "rid": "r_a1b2c3d4",
  "type": "couple",
  "status": "active",
  "createdAt": 1719129700000,
  "activatedAt": 1719129800000,
  "endedAt": null,
  "participants": {
    "uid_a": "u_8f3k2a91",
    "nickname_a": "小鹿",
    "joinedAt_a": 1719129700000,
    "status_a": "active",
    "uid_b": "u_9z8y7x6w",
    "nickname_b": "阿杰",
    "joinedAt_b": 1719129800000,
    "status_b": "active"
  },
  "settings": {
    "geofences": [
      {
        "id": "gf_home",
        "label": "家",
        "lat": 36.6512,
        "lon": 117.1201,
        "radius": 200,
        "trigger": "both",
        "enabled": true
      },
      {
        "id": "gf_office",
        "label": "公司",
        "lat": 36.6821,
        "lon": 117.1453,
        "radius": 300,
        "trigger": "enter",
        "enabled": true
      }
    ],
    "ghostModeAllowed": true
  },
  "metadata": {
    "inviteCode": "482916",
    "inviteCodeExpiresAt": 1719734500000,
    "sourceLink": "lovetrack://invite/482916"
  }
}
```

### 5.3 LocationPoint（latest）
```json
{
  "uid": "u_8f3k2a91",
  "rid": "r_a1b2c3d4",
  "ts": 1719182400123,
  "lat": 36.651216,
  "lon": 117.120108,
  "accuracy": 5.0,
  "altitude": 23.4,
  "speed": 1.2,
  "heading": 89.5,
  "source": "fused",
  "battery": 78,
  "isMoving": true,
  "clientId": "c_5f9b2e1a-7c4d-4e8b-a3f2-1d9e8c7b6a5f",
  "precisionLevel": "smart"
}
```

### 5.4 TrackSegment
```json
{
  "rid": "r_a1b2c3d4",
  "uid": "u_8f3k2a91",
  "date": "2026-06-23",
  "summary": {
    "totalDistance": 4820,
    "startAt": 1719129600000,
    "endAt": 1719216000000,
    "pointCount": 8640,
    "movingDuration": 5400,
    "stationaryDuration": 30600
  },
  "path": [
    { "ts": 1719129600000, "lat": 36.6512, "lon": 117.1201, "speed": 0.0, "isMoving": false },
    { "ts": 1719130500000, "lat": 36.6530, "lon": 117.1230, "speed": 1.4, "isMoving": true },
    { "ts": 1719131400000, "lat": 36.6580, "lon": 117.1280, "speed": 1.6, "isMoving": true },
    { "ts": 1719215900000, "lat": 36.6512, "lon": 117.1201, "speed": 0.0, "isMoving": false }
  ],
  "_pathTruncated": "示例仅展示首 3 点 + 末 1 点；path 数组实际最多 500 点（按时间升序，降采样后）",
  "stayPoints": [
    {
      "centerLat": 36.6512,
      "centerLon": 117.1201,
      "radius": 35,
      "arrivedAt": 1719129600000,
      "leftAt": 1719130500000,
      "durationSec": 900,
      "label": "家"
    },
    {
      "centerLat": 36.6821,
      "centerLon": 117.1453,
      "radius": 50,
      "arrivedAt": 1719131400000,
      "leftAt": 1719173400000,
      "durationSec": 42000,
      "label": "公司"
    }
  ],
  "createdAt": 1719216010000,
  "updatedAt": 1719216010000
}
```

### 5.5 DeviceStatus
```json
{
  "uid": "u_8f3k2a91",
  "battery": 78,
  "batteryCharging": false,
  "network": "cellular_5g",
  "appForeground": false,
  "precisionLevel": "smart",
  "locationPermission": "always",
  "ghostModeActive": false,
  "lastHeartbeatAt": 1719182400000,
  "updatedAt": 1719182400100
}
```

---

## 6. 存储层级与索引

### 6.1 Firebase Realtime Database 节点结构
```
root
├── users/
│   └── {uid}/
│       ├── (User 字段)
│       └── device/
│           └── (DeviceStatus 字段)
│
└── relationships/
    └── {rid}/
        ├── (Relationship 字段)
        ├── locations/
        │   └── {uid}/
        │       ├── latest/      ← (LocationPoint, 仅 1 个最新点)
        │       └── points/
        │           └── {ts}/    ← (LocationPoint, 保留 30 天)
        └── (settings.geofences) ← 直接挂在 Relationship 下
```

### 6.2 Firestore Collection
```
relationships/{rid}/tracks/{uid}/{date}    ← TrackSegment 文档
```

### 6.3 索引建议
| 集合 | 字段 | 索引类型 |
| --- | --- | --- |
| `relationships/{rid}/locations/{uid}/points` | `ts` | 升序 |
| `relationships/{rid}/tracks/{uid}/*` | `date` | 降序 |

### 6.4 RTDB Security Rules（草案）
```json
{
  "rules": {
    "users": {
      "$uid": {
        ".read": "auth != null && (auth.uid == $uid || root.child('relationships').child(...).child('participants').child(auth.uid).exists())",
        ".write": "auth != null && auth.uid == $uid"
      }
    },
    "relationships": {
      "$rid": {
        ".read": "auth != null && (data.child('participants/uid_a').val() == auth.uid || data.child('participants/uid_b').val() == auth.uid)",
        ".write": "auth != null && (data.child('participants/uid_a').val() == auth.uid || data.child('participants/uid_b').val() == auth.uid)",
        "locations": {
          "$uid": {
            ".write": "auth != null && auth.uid == $uid"
          }
        }
      }
    }
  }
}
```

---

## 7. 数据生命周期

| 数据 | 客户端 | 服务端 | 聚合后 | 删除 |
| --- | --- | --- | --- | --- |
| `LocationPoint.latest` | 实时显示 | 实时覆盖 | — | — |
| `LocationPoint.points/{ts}` | 缓存 7 天 | 保留 30 天 | 第 31 天聚合为 `TrackSegment` | 第 31 天删除原始 |
| `TrackSegment` | 缓存 30 天 | 保留 1 年 | 第 1 年降采样为小时级 | 第 2 年删除 |
| `DeviceStatus` | 实时 | 实时覆盖 | — | 账号注销时删除 |
| `Relationship` | 缓存 | 永久 | — | 双方均注销 → 7 天后删除 |
| `User` | 缓存 | 永久 | — | 注销后 7 天硬删除 |

---

## 8. 与 PRD / Sprint 的对齐

| PRD 功能 | 涉及实体 | Sprint 1 落地 |
| --- | --- | --- |
| F-001 注册 | User | ✅ |
| F-002 邀请配对 | Relationship | ✅ |
| F-004/F-005 实时位置 | Relationship + LocationPoint.latest | ✅ |
| F-006 轨迹采集 | LocationPoint.points | ✅（仅采集） |
| F-007 轨迹回放 | TrackSegment | ⚠️ Sprint 1 仅采集，Sprint 2 做 UI |
| F-008 围栏 | Relationship.settings.geofences | ❌ Sprint 2 |
| F-009 隐身 | User.privacySettings.ghostMode | ❌ Sprint 2 |
| F-010 精度档位 | User.privacySettings.precisionLevel + LocationPoint.precisionLevel | ❌ Sprint 2 |
| F-017 电量/网络 | DeviceStatus | ❌ P2 |

---

## 9. 待澄清问题（Open Questions）

| ID | 问题 | 决策者 | 状态 |
| --- | --- | --- | --- |
| DM-O-001 | 挚友关系（close_friend）文案是否需要独立皮肤？数据是否共用？ | PM + Designer | 已建议共用数据 + UI 分支 |
| DM-O-002 | 时区用服务端 UTC 还是客户端本地？ | 后端 | 建议服务端 UTC，客户端按用户时区展示 |
| DM-O-003 | 邀请码是否需要大写字母？纯数字易混淆？ | PM | 当前用纯数字 6 位 |
| DM-O-004 | 离线缓存用 SQLite 还是 SwiftData？ | iOS | Sprint 1 后定 |
| DM-O-005 | 围栏是否需要反向地理编码（自动填 label）？ | PM + iOS | Sprint 2 决策 |

---

## 10. 文档版本

| 版本 | 日期 | 变更 | 作者 |
| --- | --- | --- | --- |
| v1.0 | 2026-06-16 | 初版（5 实体 + ER 图 + JSON 示例） | requirement-agent |