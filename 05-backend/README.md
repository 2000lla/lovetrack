# =====================================================
# LoveTrack Backend - Sprint 1 极简后端
# =====================================================

Node.js 20 + Express 4 + WebSocket（ws 库）+ Docker

## 目录结构
```
05-backend/
├── package.json          # 依赖
├── Dockerfile            # 镜像构建
├── docker-compose.yml    # 本地一键启动
└── src/
    └── server.js         # 全部逻辑（单文件 ~250 行）
```

## API 速览

### HTTP REST

| Method | Path | Body | 用途 |
|--------|------|------|------|
| GET | `/healthz` | - | 健康检查 |
| POST | `/bind` | `{ userId }` | 创建邀请码，返回 6 位 code（10 分钟有效） |
| POST | `/pair` | `{ code, userId }` | 用邀请码绑定对方 |
| GET | `/location/:userId` | - | 拉取某用户最后位置（离线场景） |

### WebSocket `/sync?userId=xxx`

客户端发：
- `{ type: "location_update", payload: { lat, lng, battery } }` — 上报位置

服务端推：
- `{ type: "partner_location", payload: { lat, lng, battery, timestamp } }` — 对方位置更新
- `{ type: "pong", timestamp }` — 心跳响应

## 本地启动

### 方式 A：Docker（推荐）
```bash
cd 05-backend
docker compose up -d
docker compose logs -f
```

### 方式 B：直接 Node.js
```bash
cd 05-backend
npm install
npm start
```

服务起在 `http://localhost:3000`

## 快速测试

```bash
# 健康检查
curl http://localhost:3000/healthz

# 创建邀请码
curl -X POST http://localhost:3000/bind \
  -H "Content-Type: application/json" \
  -d '{"userId":"alice"}'
# => {"code":"ABC123","expiresIn":600}

# 用邀请码绑定（bob 输入 alice 的邀请码）
curl -X POST http://localhost:3000/pair \
  -H "Content-Type: application/json" \
  -d '{"code":"ABC123","userId":"bob"}'
# => {"inviterId":"alice","inviteeId":"bob","status":"paired"}
```

WebSocket 测试用 `wscat`：
```bash
npm install -g wscat
wscat -c "ws://localhost:3000/sync?userId=alice"
> {"type":"location_update","payload":{"lat":36.65,"lng":117.02,"battery":0.85}}
```

## 部署到云服务器（Ubuntu）

1. **安装 Docker**
   ```bash
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   sudo usermod -aG docker $USER
   ```

2. **拷贝代码 + 启动**
   ```bash
   scp -r 05-backend user@your-server:/home/user/
   ssh user@your-server "cd /home/user/05-backend && docker compose up -d"
   ```

3. **开防火墙端口**
   ```bash
   sudo ufw allow 3000/tcp
   ```

4. **iOS App 配置**
   - Base URL: `http://your-server-ip:3000`
   - WebSocket URL: `ws://your-server-ip:3000/sync?userId=xxx`

⚠️ **生产前必须加**：
- HTTPS（用 nginx + Let's Encrypt）
- WebSocket 鉴权（用 token 替代明文 userId）
- 持久化（PostgreSQL 或 Redis）
- 速率限制（防滥用）

## Sprint 1 Demo 场景

1. Alice 在 iPhone A 上打开 App → 点"创建邀请码" → 显示 6 位码
2. Bob 在 iPhone B 上打开 App → 输入邀请码 → 双方绑定成功
3. Alice 开启定位 → iPhone B 实时看到 Alice 位置在地图上移动
4. Alice 关掉 App → B 显示 Alice 最后位置（不消失）

完成 Sprint 1 demo 周五目标。

## 已知限制（Sprint 1 不修）

- 数据全在内存，重启丢（Demo 够用）
- 没有鉴权，任何人都能伪造 userId（Demo 够用）
- 没有 HTTPS（本地 OK，云上必须加）
- 单进程不能水平扩展（QPS 上千再考虑 Redis）