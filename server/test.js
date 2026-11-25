// Headless check of the room protocol: room code, join by code, theme, emote and signal relay.
// Run:  node server/test.js      (starts the real server on a spare port and talks to it)
const { spawn } = require('child_process');
const WebSocket = require('ws');

const PORT = 8711;
const URL = `ws://127.0.0.1:${PORT}`;
let failures = 0;

const ok = (cond, what, extra = '') => {
  console.log(`${cond ? 'ok  ' : 'FAIL'}  ${what}${extra ? '  ' + extra : ''}`);
  if (!cond) failures++;
};

function client(name) {
  const ws = new WebSocket(URL);
  const c = { ws, name, seen: [], room: null };
  ws.on('message', (d) => {
    const m = JSON.parse(d.toString());
    c.seen.push(m);
    if (m.t === 'room') c.room = m;
  });
  c.send = (o) => ws.send(JSON.stringify(o));
  c.ready = new Promise((res) => ws.on('open', () => { c.send({ t: 'hello', name, friends: [] }); res(); }));
  c.last = (t) => [...c.seen].reverse().find((m) => m.t === t);
  c.count = (t) => c.seen.filter((m) => m.t === t).length;
  return c;
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const srv = spawn(process.execPath, [`${__dirname}/server.js`], { env: { ...process.env, PORT: String(PORT) }, stdio: 'ignore' });
  await wait(700);
  const host = client('Rashid');
  const mate = client('Badr');
  const third = client('Yousef');
  await Promise.all([host.ready, mate.ready, third.ready]);
  await wait(150);

  // --- room code ---
  host.send({ t: 'create', map: 'forest' });
  await wait(200);
  const code = host.room && host.room.code;
  ok(/^\d{4,5}$/.test(String(code)), 'the room gets a 4-5 digit code', String(code));
  ok(host.room.host === 'Rashid', 'the maker is the host');

  // --- a friend joins by typing the code ---
  mate.send({ t: 'join', code });
  await wait(200);
  ok(mate.room && mate.room.code === code, 'a friend joins with the code alone');
  ok(host.room.players.length === 2, 'the host sees them in the room', String(host.room.players.length));
  third.send({ t: 'join', code: '0000' });
  await wait(200);
  ok(third.last('error') && third.last('error').code === 'no_room', 'a wrong code is refused');
  third.send({ t: 'join', code });
  await wait(200);
  ok(third.room && third.room.players.length === 3, 'a third player joins the same room');

  // --- the hidden character: never handed out, picked only on request, opened by a gift ---
  ok(host.room.players.every((p) => p.char !== 'survivor4'), 'nobody is given the hidden character on joining');
  mate.send({ t: 'gift', to: 'Rashid', on: true });
  await wait(200);
  const gift = host.last('gift');
  ok(gift && gift.from === 'Badr' && gift.on === true, 'a gift reaches the friend it is for', JSON.stringify(gift));
  mate.send({ t: 'set', char: 'survivor4' });
  await wait(200);
  ok(host.room.players.find((p) => p.name === 'Badr').char === 'survivor4', 'the hidden character can be picked by a phone that asks for it');

  // --- map + theme are the host's choice and reach everyone ---
  ok(host.room.theme === 'normal', 'rooms start on the normal theme');
  host.send({ t: 'set', map: 'rubkhali' });
  host.send({ t: 'set', theme: 'snow' });
  await wait(200);
  ok(mate.room.map === 'rubkhali', 'the new desert map is allowed', mate.room.map);
  ok(mate.room.theme === 'snow', 'the theme reaches the other players', mate.room.theme);
  host.send({ t: 'set', map: 'garage' });
  await wait(200);
  ok(mate.room.map === 'garage', 'the car park map is allowed', mate.room.map);
  host.send({ t: 'set', map: 'beach' });
  await wait(200);
  ok(mate.room.map === 'beach', 'the beach map is allowed', mate.room.map);
  host.send({ t: 'set', theme: 'fog' });
  await wait(200);
  ok(mate.room.theme === 'fog', 'the host can pick the foggy weather', mate.room.theme);
  host.send({ t: 'set', theme: 'snow' }); // back to what the rest of the checks expect
  await wait(150);
  host.send({ t: 'set', map: 'rubkhali' });
  await wait(150);
  mate.send({ t: 'set', theme: 'halloween' }); // not the host
  await wait(200);
  ok(host.room.theme === 'snow', 'only the host changes the theme');

  // --- campfire emotes are relayed to the rest of the room ---
  const before = mate.count('emote');
  host.send({ t: 'emote', k: 1 });
  await wait(200);
  const em = mate.last('emote');
  ok(mate.count('emote') === before + 1 && em.n === 'Rashid' && em.k === 1, 'an emote reaches the others', JSON.stringify(em));
  ok(host.count('emote') === 0, 'the sender does not get their own emote back');

  // --- start carries map, theme and seed ---
  host.send({ t: 'start' });
  await wait(250);
  const st = mate.last('started');
  ok(!!st && st.map === 'rubkhali' && st.theme === 'snow' && Number.isFinite(st.seed), 'start sends map + theme + seed', JSON.stringify({ map: st && st.map, theme: st && st.theme }));
  ok(st.players.length === 3, 'everyone is in the player list');

  // --- quick signals only reach your own side ---
  const killer = st.players.find((p) => p.role === 'killer').name;
  const survivors = st.players.filter((p) => p.role !== 'killer').map((p) => p.name);
  const byName = { Rashid: host, Badr: mate, Yousef: third };
  const sender = byName[survivors[0]];
  const mateSurv = byName[survivors[1]];
  const theKiller = byName[killer];
  const kBefore = theKiller.count('sig');
  sender.send({ t: 'sig', k: 1, p: [10, -4] });
  await wait(200);
  ok(mateSurv.count('sig') === 1, 'a survivor signal reaches the other survivor');
  ok(theKiller.count('sig') === kBefore, 'the killer never sees survivor signals');

  // --- the round's event and the call to prayer come from the room seed ---
  const { Rules } = require(`${__dirname}/rules.js`);
  const r1 = new Rules(st.players, st.seed);
  const r2 = new Rules(st.players, st.seed);
  ok(r1.evKind === r2.evKind && r1.evAt === r2.evAt && r1.adhanAt === r2.adhanAt,
    'the same seed plans the same event for everyone', `event ${r1.evKind} at ${r1.evAt}s, adhan at ${r1.adhanAt}s`);
  ok(r1.evKind >= 0 && r1.evKind <= 2 && r1.evAt >= 60 && r1.evAt <= 180, 'the event lands between 1 and 3 minutes');
  r1.setLayout({ g: [[0, 0]], p: [[1, 1]], h: [[2, 2]], x: [[3, 3]], d: [[4, 4], [5, 5]] });
  ok(r1.doors.length === 2, 'the doors come from the layout the clients send');
  r1.clock = r1.evAt + 0.01;
  r1.tick(0.1);
  const snap = r1.snapshot();
  ok(snap.ek === r1.evKind && snap.et > 0, 'the snapshot carries the running event', JSON.stringify({ ek: snap.ek, et: snap.et }));
  r1.clock = r1.adhanAt + 0.01;
  r1.tick(0.1);
  ok(r1.snapshot().ad === 1, 'and the call to prayer');

  // --- a door swings for everyone (the clients send the map layout first, as the game does) ---
  host.send({ t: 'layout', d: { g: [[0, 0], [8, 8]], p: [[1, 1]], h: [[2, 2]], x: [[3, 3]], d: [[4, 4], [5, 5]] } });
  await wait(250);
  // --- a door swings for everyone ---
  const killerName = st.players.find((p) => p.role === 'killer').name;
  const byName2 = { Rashid: host, Badr: mate, Yousef: third };
  const doorMan = byName2[killerName];
  const watcher = byName2[st.players.find((p) => p.role !== 'killer').name];
  const evBefore = watcher.count('ev');
  doorMan.send({ t: 'ev', d: { k: 'door', i: 0, on: true } });
  await wait(250);
  const doorEv = [...watcher.seen].reverse().find((m) => m.t === 'ev' && m.d && m.d.k === 'door');
  ok(!!doorEv && doorEv.d.on === true, 'closing a door reaches the other players', JSON.stringify(doorEv && doorEv.d));
  const gs = [...watcher.seen].reverse().find((m) => m.t === 'ev' && m.d && m.d.k === 'gs');
  ok(!!gs && Array.isArray(gs.d.dr) && gs.d.dr[0] === true, 'the snapshot carries the door states',
    gs ? JSON.stringify(gs.d.dr) : '-');
  ok(watcher.count('ev') > evBefore, 'the room keeps getting snapshots');

  // --- two survivors get someone off the hook faster than one (same numbers as rules.gd) ---
  const timeRescue = (hands) => {
    const pl = [{ name: 'K', role: 'killer' }, { name: 'A', role: 'survivor' }, { name: 'B', role: 'survivor' },
      { name: 'C', role: 'survivor' }, { name: 'D', role: 'survivor' }];
    const r = new Rules(pl, 777);
    r.setLayout({ g: [[0, 0]], p: [[1, 1]], h: [[0, 0]], x: [[3, 3]], d: [[4, 4]] });
    for (const n of ['A', 'B', 'C', 'D']) r.setPos(n, [0, 0, 0, 0]);
    Object.assign(r.s.C, { hp: 'hooked', hooks: 1, hook_i: 0, t: 60 });
    for (const n of ['A', 'B', 'D'].slice(0, hands)) r.handle({ k: 'rescue', n: 'C', on: true }, n);
    for (let took = 0; took < 6; took += 0.1) {
      const ev = r.tick(0.1).find((e) => e.k === 'rescued');
      if (ev) return { took: Math.round((took + 0.1) * 10) / 10, hands: ev.hands };
    }
    return { took: -1, hands: 0 };
  };
  const one = timeRescue(1);
  const two = timeRescue(2);
  ok(one.took === 2.0 && one.hands === 1, 'one survivor takes two seconds to unhook', `${one.took}s`);
  ok(two.took < one.took && two.hands === 2, 'two survivors do it faster, and the event says how many',
    `${two.took}s with ${two.hands} hands`);
  const rs = new Rules([{ name: 'K', role: 'killer' }, { name: 'A', role: 'survivor' }, { name: 'C', role: 'survivor' }], 5);
  rs.setLayout({ g: [[0, 0]], p: [[1, 1]], h: [[0, 0]], x: [[3, 3]], d: [[4, 4]] });
  Object.assign(rs.s.C, { hp: 'hooked', hooks: 1, hook_i: 0, t: 60 });
  rs.handle({ k: 'rescue', n: 'C', on: true }, 'A');
  rs.tick(0.4);
  const row = rs.snapshot().s.C;
  ok(row[8] > 0 && row[9] === 1, 'the snapshot carries the unhook progress and the hands on it', JSON.stringify([row[8], row[9]]));

  // --- play again puts everyone back in the same room ---
  host.send({ t: 'lobby' });
  await wait(200);
  ok(mate.room.state === 'lobby' && mate.room.code === code, 'play again keeps the same room', mate.room.code);
  ok(mate.room.players.length === 3, 'with the same players');

  // --- «وضع السلاح»: a stun gun for the survivors, three shots, a hit leaves her dizzy ---
  const rg = new Rules([{ name: 'K', role: 'killer' }, { name: 'A', role: 'survivor' }], 5, { gun: true });
  rg.setLayout({ g: [[0, 0]], p: [[1, 1]], h: [[0, 0]], x: [[3, 3]], d: [[4, 4]] });
  rg.pos.K = [5, 0, 0]; rg.pos.A = [0, 0, 0];
  const sh = rg.handle({ k: 'shoot', hit: true }, 'A');
  ok(sh.some((e) => e.k === 'shot' && e.hit) && rg.stun === 3 && rg.s.A.ammo === 2, 'a hit stuns her for 3 s and costs a shot', JSON.stringify(sh));
  rg.stun = 0; rg.pos.K = [60, 0, 0];
  rg.handle({ k: 'shoot', hit: true }, 'A');
  ok(rg.stun === 0 && rg.s.A.ammo === 1, 'out of range it misses, whatever the phone says');
  rg.handle({ k: 'shoot', hit: false }, 'A'); rg.handle({ k: 'shoot', hit: true }, 'A');
  ok(rg.s.A.ammo === 0, 'three shots and the gun is empty');
  ok(rg.snapshot().s.A[13] === 0 && rg.snapshot().gn === true, 'the snapshot carries the shots left and the mode');
  const rn = new Rules([{ name: 'K', role: 'killer' }, { name: 'A', role: 'survivor' }], 5);
  rn.setLayout({ g: [[0, 0]], p: [[1, 1]], h: [[0, 0]], x: [[3, 3]], d: [[4, 4]] });
  ok(rn.handle({ k: 'shoot', hit: true }, 'A').length === 0, 'no gun outside the mode');
  host.send({ t: 'set', gun: true });
  await wait(150);
  ok(mate.room.gun === true, 'the host switches the gun mode on for the room');

  // --- friends: where they are, invites that wait, the profile line ---
  const fa = client('Saud');
  await fa.ready;
  fa.send({ t: 'friends', friends: ['Rashid', 'Ghanim'] });
  await wait(150);
  const fl = fa.last('friends');
  ok(fl && fl.status && fl.status.Rashid === 'room', 'a friend in a room shows as «in a room»', JSON.stringify(fl && fl.status));
  host.send({ t: 'invite', to: 'Ghanim' });
  await wait(150);
  ok(host.last('error') && host.last('error').code === 'invite_later', 'an invite to an offline friend is kept');
  const gh = client('Ghanim');
  await gh.ready;
  await wait(200);
  ok(gh.last('invite') && gh.last('invite').from === 'Rashid' && gh.last('invite').later, 'and handed over when he comes online');
  fa.send({ t: 'stats', s: { lv: 3, xp: 10, esc: 1, kills: 0, rounds: 2, ch: 'survivor6', bio: 'هلا <b>' } });
  host.send({ t: 'friends', friends: ['Saud'] });
  await wait(200);
  const sr = (host.last('friends').stats || []).find((x) => x.name === 'Saud');
  ok(sr && sr.ch === 'survivor6' && sr.bio === 'هلا b', 'the profile carries the character and a clean line', JSON.stringify(sr));
  fa.ws.close(); gh.ws.close();

  // --- a phone coming back after its connection dropped: it takes its own name back ---
  const a1 = client('Mubarak');
  await a1.ready; await wait(150);
  let a1closed = false; a1.ws.on('close', () => { a1closed = true; });
  const a2 = client('Mubarak'); // the same phone (same address), its old socket not noticed dead yet
  await a2.ready; await wait(250);
  ok(a2.count('welcome') === 1 && !a2.last('error'), 'a reconnecting phone gets its name back (no «name taken»)');
  ok(a1closed, 'and the old socket is closed');
  a2.ws.close();
  // one bad message does not take the server down
  host.send({ t: 'layout', d: { g: null } }); host.send({ t: 'set', role: { x: 1 } }); host.send({ t: 'ev', d: { k: 'hit', n: {} } });
  await wait(200);
  const after = client('Ali'); await after.ready; await wait(150);
  ok(after.count('welcome') === 1, 'the server is still up after malformed messages');
  after.ws.close();

  for (const c of [host, mate, third]) c.ws.close();
  srv.kill();
  await wait(150);
  console.log(failures === 0 ? '\nall server checks passed' : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
})();
