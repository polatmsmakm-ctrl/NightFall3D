// Match rules (server authoritative). Mirrors scripts/rules.gd — keep the two in step.
const NEED = 5, GEN_TIME = 60, HEAL_TIME = 8, SELF_HEAL_TIME = 12, HOOK_TIME = [60, 30];
const BLEED_TIME = 120, HIT_COOLDOWN = 1.5, POWER_CD = 20, STUN_TIME = 2.5;
const LIVE = ['ok', 'hurt', 'down', 'carried', 'hooked'];
const REACH = 4.5; // generous: positions arrive ~15 times a second

class Rules {
  constructor(players) {
    this.gens = []; this.gates = []; this.pallets = []; this.s = {}; this.roles = {};
    this.killer = ''; this.carrying = ''; this.stun = 0; this.powerCd = 0;
    this.healers = {}; this.lastHit = {}; this.powered = false; this.over = false; this.clock = 0;
    this.pos = {}; this.layout = null; this.ready = false;
    for (const p of players) {
      this.roles[p.name] = p.role;
      if (p.role === 'killer') this.killer = p.name;
      else this.s[p.name] = { hp: 'ok', hooks: 0, hook_i: -1, t: 0, heal: 0, locker: -1, item: true };
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
          if (d.ok) this.gens[i].p = Math.min(this.gens[i].p + 0.03, 1);
          else { this.gens[i].p = Math.max(this.gens[i].p - 0.08, 0); out.push({ k: 'boom', i }); }
        }
        break;
      case 'escape':
        if (this.freeNow(from) && this.powered) { this.s[from].hp = 'escaped'; this.drop(from); }
        break;
      case 'hit':
        if (isKiller && this.stun <= 0 && this.carrying === '' && this.freeNow(n) && this.nearPlayer(from, n)
          && this.clock - (this.lastHit[n] ?? -99) > HIT_COOLDOWN) {
          this.lastHit[n] = this.clock;
          if (this.s[n].hp === 'ok') { this.s[n].hp = 'hurt'; this.s[n].heal = 0; this.drop(n); } else this.down(n);
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
          else { p.hp = 'hooked'; p.hook_i = i; p.t = HOOK_TIME[p.hooks - 1]; }
          out.push({ k: 'hooked', n: this.carrying, s: p.hp });
          this.carrying = '';
        }
        break;
      case 'rescue':
        if (this.freeNow(from) && this.hp(n) === 'hooked' && this.near(from, L.h[this.s[n].hook_i])) {
          const p = this.s[n]; p.hp = 'hurt'; p.hook_i = -1; p.heal = 0;
          out.push({ k: 'rescued', n, by: from });
        }
        break;
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
          if (this.killer && this.pos[this.killer] && this.near(this.killer, L.p[i], 2.3)) { this.stun = STUN_TIME; out.push({ k: 'stun' }); }
        }
        break;
      case 'break':
        if (isKiller && i >= 0 && i < this.pallets.length && this.pallets[i] === 1 && this.near(from, L.p[i])) {
          this.pallets[i] = 2; out.push({ k: 'broke', i });
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
      if (g.p >= 1) { g.p = 1; g.done = true; g.reps = {}; }
    }
    if (!this.powered && this.doneCount() >= NEED) {
      this.powered = true;
      for (const g of this.gens) g.reps = {};
      for (const g of this.gates) g.open = true;
    }
    for (const n in this.s) {
      const p = this.s[n];
      if (p.hp === 'hooked' || p.hp === 'down') { p.t -= dt; if (p.t <= 0) p.hp = 'dead'; }
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
        if (self) p.item = false;
        delete this.healers[h];
      }
    }
    const names = Object.keys(this.s);
    if (names.length > 0 && !names.some((n) => LIVE.includes(this.s[n].hp))) this.over = true;
  }

  snapshot() {
    const r3 = (v) => Math.round(v * 1000) / 1000;
    const ss = {};
    for (const n in this.s) { const p = this.s[n]; ss[n] = [p.hp, p.hooks, p.hook_i, Math.ceil(p.t), r3(p.heal), p.locker, p.item]; }
    return {
      k: 'gs', g: this.gens.map((g) => r3(g.p)), d: this.gens.map((g) => g.done), to: this.gates.map((g) => g.open),
      pw: this.powered, s: ss, pl: this.pallets, kc: this.carrying, ks: r3(this.stun), kp: Math.round(this.powerCd * 10) / 10, ov: this.over,
    };
  }
}
module.exports = { Rules };
