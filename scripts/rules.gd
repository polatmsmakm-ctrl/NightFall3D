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
## «وضع السلاح» (the host's choice): every survivor carries a stun gun, GUN_SHOTS shots a round; a hit
## within GUN_RANGE leaves the killer dizzy for GUN_STUN seconds (and she drops whoever she carries).
const GUN_SHOTS := 3
const GUN_RANGE := 22.0
const GUN_STUN := 3.0
var gun := false
## «وضع القنّاص» (Kuwait City only): one gate (the one on the Kuwait Towers side, gate 0), the
## killer on a rooftop with a rifle that drops anyone it hits, no moon: the round runs until
## everybody is dead or out.
var sniper := false
const SNIPE_CD := 1.2      # a bolt-action: this long between shots, no limit on them
var snipe_t := -99.0
const GATE_DELAY := 10.0 # the generators are done: the gates open this long after (a countdown on every phone)
const DOOM_TIME := 120.0 # once the gates have power the moon falls: this long to get out
const MASH_STEP := 0.03 # each tap on "free yourself"
const MASH_DECAY := 0.1 # lost per second, so you have to keep hammering the button
const RESCUE_TIME := 2.0 # seconds to lift someone off a hook; two of you halve it
const CAR_SEATS := 6 # an escape car seats six: every survivor a room can have
const ROAD_TIME := 120.0 # from the first one getting into a gate's escape car to the last gate, 600 m on
const LIVE := ["ok", "hurt", "down", "carried", "hooked"]
# the rescue helicopter (both rules files): one free survivor left, it comes, hovers with a rope ladder
# down, the survivor climbs it and is out; caught before the top of the ladder, it leaves at once
const HELI_COME := 22.0
const HELI_WAIT := 75.0
const CLIMB_TIME := 6.0
const CLIMB_SAFE := 0.3 # this far up the ladder the killer cannot reach her any more
## One ability per survivor character. The rules apply the ones that touch the round (fix, lift,
## rise, tough, medic); main.gd does the rest on the phone (burst, sense, ghost). Same table in rules.js.
const PERK := {"survivor1": "burst", "survivor2": "fix", "survivor3": "lift", "survivor4": "rise",
	"survivor5": "tough", "survivor6": "sense", "survivor7": "medic", "survivor8": "ghost", "survivor9": "mend"}
## Name, one line and an icon for each, for the character stand, the HUD and «طريقة اللعب».
const PERK_INFO := {
	"burst": ["Second Wind", "When you're hit or come off the hook, you run faster and longer", "shoe"],
	"fix": ["Repair Hands", "Repairs generators 30% faster", "wrench"],
	"lift": ["The Protector", "Lifts people off the hook like two", "rescue"],
	"rise": ["Valkyrie Wing", "If you're down and nobody picks you up for 20 seconds, you get up yourself (once)", "star"],
	"tough": ["Tough Skin", "The first hit of the round does nothing", "shield"],
	"sense": ["Night Eye", "You sense the killer within 28 m, and an arrow shows where she is", "eye"],
	"medic": ["Field Medic", "Heals others 60% faster", "heal"],
	"ghost": ["Ghost Step", "The killer can't see your run marks and your steps are quiet", "crouch"],
	"aid": ["The Medic", "Carries the first-aid kit: heals others twice as fast, heals himself in 8 seconds, and the kit never runs out", "heal"],
	"mend": ["Bloom", "If you're hurt and not hit again for 45 seconds, you're healthy again", "heal"],
}
const SENSE_R := 28.0     # «عين الليل»: how close she has to be
const FIX_MUL := 1.3      # «يد المصلّح»: repairs 30% faster
const GRID_CUTS := 2      # the killer may pull the power box twice a round
const GRID_GAP := 60.0    # and only this long after the power came back
const GRID_OFF_GAP := 15.0 # Halloween: a survivor may switch the power off again this long after it came back
const GRID_FIX := 12.0    # Kuwait City's power box: one survivor brings the street lights back in 12 s
const MEND_TIME := 45.0   # «تفتّح»: how long Bloom has to stay hurt (and not hit again) to mend
const AID_MUL := 2.0      # «المسعف» (picked instead of the character's own perk): carries the first-aid kit, heals others twice as fast
const AID_SELF := 8.0     # and himself in 8 s, and the kit never runs out
const MEDIC_MUL := 1.6    # «طب ميداني»: heals the others 60% faster
const LIFT_W := 1.8       # «الحامي»: lifts someone off a hook like nearly two people
const RISE_TIME := 20.0   # «جناح الفالكيري»: down this long without being picked up, she gets up (once)
const TRAPS := 4          # the killer's traps armed at once: a fifth one takes the oldest one's place
const HELD_TIME := 4.0    # caught in a trap: held this long
# one random event per round, picked from the seed so every client agrees
const EVENT_LEN := [20.0, 40.0, 5.0] # 0 blackout, 1 heavy fog, 2 alarm
const ADHAN_LEN := 55.0              # the length of assets/sfx/adhan.mp3

var gens: Array = [] # {p, done, reps}
var gates: Array = [] # {open}
# the escape car behind each gate: st 0 waiting, 1 on the road, 2 caught (rammed or out of time),
# 3 through the last gate. The first one in drives; who lists everyone in it, driver first.
var roads: Array = [] # {st, drv, who, t, why, flat}
var perk := {}            # survivor name -> perk id (PERK)
var traps: Array = []     # the killer's traps: [x, z, armed, y], at most TRAPS slots, reused oldest first
var trap_k := 0           # the next slot to arm
var spikes: Array = []    # per road: [x, z, armed] — a strip of spikes across it bursts the escape car's tyres
var pallets: Array = [] # 0 standing, 1 dropped, 2 broken
var s := {} # survivor name -> {hp, hooks, hook_i, t, heal, locker, item}
var roles := {}
var killer := ""
var carrying := ""
var stun := 0.0
var power_cd := 0.0
var healers := {} # healer -> target
var beast := false # the killer is «الوحش» (killer2): his second hook is not let go (eaten)
var rescuers := {} # rescuer -> the hooked survivor they are lifting
var last_hit := {}
var powered := false
var heli := {"st": 0, "t": 0.0, "who": "", "p": 0.0, "hp0": ""} # 0 none, 1 coming, 2 hovering, 3 climbing, 4 away with her, 5 left
var heli_ok := false # the map has a spot for it (main sets it; the server knows it from layout.k)
var gate_t := -1.0 # counting down to the gates opening (-1: not yet / done)
var gate_delay := GATE_DELAY # (the tests that are not about the countdown set it to 0)
var doom := -1.0 # seconds until the moon hits (-1: not falling yet)
var over := false
var clock := 0.0
var n_hatch := 0
var hatch := -1 # which hatch is open (-1: none): opens when one survivor is left
var score := {} # name -> points
var doors: Array = []   # every doorway: true when the leaf is shut
var ev_kind := -1       # which event this round will bring
var ev_at := 1e9        # when it fires, seconds into the round
var ev_t := 0.0         # seconds of it left
var ev_n := ""          # the survivor the alarm gives away
var ev_fired := false
var has_grid := false   # the map has a power box (Kuwait City): the killer cuts it, survivors fix it
## The power box's mode, from the room's weather: Halloween's lights can be switched off by the
## survivors too, and «بين العصر والمغرب» starts with them off (they come on when someone fixes it).
func set_grid_mode(m: int) -> void:
	grid_mode = m
	grid = m != 2

var grid_mode := 0      # 0 Kuwait City, 1 Halloween (survivors may switch it off too), 2 «بين العصر والمغرب» (starts off)
var grid := true
var grid_p := 0.0
var grid_reps := {}
var grid_cuts := 0
var grid_wait := 0.0
var adhan_at := 1e9     # when the call to prayer starts
var adhan := 0          # 0 not yet, 1 playing, 2 done

func setup(n_gens: int, n_gates: int, n_pallets: int, hatches: int, players: Array, seed := 0, n_doors := 0) -> void:
	n_hatch = hatches
	for i in n_doors: doors.append(false)
	# the same seed on the server and on every phone, so the round plays out the same
	ev_kind = absi(seed) % 3
	ev_at = 60.0 + float((absi(seed) / 3) % 121)
	adhan_at = 40.0 + float((absi(seed) / 379) % 151)
	for i in n_gens: gens.append({"p": 0.0, "done": false, "reps": {}})
	for i in n_gates:
		gates.append({"open": false})
		roads.append({"st": 0, "drv": "", "who": [], "t": ROAD_TIME, "why": "", "flat": false})
		spikes.append([0.0, 0.0, false])
	for i in n_pallets: pallets.append(0)
	for pl in players:
		roles[str(pl.name)] = str(pl.role)
		score[str(pl.name)] = 0.0
		if str(pl.role) == "killer":
			killer = str(pl.name)
			beast = str(pl.get("char", "")) == "killer2"
		else:
			var pk: String = "aid" if str(pl.get("perk", "")) == "aid" else PERK.get(str(pl.get("char", "")), "") # a picked perk («المسعف») replaces the character's
			perk[str(pl.name)] = pk
			s[str(pl.name)] = {"hp": "ok", "hooks": 0, "hook_i": -1, "t": 0.0, "heal": 0.0, "locker": -1, "item": true, "esc": 0.0, "resc": 0.0, "car": -1,
				"held": 0.0, "shield": pk == "tough", "risen": false, "rt": 0.0, "ammo": GUN_SHOTS if gun else 0}

## «الوحش» eats whoever hangs on his hook for the second time (scripts/feast.gd draws it): from then on
## nobody can lift them off — the hook's clock runs out and only the head is left.
func eaten(name: String) -> bool:
	return beast and s.has(name) and s[name].hp == "hooked" and int(s[name].hooks) >= 2

func add(name: String, pts: float) -> void:
	if score.has(name): score[name] += pts

func done_count() -> int:
	var n := 0
	for g in gens:
		if g.done: n += 1
	return n

func hp(name: String) -> String:
	return s[name].hp if s.has(name) else ""

## Standing, free to act (not hiding, not in an escape car).
func free_now(name: String) -> bool:
	return s.has(name) and s[name].hp in ["ok", "hurt"] and s[name].locker < 0 and int(s[name].get("car", -1)) < 0

## The escape car this survivor is riding in, -1 none.
func car_of(name: String) -> int:
	return int(s[name].get("car", -1)) if s.has(name) else -1

## Everyone in the car is out: through the last gate.
func _arrive(i: int) -> Dictionary:
	var r: Dictionary = roads[i]
	r.st = 3
	for n in r.who:
		if not s.has(n): continue
		if s[n].hp in ["ok", "hurt"]:
			s[n].hp = "escaped"
			add(n, 200.0)
		s[n].car = -1
	return {"k": "arrive", "i": i, "who": r.who.duplicate()}

## The car stops dead and everyone in it is thrown out onto the road, down: the killer's to hang.
func _caught(i: int, why: String) -> Dictionary:
	var r: Dictionary = roads[i]
	r.st = 2
	r.why = why
	for n in r.who:
		if not s.has(n): continue
		s[n].car = -1
		if s[n].hp in ["ok", "hurt"]:
			_down(n)
			add(killer, 60.0)
	return {"k": "caught", "i": i, "why": why, "who": r.who.duplicate()}

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
	rescuers.erase(name)

func _drop_all() -> void:
	for g in gens: g.reps.clear()
	healers.clear()
	rescuers.clear()
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
		"cut": # the killer pulls the power box: every street light on the map goes out
			if is_killer and has_grid and grid and grid_cuts < GRID_CUTS and grid_wait <= 0.0:
				grid = false; grid_p = 0.0; grid_reps.clear(); grid_cuts += 1
				add(from, 40.0)
				out.append({"k": "grid", "on": false, "by": from})
		"off": # Halloween: a survivor switches the whole map dark (to hide); a short wait after a repair
			if not is_killer and has_grid and grid and grid_mode == 1 and free_now(from) and grid_wait <= GRID_GAP - GRID_OFF_GAP:
				grid = false; grid_p = 0.0; grid_reps.clear()
				out.append({"k": "grid", "on": false, "by": from, "sv": true})
		"pfix":
			if has_grid and not grid and d.get("on", false) and free_now(from): grid_reps[from] = true
			else: grid_reps.erase(from)
		"rep":
			if i >= 0 and i < gens.size():
				if d.get("on", false) and free_now(from) and not gens[i].done and not powered and gate_t < 0.0: gens[i].reps[from] = true
				else: gens[i].reps.erase(from)
		"skill":
			if i >= 0 and i < gens.size() and gens[i].reps.has(from):
				if d.get("ok", false):
					gens[i].p = minf(gens[i].p + 0.03, 1.0)
					add(from, 5.0)
				else:
					gens[i].p = maxf(gens[i].p - 0.08, 0.0)
					out.append({"k": "boom", "i": i})
		"board": # into the escape car past a gate: the first one in drives, the rest ride with them
			if powered and i >= 0 and i < roads.size() and (i == 0 or not sniper) and free_now(from) and int(roads[i].st) <= 1 and (roads[i].who as Array).size() < CAR_SEATS:
				var r: Dictionary = roads[i]
				if r.st == 0:
					r.st = 1; r.t = ROAD_TIME; r.drv = from
				r.who.append(from)
				s[from].car = i
				_drop(from)
				out.append({"k": "board", "i": i, "n": from, "drv": r.drv == from})
		"arrive": # the driver has reached the last gate: everyone in the car is out
			if i >= 0 and i < roads.size() and int(roads[i].st) == 1 and roads[i].drv == from:
				out.append(_arrive(i))
		"ram": # the killer's car hit the escape car
			if is_killer and i >= 0 and i < roads.size() and int(roads[i].st) == 1:
				out.append(_caught(i, "ram"))
		"escape":
			if free_now(from) and (powered or (hatch >= 0 and d.get("h", false))):
				s[from].hp = "escaped"
				add(from, 150.0)
				_drop(from)
		"ladder": # the last survivor takes hold of the helicopter's rope ladder
			if int(heli.st) == 2 and from == str(heli.who) and free_now(from):
				heli.st = 3; heli.p = 0.0; heli.hp0 = str(s[from].hp)
				_drop(from)
				out.append({"k": "heli", "st": 3, "n": from})
		"hit":
			if int(heli.st) == 3 and n == str(heli.who) and float(heli.p) >= CLIMB_SAFE: return out # out of her reach up the ladder
			if is_killer and stun <= 0.0 and carrying == "" and free_now(n) and clock - float(last_hit.get(n, -99.0)) > HIT_COOLDOWN:
				last_hit[n] = clock
				if s[n].get("shield", false): # «جلد قاسي»: the first blow of the round does nothing
					s[n].shield = false
					out.append({"k": "shield", "n": n})
				elif s[n].hp == "ok":
					s[n].hp = "hurt"; s[n].heal = 0.0
					_drop(n)
					add(from, 30.0)
					out.append({"k": "hurt", "n": n, "s": s[n].hp})
				else:
					_down(n)
					add(from, 50.0)
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
		"rescue": # hold it: two survivors on the same hook get them down twice as fast
			if d.get("on", false) and free_now(from) and hp(n) == "hooked" and not eaten(n): rescuers[from] = n
			else: rescuers.erase(from)
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
				elif s.has(n) and s[n].hp in ["hurt", "down"] and s[n].locker < 0 and car_of(n) < 0: healers[from] = n
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
		"snipe": # the killer's rifle: n = whoever her phone says the bullet hit ("" missed), p = where it struck
			if sniper and is_killer and clock - snipe_t >= SNIPE_CD:
				snipe_t = clock
				var hn := str(d.get("n", ""))
				var hp = d.get("p", [])
				var hit := hn != "" and s.has(hn) and free_now(hn)
				if hit: # down at once, whatever they had (no shield either)
					s[hn].shield = false
					_down(hn)
					add(from, 60.0)
				out.append({"k": "snipe", "by": from, "n": hn if hit else "", "p": hp if hp is Array else []})
		"shoot": # the stun gun; the shooter's phone says whether it hit her (and checked the range)
			if gun and not is_killer and free_now(from) and int(s[from].get("ammo", 0)) > 0:
				s[from].ammo = int(s[from].ammo) - 1
				var hit: bool = bool(d.get("hit", false)) and killer != "" and stun <= 0.0
				if hit:
					stun = GUN_STUN
					add(from, 60.0)
				out.append({"k": "shot", "n": from, "hit": hit, "left": int(s[from].ammo)})
				if hit: out.append({"k": "stun", "by": "gun"})
		"break":
			if is_killer and i >= 0 and i < pallets.size() and pallets[i] == 1:
				pallets[i] = 2
				add(from, 10.0)
				out.append({"k": "broke", "i": i})
		"power":
			if is_killer and power_cd <= 0.0 and stun <= 0.0 and carrying == "":
				power_cd = POWER_CD
				out.append({"k": "power"})
		"trap": # the killer sets a trap at her feet: p = [x, z]
			var tp = d.get("p", [])
			if is_killer and stun <= 0.0 and carrying == "" and tp is Array and tp.size() >= 2:
				var k := trap_k % TRAPS
				trap_k += 1
				var e := [snappedf(float(tp[0]), 0.01), snappedf(float(tp[1]), 0.01), true, snappedf(float(tp[2]), 0.01) if tp.size() > 2 else 0.0]
				if k < traps.size(): traps[k] = e
				else:
					k = traps.size()
					traps.append(e)
				out.append({"k": "trap", "i": k})
		"snap": # a survivor's own phone: I stepped into trap i
			if free_now(from) and i >= 0 and i < traps.size() and traps[i][2]:
				traps[i][2] = false
				s[from].held = HELD_TIME
				_drop(from)
				add(killer, 25.0)
				out.append({"k": "snap", "i": i, "n": from})
		"disarm": # a survivor springs it with a stick
			if free_now(from) and i >= 0 and i < traps.size() and traps[i][2]:
				traps[i][2] = false
				add(from, 15.0)
				out.append({"k": "disarm", "i": i, "n": from})
		"spike": # the killer lays a strip of spikes across escape road i (one per road; laying it again moves it)
			var sp = d.get("p", [])
			if is_killer and stun <= 0.0 and carrying == "" and i >= 0 and i < roads.size() and int(roads[i].st) <= 1 and sp is Array and sp.size() >= 2:
				spikes[i] = [snappedf(float(sp[0]), 0.01), snappedf(float(sp[1]), 0.01), true]
				out.append({"k": "spike", "i": i})
		"pop": # the escape car's driver: we went over the spikes
			if i >= 0 and i < roads.size() and int(roads[i].st) == 1 and roads[i].drv == from and spikes[i][2]:
				spikes[i][2] = false
				roads[i].flat = true
				add(killer, 40.0)
				out.append({"k": "pop", "i": i})
		"door": # anyone can swing a door shut or open again
			if i >= 0 and i < doors.size() and (is_killer or free_now(from)):
				var shut: bool = d.get("on", false)
				if doors[i] != shut:
					doors[i] = shut
					out.append({"k": "door", "i": i, "on": shut, "by": from})
	return out

func tick(dt: float) -> Array:
	var out := []
	if over: return out
	clock += dt
	stun = maxf(stun - dt, 0.0)
	power_cd = maxf(power_cd - dt, 0.0)
	if stun > 0.0 and carrying != "":
		_down(carrying)
		carrying = ""
	for g in gens:
		if g.done or powered: continue
		var w := 0.0
		for r in g.reps: w += FIX_MUL if perk.get(r, "") == "fix" else 1.0
		g.p += dt * w / GEN_TIME
		for r in g.reps: add(r, dt * 100.0 / GEN_TIME) # one point per percent repaired
		if g.p >= 1.0:
			g.p = 1.0; g.done = true; g.reps.clear()
	if not powered and gate_t < 0.0 and done_count() >= NEED:
		gate_t = gate_delay # the last generator: a countdown, then the gates open
		for g in gens: g.reps.clear()
	if not powered and gate_t >= 0.0:
		gate_t = maxf(gate_t - dt, 0.0)
	if not powered and gate_t == 0.0:
		gate_t = -1.0
		powered = true
		doom = -1.0 if sniper else DOOM_TIME # (the sniper mode has no moon: it ends when they are all dead or out)
		for g in gens: g.reps.clear()
		for gi in gates.size():
			if gi == 0 or not sniper: gates[gi].open = true
	if powered and doom > 0.0:
		doom = maxf(doom - dt, 0.0)
		if doom <= 0.0: # the moon lands: nobody left inside survives (the escape cars are already out)
			for n in s:
				if s[n].hp in LIVE and car_of(n) < 0: s[n].hp = "dead"
			_drop_all()
	for i in roads.size(): # the road clock: out of time, the car stops where it is
		var r: Dictionary = roads[i]
		if int(r.st) != 1: continue
		r.t = maxf(float(r.t) - dt, 0.0)
		if r.t <= 0.0: out.append(_caught(i, "time"))
	if has_grid and grid: grid_wait = maxf(grid_wait - dt, 0.0)
	if has_grid and not grid:
		for gn in grid_reps.keys():
			if not free_now(gn): grid_reps.erase(gn)
		grid_p += dt * float(grid_reps.size()) / GRID_FIX
		for gn in grid_reps: add(gn, dt * 60.0 / GRID_FIX)
		if grid_p >= 1.0:
			grid = true; grid_p = 0.0; grid_reps.clear(); grid_wait = GRID_GAP
			out.append({"k": "grid", "on": true})
	for n in s:
		var p: Dictionary = s[n]
		p.held = maxf(float(p.get("held", 0.0)) - dt, 0.0) if p.hp in ["ok", "hurt"] else 0.0
		if perk.get(n, "") == "rise": # «جناح الفالكيري»: left down long enough, she gets up by herself, once
			if p.hp == "down" and not p.risen:
				p.rt = float(p.rt) + dt
				if p.rt >= RISE_TIME:
					p.hp = "hurt"; p.risen = true; p.rt = 0.0; p.heal = 0.0
					healers.erase(n)
					out.append({"k": "rise", "n": n})
			elif p.hp != "down": p.rt = 0.0
		if perk.get(n, "") == "mend": # «تفتّح» (Bloom): hurt and left alone long enough, she mends herself
			if p.hp == "hurt":
				p.rt = float(p.rt) + dt
				if p.rt >= MEND_TIME:
					p.hp = "ok"; p.rt = 0.0; p.heal = 0.0
					healers.erase(n)
					out.append({"k": "mend", "n": n})
			else: p.rt = 0.0
		if p.hp == "hooked": p.esc = maxf(p.esc - MASH_DECAY * dt, 0.0)
		if p.hp == "hooked" or p.hp == "down":
			p.t -= dt
			if p.t <= 0.0:
				p.hp = "dead"
				add(killer, 100.0)
	# lifting someone off a hook: everybody pulling on the same person adds up
	var pulling := {}
	var pull_w := {} # «الحامي» pulls like nearly two
	for r in rescuers.keys():
		var tgt: String = rescuers[r]
		if not free_now(r) or hp(tgt) != "hooked":
			rescuers.erase(r)
			continue
		pulling[tgt] = int(pulling.get(tgt, 0)) + 1
		pull_w[tgt] = float(pull_w.get(tgt, 0.0)) + (LIFT_W if perk.get(r, "") == "lift" else 1.0)
	for n in s:
		var p: Dictionary = s[n]
		var hands: int = int(pulling.get(n, 0))
		if p.hp != "hooked":
			p.resc = 0.0
			continue
		if hands <= 0:
			p.resc = maxf(p.resc - dt * 0.5, 0.0)
			continue
		p.resc += dt * float(pull_w.get(n, hands)) / RESCUE_TIME
		if p.resc >= 1.0:
			p.resc = 0.0
			p.hp = "hurt"; p.hook_i = -1; p.heal = 0.0
			var by := ""
			for r in rescuers.keys():
				if rescuers[r] == n:
					add(r, 60.0 if hands == 1 else 40.0)
					by = r if by == "" else by
					rescuers.erase(r)
			out.append({"k": "rescued", "n": n, "by": by, "hands": hands})
	for h in healers.keys():
		var tgt: String = healers[h]
		var p: Dictionary = s.get(tgt, {})
		var self_heal: bool = h == tgt
		var valid: bool = free_now(h) and not p.is_empty() and (p.hp == "hurt" or (p.hp == "down" and not self_heal)) and (not self_heal or p.item)
		if not valid:
			healers.erase(h)
			continue
		var aid: bool = perk.get(h, "") == "aid"
		p.heal += dt / ((AID_SELF if aid else SELF_HEAL_TIME) if self_heal else HEAL_TIME) * (1.0 if self_heal else (AID_MUL if aid else (MEDIC_MUL if perk.get(h, "") == "medic" else 1.0)))
		if p.heal >= 1.0:
			p.heal = 0.0
			p.hp = "hurt" if p.hp == "down" else "ok"
			add(h, 20.0 if self_heal else 40.0)
			if self_heal and not aid: p.item = false # «المسعف»'s kit never runs out
			healers.erase(h)
	# the one random event of the round, and the call to prayer
	if not ev_fired and clock >= ev_at:
		ev_fired = true
		ev_t = EVENT_LEN[ev_kind]
		if ev_kind == 2:
			var live_names := []
			for n in s:
				if s[n].hp in LIVE: live_names.append(n)
			live_names.sort()
			if live_names.is_empty(): ev_t = 0.0
			else: ev_n = str(live_names[(absi(int(ev_at)) / 11) % live_names.size()])
	elif ev_t > 0.0:
		ev_t = maxf(ev_t - dt, 0.0)
	if adhan == 0 and clock >= adhan_at: adhan = 1
	elif adhan == 1 and clock >= adhan_at + ADHAN_LEN: adhan = 2
	if s.size() > 0:
		var live := 0
		for n in s:
			if s[n].hp in LIVE: live += 1
		if live == 0: over = true
		elif live == 1 and s.size() > 1 and hatch < 0 and n_hatch > 0 and not powered:
			hatch = randi() % n_hatch # last one standing: a way out opens somewhere
		_step_heli(dt, live, out)
	return out

func _step_heli(dt: float, live: int, out: Array) -> void:
	if int(heli.st) == 0 and live == 1 and s.size() > 1 and heli_ok:
		for n in s:
			if not (s[n].hp in LIVE): continue
			if s[n].hp in ["ok", "hurt"] and int(s[n].get("car", -1)) < 0: # the one left, and free
				heli = {"st": 1, "t": HELI_COME, "who": n, "p": 0.0, "hp0": ""}
				out.append({"k": "heli", "st": 1, "n": n})
			break
	var st := int(heli.st)
	if st < 1 or st > 3: return
	var who := str(heli.who)
	var p = s.get(who)
	if st == 3 and p and str(p.hp) != str(heli.hp0) and float(heli.p) < CLIMB_SAFE: _down(who) # struck off the bottom of the ladder
	if p == null or not (p.hp in ["ok", "hurt"]) or int(p.get("car", -1)) >= 0: # caught: it leaves at once
		heli.st = 5
		out.append({"k": "heli", "st": 5, "n": who})
		return
	if st == 1:
		heli.t = float(heli.t) - dt
		if float(heli.t) <= 0.0:
			heli.st = 2; heli.t = HELI_WAIT
			out.append({"k": "heli", "st": 2, "n": who})
	elif st == 2:
		heli.t = float(heli.t) - dt
		if float(heli.t) <= 0.0:
			heli.st = 5
			out.append({"k": "heli", "st": 5, "n": who})
	elif st == 3:
		heli.p = minf(float(heli.p) + dt / CLIMB_TIME, 1.0)
		if float(heli.p) >= 1.0:
			heli.st = 4; p.hp = "escaped"; add(who, 300.0); _drop(who)
			out.append({"k": "heli", "st": 4, "n": who})

## How many survivors are pulling on the same hooked player right now.
func hands_on(name: String) -> int:
	var n := 0
	for r in rescuers:
		if rescuers[r] == name: n += 1
	return n

func snapshot() -> Dictionary:
	var gp := []; var gd := []; var to := []; var ss := {}; var sc := {}
	for n in score: sc[n] = roundi(score[n])
	for g in gens: gp.append(snappedf(g.p, 0.001)); gd.append(g.done)
	for g in gates: to.append(g.open)
	for n in s:
		var p: Dictionary = s[n]
		var hands := hands_on(n)
		ss[n] = [p.hp, p.hooks, p.hook_i, ceili(p.t), snappedf(p.heal, 0.001), p.locker, p.item, snappedf(p.esc, 0.001), snappedf(p.resc, 0.001), hands, int(p.get("car", -1)),
			snappedf(float(p.get("held", 0.0)), 0.1), bool(p.get("shield", false)), int(p.get("ammo", 0))]
	var rd := []
	for r in roads: rd.append([r.st, r.drv, r.who, snappedf(float(r.t), 0.1), r.why, bool(r.get("flat", false))])
	return {"tp": traps, "sp": spikes, "rd": rd, "k": "gs", "g": gp, "d": gd, "to": to, "pw": powered, "gn": gun, "s": ss, "pl": pallets, "kc": carrying, "ks": snappedf(stun, 0.01), "kp": snappedf(power_cd, 0.1), "ov": over, "hx": hatch, "sc": sc, "dm": snappedf(doom, 0.1), "gt": snappedf(gate_t, 0.1), "hl": [heli.st, snappedf(float(heli.t), 0.1), heli.who, snappedf(float(heli.p), 0.001)],
		"dr": doors, "ek": ev_kind if ev_fired else -1, "et": snappedf(ev_t, 0.1), "en": ev_n, "ad": adhan, "pb": [grid, snappedf(grid_p, 0.001), grid_cuts, ceili(grid_wait)] if has_grid else [], "ck": snappedf(clock, 0.1)}

func apply(v: Dictionary) -> void:
	for i in mini(gens.size(), v.g.size()):
		gens[i].p = float(v.g[i]); gens[i].done = bool(v.d[i])
	for i in mini(gates.size(), v.to.size()): gates[i].open = bool(v.to[i])
	for i in mini(pallets.size(), v.pl.size()): pallets[i] = int(v.pl[i])
	powered = bool(v.pw)
	gun = bool(v.get("gn", gun))
	for n in v.s:
		var a: Array = v.s[n]
		s[n] = {"hp": str(a[0]), "hooks": int(a[1]), "hook_i": int(a[2]), "t": float(a[3]), "heal": float(a[4]), "locker": int(a[5]), "item": bool(a[6]),
			"esc": float(a[7]) if a.size() > 7 else 0.0, "resc": float(a[8]) if a.size() > 8 else 0.0, "hands": int(a[9]) if a.size() > 9 else 0, "car": int(a[10]) if a.size() > 10 else -1,
			"held": float(a[11]) if a.size() > 11 else 0.0, "shield": bool(a[12]) if a.size() > 12 else false, "risen": false, "rt": 0.0,
			"ammo": int(a[13]) if a.size() > 13 else 0}
	var tp = v.get("tp", [])
	if tp is Array: traps = (tp as Array).duplicate(true)
	var sp = v.get("sp", [])
	if sp is Array:
		for i in mini(spikes.size(), sp.size()): spikes[i] = (sp[i] as Array).duplicate()
	if v.has("rd"):
		for i in mini(roads.size(), v.rd.size()):
			var e: Array = v.rd[i]
			roads[i] = {"st": int(e[0]), "drv": str(e[1]), "who": (e[2] as Array).duplicate(), "t": float(e[3]), "why": str(e[4]) if e.size() > 4 else "",
				"flat": bool(e[5]) if e.size() > 5 else false}
	carrying = str(v.kc)
	stun = float(v.ks)
	power_cd = float(v.kp)
	over = bool(v.ov)
	hatch = int(v.get("hx", -1))
	doom = float(v.get("dm", -1.0))
	gate_t = float(v.get("gt", -1.0))
	var hl: Array = v.get("hl", [0, 0.0, "", 0.0])
	if hl.size() >= 4: heli = {"st": int(hl[0]), "t": float(hl[1]), "who": str(hl[2]), "p": float(hl[3]), "hp0": str(heli.get("hp0", ""))}
	var dr = v.get("dr", [])
	if dr is Array:
		for i in mini(doors.size(), dr.size()): doors[i] = bool(dr[i])
	ev_kind = int(v.get("ek", -1))
	ev_fired = ev_kind >= 0
	ev_t = float(v.get("et", 0.0))
	ev_n = str(v.get("en", ""))
	adhan = int(v.get("ad", 0))
	if v.has("ck"): clock = float(v.ck)
	var pb = v.get("pb", [])
	if pb is Array and (pb as Array).size() >= 2:
		has_grid = true; grid = bool(pb[0]); grid_p = float(pb[1])
		if (pb as Array).size() >= 4: grid_cuts = int(pb[2]); grid_wait = float(pb[3])
	for n in v.get("sc", {}): score[n] = float(v.sc[n])
