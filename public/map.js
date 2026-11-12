// خريطة اللعبة: مشتركة بين السيرفر والعميل (نفس الـ seed = نفس الخريطة عند الجميع)
(function (root) {
  const W = 2400, H = 1800, T = 40;

  const gens = [[520, 420], [1880, 460], [1200, 900], [480, 1380], [1920, 1360]].map(([x, y]) => ({ x, y }));
  const exits = [{ x: 1200, y: 100 }, { x: 1200, y: H - 100 }];
  const survSpawn = { x: 300, y: 900 };
  const killerSpawn = { x: 2100, y: 900 };

  const reserved = [
    ...gens.map(g => ({ x: g.x, y: g.y, r: 130 })),
    ...exits.map(e => ({ x: e.x, y: e.y, r: 150 })),
    { x: survSpawn.x, y: survSpawn.y, r: 200 },
    { x: killerSpawn.x, y: killerSpawn.y, r: 160 },
  ];

  function rng(a) {
    return function () {
      a |= 0; a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  const rand = rng(1337);

  // [x, y, w, h]
  const walls = [[0, 0, W, T], [0, H - T, W, T], [0, 0, T, H], [W - T, 0, T, H]];
  let tries = 0;
  while (walls.length < 4 + 36 && tries < 4000) {
    tries++;
    const horiz = rand() < 0.5;
    const w = horiz ? 120 + rand() * 230 : 34 + rand() * 20;
    const h = horiz ? 34 + rand() * 20 : 120 + rand() * 230;
    const x = T + 60 + rand() * (W - 2 * T - 120 - w);
    const y = T + 60 + rand() * (H - 2 * T - 120 - h);
    let ok = true;
    for (const c of reserved) {
      const cx = Math.max(x, Math.min(c.x, x + w));
      const cy = Math.max(y, Math.min(c.y, y + h));
      if ((cx - c.x) ** 2 + (cy - c.y) ** 2 < c.r * c.r) { ok = false; break; }
    }
    if (ok) walls.push([Math.round(x), Math.round(y), Math.round(w), Math.round(h)]);
  }

  const MAP = { W, H, T, walls, gens, exits, survSpawn, killerSpawn };
  if (typeof module !== 'undefined' && module.exports) module.exports = MAP;
  else root.MAP = MAP;
})(typeof window !== 'undefined' ? window : globalThis);
