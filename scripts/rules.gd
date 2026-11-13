class_name Rules
extends RefCounted
## Match rules. Online the server runs the same logic (server/rules.js) and sends snapshots;
## in trial mode this copy runs on the phone. Keep the two files in step.

const NEED := 5
const GEN_TIME := 60.0
const HEAL_TIME := 8.0
const SELF_HEAL_TIME := 12.0
const HOOK_TIME := [60.0, 30.0]
const BLEED_TIME := 120.0
const HIT_COOLDOWN := 1.5
const POWER_CD := 20.0
const STUN_TIME := 2.5
const DOOM_TIME := 120.0 # once the gates have power the moon falls: this long to get out
const MASH_STEP := 0.03 # each tap on "free yourself"
const MASH_DECAY := 0.1 # lost per second, so you have to keep hammering the button
const LIVE := ["ok", "hurt", "down", "carried", "hooked"]

var gens: Array = [] # {p, done, reps}
var gates: Array = [] # {open}
var pallets: Array = [] # 0 standing, 1 dropped, 2 broken
var s := {} # survivor name -> {hp, hooks, hook_i, t, heal, locker, item}
var roles := {}
var killer := ""
var carrying := ""
var stun := 0.0
var power_cd := 0.0
var healers := {} # healer -> target
var last_hit := {}
var powered := false
var doom := -1.0 # seconds until the moon hits (-1: not falling yet)
var over := false
var clock := 0.0
var n_hatch := 0
var hatch := -1 # which hatch is open (-1: none): opens when one survivor is left
var score := {} # name -> points

func setup(n_gens: int, n_gates: int, n_pallets: int, hatches: int, players: Array) -> void:
	n_hatch = hatches
	for i in n_gens: gens.append({"p": 0.0, "done": false, "reps": {}})
	for i in n_gates: gates.append({"open": false})
	for i in n_pallets: pallets.append(0)
	for pl in players:
		roles[str(pl.name)] = str(pl.role)
		score[str(pl.name)] = 0.0
		if str(pl.role) == "killer": killer = str(pl.name)
		else: s[str(pl.name)] = {"hp": "ok", "hooks": 0, "hook_i": -1, "t": 0.0, "heal": 0.0, "locker": -1, "item": true, "esc": 0.0}

func add(name: String, pts: float) -> void:
	if score.has(name): score[name] += pts

func done_count() -> int:
	var n := 0
	for g in gens:
		if g.done: n += 1
	return n

func hp(name: String) -> String:
	return s[name].hp if s.has(name) else ""

## Standing, free to act.
func free_now(name: String) -> bool:
	return s.has(name) and s[name].hp in ["ok", "hurt"] and s[name].locker < 0

func locker_user(i: int) -> String:
	for n in s:
		if s[n].locker == i: return n
	return ""

func hook_user(i: int) -> String:
	for n in s:
		if s[n].hp == "hooked" and s[n].hook_i == i: return n
	return ""

func _drop(name: String) -> void:
	for g in gens: g.reps.erase(name)
	healers.erase(name)

func _drop_all() -> void:
	for g in gens: g.reps.clear()
	healers.clear()
	carrying = ""

func _down(name: String) -> void:
	s[name].hp = "down"; s[name].t = BLEED_TIME; s[name].heal = 0.0
	_drop(name)

## Player inputs. Returns events for everyone (sounds, messages).
func handle(d: Dictionary, from: String) -> Array:
	if over: return []
	var out := []
	var i := int(d.get("i", -1))
	var n := str(d.get("n", ""))
	var is_killer := from == killer
	match str(d.get("k", "")):
		"rep":
			if i >= 0 and i < gens.size():
				if d.get("on", false) and free_now(from) and not gens[i].done and not powered: gens[i].reps[from] = true
				else: gens[i].reps.erase(from)
		"skill":
			if i >= 0 and i < gens.size() and gens[i].reps.has(from):
				if d.get("ok", false):
					gens[i].p = minf(gens[i].p + 0.03, 1.0)
					add(from, 5.0)
				else:
					gens[i].p = maxf(gens[i].p - 0.08, 0.0)
					out.append({"k": "boom", "i": i})
		"escape":
			if free_now(from) and (powered or (hatch >= 0 and d.get("h", false))):
				s[from].hp = "escaped"
				add(from, 150.0)
				_drop(from)
		"hit":
			if is_killer and stun <= 0.0 and carrying == "" and free_now(n) and clock - float(last_hit.get(n, -99.0)) > HIT_COOLDOWN:
				last_hit[n] = clock
				if s[n].hp == "ok":
					s[n].hp = "hurt"; s[n].heal = 0.0
					_drop(n)
				else: _down(n)
				add(from, 30.0 if s[n].hp == "hurt" else 50.0)
				out.append({"k": "hurt", "n": n, "s": s[n].hp})
		"pickup":
			if is_killer and stun <= 0.0 and carrying == "" and hp(n) == "down":
				s[n].hp = "carried"
				carrying = n
		"hook":
			if is_killer and carrying != "" and i >= 0 and hook_user(i) == "":
				var p: Dictionary = s[carrying]
				p.hooks += 1
				if p.hooks >= 3: p.hp = "dead"
				else:
					p.hp = "hooked"; p.hook_i = i; p.t = HOOK_TIME[p.hooks - 1]; p.esc = 0.0
				add(from, 80.0 if p.hp == "hooked" else 180.0)
				out.append({"k": "hooked", "n": carrying, "s": p.hp})
				carrying = ""
		"rescue":
			if free_now(from) and hp(n) == "hooked":
				s[n].hp = "hurt"; s[n].hook_i = -1; s[n].heal = 0.0
				add(from, 60.0)
				out.append({"k": "rescued", "n": n, "by": from})
		"struggle": # one tap on "free yourself": only on the first hook, and the bar drains unless you keep tapping
			if hp(from) == "hooked" and s[from].hooks == 1:
				s[from].esc += MASH_STEP
				if s[from].esc >= 1.0:
					s[from].hp = "hurt"; s[from].hook_i = -1; s[from].heal = 0.0; s[from].esc = 0.0
					add(from, 30.0)
					out.append({"k": "rescued", "n": from, "by": from})
		"heal":
			if d.get("on", false) and free_now(from):
				if n == from:
					if s[n].hp == "hurt" and s[n].item: healers[from] = n
				elif s.has(n) and s[n].hp in ["hurt", "down"] and s[n].locker < 0: healers[from] = n
			else: healers.erase(from)
		"locker":
			if d.get("on", false):
				if free_now(from) and locker_user(i) == "":
					_drop(from)
					s[from].locker = i
			elif s.has(from): s[from].locker = -1
		"search":
			if is_killer and stun <= 0.0 and carrying == "":
				var who := locker_user(i)
				if who != "":
					s[who].locker = -1; s[who].hp = "carried"
					_drop(who)
					carrying = who
					out.append({"k": "grabbed", "n": who})
				else: out.append({"k": "empty"})
		"pallet":
			if free_now(from) and i >= 0 and i < pallets.size() and pallets[i] == 0:
				pallets[i] = 1
				out.append({"k": "pallet", "i": i})
		"break":
			if is_killer and i >= 0 and i < pallets.size() and pallets[i] == 1:
				pallets[i] = 2
				add(from, 10.0)
				out.append({"k": "broke", "i": i})
		"power":
			if is_killer and power_cd <= 0.0 and stun <= 0.0 and carrying == "":
				power_cd = POWER_CD
				out.append({"k": "power"})
	return out

func tick(dt: float) -> void:
	if over: return
	clock += dt
	stun = maxf(stun - dt, 0.0)
	power_cd = maxf(power_cd - dt, 0.0)
	if stun > 0.0 and carrying != "":
		_down(carrying)
		carrying = ""
	for g in gens:
		if g.done or powered: continue
		g.p += dt * g.reps.size() / GEN_TIME
		for r in g.reps: add(r, dt * 100.0 / GEN_TIME) # one point per percent repaired
		if g.p >= 1.0:
			g.p = 1.0; g.done = true; g.reps.clear()
	if not powered and done_count() >= NEED:
		powered = true
		doom = DOOM_TIME
		for g in gens: g.reps.clear()
		for g in gates: g.open = true
	if powered and doom > 0.0:
		doom = maxf(doom - dt, 0.0)
		if doom <= 0.0: # the moon lands: nobody left inside survives
			for n in s:
				if s[n].hp in LIVE: s[n].hp = "dead"
			_drop_all()
	for n in s:
		var p: Dictionary = s[n]
		if p.hp == "hooked": p.esc = maxf(p.esc - MASH_DECAY * dt, 0.0)
		if p.hp == "hooked" or p.hp == "down":
			p.t -= dt
			if p.t <= 0.0:
				p.hp = "dead"
				add(killer, 100.0)
	for h in healers.keys():
		var tgt: String = healers[h]
		var p: Dictionary = s.get(tgt, {})
		var self_heal: bool = h == tgt
		var valid: bool = free_now(h) and not p.is_empty() and (p.hp == "hurt" or (p.hp == "down" and not self_heal)) and (not self_heal or p.item)
		if not valid:
			healers.erase(h)
			continue
		p.heal += dt / (SELF_HEAL_TIME if self_heal else HEAL_TIME)
		if p.heal >= 1.0:
			p.heal = 0.0
			p.hp = "hurt" if p.hp == "down" else "ok"
			add(h, 20.0 if self_heal else 40.0)
			if self_heal: p.item = false
			healers.erase(h)
	if s.size() > 0:
		var live := 0
		for n in s:
			if s[n].hp in LIVE: live += 1
		if live == 0: over = true
		elif live == 1 and s.size() > 1 and hatch < 0 and n_hatch > 0 and not powered:
			hatch = randi() % n_hatch # last one standing: a way out opens somewhere

func snapshot() -> Dictionary:
	var gp := []; var gd := []; var to := []; var ss := {}; var sc := {}
	for n in score: sc[n] = roundi(score[n])
	for g in gens: gp.append(snappedf(g.p, 0.001)); gd.append(g.done)
	for g in gates: to.append(g.open)
	for n in s:
		var p: Dictionary = s[n]
		ss[n] = [p.hp, p.hooks, p.hook_i, ceili(p.t), snappedf(p.heal, 0.001), p.locker, p.item, snappedf(p.esc, 0.001)]
	return {"k": "gs", "g": gp, "d": gd, "to": to, "pw": powered, "s": ss, "pl": pallets, "kc": carrying, "ks": snappedf(stun, 0.01), "kp": snappedf(power_cd, 0.1), "ov": over, "hx": hatch, "sc": sc, "dm": snappedf(doom, 0.1)}

func apply(v: Dictionary) -> void:
	for i in mini(gens.size(), v.g.size()):
		gens[i].p = float(v.g[i]); gens[i].done = bool(v.d[i])
	for i in mini(gates.size(), v.to.size()): gates[i].open = bool(v.to[i])
	for i in mini(pallets.size(), v.pl.size()): pallets[i] = int(v.pl[i])
	powered = bool(v.pw)
	for n in v.s:
		var a: Array = v.s[n]
		s[n] = {"hp": str(a[0]), "hooks": int(a[1]), "hook_i": int(a[2]), "t": float(a[3]), "heal": float(a[4]), "locker": int(a[5]), "item": bool(a[6]), "esc": float(a[7]) if a.size() > 7 else 0.0}
	carrying = str(v.kc)
	stun = float(v.ks)
	power_cd = float(v.kp)
	over = bool(v.ov)
	hatch = int(v.get("hx", -1))
	doom = float(v.get("dm", -1.0))
	for n in v.get("sc", {}): score[n] = float(v.sc[n])
