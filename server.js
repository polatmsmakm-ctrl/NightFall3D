// Nightfall — سيرفر اللعبة (غرف + منطق قاتل/ناجين)
const http = require('http');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { WebSocketServer } = require('ws');
const MAP = require('./public/map.js');

const PORT = process.env.PORT || 3000;
const PUBLIC = path.join(__dirname, 'public');
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml', '.glb': 'model/gltf-binary',
};

const gzCache = new Map();
const server = http.createServer((req, res) => {
  let u = decodeURIComponent(req.url.split('?')[0]);
  if (u === '/health') { res.writeHead(200); return res.end('ok'); }
  if (u === '/') u = '/index.html';
  const f = path.join(PUBLIC, path.normalize(u));
  if (!f.startsWith(PUBLIC)) { res.writeHead(403); return res.end(); }
  fs.readFile(f, (e, d) => {
    if (e) { res.writeHead(404); return res.end('not found'); }
    const type = MIME[path.extname(f)] || 'application/octet-stream';
    const headers = { 'Content-Type': type, 'Cache-Control': (f.includes(path.sep + 'vendor' + path.sep) || f.includes(path.sep + 'assets' + path.sep)) ? 'public, max-age=86400' : 'no-cache' };
    if (/gzip/.test(req.headers['accept-encoding'] || '') && /^(text|application\/(javascript|json))|javascript/.test(type)) {
      let z = gzCache.get(f);
      if (!z || z.src !== d.length) { z = { src: d.length, buf: zlib.gzipSync(d, { level: 6 }) }; gzCache.set(f, z); }
      headers['Content-Encoding'] = 'gzip';
      res.writeHead(200, headers); return res.end(z.buf);
    }
    res.writeHead(200, headers);
    res.end(d);
  });
});

const wss = new WebSocketServer({ server });

// ---------- إعدادات اللعب ----------
const SIM = require('./public/sim.js');
const C = SIM.C;
const MAX_PLAYERS = 7;        // قاتل + 6 ناجين
const GEN_TIME = 45;          // ثواني لمولد بلاعب واحد
const REVIVE_TIME = 5;
const BLEEDOUT = 45;
const TICK = 30;
const LAG = +process.env.NF_LAG || 0;
const SNAP_EVERY = 2;         // لقطة للعملاء كل تيكين (15 مرة بالثانية)

const rooms = new Map();
let nextId = 1;

function makeCode() {
  const L = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  let c;
  do { c = ''; for (let i = 0; i < 4; i++) c += L[Math.floor(Math.random() * L.length)]; } while (rooms.has(c));
  return c;
}

function getRoom(code) {
  if (!rooms.has(code)) {
    rooms.set(code, { code, players: new Map(), hostId: null, phase: 'lobby', gens: [], need: 0, done: 0, exitOpen: false, ev: [], result: null, endAt: 0 });
  }
  return rooms.get(code);
}

function send(ws, obj) { if (ws.readyState === 1) ws.send(JSON.stringify(obj)); }
function broadcast(room, obj) { const s = JSON.stringify(obj); for (const p of room.players.values()) if (p.ws.readyState === 1) p.ws.send(s); }

function lobbyInfo(room) {
  return { t: 'lobby', code: room.code, host: room.hostId, phase: room.phase, players: [...room.players.values()].map(p => ({ id: p.id, n: p.name })) };
}

// ---------- بدء الجولة ----------
function startGame(room) {
  const list = [...room.players.values()];
  const killer = list[Math.floor(Math.random() * list.length)];
  let si = 0;
  const survCount = list.length - 1;
  for (const p of list) {
    p.role = p === killer ? 'k' : 's';
    p.state = 'alive'; p.hp = p.role === 's' ? 2 : 0;
    SIM.reset(p); p.r = p.role; p.st = p.state;
    p.bleed = 0; p.rv = 0; p.rvTouched = false;
    p.q = []; p.bucket = 4; p.ack = 0; p.act = false; p.fa = 0;
    if (p.role === 'k') { p.x = MAP.killerSpawn.x; p.y = MAP.killerSpawn.y; p.fa = Math.PI; }
    else {
      const a = (si / Math.max(survCount, 1)) * Math.PI * 2;
      p.x = MAP.survSpawn.x + Math.cos(a) * 90; p.y = MAP.survSpawn.y + Math.sin(a) * 90;
      si++;
    }
  }
  room.gens = MAP.gens.map(() => ({ p: 0 }));
  room.need = Math.min(5, Math.max(2, survCount + 1));
  room.done = 0; room.exitOpen = false; room.ev = []; room.result = null;
  room.phase = 'play';
  broadcast(room, { t: 'start' });
}

function endGame(room, reason) {
  const survs = [...room.players.values()].filter(p => p.role === 's');
  const escaped = survs.filter(p => p.state === 'escaped').length;
  room.phase = 'end';
  room.endAt = Date.now() + 10000;
  room.result = { escaped, total: survs.length, reason: reason || '' };
  broadcast(room, { t: 'end', ...room.result });
}

// ---------- ضربة القاتل: أقرب ناجي داخل مخروط قدامه أثناء الاندفاعة ----------
function tryHit(room, killer, survs) {
  let best = null, bd = C.ATTACK_REACH;
  for (const s of survs) {
    if (s.state !== 'alive' && s.state !== 'downed') continue;
    const dx = s.x - killer.x, dy = s.y - killer.y, d = Math.hypot(dx, dy);
    if (d >= bd) continue;
    let da = Math.atan2(dy, dx) - killer.lfa; while (da > Math.PI) da -= 2 * Math.PI; while (da < -Math.PI) da += 2 * Math.PI;
    if (d > 22 && Math.abs(da) > C.ATTACK_ARC) continue;
    bd = d; best = s;
  }
  if (!best) return;
  killer.hitDone = true; killer.lunge = 0; killer.cd = C.HIT_CD; killer.slow = C.HIT_SLOW; killer.slowK = C.HIT_SLOW_K;
  if (best.state === 'alive') {
    best.hp -= 1; best.boost = C.HIT_BOOST;
    if (best.hp <= 0) { best.state = 'downed'; best.bleed = BLEEDOUT; best.rv = 0; best.boost = 0; }
    room.ev.push({ e: 'hit', x: best.x, y: best.y, down: best.state === 'downed' });
  } else {
    best.state = 'dead';
    room.ev.push({ e: 'kill', x: best.x, y: best.y });
  }
}

// ---------- تحديث اللعبة ----------
function update(room, dt) {
  const players = [...room.players.values()];
  const killer = players.find(p => p.role === 'k');
  const survs = players.filter(p => p.role === 's');
  for (const p of players) p.rvTouched = false;

  // حركة: كل رسالة تحكم من اللاعب = خطوة محاكاة واحدة (نفس اللي حسبها جواله بالضبط)
  for (const p of players) {
    p.bucket = Math.min(8, p.bucket + TICK * dt * 1.15);
    while (p.q.length && p.bucket >= 1) {
      const inp = p.q.shift(); p.bucket -= 1;
      p.r = p.role; p.st = p.state;
      SIM.step(p, inp, MAP.walls);
      p.ack = inp.s; p.act = !!inp.act;
      if (p.swing) { p.swing = false; p.hitDone = false; room.ev.push({ e: 'swing', x: p.x, y: p.y }); }
      if (p.role === 'k' && p.lunge > 0 && !p.hitDone) tryHit(room, p, survs);
    }
    if (p.q.length > 12) p.q.splice(0, p.q.length - 12);
  }

  // ناجين: نزيف + تصليح + إنقاذ
  const workers = room.gens.map(() => 0);
  for (const s of survs) {
    if (s.state === 'downed') {
      s.bleed -= dt;
      if (s.bleed <= 0) { s.state = 'dead'; room.ev.push({ e: 'kill', x: s.x, y: s.y }); }
      continue;
    }
    if (s.state !== 'alive' || !s.act) continue;
    // إنقاذ أولاً
    let mate = null, md = 62;
    for (const o of survs) {
      if (o === s || o.state !== 'downed') continue;
      const d = Math.hypot(o.x - s.x, o.y - s.y);
      if (d < md) { md = d; mate = o; }
    }
    if (mate) {
      mate.rv += dt / REVIVE_TIME; mate.rvTouched = true;
      if (mate.rv >= 1) { mate.state = 'alive'; mate.hp = 1; mate.rv = 0; mate.boost = 1.2; mate.stam = 1; mate.exh = false; room.ev.push({ e: 'revive', x: mate.x, y: mate.y }); }
      continue;
    }
    // مولد
    let gi = -1, gd = 78;
    room.gens.forEach((g, i) => {
      if (g.p >= 1) return;
      const d = Math.hypot(MAP.gens[i].x - s.x, MAP.gens[i].y - s.y);
      if (d < gd) { gd = d; gi = i; }
    });
    if (gi >= 0) workers[gi]++;
  }
  for (const s of survs) if (!s.rvTouched && s.rv > 0) s.rv = Math.max(0, s.rv - dt / 2);

  room.gens.forEach((g, i) => {
    if (workers[i] > 0 && g.p < 1) {
      g.p = Math.min(1, g.p + (workers[i] * dt) / GEN_TIME);
      if (g.p >= 1) {
        room.done++;
        room.ev.push({ e: 'gen', x: MAP.gens[i].x, y: MAP.gens[i].y });
        if (room.done >= room.need && !room.exitOpen) { room.exitOpen = true; room.ev.push({ e: 'exit' }); }
      }
    }
  });

  // هروب
  if (room.exitOpen) {
    for (const s of survs) {
      if (s.state !== 'alive') continue;
      for (const ex of MAP.exits) {
        if (Math.hypot(s.x - ex.x, s.y - ex.y) < 90) {
          s.state = 'escaped';
          room.ev.push({ e: 'escape', x: s.x, y: s.y });
          break;
        }
      }
    }
  }

  // نهاية الجولة
  if (!survs.some(s => s.state === 'alive' || s.state === 'downed')) endGame(room);
}

function snapshot(room) {
  return {
    t: 's', ph: room.phase, done: room.done, need: room.need, exitOpen: room.exitOpen,
    gens: room.gens.map(g => Math.round(g.p * 1000) / 1000),
    pl: [...room.players.values()].map(p => ({
      id: p.id, n: p.name, x: Math.round(p.x * 10) / 10, y: Math.round(p.y * 10) / 10,
      r: p.role, st: p.state, hp: p.hp, fa: Math.round(p.fa * 100) / 100,
      atk: p.atk > 0 ? 1 : 0, rv: Math.round(p.rv * 100) / 100,
      bl: p.state === 'downed' ? Math.round(p.bleed) : 0, bo: p.boost > 0 ? 1 : 0,
      cr: p.cr ? 1 : 0, sp: p.sp ? 1 : 0,
    })),
    ev: room.ev,
  };
}

// ---------- الاتصال ----------
wss.on('connection', (ws) => {
  if (LAG) {      // للتجربة فقط: NF_LAG=80 يحاكي تأخير شبكة 80ms بكل اتجاه
    const rawSend = ws.send.bind(ws), rawOn = ws.on.bind(ws);
    ws.send = d => setTimeout(() => { if (ws.readyState === 1) rawSend(d); }, LAG);
    ws.on = (ev, fn) => rawOn(ev, ev === 'message' ? (...a) => setTimeout(() => fn(...a), LAG) : fn);
  }
  const me = { id: nextId++, ws, room: null, name: 'لاعب', role: null, state: 'alive', hp: 0, x: 0, y: 0, fa: 0, act: false, bleed: 0, rv: 0, q: [], bucket: 4, ack: 0 };
  SIM.reset(me);

  ws.on('message', (raw) => {
    let m; try { m = JSON.parse(raw); } catch { return; }

    if (m.t === 'join') {
      if (me.room) return;
      const name = String(m.name || 'لاعب').trim().slice(0, 14) || 'لاعب';
      let code = String(m.room || '').toUpperCase().replace(/[^A-Z]/g, '').slice(0, 4);
      if (!code) code = makeCode();
      else if (!rooms.has(code) && m.mustExist) return send(ws, { t: 'err', msg: 'الغرفة غير موجودة' });
      const room = getRoom(code);
      if (room.players.size >= MAX_PLAYERS) return send(ws, { t: 'err', msg: 'الغرفة ممتلئة (7 لاعبين كحد أقصى)' });
      if (room.phase === 'play') return send(ws, { t: 'err', msg: 'الجولة شغالة الحين، انتظر تخلص' });
      me.name = name; me.room = room;
      room.players.set(me.id, me);
      if (!room.hostId) room.hostId = me.id;
      send(ws, { t: 'joined', id: me.id, code });
      broadcast(room, lobbyInfo(room));
      return;
    }

    const room = me.room;
    if (!room) return;

    if (m.t === 'start') {
      if (room.hostId !== me.id || room.phase === 'play') return;
      if (room.players.size < 2) return send(ws, { t: 'err', msg: 'تحتاج لاعبين على الأقل' });
      startGame(room);
    } else if (m.t === 'i') {
      if (room.phase !== 'play' || me.q.length > 16) return;
      me.q.push({
        s: m.s | 0,
        dx: Math.max(-1, Math.min(1, +m.dx || 0)), dy: Math.max(-1, Math.min(1, +m.dy || 0)),
        act: !!m.act, sp: !!m.sp, cr: !!m.cr,
        aim: typeof m.aim === 'number' && isFinite(m.aim) ? m.aim : undefined,   // اتجاه الكاميرا: القاتل يضرب باتجاهه
      });
    }
  });

  ws.on('close', () => {
    const room = me.room;
    if (!room) return;
    room.players.delete(me.id);
    if (room.players.size === 0) { rooms.delete(room.code); return; }
    if (room.hostId === me.id) room.hostId = room.players.values().next().value.id;
    if (room.phase === 'play') {
      const left = [...room.players.values()];
      const hasKiller = left.some(p => p.role === 'k');
      const hasSurv = left.some(p => p.role === 's' && (p.state === 'alive' || p.state === 'downed'));
      if (!hasKiller) endGame(room, 'القاتل طلع من اللعبة');
      else if (!hasSurv) endGame(room);
    }
    broadcast(room, lobbyInfo(room));
  });
});

// ---------- الحلقة الرئيسية ----------
let last = Date.now(), tickN = 0;
setInterval(() => {
  const now = Date.now();
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now; tickN++;
  for (const room of rooms.values()) {
    if (room.phase === 'play') update(room, dt);
    if (room.phase === 'end' && now >= room.endAt) {
      room.phase = 'lobby'; room.result = null;
      for (const p of room.players.values()) { p.role = null; p.state = 'alive'; }
      broadcast(room, lobbyInfo(room));
    }
    if ((room.phase === 'play' || room.phase === 'end') && tickN % SNAP_EVERY === 0) {
      // لقطة مشتركة + حالة الحركة الدقيقة لكل لاعب لنفسه (عشان يطابق توقّعه)
      const base = JSON.stringify(snapshot(room)).slice(0, -1);
      for (const p of room.players.values()) {
        if (p.ws.readyState !== 1) continue;
        p.ws.send(base + ',"me":' + JSON.stringify({ a: p.ack, ...SIM.pack(p) }) + '}');
      }
      room.ev = [];
    }
  }
}, 1000 / TICK);

server.listen(PORT, () => console.log(`Nightfall شغال على المنفذ ${PORT}`));
