// NightFall online server: presence (friends by username), rooms, lobby, state relay.
// Everything is in memory: friend lists live on each phone and are re-sent on connect.
const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8080;
const MAX_PLAYERS = 7;
const MAPS = ['forest', 'village'];
const CHARS = ['killer', 'survivor1', 'survivor2', 'survivor3', 'survivor4'];

const users = new Map();   // lowercase name -> client
const rooms = new Map();   // code -> room

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end(`NightFall server OK. online=${users.size} rooms=${rooms.size}`);
});
const wss = new WebSocketServer({ server, maxPayload: 16 * 1024 });

const send = (c, obj) => { if (c.ws.readyState === 1) c.ws.send(JSON.stringify(obj)); };
const key = (n) => String(n || '').trim().toLowerCase();
const validName = (n) => typeof n === 'string' && n.trim().length >= 2 && n.trim().length <= 16 && !/[\s"\\<>]/.test(n.trim());

function roomView(r) {
  return {
    t: 'room', code: r.code, host: r.host, map: r.map, state: r.state,
    players: r.members.map((m) => ({ name: m.name, role: m.role, char: m.char })),
  };
}
function broadcast(r, obj, except) { for (const m of r.members) if (m !== except) send(m, obj); }
function newCode() {
  let c;
  do { c = String(Math.floor(1000 + Math.random() * 9000)); } while (rooms.has(c));
  return c;
}
function freeSurvivor(r) {
  const used = new Set(r.members.map((m) => m.char));
  return CHARS.slice(1).find((c) => !used.has(c)) || 'survivor1';
}
function notifyWatchers(name, online) {
  const k = key(name);
  for (const c of users.values()) if (c.friends.has(k)) send(c, { t: 'presence', name, online });
}
function sendPresence(c) {
  const online = [];
  for (const f of c.friends) { const u = users.get(f); if (u) online.push(u.name); }
  send(c, { t: 'friends', online });
}
function leaveRoom(c) {
  const r = c.room;
  if (!r) return;
  c.room = null;
  r.members = r.members.filter((m) => m !== c);
  if (r.members.length === 0) { rooms.delete(r.code); return; }
  if (r.host === c.name) r.host = r.members[0].name;
  broadcast(r, { t: 'left', name: c.name });
  broadcast(r, roomView(r));
}
function joinRoom(c, r) {
  leaveRoom(c);
  const hasKiller = r.members.some((m) => m.role === 'killer');
  c.role = hasKiller ? 'survivor' : 'killer';
  c.char = hasKiller ? freeSurvivor(r) : 'killer';
  c.room = r;
  r.members.push(c);
  broadcast(r, roomView(r));
}

const handlers = {
  hello(c, m) {
    if (c.name) return;
    if (!validName(m.name)) return send(c, { t: 'error', code: 'bad_name' });
    const name = m.name.trim();
    if (users.has(key(name))) return send(c, { t: 'error', code: 'name_taken' });
    c.name = name;
    users.set(key(name), c);
    handlers.friends(c, m);
    send(c, { t: 'welcome', name, maps: MAPS });
    notifyWatchers(name, true);
  },
  friends(c, m) {
    c.friends = new Set((Array.isArray(m.friends) ? m.friends : []).slice(0, 100).map(key));
    sendPresence(c);
  },
  create(c, m) {
    leaveRoom(c);
    const r = { code: newCode(), host: c.name, map: MAPS.includes(m.map) ? m.map : MAPS[0], state: 'lobby', members: [] };
    rooms.set(r.code, r);
    joinRoom(c, r);
  },
  join(c, m) {
    const r = rooms.get(String(m.code || '').trim());
    if (!r) return send(c, { t: 'error', code: 'no_room' });
    if (r.members.includes(c)) return;
    if (r.members.length >= MAX_PLAYERS) return send(c, { t: 'error', code: 'room_full' });
    if (r.state !== 'lobby') return send(c, { t: 'error', code: 'in_game' });
    joinRoom(c, r);
  },
  leave(c) { leaveRoom(c); send(c, { t: 'room', code: '' }); },
  set(c, m) {
    const r = c.room;
    if (!r || r.state !== 'lobby') return;
    if (m.map !== undefined && r.host === c.name && MAPS.includes(m.map)) r.map = m.map;
    if (m.role === 'killer' && c.role !== 'killer') {
      if (r.members.some((x) => x.role === 'killer')) return send(c, { t: 'error', code: 'killer_taken' });
      c.role = 'killer'; c.char = 'killer';
    } else if (m.role === 'survivor' && c.role !== 'survivor') {
      c.role = 'survivor'; c.char = freeSurvivor(r);
    }
    if (m.char !== undefined && c.role === 'survivor' && CHARS.indexOf(m.char) > 0) c.char = m.char;
    broadcast(r, roomView(r));
  },
  invite(c, m) {
    if (!c.room) return;
    const u = users.get(key(m.to));
    if (!u) return send(c, { t: 'error', code: 'offline' });
    send(u, { t: 'invite', from: c.name, code: c.room.code });
  },
  start(c) {
    const r = c.room;
    if (!r || r.host !== c.name || r.state !== 'lobby') return;
    r.state = 'game';
    r.seed = Math.floor(Math.random() * 1e9);
    const players = r.members.map((m, i) => ({ name: m.name, role: m.role, char: m.char, slot: i }));
    broadcast(r, { t: 'started', map: r.map, seed: r.seed, players });
  },
  lobby(c) { // host sends everyone back to the lobby
    const r = c.room;
    if (!r || r.host !== c.name) return;
    r.state = 'lobby';
    broadcast(r, roomView(r));
  },
  st(c, m) { // position relay
    const r = c.room;
    if (!r || r.state !== 'game') return;
    const p = m.p;
    if (!Array.isArray(p) || p.length !== 4 || !p.every(Number.isFinite)) return;
    broadcast(r, { t: 'st', n: c.name, p, a: String(m.a || 'idle').slice(0, 12) }, c);
  },
  ping(c) { send(c, { t: 'pong' }); },
};

wss.on('connection', (ws) => {
  const c = { ws, name: null, friends: new Set(), room: null, role: 'survivor', char: 'survivor1', alive: true };
  ws.on('pong', () => { c.alive = true; });
  ws.on('message', (data) => {
    let m;
    try { m = JSON.parse(data.toString()); } catch { return; }
    if (!m || typeof m.t !== 'string') return;
    if (!c.name && m.t !== 'hello') return;
    const h = handlers[m.t];
    if (h) h(c, m);
  });
  ws.on('close', () => {
    leaveRoom(c);
    if (c.name && users.get(key(c.name)) === c) { users.delete(key(c.name)); notifyWatchers(c.name, false); }
  });
  ws.on('error', () => {});
});

setInterval(() => {
  for (const ws of wss.clients) ws.ping();
}, 25000);

server.listen(PORT, () => console.log('NightFall server on :' + PORT));
