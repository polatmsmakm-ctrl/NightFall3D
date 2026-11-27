extends Node3D
## «الوحش» eats whoever hangs on his hook for the second time (the owner: "consume the survivor
## progressively, starting with the legs, then the thighs, then the stomach, then the chest, and
## finally the neck, until only the head remains on the hook, and blood dripping under the hook").
##
## The rules make that hook final (`Rules.eaten`: nobody can lift them off, in rules.gd and rules.js),
## and its 30 s clock is the meal: five stages of three bites each, every bite a jump of the cut, a
## splash, a crunch and a cry. The body is cut by height — they hang straight down from the hook — by a
## shader that takes the character's own maps (shaders/eaten.gdshader): below the cut nothing is drawn,
## the edge is ragged and wet, and the inside of the body shows dark red through the opening. On the
## last stage everything but the head goes (the raised arms with it) and the head is pulled up onto the
## hook, where it stays, dripping, until the round ends.
##
## No network message: it all follows from the hooked survivor's clock in the snapshot, so every phone
## shows the same bite at the same moment. No class_name (an in-game update can carry it).

const STAGES := 5
const BITES := [0.1, 0.45, 0.8]   # where in each stage the three bites fall
const SNAP := 0.045               # how much of a stage one bite takes to close its jaws
const HEAD_R := 0.19              # what is left at the end: a ball round the head
const SHADER := preload("res://shaders/eaten.gdshader")

var world: NightWorld
var rules: Rules
var blood: NFBlood
var cam := Callable()     # -> Vector3
var rig_of := Callable()  # name -> CharacterRig (or null)
var on_bite := Callable() # (name, where, stage, last) -> main's sound, cry, shake
var e := {}               # name -> {hook, prog, rig, mats, tip, lift, drip, bite}
var bites := 0            # for the tests
var held := {}            # names kept at the end of the meal (the developer tools' try-out: no death)
var chew: AudioStreamPlayer3D
var chew_s: AudioStream
var own := false          # his sound: played in step with the meal (a late phone starts it part way)
var chew_at := 0.0

func setup(w: NightWorld, r: Rules, b: NFBlood, cam_cb: Callable, rig_cb: Callable, bite_cb: Callable) -> void:
	world = w
	rules = r
	blood = b
	cam = cam_cb
	rig_of = rig_cb
	on_bite = bite_cb
	process_priority = 1000 # after main has hung everyone this frame
	chew = AudioStreamPlayer3D.new()
	chew.bus = Aud.SFX
	chew.unit_size = 7.0
	chew.max_distance = 55.0
	chew.pitch_scale = 0.72
	add_child(chew)
	if ResourceLoader.exists("res://assets/sfx/beast_feast.ogg"): # the owner's own 30 s: the hook's whole clock
		chew_s = load("res://assets/sfx/beast_feast.ogg")
		chew.pitch_scale = 1.0
		chew.volume_db = 4.0
		chew.stream = chew_s
		own = true
	elif ResourceLoader.exists("res://assets/sfx/dog_eat.ogg"):
		chew_s = load("res://assets/sfx/dog_eat.ogg")
		if chew_s is AudioStreamOggVorbis: (chew_s as AudioStreamOggVorbis).loop = true
		chew.stream = chew_s

## Being eaten now, or what is left of them still hangs there: main keeps them on the hook.
func keeps(n: String) -> bool:
	return e.has(n)

func hook_of(n: String) -> int:
	return int(e[n].hook) if e.has(n) else -1

## 0..1 through the meal (1: only the head).
func progress(n: String) -> float:
	return float(e[n].prog) if e.has(n) else 0.0

func _process(dt: float) -> void:
	if rules == null: return
	var eating := false
	var c: Vector3 = cam.call() if cam.is_valid() else Vector3.INF
	for n in rules.s:
		var p: Dictionary = rules.s[n]
		var prog := -1.0
		if held.has(n) and e.has(n):
			prog = 1.0
		elif rules.eaten(n):
			prog = clampf(1.0 - float(p.t) / float(Rules.HOOK_TIME[1]), 0.0, 1.0)
			if not e.has(n): e[n] = {"hook": int(p.hook_i), "prog": prog, "rig": null, "mats": [], "tip": Vector3.INF, "lift": 0.0, "drip": 0.0}
		elif e.has(n):
			if p.hp == "dead": prog = 1.0
			else: # let go some other way (a new round's state, a test): give them their body back
				_restore(n)
				e.erase(n)
				continue
		if prog < 0.0: continue
		var x: Dictionary = e[n]
		var was: float = x.prog
		x.prog = maxf(prog, was) # never grows back
		var r = rig_of.call(n) if rig_of.is_valid() else null
		if r == null or not is_instance_valid(r): continue
		var rig := r as CharacterRig
		if x.rig != rig: _dress(n, rig)
		# hanging where main put them, lifted by what the last stage has pulled up so far
		rig.position.y = (world.hook_hang_y if world else 0.62) + float(x.lift)
		var lv := _levels(rig)
		if x.prog < 0.5: # where the hands hold the hook: the head ends up there
			x.tip = (rig.bone_at("mixamorig_LeftHand") + rig.bone_at("mixamorig_RightHand")) * 0.5 - Vector3(0, float(x.lift), 0)
		var cut := _cut(lv, x.prog)
		var head_c := rig.bone_at("mixamorig_Head") + Vector3(0, 0.1, 0)
		var last: bool = x.prog >= (STAGES - 1 + BITES[0]) / STAGES
		# the bites that fell since the last frame (one per frame at most: a late phone does not spray five at once)
		var b0 := _bite_count(was)
		var b1 := _bite_count(x.prog)
		if b1 > b0:
			var stage := mini((b1 - 1) / BITES.size(), STAGES - 1)
			var at := Vector3(head_c.x, cut, head_c.z)
			bites += 1
			if blood:
				blood.splash(at, Vector3(randf_range(-1, 1), -0.4, randf_range(-1, 1)).normalized(), c)
				for k in 5: blood.drip(at, Vector3(randf_range(-1.6, 1.6), randf_range(0.5, 2.2), randf_range(-1.6, 1.6)), 0.05, true)
			if on_bite.is_valid(): on_bite.call(n, at, stage, b1 >= STAGES * BITES.size())
		# the head goes up onto the hook once nothing else is left
		var want_lift := 0.0
		if x.prog >= 1.0 and Vector3(x.tip) != Vector3.INF:
			want_lift = maxf(float(Vector3(x.tip).y) - 0.1 - (head_c.y - float(x.lift)), 0.0)
		x.lift = move_toward(float(x.lift), want_lift, dt * 0.9)
		for m in x.mats:
			(m as ShaderMaterial).set_shader_parameter("cut_y", cut)
			(m as ShaderMaterial).set_shader_parameter("head_c", head_c)
			(m as ShaderMaterial).set_shader_parameter("head_r", HEAD_R if last else 100.0)
		# blood runs down out of what is left and drips off it onto the ground under the hook
		x.drip = float(x.drip) - dt
		if x.drip <= 0.0 and blood:
			x.drip = randf_range(0.06, 0.16) if x.prog < 1.0 else randf_range(0.25, 0.6)
			var from := Vector3(head_c.x, cut, head_c.z) if not last else head_c - Vector3(0, HEAD_R * 0.9, 0)
			from += Vector3(randf_range(-0.08, 0.08), 0.0, randf_range(-0.08, 0.08))
			var near: bool = c == Vector3.INF or c.distance_to(from) < 45.0
			blood.drip(from, Vector3(randf_range(-0.15, 0.15), -0.2, randf_range(-0.15, 0.15)), randf_range(0.03, 0.06), near)
		if x.prog < 1.0:
			eating = true
			chew.global_position = Vector3(head_c.x, cut, head_c.z)
			chew_at = float(x.prog) * float(Rules.HOOK_TIME[1])
	if eating and chew_s and not chew.playing:
		chew.play(minf(chew_at, chew_s.get_length() - 0.5) if own else 0.0)
	elif not eating and chew.playing: chew.stop()

## How many bites have fallen by `prog`.
func _bite_count(prog: float) -> int:
	var n := 0
	for k in STAGES:
		for u in BITES:
			if prog >= (k + float(u)) / STAGES: n += 1
	return n

## The heights the cut climbs through: under the feet, the knees, the hips, the stomach, the chest, the neck.
func _levels(rig: CharacterRig) -> Array:
	var y := func(b: String) -> float: return rig.bone_at("mixamorig_" + b).y
	var feet: float = minf(y.call("LeftToeBase"), y.call("RightToeBase"))
	return [feet - 0.14, (float(y.call("LeftLeg")) + float(y.call("RightLeg"))) * 0.5,
		(float(y.call("LeftUpLeg")) + float(y.call("RightUpLeg"))) * 0.5 + 0.04,
		y.call("Spine2"), y.call("Neck"), float(y.call("Head")) + 0.01]

## The cut at `prog`: within each stage three bites, each a quick jump a third of the way up.
func _cut(lv: Array, prog: float) -> float:
	var k := mini(int(floor(prog * STAGES)), STAGES - 1)
	var u := prog * STAGES - k
	var f := 0.0
	for b in BITES: f += smoothstep(float(b), float(b) + SNAP, u) / BITES.size()
	if prog >= 1.0: f = 1.0
	return lerpf(float(lv[k]), float(lv[k + 1]), f)

## Every surface of the character gets the cutting shader, fed with its own maps.
func _dress(n: String, rig: CharacterRig) -> void:
	var x: Dictionary = e[n]
	(load("res://scripts/crumbs.gd") as GDScript).mark("the Beast eats %s" % n)
	x.rig = rig
	x.mats = []
	var seed := float(absi(n.hash()) % 1000)
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null: continue
		m.material_overlay = null
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s)
			var sm := ShaderMaterial.new()
			sm.shader = SHADER
			if src is BaseMaterial3D:
				var b := src as BaseMaterial3D
				sm.set_shader_parameter("albedo_col", b.albedo_color)
				if b.albedo_texture: sm.set_shader_parameter("albedo_tex", b.albedo_texture)
				if b.normal_enabled and b.normal_texture:
					sm.set_shader_parameter("normal_tex", b.normal_texture)
					sm.set_shader_parameter("has_normal", true)
					sm.set_shader_parameter("normal_k", b.normal_scale)
				var mr := b.roughness_texture if b.roughness_texture else b.metallic_texture
				if mr:
					sm.set_shader_parameter("mr_tex", mr)
					sm.set_shader_parameter("has_mr", true)
				sm.set_shader_parameter("metal", b.metallic)
				sm.set_shader_parameter("rough", b.roughness)
			sm.set_shader_parameter("seed", seed)
			m.set_surface_override_material(s, sm)
			x.mats.append(sm)

func _restore(n: String) -> void:
	var rig = e[n].rig
	if rig == null or not is_instance_valid(rig): return
	for mi in (rig as Node).find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null: continue
		for s in m.mesh.get_surface_count(): m.set_surface_override_material(s, null)
