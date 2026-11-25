// The other phone for tools/online.tscn. Reads "code x y z mode" from /tmp/code.txt, joins that
// room as "Bot" and plays its part:
//   forest / kuwait-sniper — a survivor standing at (x, y, z); in forest it holds «تصليح» on generator 2
//   forest-surv            — the killer: walks to "Tester" (from the relayed positions) and swings
// It logs every server event it receives (B event ...), so the CI log shows both phones' view.
// node tools/online_bot.js ws://127.0.0.1:8099
const fs = require('fs');
const WebSocket = require(process.env.WS_MODULE || 'ws');
const url = process.argv[2] || 'ws://127.0.0.1:8099';
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
(async () => {
  let line = '';
  for (let i = 0; i < 1200 && !line; i++) { try { line = fs.readFileSync('/tmp/code.txt', 'utf8').trim(); } catch { } await wait(100); }
  if (!line) { console.log('B no room code'); process.exit(1); }
  const [code, x, y, z, mode = 'forest'] = line.split(' ');
  const ws = new WebSocket(url);
  const send = (m) => ws.send(JSON.stringify(m));
  let started = false; let gens = null; let hp = ''; let role = ''; let tester = null;
  ws.on('message', (d) => {
    const m = JSON.parse(d.toString());
    if (m.t === 'welcome') send({ t: 'join', code });
    if (m.t === 'room' && Array.isArray(m.players)) { const me = m.players.find((p) => p.name === 'Bot'); if (me) role = me.role; }
    if (m.t === 'started') { started = true; console.log('B started', mode, 'as', role, 'sniper', !!m.sniper); }
    if (m.t === 'st' && m.n === 'Tester') tester = m.p;
    if (m.t === 'ev' && m.d && m.d.k === 'gs') { gens = m.d.g; hp = m.d.s && m.d.s.Bot ? m.d.s.Bot[0] : hp; }
    if (m.t === 'ev' && m.d && m.d.k !== 'gs') console.log('B event', JSON.stringify(m.d));
  });
  ws.on('close', (c) => console.log('B closed', c));
  await new Promise((r) => ws.on('open', r));
  send({ t: 'hello', name: 'Bot' });
  for (let i = 0; i < 1200 && !started; i++) await wait(100);
  if (!started) { console.log('B never started (role ' + role + ')'); process.exit(1); }
  const pos = [Number(x), Number(y), Number(z), 0];
  let lastHit = 0;
  for (let k = 0; k < 1200; k++) {
    let anim = 'idle';
    if (role === 'killer' && tester) { // walk at 4.6 m/s toward the survivor and swing within reach
      const dx = tester[0] - pos[0]; const dz = tester[2] - pos[2]; const dist = Math.hypot(dx, dz);
      if (dist > 1.6) { const s = Math.min(0.46, dist - 1.5); pos[0] += dx / dist * s; pos[2] += dz / dist * s; pos[1] = tester[1]; anim = 'run'; }
      pos[3] = Math.atan2(dx, dz);
      if (dist < 2.2 && Date.now() - lastHit > 2500) { lastHit = Date.now(); send({ t: 'ev', d: { k: 'hit', n: 'Tester' } }); anim = 'attack'; }
    } else if (mode === 'forest') {
      anim = 'repair';
      if (k % 5 === 0) send({ t: 'ev', d: { k: 'rep', i: 2, on: true } });
    }
    send({ t: 'st', p: pos.map((v) => Math.round(v * 100) / 100), a: anim, f: 0, v: 0, g: 0, gp: 0 });
    if (k % 20 === 0) console.log('B', role, 'gens', JSON.stringify(gens), 'hp', hp, 'at', pos.map((v) => v.toFixed(1)).join(','));
    await wait(100);
  }
  process.exit(0);
})();
