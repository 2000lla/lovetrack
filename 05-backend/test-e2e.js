// End-to-end self-test: pair alice + bob, exchange location, verify protocol contract.
// Mirrors what HTTPRealtimeSyncService.swift does on the iOS side.
// Usage: node test-e2e.js
const WebSocket = require('ws');
const http = require('http');

const BASE = 'http://localhost:3000';
const WS = 'ws://localhost:3000/sync';

function postJSON(path, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const req = http.request(BASE + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': data.length },
    }, (res) => {
      let chunks = '';
      res.on('data', c => chunks += c);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(chunks) }); }
        catch (e) { resolve({ status: res.statusCode, body: chunks }); }
      });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

function openWS(userId, label) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`${WS}?userId=${userId}`);
    const inbox = [];
    ws.on('open', () => {
      console.log(`[${label}] WS open`);
      resolve({ ws, inbox, label });
    });
    ws.on('message', (data) => {
      const msg = JSON.parse(data.toString());
      console.log(`[${label}] ←`, JSON.stringify(msg));
      inbox.push(msg);
    });
    ws.on('error', reject);
  });
}

function send(ws, msg) {
  const s = JSON.stringify(msg);
  console.log(`→ ${s}`);
  ws.send(s);
}

const sleep = (ms) => new Promise(r => setTimeout(r, ms));

async function main() {
  let pass = 0, fail = 0;
  const check = (name, ok, detail = '') => {
    if (ok) { pass++; console.log(`  ✅ ${name}`); }
    else    { fail++; console.log(`  ❌ ${name}${detail ? ' — ' + detail : ''}`); }
  };

  console.log('\n=== Step 1: alice binds → gets invite code ===');
  const bind = await postJSON('/bind', { userId: 'alice' });
  check('POST /bind 200', bind.status === 200, JSON.stringify(bind));
  check('returns 6-char code', typeof bind.body.code === 'string' && bind.body.code.length === 6);
  const code = bind.body.code;
  console.log(`  code = ${code}`);

  console.log('\n=== Step 2: bob pairs with code ===');
  const pair = await postJSON('/pair', { code, userId: 'bob' });
  check('POST /pair 200', pair.status === 200, JSON.stringify(pair));
  check('returns inviterId=alice', pair.body.inviterId === 'alice');
  check('returns inviteeId=bob', pair.body.inviteeId === 'bob');
  check('status=paired', pair.body.status === 'paired');

  console.log('\n=== Step 3: open WS for alice + bob ===');
  const A = await openWS('alice', 'alice');
  const B = await openWS('bob', 'bob');
  await sleep(300);

  console.log('\n=== Step 4: alice receives pair_success push ===');
  const alicePS = A.inbox.find(m => m.type === 'pair_success');
  check('alice got pair_success', !!alicePS);
  check('pair_success.inviteeId=bob', alicePS?.payload?.inviteeId === 'bob');

  console.log('\n=== Step 5: alice sends location_update ===');
  send(A.ws, { type: 'location_update', payload: { lat: 36.6512, lng: 117.1201, battery: 0.85 } });
  await sleep(300);
  console.log('\n=== Step 5b: bob also sends location_update (so alice has partner_location to replay) ===');
  send(B.ws, { type: 'location_update', payload: { lat: 36.6700, lng: 117.1400, battery: 0.72 } });
  await sleep(300);

  console.log('\n=== Step 6: bob receives partner_location ===');
  const bobLoc = B.inbox.find(m => m.type === 'partner_location');
  check('bob got partner_location', !!bobLoc);
  check('lat=36.6512', bobLoc?.payload?.lat === 36.6512);
  check('lng=117.1201', bobLoc?.payload?.lng === 117.1201);
  check('battery=0.85', bobLoc?.payload?.battery === 0.85);
  check('timestamp present', typeof bobLoc?.payload?.timestamp === 'number' && bobLoc.payload.timestamp > Date.now() - 60_000);

  console.log('\n=== Step 7: ping/pong round-trip ===');
  const before = A.inbox.length;
  send(A.ws, { type: 'ping' });
  await sleep(300);
  const newMsgs = A.inbox.slice(before);
  check('alice got pong', newMsgs.some(m => m.type === 'pong'));

  console.log('\n=== Step 8: HTTP /location/:userId fallback ===');
  const loc = await new Promise((resolve) => {
    http.get(`${BASE}/location/alice`, (res) => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(d) }));
    });
  });
  check('GET /location/alice 200', loc.status === 200);
  check('lat=36.6512', loc.body.lat === 36.6512);

  console.log('\n=== Step 9: 404 for unknown user ===');
  const miss = await new Promise((resolve) => {
    http.get(`${BASE}/location/nobody`, (res) => {
      let d = ''; res.on('data', c => d += c);
      res.on('end', () => resolve({ status: res.statusCode, body: d }));
    });
  });
  check('GET /location/nobody 404', miss.status === 404);

  console.log('\n=== Step 10: alice reconnects WS → server replays pair_success + partner_location ===');
  A.ws.close();
  await sleep(200);
  const A2 = await openWS('alice', 'alice2');
  await sleep(500);
  const replay = A2.inbox.find(m => m.type === 'pair_success');
  check('replayed pair_success on reconnect', !!replay, JSON.stringify(A2.inbox));
  check('replay.inviteeId=bob', replay?.payload?.inviteeId === 'bob');
  const replayLoc = A2.inbox.find(m => m.type === 'partner_location');
  check('replayed partner_location on reconnect', !!replayLoc);
  check('replay.lat=36.6700 (bob sent this)', replayLoc?.payload?.lat === 36.6700);

  console.log('\n=== Step 11: GET /me?userId=alice ===');
  const me = await new Promise((resolve) => {
    http.get(`${BASE}/me?userId=alice`, (res) => {
      let d = ''; res.on('data', c => d += c);
      res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(d) }));
    });
  });
  check('GET /me 200', me.status === 200);
  check('relationship.status=paired', me.body.relationship?.status === 'paired');
  check('partner.id=bob', me.body.partner?.id === 'bob');
  check('lastKnownPartnerLocation.lat=36.6700 (bob sent at 36.6700)', me.body.lastKnownPartnerLocation?.lat === 36.6700);
  check('lastKnownPartnerLocation.lng=117.1400', me.body.lastKnownPartnerLocation?.lng === 117.1400);
  check('isOnline=true (just reconnected)', me.body.isOnline === true);

  console.log('\n=== Step 12: GET /me for unpaired user ===');
  const meSolo = await new Promise((resolve) => {
    http.get(`${BASE}/me?userId=solo-stranger`, (res) => {
      let d = ''; res.on('data', c => d += c);
      res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(d) }));
    });
  });
  check('solo /me 200', meSolo.status === 200);
  check('solo.relationship=null', meSolo.body.relationship === null);
  check('solo.partner=null', meSolo.body.partner === null);

  console.log('\n=== Step 13: GET /me missing userId ===');
  const meBad = await new Promise((resolve) => {
    http.get(`${BASE}/me`, (res) => {
      let d = ''; res.on('data', c => d += c);
      res.on('end', () => resolve({ status: res.statusCode, body: d }));
    });
  });
  check('/me without userId 400', meBad.status === 400);

  A2.ws.close();
  B.ws.close();
  await sleep(200);

  console.log(`\n=== Result: ${pass} passed, ${fail} failed ===`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch(e => { console.error(e); process.exit(2); });
