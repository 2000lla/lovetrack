/**
 * LoveTrack MVP Backend - Server
 *
 * 极简后端：Express + WebSocket，内存存储（重启数据丢失，Demo 专用）
 *
 * 数据模型：
 * - relationships: Map<inviteCode, { inviterId, inviteeId, status, createdAt }>
 * - locations: Map<userId, { lat, lng, battery, timestamp }>
 * - sockets: Map<userId, WebSocket>
 *
 * API:
 * - POST /bind          创建邀请码（返回 6 位 code）
 * - POST /pair          用邀请码绑定（绑定双方）
 * - GET  /healthz       健康检查
 * - WS   /sync          实时位置同步（双向）
 */

const express = require('express');
const http = require('http');
const cors = require('cors');
const { WebSocketServer } = require('ws');
const { nanoid } = require('nanoid');

// ============================================================
// 内存存储（重启丢失）
// ============================================================
const relationships = new Map(); // code -> { inviterId, inviteeId, status, createdAt }
const locations = new Map();      // userId -> { lat, lng, battery, timestamp }
const sockets = new Map();        // userId -> WebSocket

// ============================================================
// Express HTTP Server
// ============================================================
const app = express();
app.use(cors());
app.use(express.json());

// Health check
app.get('/healthz', (_req, res) => {
  res.json({
    ok: true,
    onlineUsers: sockets.size,
    activeRelationships: [...relationships.values()].filter(r => r.status === 'paired').length,
    uptime: process.uptime()
  });
});

/**
 * POST /bind
 * Body: { userId: string }
 * Returns: { code: "ABC123", expiresIn: 600 }
 *
 * 创建邀请码，10 分钟内有效
 */
app.post('/bind', (req, res) => {
  const { userId } = req.body;
  if (!userId) {
    return res.status(400).json({ error: 'userId is required' });
  }
  // 6 位大写字母数字组合
  const code = nanoid(6).toUpperCase().replace(/[-_]/g, 'X');
  relationships.set(code, {
    inviterId: userId,
    inviteeId: null,
    status: 'pending',
    createdAt: Date.now(),
    expiresAt: Date.now() + 10 * 60 * 1000,  // 10 分钟
  });
  console.log(`[bind] userId=${userId} code=${code}`);
  res.json({ code, expiresIn: 600 });
});

/**
 * POST /pair
 * Body: { code: string, userId: string }
 * Returns: { inviterId: string, inviteeId: string, status: "paired" }
 */
app.post('/pair', (req, res) => {
  const { code, userId } = req.body;
  if (!code || !userId) {
    return res.status(400).json({ error: 'code and userId are required' });
  }
  const rel = relationships.get(code);
  if (!rel) {
    return res.status(404).json({ error: 'invite code not found' });
  }
  if (rel.expiresAt < Date.now()) {
    return res.status(410).json({ error: 'invite code expired' });
  }
  if (rel.inviterId === userId) {
    return res.status(400).json({ error: 'cannot pair with yourself' });
  }
  if (rel.status === 'paired' && rel.inviteeId && rel.inviteeId !== userId) {
    return res.status(409).json({ error: 'invite code already used' });
  }
  // 绑定成功
  rel.inviteeId = userId;
  rel.status = 'paired';
  rel.pairedAt = Date.now();
  console.log(`[pair] code=${code} inviter=${rel.inviterId} invitee=${rel.inviteeId}`);
  res.json({
    inviterId: rel.inviterId,
    inviteeId: rel.inviteeId,
    status: 'paired',
  });
  // 推送给邀请方：对方已加入
  if (sockets.has(rel.inviterId)) {
    sockets.get(rel.inviterId).send(JSON.stringify({
      type: 'pair_success',
      payload: { inviteeId: userId, inviteeName: userId },
    }));
    console.log(`[ws:PUSH] pair_success → ${rel.inviterId}`);
  }
});

/**
 * GET /location/:userId
 * Returns: { lat, lng, battery, timestamp } | 404
 *
 * 用于对方离线时拉取最后位置
 */
app.get('/location/:userId', (req, res) => {
  const loc = locations.get(req.params.userId);
  if (!loc) {
    return res.status(404).json({ error: 'no location yet' });
  }
  res.json(loc);
});

// ============================================================
// HTTP Server + WebSocket Server (共享端口)
// ============================================================
const PORT = process.env.PORT || 3000;
const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/sync' });

wss.on('connection', (ws, req) => {
  // 简化版：从 URL query 拿 userId (生产环境用 token 鉴权)
  const url = new URL(req.url, `http://${req.headers.host}`);
  const userId = url.searchParams.get('userId');
  if (!userId) {
    ws.close(1008, 'userId required');
    return;
  }

  console.log(`[ws] connected userId=${userId}`);
  sockets.set(userId, ws);

  // 推送对方最近位置（如有）
  const partner = findPartner(userId);
  if (partner) {
    const partnerLoc = locations.get(partner);
    if (partnerLoc) {
      ws.send(JSON.stringify({ type: 'partner_location', payload: partnerLoc }));
    }
  }

  ws.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw.toString());
      handleWsMessage(userId, ws, msg);
    } catch (err) {
      console.error(`[ws] bad message from ${userId}:`, err.message);
    }
  });

  ws.on('close', () => {
    console.log(`[ws] disconnected userId=${userId}`);
    if (sockets.get(userId) === ws) {
      sockets.delete(userId);
    }
  });
});

function handleWsMessage(userId, ws, msg) {
  switch (msg.type) {
    case 'location_update': {
      // 上报位置
      const { lat, lng, battery } = msg.payload;
      const loc = { lat, lng, battery, timestamp: Date.now() };
      locations.set(userId, loc);

      // 推送给对方
      const partner = findPartner(userId);
      if (partner && sockets.has(partner)) {
        sockets.get(partner).send(JSON.stringify({
          type: 'partner_location',
          payload: loc,
        }));
      }
      break;
    }

    case 'ping': {
      ws.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
      break;
    }

    default:
      console.warn(`[ws] unknown msg type from ${userId}: ${msg.type}`);
  }
}

function findPartner(userId) {
  for (const rel of relationships.values()) {
    if (rel.status !== 'paired') continue;
    if (rel.inviterId === userId) return rel.inviteeId;
    if (rel.inviteeId === userId) return rel.inviterId;
  }
  return null;
}

// ============================================================
// 启动
// ============================================================
server.listen(PORT, '0.0.0.0', () => {
  console.log(`💕 LoveTrack backend listening on :${PORT}`);
  console.log(`   HTTP:    http://localhost:${PORT}/healthz`);
  console.log(`   WebSocket: ws://localhost:${PORT}/sync?userId=YOUR_ID`);
});

// 优雅关闭
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down...');
  server.close(() => process.exit(0));
});