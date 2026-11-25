// The other phone for tools/online.tscn: joins the Godot client's room as the survivor "Bot",
// stands by generator 2 (from /tmp/code.txt), keeps reporting its position and holding «تصليح».
// node tools/online_bot.js ws://127.0.0.1:8099
const fs = require('fs');
const WebSocket = require(process.env.WS_MODULE || 'ws');
const url = process.argv[2] || 'ws://127.0.0.1:8099';
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
(async () => {
  let line = '';
  for (let i = 0; i < 600 && !line; i++) { try { line = fs.readFileSync('/tmp/code.txt', 'utf8').trim(); } catch { } await wait(100); }
  if (!line) { console.log('B no room code'); process.exit(1); }
  const [code, x, y, z] = line.split(' ');
  const ws = new WebSocket(url);
  const send = (m) => ws.send(JSON.stringify(m));
  let started = false; let gens = null; let hp = '';
  ws.on('message', (d) => {
    const m = JSON.parse(d.toString());
    if (m.t === 'welcome') send({ t: 'join', code });
    if (m.t === 'started') { started = true; console.log('B started'); }
    if (m.t === 'ev' && m.d && m.d.k === 'gs') { gens = m.d.g; hp = m.d.s && m.d.s.Bot ? m.d.s.Bot[0] : hp; }
    if (m.t === 'ev' && m.d && m.d.k !== 'gs') console.log('B event', JSON.stringify(m.d));
  });
  await new Promise((r) => ws.on('open', r));
  send({ t: 'hello', name: 'Bot' });
  for (let i = 0; i < 600 && !started; i++) await wait(100);
  for (let k = 0; k < 400; k++) {
    send({ t: 'st', p: [Number(x), Number(y), Number(z), 0], a: 'repair', f: 0, v: 0, g: 0, gp: 0 });
    if (k % 5 === 0) send({ t: 'ev', d: { k: 'rep', i: 2, on: true } });
    if (k % 20 === 0) console.log('B gens', JSON.stringify(gens), 'hp', hp);
    await wait(100);
  }
  process.exit(0);
})();
