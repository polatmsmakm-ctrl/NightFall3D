// NightFall online server: presence (friends by username), rooms, lobby, state relay.
// Everything is in memory: friend lists live on each phone and are re-sent on connect.
const http = require('http');
const path = require('path');
const { WebSocketServer } = require('ws');
const { Rules } = require('./rules');

const PORT = process.env.PORT || 8080;
const MAX_PLAYERS = 7;
const MAPS = ['forest', 'village', 'fareej', 'rubkhali', 'garage', 'beach', 'city', 'kuwait', 'moon'];
const THEMES = ['normal', 'fog', 'rain', 'snow', 'halloween', 'sunset'];
const HIDDEN = ['survivor4']; // never handed out: only a phone that has it unlocked asks for it
const CHARS = ['killer', 'survivor1', 'survivor2', 'survivor3', 'survivor4', 'survivor5', 'survivor6', 'survivor7', 'survivor8', 'survivor9', 'survivor10'];
const KILLERS = ['killer', 'killer2']; // «البركة القرمزية» and «الوحش»

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
  const ch = s && (CHARS.includes(s.ch) || KILLERS.includes(s.ch)) ? s.ch : ((old && old.ch) || '');
  const bio = s && typeof s.bio === 'string' ? s.bio.replace(/[<>\\"]/g, '').trim().slice(0, 60) : ((old && old.bio) || '');
  return { name, lv: n(s && s.lv), xp: n(s && s.xp), esc: n(s && s.esc), kills: n(s && s.kills), rounds: n(s && s.rounds),
    ch, bio, seen: (old && old.seen) || 0 };
}
// ---- accounts (the Social Sidebar): a username belongs to the phone that first took it (its secret
// token), with a display name, its friends (mutual) and friend requests. Kept on disk, and every phone
// also sends its own token, friends and sent requests with hello, so a server that lost its disk
// (Render's free disk is wiped on a deploy) rebuilds them as the players come back.
const ACCOUNTS_FILE = process.env.ACCOUNTS_FILE || __dirname + '/accounts.json';
const accounts = new Map(); // lowercase name -> {name, display, token, friends:Set, inc:Set, out:Set}
try {
  for (const [k, a] of Object.entries(JSON.parse(fs.readFileSync(ACCOUNTS_FILE, 'utf8')))) {
    accounts.set(k, { name: a.name, display: a.display || a.name, token: a.token || '', friends: new Set(a.friends || []), inc: new Set(a.inc || []), out: new Set(a.out || []) });
  }
} catch (e) { /* first run */ }
let accDirty = false;
setInterval(() => {
  if (!accDirty) return;
  accDirty = false;
  const o = {};
  for (const [k, a] of accounts) o[k] = { name: a.name, display: a.display, token: a.token, friends: [...a.friends], inc: [...a.inc], out: [...a.out] };
  try { fs.writeFileSync(ACCOUNTS_FILE, JSON.stringify(o)); } catch (e) { /* read-only disk: memory only */ }
}, 15000).unref();
const cleanDisplay = (d, fallback) => {
  const s = typeof d === 'string' ? d.replace(/[<>\\"\n\r\t]/g, '').trim().slice(0, 20) : '';
  return s.length >= 2 ? s : fallback;
};
function account(name) {
  const k = key(name);
  let a = accounts.get(k);
  if (!a) { a = { name, display: name, token: '', friends: new Set(), inc: new Set(), out: new Set() }; accounts.set(k, a); accDirty = true; }
  return a;
}
function socialRow(k) {
  const a = accounts.get(k);
  const s = stats.get(k) || {};
  return { name: a ? a.name : k, display: a ? a.display : k, ch: s.ch || '', lv: s.lv || 0 };
}
// my friends, the requests I got and the ones I sent (online and status come with 'friends' / 'presence')
function sendSocial(c) {
  if (!c || !c.name) return;
  const a = accounts.get(key(c.name));
  if (!a) return;
  send(c, { t: 'social', me: { name: a.name, display: a.display }, friends: [...a.friends].map(socialRow),
    inc: [...a.inc].map(socialRow), out: [...a.out].map(socialRow) });
}
function socialBoth(ka, kb) {
  for (const k of [ka, kb]) { const u = users.get(k); if (u) { sendSocial(u); sendPresence(u); } }
}
function befriend(ka, kb) {
  const a = accounts.get(ka), b = accounts.get(kb);
  if (!a || !b) return;
  a.friends.add(kb); b.friends.add(ka);
  a.inc.delete(kb); a.out.delete(kb); b.inc.delete(ka); b.out.delete(ka);
  accDirty = true;
  socialBoth(ka, kb);
}
// where a player is right now, for their friends' lists: in the menus, in a room's lobby, or in a round
function where(c) { return c.room ? (c.room.state === 'game' ? 'game' : 'room') : 'menu'; }
const pending = new Map(); // lowercase name -> [{from, code, at}]: invites to a friend who was offline
const INVITE_KEEP = 20 * 60 * 1000;
const STALE_MS = 6000; // a connection silent this long can be replaced by its owner's new one

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end(`NightFall server OK. online=${users.size} rooms=${rooms.size}`);
});
const wss = new WebSocketServer({ server, maxPayload: 64 * 1024 /* the layout of a big map (doors, hooks) */ });

const send = (c, obj) => { if (c.ws.readyState === 1) c.ws.send(JSON.stringify(obj)); };
const key = (n) => String(n || '').trim().toLowerCase();
const validName = (n) => typeof n === 'string' && n.trim().length >= 2 && n.trim().length <= 16 && !/[\s"\\<>]/.test(n.trim());

function roomView(r) {
  return {
    t: 'room', code: r.code, host: r.host, map: r.map, theme: r.theme, gun: !!r.gun, sniper: !!r.sniper, state: r.state,
    players: r.members.map((m) => ({ name: m.name, role: m.role, char: m.char, perk: m.perk || '' })),
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
    const tok = typeof m.token === 'string' && /^[a-f0-9]{16,64}$/.test(m.token) ? m.token : '';
    const acc = accounts.get(key(name));
    // the username belongs to the phone that took it first: another phone gets «name owned»
    if (acc && acc.token && tok && acc.token !== tok) return send(c, { t: 'error', code: 'name_owned' });
    const old = users.get(key(name));
    if (old) {
      // the same phone coming back after its connection dropped (Wi-Fi to 4G, the app in the
      // background): the server may not have noticed the old socket is dead yet. Same address, or
      // the old one silent for a while, and the new connection takes the name over; before, the
      // phone got «name taken» and stopped trying until the game was restarted.
      const stale = old.ws.readyState !== 1 || Date.now() - old.last > STALE_MS || (old.ip && old.ip === c.ip);
      if (!stale) return send(c, { t: 'error', code: 'name_taken' });
      users.delete(key(name));
      try { old.ws.terminate(); } catch (e) { /* already gone */ }
    }
    c.name = name;
    users.set(key(name), c);
    const a = account(name);
    if (tok && !a.token) { a.token = tok; accDirty = true; }
    a.name = name;
    if (m.display !== undefined) { a.display = cleanDisplay(m.display, a.display || name); accDirty = true; }
    // what the phone remembers fills in what the server may have lost: its friends and its sent requests
    for (const f of (Array.isArray(m.friends) ? m.friends : []).slice(0, 100)) {
      const fk = key(f);
      if (!validName(String(f)) || fk === key(name)) continue;
      if (!a.friends.has(fk)) { a.friends.add(fk); accDirty = true; }
    }
    for (const f of (Array.isArray(m.out) ? m.out : []).slice(0, 50)) {
      const fk = key(f);
      const fa = accounts.get(fk);
      if (!fa || fk === key(name) || a.friends.has(fk)) continue;
      a.out.add(fk); fa.inc.add(key(name)); accDirty = true;
    }
    c.friends = a.friends;
    if (m.stats && typeof m.stats === 'object') { stats.set(key(name), cleanStats(name, m.stats, stats.get(key(name)))); statsDirty = true; }
    sendPresence(c);
    sendSocial(c);
    send(c, { t: 'welcome', name, maps: MAPS, ver: 6 });
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
  friends(c, m) { // an older phone's own list: kept as my friends (the Social Sidebar's requests are the new way)
    const a = account(c.name);
    for (const f of (Array.isArray(m.friends) ? m.friends : []).slice(0, 100)) if (validName(String(f)) && key(f) !== key(c.name)) a.friends.add(key(f));
    c.friends = a.friends;
    accDirty = true;
    sendPresence(c);
    sendSocial(c);
  },
  freq(c, m) { // a friend request by username
    const me = key(c.name), to = key(m.to);
    if (!validName(String(m.to || '')) || to === me) return send(c, { t: 'error', code: 'bad_friend' });
    const t = accounts.get(to);
    if (!t) return send(c, { t: 'error', code: 'no_user' });
    const a = account(c.name);
    if (a.friends.has(to)) return sendSocial(c);
    if (a.inc.has(to)) return befriend(me, to); // they had already asked me: that is a yes on both sides
    a.out.add(to); t.inc.add(me); accDirty = true;
    sendSocial(c);
    const u = users.get(to);
    if (u) { sendSocial(u); send(u, { t: 'freq_in', from: a.name, display: a.display }); }
  },
  faccept(c, m) {
    const me = key(c.name), from = key(m.from);
    const a = account(c.name);
    if (!a.inc.has(from)) return sendSocial(c);
    befriend(me, from);
    const u = users.get(from);
    if (u) send(u, { t: 'freq_ok', from: a.name, display: a.display });
  },
  fdecline(c, m) {
    const me = key(c.name), from = key(m.from);
    const a = account(c.name), f = accounts.get(from);
    a.inc.delete(from); if (f) f.out.delete(me); accDirty = true;
    socialBoth(me, from);
  },
  fcancel(c, m) {
    const me = key(c.name), to = key(m.to);
    const a = account(c.name), t = accounts.get(to);
    a.out.delete(to); if (t) t.inc.delete(me); accDirty = true;
    socialBoth(me, to);
  },
  funfriend(c, m) {
    const me = key(c.name), f = key(m.name);
    const a = account(c.name), b = accounts.get(f);
    a.friends.delete(f); if (b) b.friends.delete(me); accDirty = true;
    socialBoth(me, f);
  },
  display(c, m) { // my display name: shown to my friends beside my @username
    const a = account(c.name);
    a.display = cleanDisplay(m.display, a.display || a.name);
    accDirty = true;
    sendSocial(c);
    for (const f of a.friends) { const u = users.get(f); if (u) sendSocial(u); }
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
    if (m.map !== undefined && r.host === c.name && MAPS.includes(m.map)) { r.map = m.map; if (r.map !== 'kuwait') r.sniper = false; }
    if (m.theme !== undefined && r.host === c.name && THEMES.includes(m.theme)) r.theme = m.theme;
    if (m.gun !== undefined && r.host === c.name) r.gun = !!m.gun; // «وضع السلاح»: survivors carry a stun gun
    if (m.sniper !== undefined && r.host === c.name) { // «وضع القنّاص»: Kuwait City only, so it takes the map with it
      r.sniper = !!m.sniper;
      if (r.sniper) r.map = 'kuwait';
    }
    if (m.role === 'killer' && c.role !== 'killer') {
      if (r.members.some((x) => x.role === 'killer')) return send(c, { t: 'error', code: 'killer_taken' });
      c.role = 'killer'; c.char = 'killer';
    } else if (m.role === 'survivor' && c.role !== 'survivor') {
      c.role = 'survivor'; c.char = freeSurvivor(r);
    }
    if (m.perk !== undefined) c.perk = m.perk === 'aid' ? 'aid' : ''; // «المسعف» instead of the character's own perk
    if (m.char !== undefined && c.role === 'survivor' && CHARS.indexOf(m.char) > 0) c.char = m.char;
    if (m.char !== undefined && c.role === 'killer' && KILLERS.includes(m.char)) c.char = m.char;
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
    const players = r.members.map((m, i) => ({ name: m.name, role: m.role, char: m.char, perk: m.role === 'survivor' ? (m.perk || '') : '', slot: i }));
    // the Moon has no weather (no air): it plays its own night, or Halloween
    const theme = r.map === 'moon' && !['normal', 'halloween'].includes(r.theme || 'normal') ? 'normal' : (r.theme || 'normal');
    r.rules = new Rules(players, r.seed, { gun: !!r.gun, theme, sniper: !!r.sniper && r.map === 'kuwait', map: r.map });
    broadcast(r, { t: 'started', map: r.map, theme, gun: !!r.gun, sniper: !!r.sniper && r.map === 'kuwait', seed: r.seed, players });
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
    const d = /^dance(_[a-z]{1,10})?$/.test(String(m.d || '')) ? String(m.d) : 'dance'; // which dance (the menu «Dances»)
    broadcast(r, { t: 'emote', n: c.name, k, d }, c);
  },
  ad(c, m) { // the developer tools play (or stop) the promotional video on the billboard: every phone in the round
    const r = c.room;
    if (!r || r.state !== 'game') return;
    broadcast(r, { t: 'ad', on: m.on !== false, by: c.name });
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

wss.on('connection', (ws, req) => {
  // where the phone connects from (Render puts the real address in x-forwarded-for), to tell a
  // reconnecting phone from somebody else who picked the same name
  const ip = String((req && req.headers && req.headers['x-forwarded-for']) || (req && req.socket && req.socket.remoteAddress) || '').split(',')[0].trim();
  const c = { ws, name: null, friends: new Set(), room: null, role: 'survivor', char: 'survivor1', alive: true, ip, last: Date.now() };
  ws.c = c;
  ws.on('pong', () => { c.alive = true; });
  ws.on('message', (data) => {
    c.last = Date.now();
    let m;
    try { m = JSON.parse(data.toString()); } catch { return; }
    if (!m || typeof m.t !== 'string') return;
    if (!c.name && m.t !== 'hello') return;
    const h = handlers[m.t];
    // one bad message must never take the server (and every room on it) down
    if (h) { try { h(c, m); } catch (e) { console.error('handler', m.t, e && e.stack); } }
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

setInterval(() => { // a phone that did not answer the last ping is gone: close it, so its name and room free up
  for (const ws of wss.clients) {
    const c = ws.c;
    if (c && !c.alive) { try { ws.terminate(); } catch (e) { /* gone */ } continue; }
    if (c) c.alive = false;
    try { ws.ping(); } catch (e) { /* closing */ }
  }
}, 15000);

// game loop: 10 ticks a second, snapshot 5 times a second (or right after an input)
let tickN = 0;
setInterval(() => {
  tickN++;
  for (const r of rooms.values()) {
    if (r.state !== 'game' || !r.rules || !r.rules.ready) continue;
    try { // a fault in one room's rules stays in that room
      for (const e of r.rules.tick(0.1)) broadcast(r, { t: 'ev', n: '', d: e }); // rescues finish inside the tick
      if (r.dirty || tickN % 2 === 0) {
        r.dirty = false;
        broadcast(r, { t: 'ev', n: '', d: r.rules.snapshot() });
      }
    } catch (e) { console.error('tick', r.code, e && e.stack); }
  }
}, 100);

server.listen(PORT, () => console.log('NightFall server on :' + PORT));
