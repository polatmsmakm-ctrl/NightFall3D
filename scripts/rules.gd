class_name Rules
extends RefCounted
## Match rules. The room host runs them (tick + handle) and broadcasts snapshots; everyone else applies them.

const NEED := 5
const GEN_TIME := 60.0 # seconds for one survivor
const GATE_TIME := 12.0
const HIT_COOLDOWN := 2.0

var gens: Array = [] # {p, done, reps}
var gates: Array = [] # {p, open, holders}
var hp := {} # survivor name -> ok / hurt / dead / escaped
var roles := {}
var last_hit := {}
var powered := false
var over := false
var clock := 0.0

func setup(n_gens: int, n_gates: int, players: Array) -> void:
	for i in n_gens: gens.append({"p": 0.0, "done": false, "reps": {}})
	for i in n_gates: gates.append({"p": 0.0, "open": false, "holders": {}})
	for pl in players:
		roles[str(pl.name)] = str(pl.role)
		if str(pl.role) == "survivor": hp[str(pl.name)] = "ok"

func done_count() -> int:
	var n := 0
	for g in gens:
		if g.done: n += 1
	return n

func active(name: String) -> bool:
	return hp.get(name, "") in ["ok", "hurt"]

func _drop(name: String) -> void:
	for g in gens: g.reps.erase(name)
	for g in gates: g.holders.erase(name)

## Player input events. Returns extra events to show/broadcast (e.g. a failed skill check).
func handle(d: Dictionary, from: String) -> Array:
	if over: return []
	var out := []
	var i := int(d.get("i", -1))
	match str(d.get("k", "")):
		"rep":
			if i >= 0 and i < gens.size() and active(from):
				if d.get("on", false) and not gens[i].done and not powered: gens[i].reps[from] = true
				else: gens[i].reps.erase(from)
		"skill":
			if i >= 0 and i < gens.size() and gens[i].reps.has(from):
				if d.get("ok", false): gens[i].p = minf(gens[i].p + 0.03, 1.0)
				else:
					gens[i].p = maxf(gens[i].p - 0.08, 0.0)
					out.append({"k": "boom", "i": i})
		"gate":
			if i >= 0 and i < gates.size() and active(from):
				if d.get("on", false) and powered and not gates[i].open: gates[i].holders[from] = true
				else: gates[i].holders.erase(from)
		"escape":
			var any_open := false
			for g in gates:
				if g.open: any_open = true
			if any_open and active(from):
				hp[from] = "escaped"
				_drop(from)
		"hit":
			var n := str(d.get("n", ""))
			if roles.get(from, "") == "killer" and active(n) and clock - float(last_hit.get(n, -99.0)) > HIT_COOLDOWN:
				last_hit[n] = clock
				hp[n] = "hurt" if hp[n] == "ok" else "dead"
				_drop(n)
				out.append({"k": "hurt", "n": n, "s": hp[n]})
	return out

func tick(dt: float) -> void:
	if over: return
	clock += dt
	for g in gens:
		if g.done or powered: continue
		g.p += dt * g.reps.size() / GEN_TIME
		if g.p >= 1.0:
			g.p = 1.0; g.done = true; g.reps.clear()
	if not powered and done_count() >= NEED:
		powered = true
		for g in gens: g.reps.clear()
	for g in gates:
		if g.open or not powered: continue
		g.p += dt * (1.0 if g.holders.size() > 0 else 0.0) / GATE_TIME
		if g.p >= 1.0:
			g.p = 1.0; g.open = true; g.holders.clear()
	if hp.size() > 0:
		var playing := 0
		for n in hp:
			if active(n): playing += 1
		if playing == 0: over = true

func snapshot() -> Dictionary:
	var gp := []; var gd := []; var tp := []; var to := []
	for g in gens: gp.append(snappedf(g.p, 0.001)); gd.append(g.done)
	for g in gates: tp.append(snappedf(g.p, 0.001)); to.append(g.open)
	return {"k": "gs", "g": gp, "d": gd, "tp": tp, "to": to, "pw": powered, "hp": hp, "ov": over}

func apply(s: Dictionary) -> void:
	for i in mini(gens.size(), s.g.size()):
		gens[i].p = float(s.g[i]); gens[i].done = bool(s.d[i])
	for i in mini(gates.size(), s.tp.size()):
		gates[i].p = float(s.tp[i]); gates[i].open = bool(s.to[i])
	powered = bool(s.pw)
	hp = s.hp
	over = bool(s.ov)
