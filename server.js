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
const R = 14;                 // نصف قطر اللاعب
const SURV_SPEED = 150;
const SURV_HURT_BOOST = 190;  // دفعة سرعة بعد الضربة
const KILLER_SPEED = 168;
const MAX_PLAYERS = 7;        // قاتل + 6 ناجين
const GEN_TIME = 45;          // ثواني لمولد بلاعب واحد
const REVIVE_TIME = 5;
const BLEEDOUT = 45;
const HIT_COOLDOWN = 1.4, MISS_COOLDOWN = 0.7;
const ATTACK_REACH = 64;
const TICK = 30;

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

// ---------- فيزياء بسيطة ----------
function resolveWalls(p) {
  for (let pass = 0; pass < 2; pass++) {
    for (const [x, y, w, h] of MAP.walls) {
      const cx = Math.max(x, Math.min(p.x, x + w));
      const cy = Math.max(y, Math.min(p.y, y + h));
      let dx = p.x - cx, dy = p.y - cy;
      const d2 = dx * dx + dy * dy;
      if (d2 >= R * R) continue;
      if (d2 > 0.0001) {
        const d = Math.sqrt(d2), push = R - d;
        p.x += (dx / d) * push; p.y += (dy / d) * push;
      } else {
        // داخل المستطيل: اطلع من أقرب جهة
        const l = p.x - x, r = x + w - p.x, t = p.y - y, b = y + h - p.y;
        const m = Math.min(l, r, t, b);
        if (m === l) p.x = x - R; else if (m === r) p.x = x + w + R;
        else if (m === t) p.y = y - R; else p.y = y + h + R;
      }
    }
  }
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
    p.boost = 0; p.cd = 0; p.atk = 0; p.bleed = 0; p.rv = 0; p.rvTouched = false;
    p.dx = 0; p.dy = 0; p.act = false; p.fa = 0;
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

// ---------- تحديث اللعبة ----------
function update(room, dt) {
  const players = [...room.players.values()];
  const killer = players.find(p => p.role === 'k');
  const survs = players.filter(p => p.role === 's');
  for (const p of players) p.rvTouched = false;

  // حركة
  for (const p of players) {
    if (p.cd > 0) p.cd -= dt;
    if (p.atk > 0) p.atk -= dt;
    if (p.boost > 0) p.boost -= dt;
    if (p.state === 'dead' || p.state === 'escaped') continue;

    let mx = p.dx, my = p.dy;
    const len = Math.hypot(mx, my);
    if (len > 1) { mx /= len; my /= len; }
    let speed = p.role === 'k' ? KILLER_SPEED : SURV_SPEED;
    if (p.role === 's') {
      if (p.state === 'downed') speed = 28;
      else if (p.boost > 0) speed = SURV_HURT_BOOST;
      else if (p.hp === 1) speed = SURV_SPEED * 0.95;
    }
    if (len > 0.05) {
      p.fa = Math.atan2(my, mx);
      p.x += mx * speed * dt; p.y += my * speed * dt;
      resolveWalls(p);
    }
  }

  // قاتل: ضرب (يضرب باتجاه الكاميرا لو العميل أرسل aim)
  if (killer && killer.act && killer.cd <= 0) {
    if (killer.aim !== undefined) killer.fa = killer.aim;
    const ax = killer.x + Math.cos(killer.fa) * 30, ay = killer.y + Math.sin(killer.fa) * 30;
    let best = null, bd = ATTACK_REACH;
    for (const s of survs) {
      if (s.state !== 'alive' && s.state !== 'downed') continue;
      const d = Math.hypot(s.x - ax, s.y - ay);
      if (d < bd) { bd = d; best = s; }
    }
    killer.atk = 0.25;
    if (best) {
      killer.cd = HIT_COOLDOWN;
      if (best.state === 'alive') {
        best.hp -= 1; best.boost = 1.6;
        if (best.hp <= 0) { best.state = 'downed'; best.bleed = BLEEDOUT; best.rv = 0; }
        room.ev.push({ e: 'hit', x: best.x, y: best.y, down: best.state === 'downed' });
      } else {
        best.state = 'dead';
        room.ev.push({ e: 'kill', x: best.x, y: best.y });
      }
    } else {
      killer.cd = MISS_COOLDOWN;
      room.ev.push({ e: 'swing', x: killer.x, y: killer.y });
    }
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
      if (mate.rv >= 1) { mate.state = 'alive'; mate.hp = 1; mate.rv = 0; mate.boost = 1.2; room.ev.push({ e: 'revive', x: mate.x, y: mate.y }); }
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
    })),
    ev: room.ev,
  };
}

// ---------- الاتصال ----------
wss.on('connection', (ws) => {
  const me = { id: nextId++, ws, room: null, name: 'لاعب', role: null, state: 'alive', hp: 0, x: 0, y: 0, fa: 0, dx: 0, dy: 0, act: false, boost: 0, cd: 0, atk: 0, bleed: 0, rv: 0 };

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
      me.dx = Math.max(-1, Math.min(1, +m.dx || 0));
      me.dy = Math.max(-1, Math.min(1, +m.dy || 0));
      me.act = !!m.act;
      // اتجاه التصويب (زاوية الكاميرا) يستخدمه القاتل للضرب
      me.aim = typeof m.aim === 'number' && isFinite(m.aim) ? m.aim : undefined;
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
    if ((room.phase === 'play' || room.phase === 'end') && tickN % 2 === 0) {
      broadcast(room, snapshot(room));
      room.ev = [];
    }
  }
}, 1000 / TICK);

server.listen(PORT, () => console.log(`Nightfall شغال على المنفذ ${PORT}`));
