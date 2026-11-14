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

  // --- map + theme are the host's choice and reach everyone ---
  ok(host.room.theme === 'normal', 'rooms start on the normal theme');
  host.send({ t: 'set', map: 'rubkhali' });
  host.send({ t: 'set', theme: 'snow' });
  await wait(200);
  ok(mate.room.map === 'rubkhali', 'the new desert map is allowed', mate.room.map);
  ok(mate.room.theme === 'snow', 'the theme reaches the other players', mate.room.theme);
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

  // --- play again puts everyone back in the same room ---
  host.send({ t: 'lobby' });
  await wait(200);
  ok(mate.room.state === 'lobby' && mate.room.code === code, 'play again keeps the same room', mate.room.code);
  ok(mate.room.players.length === 3, 'with the same players');

  for (const c of [host, mate, third]) c.ws.close();
  srv.kill();
  await wait(150);
  console.log(failures === 0 ? '\nall server checks passed' : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
})();
