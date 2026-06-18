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

/**
 * GET /me?userId=xxx
 * Returns: { userId, relationship: {...} | null, partner: {id,name} | null, lastKnownLocation: {...} | null }
 *
 * 用于 iOS 启动时恢复"我是不是 paired 状态"。in-memory 存储没法做这个,
 * 启动时直接查一下后端就知道。
 */
app.get('/me', (req, res) => {
  const userId = req.query.userId;
  if (!userId) {
    return res.status(400).json({ error: 'userId query param required' });
  }
  // 找关系
  let rel = null;
  let partnerId = null;
  for (const r of relationships.values()) {
    if (r.status !== 'paired') continue;
    if (r.inviterId === userId) { partnerId = r.inviteeId; rel = r; break; }
    if (r.inviteeId === userId) { partnerId = r.inviterId; rel = r; break; }
  }
  const partner = partnerId ? { id: partnerId, name: partnerId } : null;
  const partnerLoc = partnerId ? (locations.get(partnerId) || null) : null;
  // 自己最后位置
  const myLoc = locations.get(userId) || null;
  res.json({
    userId,
    relationship: rel ? {
      id: `rel_${rel.inviterId}_${rel.inviteeId}`,
      inviterId: rel.inviterId,
      inviteeId: rel.inviteeId,
      status: rel.status,
      pairedAt: rel.pairedAt,
    } : null,
    partner,
    lastKnownPartnerLocation: partnerLoc,
    myLastLocation: myLoc,
    isOnline: sockets.has(userId),
  });
});

/**
 * GET /status — 详细状态 JSON（供仪表盘消费）
 */
app.get('/status', (_req, res) => {
  const now = Date.now();
  const rels = [...relationships.values()].map(r => ({
    code: r.code,
    inviterId: r.inviterId,
    inviteeId: r.inviteeId,
    status: r.status,
    age: Math.round((now - r.createdAt) / 1000),
    expiresIn: r.expiresAt ? Math.round((r.expiresAt - now) / 1000) : null,
  }));
  const locs = [...locations.entries()].map(([userId, loc]) => ({
    userId,
    ...loc,
    age: Math.round((now - loc.timestamp) / 1000),
  }));
  const users = [...sockets.keys()];
  res.json({
    ok: true,
    uptime: process.uptime(),
    onlineUsers: sockets.size,
    onlineUserIds: users,
    activeRelationships: rels.filter(r => r.status === 'paired').length,
    relationships: rels,
    locations: locs,
  });
});

/**
 * GET / — 仪表盘 HTML 页面
 */
app.get('/', (_req, res) => {
  res.type('html').send(`<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>LoveTrack 服务状态</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', sans-serif;
  background: #0d0d0f;
  color: #f5f5f7;
  min-height: 100vh;
  display: flex; justify-content: center; align-items: flex-start;
  padding: 24px;
}
.container { width: 100%; max-width: 560px; }
.header {
  text-align: center; padding: 32px 0 24px;
}
.header h1 { font-size: 28px; font-weight: 700; letter-spacing: -0.5px; }
.header h1 .heart { color: #ff3b6e; }
.header .sub { color: #86868b; font-size: 13px; margin-top: 4px; }

/* 状态指示灯 */
.status-dot {
  display: inline-block; width: 10px; height: 10px; border-radius: 50%;
  margin-right: 6px;
}
.status-dot.ok { background: #30d158; box-shadow: 0 0 8px #30d15888; }
.status-dot.down { background: #ff453a; box-shadow: 0 0 8px #ff453a88; }

.cards { display: flex; flex-direction: column; gap: 12px; }
.card {
  background: #1c1c1e; border-radius: 16px; padding: 20px;
  border: 1px solid #2c2c2e;
}
.card-title {
  font-size: 12px; font-weight: 600; text-transform: uppercase;
  letter-spacing: 1px; color: #86868b; margin-bottom: 12px;
}
.row {
  display: flex; justify-content: space-between; align-items: center;
  padding: 8px 0; border-bottom: 1px solid #2c2c2e;
}
.row:last-child { border-bottom: none; }
.row .label { color: #98989d; font-size: 14px; }
.row .value { font-size: 14px; font-weight: 600; font-variant-numeric: tabular-nums; }
.value.green { color: #30d158; }
.value.pink { color: #ff3b6e; }
.value.amber { color: #ff9f0a; }
.value.mono { color: #a5a5aa; }

/* 关系列表 */
.rel-card {
  background: #1c1c1e; border-radius: 12px; padding: 14px;
  border: 1px solid #2c2c2e; margin-top: 8px;
}
.rel-card .pair { font-size: 14px; color: #e5e5ea; }
.rel-card .pair span { color: #86868b; font-size: 12px; }
.rel-card .meta { font-size: 11px; color: #636366; margin-top: 4px; }
.tag {
  display: inline-block; padding: 2px 8px; border-radius: 20px;
  font-size: 11px; font-weight: 600; margin-left: 6px;
}
.tag.paired { background: #30d15822; color: #30d158; }
.tag.pending { background: #ff9f0a22; color: #ff9f0a; }
.tag.expired { background: #ff453a22; color: #ff453a; }

/* 位置列表 */
.loc-row {
  display: flex; align-items: center; gap: 10px; padding: 8px 0;
  border-bottom: 1px solid #2c2c2e; font-size: 13px;
}
.loc-row:last-child { border-bottom: none; }
.loc-row .uid { color: #ff3b6e; font-weight: 500; min-width: 60px; }
.loc-row .coords { color: #a5a5aa; }
.loc-row .age { color: #636366; margin-left: auto; font-size: 12px; }

/* 页脚 */
.footer {
  text-align: center; color: #636366; font-size: 11px;
  margin-top: 20px; padding-bottom: 32px;
}
.footer .tick { color: #30d158; }

@media (max-width: 400px) {
  body { padding: 12px; }
  .header h1 { font-size: 22px; }
}
</style>
</head>
<body>
<div class="container">
  <div class="header">
    <h1><span class="heart">💕</span> LoveTrack</h1>
    <div class="sub" id="statusLine">连接中…</div>
  </div>

  <div class="cards">
    <div class="card">
      <div class="card-title">📊 概览</div>
      <div class="row"><span class="label">服务状态</span><span class="value" id="srvStatus">—</span></div>
      <div class="row"><span class="label">运行时间</span><span class="value mono" id="uptime">—</span></div>
      <div class="row"><span class="label">在线用户</span><span class="value" id="online">—</span></div>
      <div class="row"><span class="label">活跃配对</span><span class="value" id="paired">—</span></div>
    </div>

    <div class="card" id="relCard" style="display:none">
      <div class="card-title">🔗 配对关系</div>
      <div id="relList"></div>
    </div>

    <div class="card" id="locCard" style="display:none">
      <div class="card-title">📍 最近位置</div>
      <div id="locList"></div>
    </div>

    <div class="card" id="wsCard" style="display:none">
      <div class="card-title">🔌 WebSocket 在线</div>
      <div id="wsList"></div>
    </div>
  </div>

  <div class="footer">
    自动刷新 · <span class="tick" id="tick">上次: --:--:--</span>
  </div>
</div>

<script>
async function refresh() {
  try {
    const resp = await fetch('/status');
    const d = await resp.json();
    if (!d.ok) throw new Error('not ok');

    document.getElementById('statusLine').innerHTML =
      '<span class="status-dot ok"></span> 系统正常';
    document.getElementById('srvStatus').innerHTML =
      '<span class="status-dot ok"></span><span class="green">运行中</span>';
    document.getElementById('uptime').textContent = fmtUptime(d.uptime);
    document.getElementById('online').innerHTML =
      '<span class="' + (d.onlineUsers > 0 ? 'pink' : 'mono') + '">' + d.onlineUsers + ' 人</span>';
    document.getElementById('paired').innerHTML =
      '<span class="' + (d.activeRelationships > 0 ? 'green' : 'mono') + '">' + d.activeRelationships + ' 对</span>';

    // 配对关系
    const relCard = document.getElementById('relCard');
    const relList = document.getElementById('relList');
    if (d.relationships.length > 0) {
      relCard.style.display = '';
      relList.innerHTML = d.relationships.map(r => {
        let tagClass = r.status === 'paired' ? 'paired' : (r.status === 'pending' ? 'pending' : 'expired');
        let tagText = r.status === 'paired' ? '已配对' : (r.expiresIn !== null && r.expiresIn <= 0 ? '已过期' : '等待中');
        return '<div class="rel-card">' +
          '<div class="pair">' + esc(r.inviterId) + ' <span>❤️</span> ' + esc(r.inviteeId || '—') +
            '<span class="tag ' + tagClass + '">' + tagText + '</span></div>' +
          '<div class="meta">创建 ' + r.age + 's 前' + (r.expiresIn !== null ? ' · ' + (r.expiresIn > 0 ? r.expiresIn + 's 后过期' : '已过期') : '') + '</div>' +
        '</div>';
      }).join('');
    } else {
      relCard.style.display = 'none';
    }

    // 位置
    const locCard = document.getElementById('locCard');
    const locList = document.getElementById('locList');
    if (d.locations.length > 0) {
      locCard.style.display = '';
      locList.innerHTML = d.locations.map(l =>
        '<div class="loc-row">' +
          '<span class="uid">' + esc(l.userId) + '</span>' +
          '<span class="coords">' + l.lat.toFixed(5) + ', ' + l.lng.toFixed(5) + '</span>' +
          (l.battery != null ? '<span class="coords">🔋' + Math.round(l.battery) + '%</span>' : '') +
          '<span class="age">' + l.age + 's 前</span>' +
        '</div>'
      ).join('');
    } else {
      locCard.style.display = 'none';
    }

    // WebSocket 在线
    const wsCard = document.getElementById('wsCard');
    const wsList = document.getElementById('wsList');
    if (d.onlineUserIds.length > 0) {
      wsCard.style.display = '';
      wsList.innerHTML = d.onlineUserIds.map(id =>
        '<div class="loc-row"><span class="uid">' + esc(id) + '</span>' +
        '<span class="coords" style="color:#30d158">🟢 在线</span></div>'
      ).join('');
    } else if (d.onlineUsers > 0) {
      // fallback: /healthz 显示有人但 /status 没列出来
      wsCard.style.display = '';
      wsList.innerHTML = '<div class="loc-row"><span class="coords">' + d.onlineUsers + ' 人在线</span></div>';
    } else {
      wsCard.style.display = 'none';
    }

  } catch {
    document.getElementById('statusLine').innerHTML =
      '<span class="status-dot down"></span> 服务离线';
    document.getElementById('srvStatus').innerHTML =
      '<span class="status-dot down"></span><span style="color:#ff453a">离线</span>';
  }
  document.getElementById('tick').textContent = '上次: ' + new Date().toLocaleTimeString('zh-CN', {hour12: false});
}

function fmtUptime(s) {
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = Math.floor(s % 60);
  return (h > 0 ? h + 'h ' : '') + m + 'm ' + sec + 's';
}

function esc(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

refresh();
setInterval(refresh, 5000);
</script>
</body>
</html>`);
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

  // 1) 推送对方最近位置（如有）
  const partner = findPartner(userId);
  if (partner) {
    const partnerLoc = locations.get(partner);
    if (partnerLoc) {
      ws.send(JSON.stringify({ type: 'partner_location', payload: partnerLoc }));
    }
  }

  // 2) 如果已 paired 但之前漏掉了 pair_success 推送(WS 还没连就被 pair),
  //    在 WS 连接时补推一次。iOS 端靠这个恢复状态。
  for (const rel of relationships.values()) {
    if (rel.status !== 'paired') continue;
    let partnerId = null;
    if (rel.inviterId === userId) partnerId = rel.inviteeId;
    else if (rel.inviteeId === userId) partnerId = rel.inviterId;
    if (partnerId) {
      ws.send(JSON.stringify({
        type: 'pair_success',
        payload: { inviteeId: partnerId, inviteeName: partnerId },
      }));
      console.log(`[ws:PUSH] pair_success (replay) → ${userId} (partner=${partnerId})`);
      break;  // 只可能有一个 paired rel
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

      // 🐛 Bug 排查:打印谁上传 + 给谁推 + 推的坐标
      const partner = findPartner(userId);
      console.log(`[ws:loc] ${userId} 上传 lat=${lat} lng=${lng} → partner=${partner ?? "none"} 推 partner_location lat=${lat} lng=${lng}`);
      // 推送给对方
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