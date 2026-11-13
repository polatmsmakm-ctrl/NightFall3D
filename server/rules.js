// Match rules (server authoritative). Mirrors scripts/rules.gd — keep the two in step.
const NEED = 5, GEN_TIME = 60, HEAL_TIME = 8, SELF_HEAL_TIME = 12, HOOK_TIME = [60, 30];
const BLEED_TIME = 120, HIT_COOLDOWN = 1.5, POWER_CD = 20, STUN_TIME = 2.5;
const MASH_STEP = 0.03, MASH_DECAY = 0.1; // "free yourself": keep tapping or the bar drains
const LIVE = ['ok', 'hurt', 'down', 'carried', 'hooked'];
const REACH = 4.5; // generous: positions arrive ~15 times a second

class Rules {
  constructor(players) {
    this.gens = []; this.gates = []; this.pallets = []; this.s = {}; this.roles = {};
    this.killer = ''; this.carrying = ''; this.stun = 0; this.powerCd = 0;
    this.healers = {}; this.lastHit = {}; this.powered = false; this.over = false; this.clock = 0;
    this.pos = {}; this.layout = null; this.ready = false; this.hatch = -1; this.score = {};
    for (const p of players) {
      this.roles[p.name] = p.role;
      this.score[p.name] = 0;
      if (p.role === 'killer') this.killer = p.name;
      else this.s[p.name] = { hp: 'ok', hooks: 0, hook_i: -1, t: 0, heal: 0, locker: -1, item: true, esc: 0, tap: 0 };
    }
  }
  setLayout(l) { // object positions, sent by the clients (they all generate the same map)
    if (this.ready || !l || !Array.isArray(l.g) || !Array.isArray(l.p) || !Array.isArray(l.h)) return;
    if (l.g.length > 16 || l.p.length > 32 || l.h.length > 16) return;
    this.layout = l;
    for (let i = 0; i < l.g.length; i++) this.gens.push({ p: 0, done: false, reps: {} });
    for (let i = 0; i < 2; i++) this.gates.push({ open: false });
    for (let i = 0; i < l.p.length; i++) this.pallets.push(0);
    this.ready = true;
  }
  add(name, pts) { if (name in this.score) this.score[name] += pts; }
  setPos(name, p) { this.pos[name] = p; }
  near(name, xz, r = REACH) {
    const a = this.pos[name];
    if (!a || !xz) return true; // no data yet: don't block play
    return Math.hypot(a[0] - xz[0], a[2] - xz[1]) <= r;
  }
  nearPlayer(a, b, r = REACH) {
    const p = this.pos[b];
    return p ? this.near(a, [p[0], p[2]], r) : true;
  }
  doneCount() { return this.gens.filter((g) => g.done).length; }
  hp(n) { return this.s[n] ? this.s[n].hp : ''; }
  freeNow(n) { const p = this.s[n]; return !!p && (p.hp === 'ok' || p.hp === 'hurt') && p.locker < 0; }
  lockerUser(i) { return Object.keys(this.s).find((n) => this.s[n].locker === i) || ''; }
  hookUser(i) { return Object.keys(this.s).find((n) => this.s[n].hp === 'hooked' && this.s[n].hook_i === i) || ''; }
  drop(n) { for (const g of this.gens) delete g.reps[n]; delete this.healers[n]; }
  down(n) { const p = this.s[n]; p.hp = 'down'; p.t = BLEED_TIME; p.heal = 0; this.drop(n); }

  handle(d, from) {
    if (this.over || !this.ready) return [];
    const out = [];
    const i = Number.isInteger(d.i) ? d.i : -1;
    const n = typeof d.n === 'string' ? d.n : '';
    const isKiller = from === this.killer;
    const L = this.layout;
    switch (d.k) {
      case 'rep':
        if (i >= 0 && i < this.gens.length) {
          if (d.on && this.freeNow(from) && !this.gens[i].done && !this.powered && this.near(from, L.g[i])) this.gens[i].reps[from] = true;
          else delete this.gens[i].reps[from];
        }
        break;
      case 'skill':
        if (i >= 0 && i < this.gens.length && this.gens[i].reps[from]) {
          if (d.ok) { this.gens[i].p = Math.min(this.gens[i].p + 0.03, 1); this.add(from, 5); }
          else { this.gens[i].p = Math.max(this.gens[i].p - 0.08, 0); out.push({ k: 'boom', i }); }
        }
        break;
      case 'escape':
        {
          const viaHatch = this.hatch >= 0 && d.h === true && this.near(from, (L.x || [])[this.hatch]);
          if (this.freeNow(from) && (this.powered || viaHatch)) { this.s[from].hp = 'escaped'; this.add(from, 150); this.drop(from); }
        }
        break;
      case 'hit':
        if (isKiller && this.stun <= 0 && this.carrying === '' && this.freeNow(n) && this.nearPlayer(from, n)
          && this.clock - (this.lastHit[n] ?? -99) > HIT_COOLDOWN) {
          this.lastHit[n] = this.clock;
          if (this.s[n].hp === 'ok') { this.s[n].hp = 'hurt'; this.s[n].heal = 0; this.drop(n); } else this.down(n);
          this.add(from, this.s[n].hp === 'hurt' ? 30 : 50);
          out.push({ k: 'hurt', n, s: this.s[n].hp });
        }
        break;
      case 'pickup':
        if (isKiller && this.stun <= 0 && this.carrying === '' && this.hp(n) === 'down' && this.nearPlayer(from, n)) {
          this.s[n].hp = 'carried'; this.carrying = n;
        }
        break;
      case 'hook':
        if (isKiller && this.carrying !== '' && i >= 0 && i < L.h.length && this.hookUser(i) === '' && this.near(from, L.h[i])) {
          const p = this.s[this.carrying];
          p.hooks += 1;
          if (p.hooks >= 3) p.hp = 'dead';
          else { p.hp = 'hooked'; p.hook_i = i; p.t = HOOK_TIME[p.hooks - 1]; p.esc = 0; }
          this.add(from, p.hp === 'hooked' ? 80 : 180);
          out.push({ k: 'hooked', n: this.carrying, s: p.hp });
          this.carrying = '';
        }
        break;
      case 'rescue':
        if (this.freeNow(from) && this.hp(n) === 'hooked' && this.near(from, L.h[this.s[n].hook_i])) {
          const p = this.s[n]; p.hp = 'hurt'; p.hook_i = -1; p.heal = 0;
          this.add(from, 60);
          out.push({ k: 'rescued', n, by: from });
        }
        break;
      case 'struggle': { // one tap; first hook only; ignores taps faster than a human thumb
        const p = this.s[from];
        const now = Date.now();
        if (p && p.hp === 'hooked' && p.hooks === 1 && now - p.tap >= 55) {
          p.tap = now;
          p.esc += MASH_STEP;
          if (p.esc >= 1) { p.hp = 'hurt'; p.hook_i = -1; p.heal = 0; p.esc = 0; this.add(from, 30); out.push({ k: 'rescued', n: from, by: from }); }
        }
        break;
      }
      case 'heal':
        if (d.on && this.freeNow(from)) {
          const p = this.s[n];
          if (n === from) { if (p.hp === 'hurt' && p.item) this.healers[from] = n; }
          else if (p && (p.hp === 'hurt' || p.hp === 'down') && p.locker < 0 && this.nearPlayer(from, n)) this.healers[from] = n;
        } else delete this.healers[from];
        break;
      case 'locker':
        if (d.on) {
          if (this.freeNow(from) && i >= 0 && i < 32 && this.lockerUser(i) === '') { this.drop(from); this.s[from].locker = i; }
        } else if (this.s[from]) this.s[from].locker = -1;
        break;
      case 'search':
        if (isKiller && this.stun <= 0 && this.carrying === '') {
          const who = this.lockerUser(i);
          if (who) { this.s[who].locker = -1; this.s[who].hp = 'carried'; this.drop(who); this.carrying = who; out.push({ k: 'grabbed', n: who }); }
          else out.push({ k: 'empty' });
        }
        break;
      case 'pallet':
        if (this.freeNow(from) && i >= 0 && i < this.pallets.length && this.pallets[i] === 0 && this.near(from, L.p[i])) {
          this.pallets[i] = 1;
          out.push({ k: 'pallet', i });
          if (this.killer && this.pos[this.killer] && this.near(this.killer, L.p[i], 2.3)) { this.stun = STUN_TIME; this.add(from, 50); out.push({ k: 'stun' }); }
        }
        break;
      case 'break':
        if (isKiller && i >= 0 && i < this.pallets.length && this.pallets[i] === 1 && this.near(from, L.p[i])) {
          this.pallets[i] = 2; this.add(from, 10); out.push({ k: 'broke', i });
        }
        break;
      case 'power':
        if (isKiller && this.powerCd <= 0 && this.stun <= 0 && this.carrying === '') { this.powerCd = POWER_CD; out.push({ k: 'power' }); }
        break;
    }
    return out;
  }

  leave(name) {
    if (name === this.killer) { // killer quit: everyone still alive gets out
      for (const n in this.s) if (LIVE.includes(this.s[n].hp)) this.s[n].hp = 'escaped';
      this.over = true;
    } else if (this.s[name]) {
      if (this.carrying === name) this.carrying = '';
      if (LIVE.includes(this.s[name].hp)) this.s[name].hp = 'dead';
      this.s[name].locker = -1;
      this.drop(name);
    }
  }

  tick(dt) {
    if (this.over || !this.ready) return;
    this.clock += dt;
    this.stun = Math.max(this.stun - dt, 0);
    this.powerCd = Math.max(this.powerCd - dt, 0);
    if (this.stun > 0 && this.carrying !== '') { this.down(this.carrying); this.carrying = ''; }
    for (const g of this.gens) {
      if (g.done || this.powered) continue;
      g.p += dt * Object.keys(g.reps).length / GEN_TIME;
      for (const r of Object.keys(g.reps)) this.add(r, dt * 100 / GEN_TIME);
      if (g.p >= 1) { g.p = 1; g.done = true; g.reps = {}; }
    }
    if (!this.powered && this.doneCount() >= NEED) {
      this.powered = true;
      for (const g of this.gens) g.reps = {};
      for (const g of this.gates) g.open = true;
    }
    for (const n in this.s) {
      const p = this.s[n];
      if (p.hp === 'hooked') p.esc = Math.max(p.esc - MASH_DECAY * dt, 0);
      if (p.hp === 'hooked' || p.hp === 'down') { p.t -= dt; if (p.t <= 0) { p.hp = 'dead'; this.add(this.killer, 100); } }
    }
    for (const h of Object.keys(this.healers)) {
      const tgt = this.healers[h];
      const p = this.s[tgt];
      const self = h === tgt;
      const valid = this.freeNow(h) && p && (p.hp === 'hurt' || (p.hp === 'down' && !self)) && (!self || p.item) && (self || this.nearPlayer(h, tgt));
      if (!valid) { delete this.healers[h]; continue; }
      p.heal += dt / (self ? SELF_HEAL_TIME : HEAL_TIME);
      if (p.heal >= 1) {
        p.heal = 0;
        p.hp = p.hp === 'down' ? 'hurt' : 'ok';
        this.add(h, self ? 20 : 40);
        if (self) p.item = false;
        delete this.healers[h];
      }
    }
    const names = Object.keys(this.s);
    const live = names.filter((n) => LIVE.includes(this.s[n].hp)).length;
    if (names.length > 0 && live === 0) this.over = true;
    else if (live === 1 && names.length > 1 && this.hatch < 0 && !this.powered && this.layout.x && this.layout.x.length > 0) {
      this.hatch = Math.floor(Math.random() * this.layout.x.length); // last one standing: a way out opens somewhere
    }
  }

  snapshot() {
    const r3 = (v) => Math.round(v * 1000) / 1000;
    const ss = {};
    for (const n in this.s) { const p = this.s[n]; ss[n] = [p.hp, p.hooks, p.hook_i, Math.ceil(p.t), r3(p.heal), p.locker, p.item, r3(p.esc)]; }
    return {
      k: 'gs', g: this.gens.map((g) => r3(g.p)), d: this.gens.map((g) => g.done), to: this.gates.map((g) => g.open),
      pw: this.powered, s: ss, pl: this.pallets, kc: this.carrying, ks: r3(this.stun), kp: Math.round(this.powerCd * 10) / 10, ov: this.over, hx: this.hatch,
      sc: Object.fromEntries(Object.entries(this.score).map(([n, v]) => [n, Math.round(v)])),
    };
  }
}
module.exports = { Rules };
