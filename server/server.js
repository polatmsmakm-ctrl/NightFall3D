// NightFall online server: presence (friends by username), rooms, lobby, state relay.
// Everything is in memory: friend lists live on each phone and are re-sent on connect.
const http = require('http');
const { WebSocketServer } = require('ws');
const { Rules } = require('./rules');

const PORT = process.env.PORT || 8080;
const MAX_PLAYERS = 7;
const MAPS = ['forest', 'village', 'fareej', 'rubkhali', 'garage', 'beach'];
const THEMES = ['normal', 'fog', 'rain', 'snow', 'halloween'];
const HIDDEN = ['survivor4']; // never handed out: only a phone that has it unlocked asks for it
const CHARS = ['killer', 'survivor1', 'survivor2', 'survivor3', 'survivor4', 'survivor5', 'survivor6', 'survivor7', 'survivor8'];

const users = new Map();   // lowercase name -> client
const rooms = new Map();   // code -> room
// every player's numbers, as their phone last sent them (the phones are the record: this only passes
// them on to friends, and a copy on disk refills it after a restart)
const fs = require('fs');
const STATS_FILE = process.env.STATS_FILE || __dirname + '/stats.json';
const stats = new Map();   // lowercase name -> {name, lv, xp, esc, kills, rounds}
try { for (const [k, v] of Object.entries(JSON.parse(fs.readFileSync(STATS_FILE, 'utf8')))) stats.set(k, v); } catch (e) { /* first run */ }
let statsDirty = false;
setInterval(() => {
  if (!statsDirty) return;
  statsDirty = false;
  try { fs.writeFileSync(STATS_FILE, JSON.stringify(Object.fromEntries(stats))); } catch (e) { /* read-only disk: memory only */ }
}, 30000).unref();
function cleanStats(name, s, old) {
  const n = (v) => Math.max(0, Math.min(1e9, Math.floor(Number(v) || 0)));
  // the profile: the character I play most and a short line about me (both shown on my profile page)
  const ch = s && CHARS.includes(s.ch) ? s.ch : ((old && old.ch) || '');
  const bio = s && typeof s.bio === 'string' ? s.bio.replace(/[<>\\"]/g, '').trim().slice(0, 60) : ((old && old.bio) || '');
  return { name, lv: n(s && s.lv), xp: n(s && s.xp), esc: n(s && s.esc), kills: n(s && s.kills), rounds: n(s && s.rounds),
    ch, bio, seen: (old && old.seen) || 0 };
}
// where a player is right now, for their friends' lists: in the menus, in a room's lobby, or in a round
function where(c) { return c.room ? (c.room.state === 'game' ? 'game' : 'room') : 'menu'; }
const pending = new Map(); // lowercase name -> [{from, code, at}]: invites to a friend who was offline
const INVITE_KEEP = 20 * 60 * 1000;

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
    t: 'room', code: r.code, host: r.host, map: r.map, theme: r.theme, gun: !!r.gun, state: r.state,
    players: r.members.map((m) => ({ name: m.name, role: m.role, char: m.char })),
  };
}
function broadcast(r, obj, except) { for (const m of r.members) if (m !== except) send(m, obj); }
function newCode() { // short room code friends can type in: 4 digits, never reused while the room lives
  let c;
  do { c = String(Math.floor(1000 + Math.random() * 9000)); } while (rooms.has(c));
  return c;
}
function freeSurvivor(r) {
  const used = new Set(r.members.map((m) => m.char));
  return CHARS.slice(1).find((c) => !used.has(c) && !HIDDEN.includes(c)) || 'survivor1';
}
function notifyWatchers(name, online) {
  const k = key(name);
  const u = users.get(k);
  const st = online && u ? where(u) : 'off';
  const seen = stats.has(k) ? stats.get(k).seen : 0;
  for (const c of users.values()) if (c.friends.has(k)) send(c, { t: 'presence', name, online, st, seen });
}
function sendPresence(c) {
  const online = [];
  const status = {};
  const rows = [];
  for (const f of c.friends) {
    const u = users.get(f);
    if (u) { online.push(u.name); status[u.name] = where(u); }
    if (stats.has(f)) rows.push(stats.get(f));
  }
  send(c, { t: 'friends', online, status, stats: rows });
}
// a room changed state (made, joined, left, started, back to the lobby): every member's friends hear it
function notifyRoom(r) { for (const m of r.members) notifyWatchers(m.name, true); }
function leaveRoom(c) {
  const r = c.room;
  if (!r) return;
  c.room = null;
  r.members = r.members.filter((m) => m !== c);
  if (c.name && users.get(key(c.name)) === c) notifyWatchers(c.name, true);
  if (r.members.length === 0) { rooms.delete(r.code); return; }
  if (r.host === c.name) r.host = r.members[0].name;
  if (r.state === 'game' && r.rules) r.rules.leave(c.name);
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
  notifyWatchers(c.name, true);
}

const handlers = {
  hello(c, m) {
    if (c.name) return;
    if (!validName(m.name)) return send(c, { t: 'error', code: 'bad_name' });
    const name = m.name.trim();
    if (users.has(key(name))) return send(c, { t: 'error', code: 'name_taken' });
    c.name = name;
    users.set(key(name), c);
    if (m.stats && typeof m.stats === 'object') { stats.set(key(name), cleanStats(name, m.stats, stats.get(key(name)))); statsDirty = true; }
    handlers.friends(c, m);
    send(c, { t: 'welcome', name, maps: MAPS, ver: 5 });
    notifyWatchers(name, true);
    // invites that came while I was away, if their room is still open
    const waiting = pending.get(key(name)) || [];
    pending.delete(key(name));
    for (const inv of waiting) {
      const r = rooms.get(inv.code);
      if (r && r.state === 'lobby' && Date.now() - inv.at < INVITE_KEEP) send(c, { t: 'invite', from: inv.from, code: inv.code, later: true });
    }
  },
  stats(c, m) { // my numbers after a round: kept, and passed to every friend online who has me listed
    if (!m.s || typeof m.s !== 'object') return;
    const row = cleanStats(c.name, m.s, stats.get(key(c.name)));
    stats.set(key(c.name), row);
    statsDirty = true;
    const k = key(c.name);
    for (const u of users.values()) if (u !== c && u.friends.has(k)) send(u, { t: 'fstats', s: row });
  },
  friends(c, m) {
    c.friends = new Set((Array.isArray(m.friends) ? m.friends : []).slice(0, 100).map(key));
    sendPresence(c);
  },
  create(c, m) {
    leaveRoom(c);
    const r = { code: newCode(), host: c.name, map: MAPS.includes(m.map) ? m.map : MAPS[0], theme: 'normal', state: 'lobby', members: [] };
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
    if (m.theme !== undefined && r.host === c.name && THEMES.includes(m.theme)) r.theme = m.theme;
    if (m.gun !== undefined && r.host === c.name) r.gun = !!m.gun; // «وضع السلاح»: survivors carry a stun gun
    if (m.role === 'killer' && c.role !== 'killer') {
      if (r.members.some((x) => x.role === 'killer')) return send(c, { t: 'error', code: 'killer_taken' });
      c.role = 'killer'; c.char = 'killer';
    } else if (m.role === 'survivor' && c.role !== 'survivor') {
      c.role = 'survivor'; c.char = freeSurvivor(r);
    }
    if (m.char !== undefined && c.role === 'survivor' && CHARS.indexOf(m.char) > 0) c.char = m.char;
    broadcast(r, roomView(r));
  },
  gift(c, m) { // the owner opens (or shuts) the hidden character for a friend who is online
    const u = users.get(key(m.to));
    if (!u) return send(c, { t: 'error', code: 'offline' });
    send(u, { t: 'gift', from: c.name, on: m.on !== false });
  },
  invite(c, m) {
    if (!c.room) return;
    const u = users.get(key(m.to));
    if (!u) { // offline: kept, and handed over when they come online (while the room is still open)
      const k = key(m.to);
      if (!validName(String(m.to || ''))) return;
      const list = (pending.get(k) || []).filter((x) => x.from !== c.name && Date.now() - x.at < INVITE_KEEP);
      list.push({ from: c.name, code: c.room.code, at: Date.now() });
      pending.set(k, list.slice(-5));
      if (pending.size > 5000) pending.delete(pending.keys().next().value);
      return send(c, { t: 'error', code: 'invite_later' });
    }
    send(u, { t: 'invite', from: c.name, code: c.room.code });
  },
  start(c) {
    const r = c.room;
    if (!r || r.host !== c.name || r.state !== 'lobby') return;
    r.state = 'game';
    r.seed = Math.floor(Math.random() * 1e9);
    const players = r.members.map((m, i) => ({ name: m.name, role: m.role, char: m.char, slot: i }));
    r.rules = new Rules(players, r.seed, { gun: !!r.gun });
    broadcast(r, { t: 'started', map: r.map, theme: r.theme || 'normal', gun: !!r.gun, seed: r.seed, players });
    notifyRoom(r);
  },
  lobby(c) { // host sends everyone back to the lobby
    const r = c.room;
    if (!r || r.host !== c.name) return;
    r.state = 'lobby';
    r.rules = null;
    broadcast(r, roomView(r));
    notifyRoom(r);
  },
  layout(c, m) { // map object positions; the first one received is used
    const r = c.room;
    if (r && r.state === 'game' && r.rules) r.rules.setLayout(m.d);
  },
  st(c, m) { // position relay
    const r = c.room;
    if (!r || r.state !== 'game') return;
    const p = m.p;
    if (!Array.isArray(p) || p.length !== 4 || !p.every(Number.isFinite)) return;
    if (r.rules) r.rules.setPos(c.name, p);
    broadcast(r, { t: 'st', n: c.name, p, a: String(m.a || 'idle').slice(0, 12), f: m.f ? 1 : 0, v: m.v ? 1 : 0,
      g: [0, 1, 2].includes(m.g) ? m.g : 0, gp: Math.max(-1, Math.min(1, Number(m.gp) || 0)) }, c); // the gun: put away / lowered / raised, and its tilt
  },
  emote(c, m) { // campfire emote in the lobby, shown to everyone else in the room
    const r = c.room;
    if (!r) return;
    const k = Math.min(2, Math.max(0, Math.floor(Number(m.k) || 0)));
    broadcast(r, { t: 'emote', n: c.name, k }, c);
  },
  sig(c, m) { // quick signal ("come here" / "killer here" / "repairing"): relayed to the sender's own side only
    const r = c.room;
    if (!r || r.state !== 'game') return;
    const p = m.p;
    if (!Array.isArray(p) || p.length !== 2 || !p.every(Number.isFinite)) return;
    const k = Math.min(2, Math.max(0, Math.floor(Number(m.k) || 0)));
    for (const x of r.members) if (x !== c && x.role === c.role) send(x, { t: 'sig', n: c.name, k, p });
  },
  ev(c, m) { // a player's input; the server referees and tells everyone what happened
    const r = c.room;
    if (!r || r.state !== 'game' || !r.rules || typeof m.d !== 'object' || m.d === null) return;
    for (const e of r.rules.handle(m.d, c.name)) broadcast(r, { t: 'ev', n: '', d: e });
    r.dirty = true;
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
    if (c.name && users.get(key(c.name)) === c) {
      users.delete(key(c.name));
      const k = key(c.name); // last seen, for the friends' list
      if (stats.has(k)) { stats.get(k).seen = Date.now(); statsDirty = true; }
      notifyWatchers(c.name, false);
    }
  });
  ws.on('error', () => {});
});

setInterval(() => {
  for (const ws of wss.clients) ws.ping();
}, 25000);

// game loop: 10 ticks a second, snapshot 5 times a second (or right after an input)
let tickN = 0;
setInterval(() => {
  tickN++;
  for (const r of rooms.values()) {
    if (r.state !== 'game' || !r.rules || !r.rules.ready) continue;
    for (const e of r.rules.tick(0.1)) broadcast(r, { t: 'ev', n: '', d: e }); // rescues finish inside the tick
    if (r.dirty || tickN % 2 === 0) {
      r.dirty = false;
      broadcast(r, { t: 'ev', n: '', d: r.rules.snapshot() });
    }
  }
}, 100);

server.listen(PORT, () => console.log('NightFall server on :' + PORT));
