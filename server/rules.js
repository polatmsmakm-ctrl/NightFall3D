// Match rules (server authoritative). Mirrors scripts/rules.gd — keep the two in step.
const NEED = 5, GEN_TIME = 60, HEAL_TIME = 8, SELF_HEAL_TIME = 12, HOOK_TIME = [60, 30];
const BLEED_TIME = 120, HIT_COOLDOWN = 1.5, POWER_CD = 20, STUN_TIME = 2.5;
// «وضع السلاح» (the host's choice): every survivor carries a stun gun with GUN_SHOTS shots for the round;
// a hit within GUN_RANGE leaves the killer dizzy for GUN_STUN seconds (she drops whoever she carries)
const GUN_SHOTS = 3, GUN_RANGE = 22, GUN_STUN = 3;
const DOOM_TIME = 120; // once the gates have power the moon falls: this long to get out
const MASH_STEP = 0.03, MASH_DECAY = 0.1;
const RESCUE_TIME = 2; // seconds to lift someone off a hook; two of you halve it // "free yourself": keep tapping or the bar drains
const LIVE = ['ok', 'hurt', 'down', 'carried', 'hooked'];
// one random event per round, picked from the seed so every client agrees (mirrors rules.gd)
const EVENT_LEN = [20, 40, 5]; // 0 blackout, 1 heavy fog, 2 alarm
const ADHAN_LEN = 55;          // the length of assets/sfx/adhan.mp3
const REACH = 4.5; // generous: positions arrive ~15 times a second
const CAR_SEATS = 6; // an escape car seats six: every survivor a room can have
const ROAD_TIME = 120; // from the first one getting into a gate's escape car to the last gate, 600 m on
// one ability per survivor character (same table and numbers as rules.gd)
const PERK = { survivor1: 'burst', survivor2: 'fix', survivor3: 'lift', survivor4: 'rise',
  survivor5: 'tough', survivor6: 'sense', survivor7: 'medic', survivor8: 'ghost', survivor9: 'mend' };
const MEND_TIME = 45; // «تفتّح»: Bloom, hurt and left alone this long, mends herself
const FIX_MUL = 1.3, MEDIC_MUL = 1.6, LIFT_W = 1.8, RISE_TIME = 20;
const TRAPS = 4, HELD_TIME = 4; // the killer's traps armed at once; caught in one: held this long

class Rules {
  constructor(players, seed = 0, opts = {}) {
    this.gun = !!(opts && opts.gun);
    this.gens = []; this.gates = []; this.pallets = []; this.s = {}; this.roles = {};
    this.killer = ''; this.carrying = ''; this.stun = 0; this.powerCd = 0;
    this.healers = {}; this.rescuers = {}; this.lastHit = {}; this.powered = false; this.doom = -1; this.over = false; this.clock = 0;
    this.pos = {}; this.layout = null; this.ready = false; this.hatch = -1; this.score = {};
    this.doors = [];                        // every doorway: true when the leaf is shut
    // the escape car behind each gate: st 0 waiting, 1 on the road, 2 caught, 3 through the last gate
    this.roads = [];                        // {st, drv, who, t, why, cp, flat}
    this.perk = {};                         // survivor -> perk id
    this.traps = []; this.trapK = 0;        // [x, z, armed], TRAPS slots reused oldest first
    this.spikes = [];                       // per road: [x, z, armed]
    const sd = Math.abs(Math.floor(seed));
    this.evKind = sd % 3;                   // which event this round will bring
    this.evAt = 60 + (Math.floor(sd / 3) % 121);
    this.evT = 0; this.evN = ''; this.evFired = false;
    this.adhanAt = 40 + (Math.floor(sd / 379) % 151);
    this.adhan = 0;                         // 0 not yet, 1 playing, 2 done
    for (const p of players) {
      this.roles[p.name] = p.role;
      this.score[p.name] = 0;
      if (p.role === 'killer') this.killer = p.name;
      else {
        const pk = PERK[p.char] || '';
        this.perk[p.name] = pk;
        this.s[p.name] = { hp: 'ok', hooks: 0, hook_i: -1, t: 0, heal: 0, locker: -1, item: true, esc: 0, resc: 0, tap: 0, car: -1,
          held: 0, shield: pk === 'tough', risen: false, rt: 0, ammo: this.gun ? GUN_SHOTS : 0 };
      }
    }
  }
  setLayout(l) { // object positions, sent by the clients (they all generate the same map)
    if (this.ready || !l || !Array.isArray(l.g) || !Array.isArray(l.p) || !Array.isArray(l.h)) return;
    if (l.g.length > 16 || l.p.length > 32 || l.h.length > 48) return; // 9 hooks in the map + 9 along each road
    this.layout = l;
    for (let i = 0; i < l.g.length; i++) this.gens.push({ p: 0, done: false, reps: {} });
    for (let i = 0; i < 2; i++) {
      this.gates.push({ open: false });
      this.roads.push({ st: 0, drv: '', who: [], t: ROAD_TIME, why: '', cp: null, flat: false });
      this.spikes.push([0, 0, false]);
    }
    for (let i = 0; i < l.p.length; i++) this.pallets.push(0);
    const doors = Array.isArray(l.d) ? l.d.length : 0;
    for (let i = 0; i < Math.min(doors, 40); i++) this.doors.push(false);
    this.ready = true;
  }
  add(name, pts) { if (name in this.score) this.score[name] += pts; }
  setPos(name, p) {
    this.pos[name] = p;
    for (const r of this.roads) if (r.drv === name && r.st === 1) r.cp = [p[0], p[2]]; // the driver is where the car is
  }
  carPos(i) { // where a gate's escape car is now: with its driver, or where it was left, or where it waits
    const r = this.roads[i];
    if (r.drv && this.pos[r.drv] && r.st === 1) return [this.pos[r.drv][0], this.pos[r.drv][2]];
    return r.cp || ((this.layout && this.layout.c) || [])[i];
  }
  arrive(i) { // the driver reached the last gate: everyone in the car is out
    const r = this.roads[i];
    r.st = 3;
    for (const n of r.who) {
      const p = this.s[n];
      if (!p) continue;
      if (p.hp === 'ok' || p.hp === 'hurt') { p.hp = 'escaped'; this.add(n, 200); }
      p.car = -1;
    }
    return { k: 'arrive', i, who: r.who.slice() };
  }
  caught(i, why) { // the car stops dead and everyone in it is thrown out onto the road, down
    const r = this.roads[i];
    r.st = 2; r.why = why;
    for (const n of r.who) {
      const p = this.s[n];
      if (!p) continue;
      p.car = -1;
      if (p.hp === 'ok' || p.hp === 'hurt') { this.down(n); this.add(this.killer, 60); }
    }
    return { k: 'caught', i, why, who: r.who.slice() };
  }
  near(name, xz, r = REACH) {
    const a = this.pos[name];
    if (!a || !xz) return true; // no data yet: don't block play
    return Math.hypot(a[0] - xz[0], a[2] - xz[1]) <= r;
  }
  nearPlayer(a, b, r = REACH) {
    const p = this.pos[b];
    return p ? this.near(a, [p[0], p[2]], r) : true;
  }
  handsOn(name) { // how many survivors are pulling on the same hooked player
    let n = 0;
    for (const r of Object.keys(this.rescuers)) if (this.rescuers[r] === name) n++;
    return n;
  }
  doneCount() { return this.gens.filter((g) => g.done).length; }
  hp(n) { return this.s[n] ? this.s[n].hp : ''; }
  freeNow(n) { const p = this.s[n]; return !!p && (p.hp === 'ok' || p.hp === 'hurt') && p.locker < 0 && p.car < 0; }
  lockerUser(i) { return Object.keys(this.s).find((n) => this.s[n].locker === i) || ''; }
  hookUser(i) { return Object.keys(this.s).find((n) => this.s[n].hp === 'hooked' && this.s[n].hook_i === i) || ''; }
  drop(n) { for (const g of this.gens) delete g.reps[n]; delete this.healers[n]; delete this.rescuers[n]; }
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
      case 'board': // into the escape car past a gate: the first one in drives, the rest ride with them
        if (this.powered && i >= 0 && i < this.roads.length && this.freeNow(from) && this.roads[i].st <= 1 && this.roads[i].who.length < CAR_SEATS && this.near(from, this.carPos(i), 6)) {
          const r = this.roads[i];
          if (r.st === 0) { r.st = 1; r.t = ROAD_TIME; r.drv = from; }
          r.who.push(from);
          this.s[from].car = i;
          this.drop(from);
          out.push({ k: 'board', i, n: from, drv: r.drv === from });
        }
        break;
      case 'arrive':
        if (i >= 0 && i < this.roads.length && this.roads[i].st === 1 && this.roads[i].drv === from && this.near(from, (L.e || [])[i], 14)) out.push(this.arrive(i));
        break;
      case 'ram': // the killer's car hit the escape car
        if (isKiller && i >= 0 && i < this.roads.length && this.roads[i].st === 1 && this.near(from, this.carPos(i), 8)) out.push(this.caught(i, 'ram'));
        break;
      case 'escape':
        {
          const viaHatch = this.hatch >= 0 && d.h === true && this.near(from, (L.x || [])[this.hatch]);
          // on foot through the far gate at the end of a road (the car is the usual way)
          const atEnd = !L.e || L.e.some((e) => this.near(from, e, 10));
          if (this.freeNow(from) && ((this.powered && atEnd) || viaHatch)) { this.s[from].hp = 'escaped'; this.add(from, 150); this.drop(from); }
        }
        break;
      case 'hit':
        if (isKiller && this.stun <= 0 && this.carrying === '' && this.freeNow(n) && this.nearPlayer(from, n)
          && this.clock - (this.lastHit[n] ?? -99) > HIT_COOLDOWN) {
          this.lastHit[n] = this.clock;
          if (this.s[n].shield) { this.s[n].shield = false; out.push({ k: 'shield', n }); break; } // the first blow does nothing
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
      case 'rescue': // hold it: two survivors on the same hook get them down twice as fast
        if (d.on && this.freeNow(from) && this.hp(n) === 'hooked' && this.near(from, L.h[this.s[n].hook_i])) this.rescuers[from] = n;
        else delete this.rescuers[from];
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
          else if (p && (p.hp === 'hurt' || p.hp === 'down') && p.locker < 0 && p.car < 0 && this.nearPlayer(from, n)) this.healers[from] = n;
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
      case 'shoot': // a survivor fires the stun gun; their phone says whether it hit her (positions are the phones' anyway)
        if (this.gun && !isKiller && this.freeNow(from) && this.s[from].ammo > 0) {
          this.s[from].ammo -= 1;
          const hit = !!d.hit && this.killer && this.pos[this.killer] && this.nearPlayer(from, this.killer, GUN_RANGE) && this.stun <= 0;
          if (hit) { this.stun = GUN_STUN; this.add(from, 60); }
          out.push({ k: 'shot', n: from, hit: !!hit, left: this.s[from].ammo });
          if (hit) out.push({ k: 'stun', by: 'gun' });
        }
        break;
      case 'break':
        if (isKiller && i >= 0 && i < this.pallets.length && this.pallets[i] === 1 && this.near(from, L.p[i])) {
          this.pallets[i] = 2; this.add(from, 10); out.push({ k: 'broke', i });
        }
        break;
      case 'door': { // anyone can swing a door shut or open again
        const shut = !!d.on;
        if (i >= 0 && i < this.doors.length && (isKiller || this.freeNow(from)) && this.near(from, L.d && L.d[i])) {
          if (this.doors[i] !== shut) { this.doors[i] = shut; out.push({ k: 'door', i, on: shut, by: from }); }
        }
        break;
      }
      case 'trap': { // the killer sets a trap at her feet
        const tp = d.p;
        if (isKiller && this.stun <= 0 && this.carrying === '' && Array.isArray(tp) && tp.length >= 2 && tp.every((v) => typeof v === 'number') && this.near(from, tp, 4)) {
          let k = this.trapK % TRAPS;
          this.trapK += 1;
          const e = [Math.round(tp[0] * 100) / 100, Math.round(tp[1] * 100) / 100, true, Math.round((tp[2] || 0) * 100) / 100];
          if (k < this.traps.length) this.traps[k] = e; else { k = this.traps.length; this.traps.push(e); }
          out.push({ k: 'trap', i: k });
        }
        break;
      }
      case 'snap': // a survivor's own phone: I stepped into trap i
        if (this.freeNow(from) && i >= 0 && i < this.traps.length && this.traps[i][2] && this.near(from, this.traps[i], 2.5)) {
          this.traps[i][2] = false; this.s[from].held = HELD_TIME; this.drop(from); this.add(this.killer, 25);
          out.push({ k: 'snap', i, n: from });
        }
        break;
      case 'disarm':
        if (this.freeNow(from) && i >= 0 && i < this.traps.length && this.traps[i][2] && this.near(from, this.traps[i], 3)) {
          this.traps[i][2] = false; this.add(from, 15); out.push({ k: 'disarm', i, n: from });
        }
        break;
      case 'spike': { // a strip of spikes across escape road i (laying it again moves it)
        const sp = d.p;
        if (isKiller && this.stun <= 0 && this.carrying === '' && i >= 0 && i < this.roads.length && this.roads[i].st <= 1 && Array.isArray(sp) && sp.length >= 2 && typeof sp[0] === 'number' && typeof sp[1] === 'number' && this.near(from, sp, 4)) {
          this.spikes[i] = [Math.round(sp[0] * 100) / 100, Math.round(sp[1] * 100) / 100, true];
          out.push({ k: 'spike', i });
        }
        break;
      }
      case 'pop': // the escape car's driver: we went over the spikes
        if (i >= 0 && i < this.roads.length && this.roads[i].st === 1 && this.roads[i].drv === from && this.spikes[i][2] && this.near(from, this.spikes[i], 10)) {
          this.spikes[i][2] = false; this.roads[i].flat = true; this.add(this.killer, 40); out.push({ k: 'pop', i });
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
      for (const r of this.roads) { // out of the escape car; the next one in takes the wheel
        const k = r.who.indexOf(name);
        if (k < 0) continue;
        r.who.splice(k, 1);
        if (r.drv === name) r.drv = r.who[0] || '';
        this.s[name].car = -1;
      }
      if (LIVE.includes(this.s[name].hp)) this.s[name].hp = 'dead';
      this.s[name].locker = -1;
      this.drop(name);
    }
  }

  tick(dt) {
    const out = [];
    if (this.over || !this.ready) return out;
    this.clock += dt;
    this.stun = Math.max(this.stun - dt, 0);
    this.powerCd = Math.max(this.powerCd - dt, 0);
    if (this.stun > 0 && this.carrying !== '') { this.down(this.carrying); this.carrying = ''; }
    for (const g of this.gens) {
      if (g.done || this.powered) continue;
      let w = 0;
      for (const r of Object.keys(g.reps)) w += this.perk[r] === 'fix' ? FIX_MUL : 1;
      g.p += dt * w / GEN_TIME;
      for (const r of Object.keys(g.reps)) this.add(r, dt * 100 / GEN_TIME);
      if (g.p >= 1) { g.p = 1; g.done = true; g.reps = {}; }
    }
    if (!this.powered && this.doneCount() >= NEED) {
      this.powered = true;
      this.doom = DOOM_TIME;
      for (const g of this.gens) g.reps = {};
      for (const g of this.gates) g.open = true;
    }
    if (this.powered && this.doom > 0) {
      this.doom = Math.max(this.doom - dt, 0);
      if (this.doom <= 0) { // the moon lands: nobody left inside survives (the escape cars are already out)
        for (const n in this.s) if (LIVE.includes(this.s[n].hp) && this.s[n].car < 0) this.s[n].hp = 'dead';
        for (const g of this.gens) g.reps = {};
        this.healers = {}; this.carrying = '';
      }
    }
    for (let i = 0; i < this.roads.length; i++) { // the road clock: out of time, the car stops where it is
      const r = this.roads[i];
      if (r.st !== 1) continue;
      r.t = Math.max(r.t - dt, 0);
      if (r.t <= 0) out.push(this.caught(i, 'time'));
    }
    for (const n in this.s) {
      const p = this.s[n];
      p.held = (p.hp === 'ok' || p.hp === 'hurt') ? Math.max(p.held - dt, 0) : 0;
      if (this.perk[n] === 'rise') { // left down long enough, she gets up by herself, once
        if (p.hp === 'down' && !p.risen) {
          p.rt += dt;
          if (p.rt >= RISE_TIME) { p.hp = 'hurt'; p.risen = true; p.rt = 0; p.heal = 0; delete this.healers[n]; out.push({ k: 'rise', n }); }
        } else if (p.hp !== 'down') p.rt = 0;
      }
      if (this.perk[n] === 'mend') { // «تفتّح» (Bloom): hurt and left alone long enough, she mends herself
        if (p.hp === 'hurt') {
          p.rt += dt;
          if (p.rt >= MEND_TIME) { p.hp = 'ok'; p.rt = 0; p.heal = 0; delete this.healers[n]; out.push({ k: 'mend', n }); }
        } else p.rt = 0;
      }
      if (p.hp === 'hooked') p.esc = Math.max(p.esc - MASH_DECAY * dt, 0);
      if (p.hp === 'hooked' || p.hp === 'down') { p.t -= dt; if (p.t <= 0) { p.hp = 'dead'; this.add(this.killer, 100); } }
    }
    // lifting someone off a hook: everybody pulling on the same person adds up
    const pulling = {}, pullW = {};
    for (const r of Object.keys(this.rescuers)) {
      const tgt = this.rescuers[r];
      if (!this.freeNow(r) || this.hp(tgt) !== 'hooked') { delete this.rescuers[r]; continue; }
      pulling[tgt] = (pulling[tgt] || 0) + 1;
      pullW[tgt] = (pullW[tgt] || 0) + (this.perk[r] === 'lift' ? LIFT_W : 1);
    }
    for (const n in this.s) {
      const p = this.s[n];
      const hands = pulling[n] || 0;
      if (p.hp !== 'hooked') { p.resc = 0; continue; }
      if (hands <= 0) { p.resc = Math.max(p.resc - dt * 0.5, 0); continue; }
      p.resc += dt * (pullW[n] || hands) / RESCUE_TIME;
      if (p.resc >= 1) {
        p.resc = 0;
        p.hp = 'hurt'; p.hook_i = -1; p.heal = 0;
        let by = '';
        for (const r of Object.keys(this.rescuers)) {
          if (this.rescuers[r] !== n) continue;
          this.add(r, hands === 1 ? 60 : 40);
          if (by === '') by = r;
          delete this.rescuers[r];
        }
        out.push({ k: 'rescued', n, by, hands });
      }
    }
    for (const h of Object.keys(this.healers)) {
      const tgt = this.healers[h];
      const p = this.s[tgt];
      const self = h === tgt;
      const valid = this.freeNow(h) && p && (p.hp === 'hurt' || (p.hp === 'down' && !self)) && (!self || p.item) && (self || this.nearPlayer(h, tgt));
      if (!valid) { delete this.healers[h]; continue; }
      p.heal += dt / (self ? SELF_HEAL_TIME : HEAL_TIME) * (!self && this.perk[h] === 'medic' ? MEDIC_MUL : 1);
      if (p.heal >= 1) {
        p.heal = 0;
        p.hp = p.hp === 'down' ? 'hurt' : 'ok';
        this.add(h, self ? 20 : 40);
        if (self) p.item = false;
        delete this.healers[h];
      }
    }
    // the one random event of the round, and the call to prayer
    if (!this.evFired && this.clock >= this.evAt) {
      this.evFired = true;
      this.evT = EVENT_LEN[this.evKind];
      if (this.evKind === 2) {
        const liveNames = Object.keys(this.s).filter((n) => LIVE.includes(this.s[n].hp)).sort();
        if (liveNames.length === 0) this.evT = 0;
        else this.evN = liveNames[Math.floor(Math.abs(Math.floor(this.evAt)) / 11) % liveNames.length];
      }
    } else if (this.evT > 0) this.evT = Math.max(this.evT - dt, 0);
    if (this.adhan === 0 && this.clock >= this.adhanAt) this.adhan = 1;
    else if (this.adhan === 1 && this.clock >= this.adhanAt + ADHAN_LEN) this.adhan = 2;
    const names = Object.keys(this.s);
    const live = names.filter((n) => LIVE.includes(this.s[n].hp)).length;
    if (names.length > 0 && live === 0) this.over = true;
    else if (live === 1 && names.length > 1 && this.hatch < 0 && !this.powered && this.layout.x && this.layout.x.length > 0) {
      this.hatch = Math.floor(Math.random() * this.layout.x.length); // last one standing: a way out opens somewhere
    }
    return out;
  }

  snapshot() {
    const r3 = (v) => Math.round(v * 1000) / 1000;
    const ss = {};
    const pulling = {};
    for (const r of Object.keys(this.rescuers)) pulling[this.rescuers[r]] = (pulling[this.rescuers[r]] || 0) + 1;
    for (const n in this.s) {
      const p = this.s[n];
      ss[n] = [p.hp, p.hooks, p.hook_i, Math.ceil(p.t), r3(p.heal), p.locker, p.item, r3(p.esc), r3(p.resc), pulling[n] || 0, p.car, Math.round(p.held * 10) / 10, !!p.shield, p.ammo || 0];
    }
    return {
      k: 'gs', g: this.gens.map((g) => r3(g.p)), d: this.gens.map((g) => g.done), to: this.gates.map((g) => g.open),
      pw: this.powered, gn: this.gun, s: ss, pl: this.pallets, kc: this.carrying, ks: r3(this.stun), kp: Math.round(this.powerCd * 10) / 10, ov: this.over, hx: this.hatch, dm: Math.round(this.doom * 10) / 10,
      sc: Object.fromEntries(Object.entries(this.score).map(([n, v]) => [n, Math.round(v)])),
      rd: this.roads.map((r) => [r.st, r.drv, r.who, Math.round(r.t * 10) / 10, r.why, !!r.flat]),
      tp: this.traps, sp: this.spikes,
      dr: this.doors, ek: this.evFired ? this.evKind : -1, et: Math.round(this.evT * 10) / 10, en: this.evN, ad: this.adhan,
    };
  }
}
module.exports = { Rules };
