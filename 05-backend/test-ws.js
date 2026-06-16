// 简单 WebSocket 测试脚本
// 用法: node test-ws.js alice
const WebSocket = require('ws');
const userId = process.argv[2] || 'tester';

const ws = new WebSocket(`ws://localhost:3000/sync?userId=${userId}`);

ws.on('open', () => {
  console.log(`[${userId}] WS connected`);
  // 1 秒后模拟位置上报
  setTimeout(() => {
    const loc = {
      type: 'location_update',
      payload: { lat: 36.6512 + Math.random() * 0.01, lng: 117.0245 + Math.random() * 0.01, battery: 0.85 },
    };
    console.log(`[${userId}] sending:`, loc);
    ws.send(JSON.stringify(loc));
  }, 1000);

  // 3 秒后 ping
  setTimeout(() => {
    console.log(`[${userId}] sending ping`);
    ws.send(JSON.stringify({ type: 'ping' }));
  }, 3000);

  // 5 秒后关闭
  setTimeout(() => {
    console.log(`[${userId}] closing`);
    ws.close();
  }, 5000);
});

ws.on('message', (data) => {
  const msg = JSON.parse(data.toString());
  console.log(`[${userId}] recv:`, JSON.stringify(msg));
});

ws.on('close', () => {
  console.log(`[${userId}] closed`);
  process.exit(0);
});

ws.on('error', (err) => {
  console.error(`[${userId}] error:`, err.message);
  process.exit(1);
});