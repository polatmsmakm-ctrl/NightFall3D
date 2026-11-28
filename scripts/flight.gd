class_name NFFlight
extends Node3D
## «The Moon», stage 2: the rocket chase. Everything happens here, far above the map (FLY_O): the
## flight runs along -z from the Moon to the Earth, FLY_LEN metres (Rules.FLY_LEN), through a field of
## meteors that every phone builds the same from the room's seed and moves by the same clock (the
## rules' `fl.c`), so nothing about them is ever sent: the phone that sees its own ship touch one says so
## (`mhit`) and the meteor is gone everywhere.
## The rocket belongs to its pilot's phone (the first one aboard steers it with the stick; its position
## is the pilot's `st`), the boost to the second one aboard (a button: `boost`), her ship to the
## killer's phone. Everyone else follows the positions they are sent, a little ahead of them.

const FLY_O := Vector3(0.0, 20000.0, 0.0)
const TUBE_X := 70.0        # how far off the line a ship may stray, side to side
const TUBE_Y := 46.0        # and up and down
const CRUISE := 235.0       # the rocket without the boost (m/s; the HUD shows it as it is)
const ROCKET_MAX := 300.0   # with the boost
const KILLER_MAX := 320.0   # her ship
const DMG_MUL := 0.5        # a damaged engine: this much of the speed
const LIFT := 4.0           # seconds of lift-off on the Moon before the rocket is in the pilot's hands
const K_LIFT := 3.0         # and her ship's
const WASH_L := 110.0       # her ship in the rocket's exhaust: this far behind it
const WASH_R := 10.0        # and this near its line, it slows her down: she has to come alongside
const WASH_MUL := 0.82
const R_ROCKET := 3.4       # the rocket's radius (meteors, the ram) and half its length
const ROCKET_HALF := 11.0
const R_KSHIP := 3.8
const RAM_D := 8.0          # her ship this near the rocket's line: rammed
const VIEW := 3800.0        # meteors drawn this far ahead
const SPAN_X := 170.0       # meteors crossing the line wrap round out here
const SPAN_Y := 120.0
const BIG_R := 12.0         # a meteor this big is announced
const WARN_D := 1800.0      # this far ahead

var m: Node                 # main
var met: Array = []         # every meteor: [z, x0, y0, r, kind, speed, phase, mesh, spin, t0]
var clk := 0.0              # the flight's clock, kept smooth between snapshots
var cam: Camera3D
var rocket: Node3D          # the rocket in flight (his model, nose down the line)
var kship: Node3D           # her ship in flight
var r_loc := Vector3.ZERO   # the rocket: x, y off the line, z metres flown
var r_vel := Vector3.ZERO   # sideways, up, forward
var k_loc := Vector3(0, 0, -400)
var k_vel := Vector3.ZERO
var k_on := false           # her ship is out here
var k_t := -1.0             # seconds since she took off (her phone and every other one)
var r_sample := {}          # the last position each followed ship was sent: {p, v, t}
var k_sample := {}
var trauma := 0.0           # the flight camera's shake
var look := Vector2.ZERO    # the camera swung round by a drag
var look_idle := 0.0
var flames_r: Array = []    # the rocket's five flames
var flames_k: Array = []
var r_light: OmniLight3D
var k_light: OmniLight3D
var mm: Array = []          # one MultiMesh per rock model
var mm_base: Array = []     # [the mesh's own transform, its size]
var streaks: MultiMeshInstance3D
var streak_p: PackedVector3Array = PackedVector3Array()
var gone := {}              # meteors already hit (the rules' list, and mine on their way to it)
var sent := {}              # meteors I reported
var warned := {}            # big meteors already announced
var warn_t := 0.0           # the big-meteor alarm on screen
var warn_at := Vector3.INF  # where it is
var hit_flash := 0.0
var dmg_fx: GPUParticles3D  # sparks and smoke off a damaged engine
var k_dmg_fx: GPUParticles3D
var eng: AudioStreamPlayer
var wind: AudioStreamPlayer
var sky_set := false        # the sky is turned toward the Earth on this phone
var landed := false
var sent_land := false
var sent_ram := false
var pass_cd := 0.0
var r_lift := 0.0           # the rocket on the pad: how far it has risen
var k_lift_n: Node3D        # her ship rising off the pad (every phone)
var shown := false          # the flight's own camera is in use on this phone
var bot_k := false          # trial mode: the computer killer flies (this phone flies her)
var bot_wait := -1.0

func setup(main: Node, seed: int) -> void:
	m = main
	name = "Flight"
	_gen_meteors(seed)
	cam = Camera3D.new()
	cam.far = 6000.0
	cam.near = 0.2
	cam.fov = 70.0
	add_child(cam)
	rocket = _make_rocket()
	add_child(rocket)
	rocket.visible = false
	kship = _make_kship()
	add_child(kship)
	kship.visible = false
	for name_k in ["moon_rock1", "moon_rock2"]:
		var mi := MultiMeshInstance3D.new()
		var mmesh := MultiMesh.new()
		mmesh.transform_format = MultiMesh.TRANSFORM_3D
		var mt: Array = m.world._rock_mesh(name_k) if m.world.has_method("_rock_mesh") else []
		if mt.is_empty():
			var sm := SphereMesh.new()
			sm.radius = 0.5; sm.height = 1.0
			mt = [sm, Transform3D()]
		mmesh.mesh = mt[0]
		mmesh.instance_count = 180
		mmesh.visible_instance_count = 0
		mi.multimesh = mmesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5)) # its instances are all over the line
		add_child(mi)
		mm.append(mi)
		var ab: AABB = (mt[1] as Transform3D) * (mt[0] as Mesh).get_aabb()
		mm_base.append([mt[1], maxf(ab.size.x, maxf(ab.size.y, ab.size.z))])
	_build_streaks()
	dmg_fx = _sparks()
	rocket.add_child(dmg_fx)
	dmg_fx.position = Vector3(0, 0, ROCKET_HALF - 2.0)
	k_dmg_fx = _sparks()
	kship.add_child(k_dmg_fx)
	k_dmg_fx.position = Vector3(0, 1.2, 5.0)
	eng = _loop("res://assets/sfx/engine.ogg", -60.0)
	wind = _loop("res://assets/sfx/heli.ogg", -60.0)
	visible = true

func _loop(path: String, db: float) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.bus = Aud.SFX
	if ResourceLoader.exists(path):
		var st = load(path)
		if st is AudioStreamOggVorbis: (st as AudioStreamOggVorbis).loop = true
		a.stream = st
	a.volume_db = db
	add_child(a)
	return a

# ---------------- the meteors ----------------
## The same field on every phone: denser, faster and bigger the nearer the Earth.
## kind 0 drifts where it is, 1 crosses the line from the side, 2 comes at you down the line,
## 3 falls across it from above.
func _gen_meteors(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(seed) * 7919 + 1969
	var z := 1500.0
	while z < Rules.FLY_LEN - 600.0:
		var f := z / Rules.FLY_LEN
		z += lerpf(95.0, 34.0, f) * rng.randf_range(0.5, 1.5)
		var w := rng.randf()
		var kind := 0
		if w < 0.2 + 0.12 * f: kind = 1
		elif w < 0.33 + 0.24 * f: kind = 2
		elif w < 0.38 + 0.3 * f: kind = 3
		var big := rng.randf() < 0.03 + 0.05 * f
		var r := rng.randf_range(BIG_R + 1.0, 26.0) if big else rng.randf_range(1.4, 3.2) * (1.0 + rng.randf() * rng.randf() * 2.4)
		var sp := 0.0
		match kind:
			1: sp = rng.randf_range(20.0, 46.0) * (1.0 + 0.6 * f) * (1.0 if rng.randf() < 0.5 else -1.0)
			2: sp = rng.randf_range(30.0, 80.0) * (1.0 + 0.5 * f)
			3: sp = rng.randf_range(16.0, 38.0) * (1.0 + 0.5 * f)
		# where the line will be when the rocket gets here, give or take: kind 2 is at z then
		var t0 := LIFT + z / 250.0
		met.append([z, rng.randf_range(-TUBE_X - 12.0, TUBE_X + 12.0), rng.randf_range(-TUBE_Y - 8.0, TUBE_Y + 8.0), r, kind, sp,
			rng.randf() * TAU, rng.randi() % 2, rng.randf_range(0.1, 0.9) * (1.0 if rng.randf() < 0.5 else -1.0), t0])

func meteor_count() -> int:
	return met.size()

## Where meteor i is at flight time t, in the flight's frame (x, y off the line, z metres along it),
## and how big it is drawn there (meteors wrapping round fade out at the far edges).
func meteor_at(i: int, t: float) -> Array:
	var e: Array = met[i]
	var x: float = e[1]; var y: float = e[2]; var z: float = e[0]
	var k := 1.0
	match int(e[4]):
		0:
			x += 5.0 * sin(t * 0.3 + float(e[6])); y += 4.0 * cos(t * 0.23 + float(e[6]))
		1:
			x = wrapf(x + float(e[5]) * t, -SPAN_X, SPAN_X)
			k = smoothstep(SPAN_X, SPAN_X - 30.0, absf(x))
		2:
			z += float(e[5]) * (float(e[9]) - t)
		3:
			y = wrapf(y - float(e[5]) * t, -SPAN_Y, SPAN_Y)
			k = smoothstep(SPAN_Y, SPAN_Y - 25.0, absf(y))
	return [Vector3(x, y, z), float(e[3]) * k]

static func to_world(l: Vector3) -> Vector3:
	return FLY_O + Vector3(l.x, l.y, -l.z)

static func to_flight(w: Vector3) -> Vector3:
	return Vector3(w.x - FLY_O.x, w.y - FLY_O.y, -(w.z - FLY_O.z))

static func in_space(w: Vector3) -> bool:
	return w.y > FLY_O.y - 2000.0

# ---------------- the ships ----------------
func _flame_mat(core: Color, tail: Color, s: float) -> ShaderMaterial:
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/flame.gdshader")
	fm.set_shader_parameter("core", core)
	fm.set_shader_parameter("tail", tail)
	fm.set_shader_parameter("seed", s)
	return fm

## A cone of fire pointing back (+z) out of a nozzle at `at`, `r` wide at the nozzle and `l` long.
func _flame(parent: Node3D, at: Vector3, r: float, l: float, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r; cm.bottom_radius = 0.04; cm.height = l; cm.radial_segments = 20; cm.rings = 1
	cm.cap_top = false; cm.cap_bottom = false
	cm.material = mat
	mi.mesh = cm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.x = -PI / 2.0 # its axis along +z: the wide top (UV.y 0) at the nozzle, the tip behind
	mi.position = at + Vector3(0, 0, l / 2.0)
	mi.set_meta("base", [at, r, l])
	parent.add_child(mi)
	return mi

## His Escape Rocket on its side, nose down the line (-z), its middle on the node.
func _make_rocket() -> Node3D:
	var n := Node3D.new()
	n.name = "Rocket"
	var ps: PackedScene = load("res://assets/props/moon_rocket_ship.glb") if ResourceLoader.exists("res://assets/props/moon_rocket_ship.glb") else null
	var body := Node3D.new()
	body.rotation.x = -PI / 2.0 # its nose (+y in the model) down the line (-z)
	n.add_child(body)
	if ps:
		var mdl := ps.instantiate() as Node3D
		mdl.position = Vector3(-0.15, -13.5, 0.5) # the model's axis on the node, its middle at the node
		body.add_child(mdl)
	else:
		var cyl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.9; cm.bottom_radius = 2.2; cm.height = 24.0
		cyl.mesh = cm
		body.add_child(cyl)
	# five nozzles at its foot: the core and the four boosters round it
	var tail := ROCKET_HALF + 1.6
	var fm := _flame_mat(Color(0.8, 0.9, 1.0), Color(1.0, 0.45, 0.1), 0.0)
	flames_r.append(_flame(n, Vector3(0, 0, tail), 1.5, 16.0, fm))
	for k in 4:
		var a := PI / 4.0 + k * PI / 2.0
		flames_r.append(_flame(n, Vector3(cos(a) * 2.5, sin(a) * 2.5, tail - 1.2), 0.9, 11.0, _flame_mat(Color(0.85, 0.9, 1.0), Color(1.0, 0.5, 0.12), float(k + 1))))
	r_light = OmniLight3D.new()
	r_light.light_color = Color(1.0, 0.6, 0.3)
	r_light.light_energy = 6.0
	r_light.omni_range = 45.0
	r_light.position = Vector3(0, 0, tail + 6.0)
	n.add_child(r_light)
	var key := OmniLight3D.new() # a soft light on its body so it reads against the black
	key.light_color = Color(0.75, 0.82, 1.0)
	key.light_energy = 1.2
	key.omni_range = 30.0
	key.position = Vector3(6.0, 9.0, -4.0)
	n.add_child(key)
	return n

## His spaceship for her, nose down the line, two blue engines.
func _make_kship() -> Node3D:
	var n := Node3D.new()
	n.name = "KillerShip"
	var ps: PackedScene = load("res://assets/props/moon_ship.glb") if ResourceLoader.exists("res://assets/props/moon_ship.glb") else null
	if ps:
		var mdl := ps.instantiate() as Node3D
		mdl.position = Vector3(0, -1.7, 0)
		mdl.scale = Vector3.ONE * 1.15
		n.add_child(mdl)
	var fm := _flame_mat(Color(0.75, 0.95, 1.0), Color(0.1, 0.55, 1.0), 3.0)
	for sx in [-1.0, 1.0]:
		flames_k.append(_flame(n, Vector3(sx * 3.95, 0.25, 7.7), 1.15, 12.0, fm))
	k_light = OmniLight3D.new()
	k_light.light_color = Color(0.35, 0.75, 1.0)
	k_light.light_energy = 5.0
	k_light.omni_range = 38.0
	k_light.position = Vector3(0, 0.5, 13.0)
	n.add_child(k_light)
	var red := OmniLight3D.new() # and something red on her, so she reads as the threat behind you
	red.light_color = Color(1.0, 0.12, 0.08)
	red.light_energy = 1.4
	red.omni_range = 16.0
	red.position = Vector3(0, 3.5, -2.0)
	n.add_child(red)
	return n

func _sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 35.0
	pm.initial_velocity_min = 8.0; pm.initial_velocity_max = 26.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5; pm.scale_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	g.set_color(1, Color(0.25, 0.22, 0.2, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.22, 0.22)
	var mat := StandardMaterial3D.new()
	var dot := GradientTexture2D.new()
	var dg := Gradient.new()
	dg.set_color(0, Color(1, 1, 1, 1)); dg.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = dg
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5); dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 32; dot.height = 32
	mat.albedo_texture = dot
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	qm.material = mat
	p.draw_pass_1 = qm
	p.amount = 60
	p.lifetime = 0.9
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	return p

## Dust lit by the ships, streaming past the camera: how fast you are going.
func _build_streaks() -> void:
	streaks = MultiMeshInstance3D.new()
	var mmesh := MultiMesh.new()
	mmesh.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.7, 0.8, 1.0, 0.35)
	bm.material = mat
	mmesh.mesh = bm
	var n := 90 if Gfx.weak else 160
	mmesh.instance_count = n
	streaks.multimesh = mmesh
	streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	streaks.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in n: streak_p.append(Vector3(rng.randf_range(-70, 70), rng.randf_range(-45, 45), rng.randf_range(-400, 0)))
	add_child(streaks)

# ---------------- who is where ----------------
func _fl() -> Dictionary:
	return m.rules.fl

## What I am doing in it: "" not in it, "pad" aboard and waiting, "lift" the rocket lifting off,
## "fly" in the rocket, "klift" her ship lifting off, "kfly" flying her ship.
func me_mode() -> String:
	if m.rules == null or m.world == null or m.world.map_id != "moon": return ""
	var f := _fl()
	var st := int(f.st)
	if m.my_role == "killer":
		if bool(f.ks) and st == 2: return "klift" if k_t < K_LIFT else "kfly"
		return ""
	if not m.rules.in_rocket(m.my_name): return ""
	if st == 1: return "pad"
	return "lift" if clk < LIFT else "fly"

func flying(mode := "") -> bool:
	var md := me_mode() if mode == "" else mode
	return md in ["fly", "kfly"]

func is_pilot() -> bool:
	return str(_fl().pil) == m.my_name

func is_boost() -> bool:
	var f := _fl()
	return str(f.bst) == m.my_name or (str(f.pil) == m.my_name and str(f.bst) == "")

func rocket_world() -> Vector3:
	return to_world(r_loc)

func kship_world() -> Vector3:
	return to_world(k_loc)

## The speed the rocket aims for: the boost, minus a damaged engine.
func rocket_target() -> float:
	var f := _fl()
	var v := ROCKET_MAX if (bool(f.b) and float(f.e) > 0.0) else CRUISE
	if float(f.dm) > 0.0: v *= DMG_MUL
	return v

# ---------------- every frame ----------------
## Called by main every frame on the Moon.
func step(dt: float) -> void:
	var f := _fl()
	var st := int(f.st)
	# the flight's clock: the rules' one, kept smooth between snapshots
	if st == 2:
		var c := float(f.c)
		if m.offline or absf(clk - c) > 0.5: clk = c
		else: clk = lerpf(clk + dt, c, 1.0 - exp(-2.0 * dt))
	elif st < 2: clk = 0.0
	for h in f.hits:
		if not gone.has(int(h)):
			gone[int(h)] = true
	_bot_fly(dt)
	_pad_rocket(dt)
	_pad_kship(dt)
	# the ships out here: mine I fly (step_me), the others follow what they are sent
	var md := me_mode()
	if st == 2:
		if not (md in ["fly", "lift"] and is_pilot()): _follow_rocket(dt)
		if bool(f.ks):
			if k_t < 0.0: k_t = 0.0
			k_t += dt
			if not (m.my_role == "killer" or bot_k): _follow_kship(dt)
		k_on = bool(f.ks) and k_t >= K_LIFT
	else:
		k_on = false
	rocket.visible = st == 2 and clk >= LIFT - 0.05 and st != 4
	kship.visible = k_on and st == 2
	rocket.global_position = rocket_world()
	_orient(rocket, r_vel, dt, 1.0)
	kship.global_position = kship_world()
	_orient(kship, k_vel, dt, 1.4)
	_flames(dt)
	var watch := _watch_point()
	var on_pad: bool = md in ["pad", "lift", "klift"]
	shown = watch != Vector3.INF
	visible = st >= 2 or shown
	if st == 2 or shown: _meteors(watch if shown else rocket_world())
	if shown:
		_camera(dt)
		_streaks(dt)
	elif on_pad: _pad_camera(dt, md)
	streaks.visible = shown
	_sky(shown)
	if not shown and not on_pad and cam.current and m.main_cam and m.get("ending") == null: m.main_cam.make_current()
	_sound(dt, shown)
	if st >= 3 and m.my_role == "killer" and in_space(m.body.position): # the flight is over: back on the pad
		m.body.position = m.world.kship_spot + Vector3(0, 0.5, 8.0)
	warn_t = maxf(warn_t - dt, 0.0)
	hit_flash = maxf(hit_flash - dt * 1.8, 0.0)
	pass_cd = maxf(pass_cd - dt, 0.0)
	dmg_fx.emitting = st == 2 and float(f.dm) > 0.0
	k_dmg_fx.emitting = k_on and float(f.kd) > 0.0

## Where this phone's flight camera looks from (INF: it is not in use). Mine, or the one I watch.
func _watch_point() -> Vector3:
	var md := me_mode()
	if md in ["fly"]: return rocket_world()
	if md == "kfly": return kship_world()
	var sp: String = m.spectating
	if sp != "" and int(_fl().st) == 2:
		if m.rules.in_rocket(sp) and clk >= LIFT: return rocket_world()
		if sp == m.rules.killer and k_on: return kship_world()
	return Vector3.INF

## On the pad and lifting off: a camera off to one side of the rocket (or her ship), looking up at it.
func _pad_camera(dt: float, md: String) -> void:
	var w: NightWorld = m.world
	var tgt: Node3D = w.kship_node if md == "klift" else w.rocket
	if tgt == null: return
	if not cam.current: cam.make_current()
	var foot := w.kship_spot if md == "klift" else NightWorld.MOON_ROCKET
	var from := foot + Vector3(26.0, 5.0, 34.0)
	cam.global_position = cam.global_position.lerp(from, 1.0 - exp(-3.0 * dt)) if cam.global_position.distance_to(from) < 60.0 else from
	var aim := tgt.global_position + Vector3(0, 10.0 if md != "klift" else 1.0, 0)
	cam.look_at(aim, Vector3.UP)
	trauma = maxf(trauma - dt * 1.2, 0.0)
	if md != "pad": trauma = maxf(trauma, 0.35)
	var sh := trauma * trauma
	var tt := Time.get_ticks_msec() / 1000.0
	cam.rotate_object_local(Vector3(1, 0, 0), sh * 0.05 * sin(tt * 37.0))
	cam.rotate_object_local(Vector3(0, 0, 1), sh * 0.05 * sin(tt * 29.0 + 1.3))
	cam.fov = lerpf(cam.fov, 62.0 + Gfx.fov_add, 1.0 - exp(-3.0 * dt))

func cam_target() -> Node3D:
	var md := me_mode()
	if md == "kfly": return kship
	var sp: String = m.spectating
	if sp != "" and sp == m.rules.killer and k_on: return kship
	return rocket

## The rocket's pad: on the Moon it rises off its mount and climbs out of sight.
func _pad_rocket(dt: float) -> void:
	var w: NightWorld = m.world
	if w.rocket == null: return
	var st := int(_fl().st)
	var base := NightWorld.MOON_ROCKET + Vector3(0, 0.5, 0)
	if st >= 2:
		var t := clk if st == 2 else 30.0
		var h := 2.2 * t * t + 2.0 * t
		w.rocket.position = base + Vector3(0, h, 0)
		w.rocket.visible = h < 3000.0
		if not w.rocket.has_meta("fire") and h > 0.0:
			w.rocket.set_meta("fire", true)
			var fm := _flame_mat(Color(0.85, 0.9, 1.0), Color(1.0, 0.45, 0.1), 9.0)
			for k in 5:
				var a := PI / 4.0 + k * PI / 2.0
				var at := Vector3(0.15, 1.2, -0.5) if k == 4 else Vector3(0.15 + cos(a) * 2.5, 1.2, -0.5 + sin(a) * 2.5)
				var fl := _flame(w.rocket, Vector3.ZERO, 1.5 if k == 4 else 0.9, 18.0 if k == 4 else 12.0, fm)
				fl.rotation = Vector3.ZERO # upright: the wide top at the nozzle, the tip pointing down
				fl.position = at - Vector3(0, (fl.get_meta("base") as Array)[2] / 2.0, 0)
			var pl := OmniLight3D.new()
			pl.light_color = Color(1.0, 0.6, 0.25)
			pl.light_energy = 12.0
			pl.omni_range = 90.0
			pl.position = Vector3(0, -4.0, 0)
			w.rocket.add_child(pl)
			NFDecor.burst(w, base, Vector3.UP, 60, 4.0, 3.5, Vector2(4.0, 14.0), 80.0, Vector3(0, -0.4, 0),
				Color(0.85, 0.82, 0.78, 0.8), Color(0.4, 0.38, 0.36, 0.0), false, 4.0)
	else:
		w.rocket.position = base
		w.rocket.visible = true

## Her ship parked on the pad: it lifts off when she takes it.
func _pad_kship(_dt: float) -> void:
	var w: NightWorld = m.world
	if w.kship_node == null: return
	var f := _fl()
	if bool(f.ks) and k_t >= 0.0:
		var h := 6.0 * k_t * k_t
		w.kship_node.position = w.kship_spot + Vector3(0, h + 1.2, 0)
		w.kship_node.visible = h < 1500.0
	else:
		w.kship_node.position = w.kship_spot + Vector3(0, 1.2, 0)
		w.kship_node.visible = true

## Nose down the line, banked into the turn, tipped up or down with the climb.
func _orient(n: Node3D, v: Vector3, dt: float, bank: float) -> void:
	var roll := clampf(-v.x / 34.0, -1.0, 1.0) * 0.55 * bank
	var pit := clampf(v.y / 34.0, -1.0, 1.0) * 0.22
	var yw := clampf(-v.x / maxf(v.z, 60.0), -0.3, 0.3)
	var want := Basis.from_euler(Vector3(pit, yw, roll))
	n.basis = n.basis.slerp(want, 1.0 - exp(-6.0 * dt)).orthonormalized()

func _flames(_dt: float) -> void:
	var f := _fl()
	var boost := bool(f.b) and float(f.e) > 0.0
	var pw := 0.0
	if int(f.st) == 2: pw = (1.9 if boost else 1.0) * (0.55 if float(f.dm) > 0.0 else 1.0)
	for fl in flames_r:
		var b: Array = fl.get_meta("base")
		var l := float(b[2]) * (1.7 if boost else 1.0) * (0.6 if float(f.dm) > 0.0 else 1.0) * randf_range(0.92, 1.08)
		fl.scale = Vector3(1.0, l / float(b[2]), 1.0)
		fl.position = (b[0] as Vector3) + Vector3(0, 0, l / 2.0)
		(fl.mesh.material as ShaderMaterial).set_shader_parameter("power", pw)
		if boost: (fl.mesh.material as ShaderMaterial).set_shader_parameter("core", Color(0.6, 0.8, 1.0))
		else: (fl.mesh.material as ShaderMaterial).set_shader_parameter("core", Color(0.85, 0.9, 1.0))
	r_light.light_energy = 3.0 + 5.0 * pw
	var kp := (0.5 if float(f.kd) > 0.0 else 1.2) if k_on else 0.0
	for fl in flames_k:
		var b: Array = fl.get_meta("base")
		var l := float(b[2]) * (0.6 + 0.6 * kp) * randf_range(0.92, 1.08)
		fl.scale = Vector3(1.0, l / float(b[2]), 1.0)
		fl.position = (b[0] as Vector3) + Vector3(0, 0, l / 2.0)
		(fl.mesh.material as ShaderMaterial).set_shader_parameter("power", kp)
	k_light.light_energy = 2.0 + 4.0 * kp

## Draw the meteors near `at` and, for the ships flown on this phone, see whether they hit one.
func _meteors(at: Vector3) -> void:
	var a := to_flight(at)
	var lo := a.z - 250.0
	var hi := a.z + VIEW
	var cnt := [0, 0]
	var big_near := Vector3.INF
	var big_d := 1e9
	for i in met.size():
		if gone.has(i): continue
		var e: Array = met[i]
		# a cheap look first: where along the line it is
		var z: float = e[0]
		if int(e[4]) == 2: z += float(e[5]) * (float(e[9]) - clk)
		if z < lo or z > hi: continue
		var mp: Array = meteor_at(i, clk)
		var p: Vector3 = mp[0]
		var r: float = mp[1]
		if r < 0.05: continue
		var k := int(e[7])
		if cnt[k] < (mm[k] as MultiMeshInstance3D).multimesh.instance_count:
			var base: Array = mm_base[k]
			var s := r * 2.0 / maxf(float(base[1]), 0.01)
			var spin := float(e[8]) * clk + float(e[6])
			var b := Basis(Vector3(0.3, 1.0, 0.2).normalized(), spin).scaled(Vector3.ONE * s)
			(mm[k] as MultiMeshInstance3D).multimesh.set_instance_transform(cnt[k], Transform3D(b, to_world(p)) * (base[0] as Transform3D))
			cnt[k] += 1
		# the big ones ahead: an alarm, once each
		if r >= BIG_R and p.z > a.z + 60.0 and p.z - a.z < WARN_D and absf(p.x - a.x) < 90.0 and absf(p.y - a.y) < 70.0:
			if p.z - a.z < big_d:
				big_d = p.z - a.z; big_near = to_world(p)
			if not warned.has(i) and int(_fl().st) == 2 and (flying() or shown):
				warned[i] = true
				warn_t = 3.0
				if m.has_method("_sfx"): m._sfx("warn", null, -2.0, 0.9)
				NFHaptics.pulse("beat")
		# one going past close: the rush of it
		if flying() and pass_cd <= 0.0:
			var me := r_loc if m.my_role != "killer" else k_loc
			if absf(p.z - me.z) < 20.0 and Vector2(p.x - me.x, p.y - me.y).length() < r + 16.0:
				pass_cd = 0.6
				if m.has_method("_sfx"): m._sfx("car_pass", null, -6.0, randf_range(0.7, 0.9))
	warn_at = big_near
	for k in mm.size(): (mm[k] as MultiMeshInstance3D).multimesh.visible_instance_count = cnt[k]

## The meteors near a ship flown on this phone: did it touch one? (Every physics step, so a fast
## ship cannot pass through a small rock between two frames.)
func _collide(s: Vector3, sr: float, sl: float) -> void:
	for i in met.size():
		if gone.has(i) or sent.has(i): continue
		var e: Array = met[i]
		var z: float = e[0]
		if int(e[4]) == 2: z += float(e[5]) * (float(e[9]) - clk)
		if absf(z - s.z) > sl + float(e[3]) + sr + 2.0: continue
		var mp: Array = meteor_at(i, clk)
		_touch(i, mp[0], mp[1], s, sr, sl)

## Did the ship at `s` (radius sr, half length sl along the line) touch meteor i? Once each.
func _touch(i: int, p: Vector3, r: float, s: Vector3, sr: float, sl: float) -> void:
	if sent.has(i): return
	var dz := maxf(absf(p.z - s.z) - sl, 0.0)
	var dxy := Vector2(p.x - s.x, p.y - s.y).length()
	if sqrt(dxy * dxy + dz * dz) < r * 0.82 + sr:
		sent[i] = true
		m._ev({"k": "mhit", "m": i})

func _follow_rocket(dt: float) -> void:
	var pil := str(_fl().pil)
	var p := Vector3.INF
	if pil == m.my_name: p = m.body.position
	elif m.remotes.has(pil): p = m.remotes[pil].pos
	if p == Vector3.INF or not in_space(p):
		if clk < LIFT: r_loc = Vector3.ZERO; r_vel = Vector3(0, 0, 60.0)
		return
	var l := _predict(r_sample, to_flight(p))
	if l.distance_to(r_loc) > 300.0: r_loc = l
	else: r_loc = r_loc.lerp(l, 1.0 - exp(-9.0 * dt))
	r_vel = r_vel.lerp(r_sample.get("v", Vector3.ZERO), 1.0 - exp(-4.0 * dt))

func _follow_kship(dt: float) -> void:
	var kn: String = m.rules.killer
	if not m.remotes.has(kn): return
	var p: Vector3 = m.remotes[kn].pos
	if not in_space(p): return
	var l := _predict(k_sample, to_flight(p))
	if l.distance_to(k_loc) > 300.0: k_loc = l
	else: k_loc = k_loc.lerp(l, 1.0 - exp(-9.0 * dt))
	k_vel = k_vel.lerp(k_sample.get("v", Vector3.ZERO), 1.0 - exp(-4.0 * dt))

## A position that arrives ~15 times a second, run on by the speed it was going at (at most 0.3 s).
func _predict(sm: Dictionary, l: Vector3) -> Vector3:
	var now := Time.get_ticks_msec() / 1000.0
	if not sm.has("p") or (sm.p as Vector3) != l:
		if sm.has("p"):
			var gap := maxf(now - float(sm.t), 0.02)
			var v := (l - (sm.p as Vector3)) / gap
			if v.length() < 600.0: sm.v = (sm.get("v", v) as Vector3).lerp(v, 0.5)
		sm.p = l
		sm.t = now
	return (sm.p as Vector3) + (sm.get("v", Vector3.ZERO) as Vector3) * minf(now - float(sm.t), 0.3)

# ---------------- my own ship ----------------
## Called by main's physics step while I am in it: flies what is mine, puts my body where I am.
func step_me(dt: float) -> void:
	var md := me_mode()
	var f := _fl()
	var stick: Vector2 = m.stick_vec
	if stick == Vector2.ZERO:
		stick = Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	match md:
		"pad", "lift": # inside the rocket on the pad (the camera watches it from outside)
			m.body.position = NightWorld.MOON_BOARD
			if md == "lift" and is_pilot():
				r_loc = Vector3.ZERO
				r_vel = Vector3(0, 0, 40.0)
		"fly":
			if is_pilot():
				_fly(dt, stick, true)
				_collide(r_loc, R_ROCKET, ROCKET_HALF)
				if not sent_land and r_loc.z >= Rules.FLY_LEN:
					sent_land = true
					m._ev({"k": "rland"})
			m.body.position = rocket_world()
		"klift":
			m.body.position = m.world.kship_spot
			k_loc = Vector3(0, 0, -60.0)
			k_vel = Vector3(0, 0, 80.0)
		"kfly":
			_fly(dt, stick, false)
			_collide(k_loc, R_KSHIP, 6.0)
			m.body.position = kship_world()
			_ram_check()
	m.body.velocity = Vector3.ZERO

## Fly a ship: the stick moves it about the line; forward it runs up to its top speed by itself.
func _fly(dt: float, stick: Vector2, is_rocket: bool) -> void:
	var f := _fl()
	var loc := r_loc if is_rocket else k_loc
	var vel := r_vel if is_rocket else k_vel
	var top: float
	var acc: float
	var side: float
	var side_a: float
	if is_rocket:
		top = rocket_target()
		acc = 70.0 if top > vel.z else 140.0
		side = 36.0; side_a = 80.0
	else:
		top = KILLER_MAX * (DMG_MUL if float(f.kd) > 0.0 else 1.0)
		# right in the rocket's exhaust: it throws her about and holds her back
		var d := r_loc - loc
		if d.z > 0.0 and d.z < WASH_L and Vector2(d.x, d.y).length() < WASH_R and rocket.visible:
			top *= WASH_MUL
			trauma = maxf(trauma, 0.25)
		acc = 32.0 if top > vel.z else 120.0
		side = 38.0; side_a = 42.0 # heavier: she cannot jink like the rocket
	if m.rules.over: stick = Vector2.ZERO
	vel.z = move_toward(vel.z, top, acc * dt)
	vel.x = move_toward(vel.x, stick.x * side, side_a * dt)
	vel.y = move_toward(vel.y, -stick.y * side * 0.8, side_a * dt)
	loc += vel * dt
	# the edges of the line: soft walls
	if absf(loc.x) > TUBE_X:
		loc.x = signf(loc.x) * TUBE_X; vel.x = 0.0
	if absf(loc.y) > TUBE_Y:
		loc.y = signf(loc.y) * TUBE_Y; vel.y = 0.0
	if is_rocket:
		r_loc = loc; r_vel = vel
	else:
		k_loc = loc; k_vel = vel

## Her ship against the rocket: the phone flying her says when they touch.
func _ram_check() -> void:
	if sent_ram or not rocket.visible or int(_fl().st) != 2: return
	var d := r_loc - k_loc
	var dz := maxf(absf(d.z) - ROCKET_HALF, 0.0)
	var dxy := Vector2(d.x, d.y).length()
	if sqrt(dxy * dxy + dz * dz) < RAM_D:
		sent_ram = true
		m._ev({"k": "rram"})

## Trial mode: the computer killer takes her ship once she could have reached it, and flies it here.
func _bot_fly(dt: float) -> void:
	if not (m.offline and m.bot != null) or m.rules.killer == "": return
	var f := _fl()
	var kn: String = m.rules.killer
	if int(f.st) != 2: return
	if not bool(f.ks):
		if bot_wait < 0.0 and float(f.c) >= Rules.KSHIP_LOCK:
			var kp: Vector3 = m.remotes[kn].pos if m.remotes.has(kn) else m.world.kship_spot
			bot_wait = minf(Vector2(kp.x - m.world.kship_spot.x, kp.z - m.world.kship_spot.z).length() / 6.0, 10.0) + randf_range(1.0, 3.0)
		if bot_wait >= 0.0:
			bot_wait -= dt
			if bot_wait <= 0.0 and m.rules.carrying == "" and m.rules.stun <= 0.0:
				for e in m.rules.handle({"k": "kship"}, kn): m._on_event(e)
		return
	bot_k = true
	if k_t < K_LIFT:
		k_loc = Vector3(0, 0, -60.0); k_vel = Vector3(0, 0, 80.0)
		if m.remotes.has(kn): m.remotes[kn].pos = m.world.kship_node.global_position if m.world.kship_node else m.world.kship_spot
		return
	# chase the rocket: come up beside it out of the exhaust, then swing in; dodge what is in front
	var d := r_loc - k_loc
	var aim := Vector2(r_loc.x, r_loc.y)
	if d.z > 40.0: aim += Vector2(14.0 if k_loc.x >= r_loc.x else -14.0, 0.0) # alongside, not behind
	for i in met.size():
		if gone.has(i): continue
		var z: float = met[i][0]
		if int(met[i][4]) == 2: z += float(met[i][5]) * (float(met[i][9]) - clk)
		if z < k_loc.z or z > k_loc.z + 160.0: continue
		var mp: Array = meteor_at(i, clk)
		var p: Vector3 = mp[0]
		var off := Vector2(k_loc.x - p.x, k_loc.y - p.y)
		if off.length() < float(mp[1]) + 9.0: aim = Vector2(k_loc.x, k_loc.y) + off.normalized() * 30.0
	var st := (aim - Vector2(k_loc.x, k_loc.y)) / 18.0
	_fly(dt, Vector2(clampf(st.x, -1.0, 1.0), clampf(-st.y, -1.0, 1.0)), false)
	if m.remotes.has(kn): m.remotes[kn].pos = kship_world()
	var dz := maxf(absf(d.z) - ROCKET_HALF, 0.0)
	var dxy := Vector2(d.x, d.y).length()
	if not sent_ram and rocket.visible and sqrt(dxy * dxy + dz * dz) < RAM_D:
		sent_ram = true
		for e in m.rules.handle({"k": "rram"}, kn): m._on_event(e)
	for i in met.size(): # her own meteors (the rules hear it as her)
		if gone.has(i) or sent.has(i): continue
		var z: float = met[i][0]
		if int(met[i][4]) == 2: z += float(met[i][5]) * (float(met[i][9]) - clk)
		if absf(z - k_loc.z) > 40.0: continue
		var mp: Array = meteor_at(i, clk)
		var p: Vector3 = mp[0]
		var dz2 := maxf(absf(p.z - k_loc.z) - 6.0, 0.0)
		var dxy2 := Vector2(p.x - k_loc.x, p.y - k_loc.y).length()
		if sqrt(dxy2 * dxy2 + dz2 * dz2) < float(mp[1]) * 0.82 + R_KSHIP:
			sent[i] = true
			for e in m.rules.handle({"k": "mhit", "m": i}, kn): m._on_event(e)

# ---------------- the camera, the sky, the sound ----------------
func _camera(dt: float) -> void:
	var t := cam_target()
	if not cam.current: cam.make_current()
	look_idle += dt
	if look_idle > 1.0: look = look.lerp(Vector2.ZERO, 1.0 - exp(-2.5 * dt))
	var v: Vector3 = r_vel if t == rocket else k_vel
	var spd := v.z
	var back := 32.0 if t == rocket else 22.0
	var up := 10.0 if t == rocket else 6.0
	var b := Basis.from_euler(Vector3(look.y, look.x, 0.0))
	var off := b * Vector3(-v.x * 0.12 + (7.0 if t == rocket else 0.0), up, back + spd * 0.012)
	var want := t.global_position + off
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-10.0 * dt)) if cam.global_position.distance_to(want) < 80.0 else want
	var look_at := t.global_position + b * Vector3(v.x * 0.15, 3.0 if t == rocket else 1.5, -55.0)
	cam.look_at(look_at, Vector3.UP)
	trauma = maxf(trauma - dt * 1.4, 0.0)
	var sh := trauma * trauma
	var tt := Time.get_ticks_msec() / 1000.0
	cam.rotate_object_local(Vector3(1, 0, 0), sh * 0.06 * sin(tt * 37.0))
	cam.rotate_object_local(Vector3(0, 0, 1), sh * 0.07 * sin(tt * 29.0 + 1.3))
	var boost := bool(_fl().b) and float(_fl().e) > 0.0 and t == rocket
	cam.fov = lerpf(cam.fov, 66.0 + Gfx.fov_add + clampf(spd / 300.0, 0.0, 1.1) * 10.0 + (8.0 if boost else 0.0), 1.0 - exp(-3.0 * dt))

## A drag on the right half swings the camera; it comes back by itself.
func drag(rel: Vector2) -> void:
	look.x = clampf(look.x - rel.x * 0.005, -2.6, 2.6)
	look.y = clampf(look.y - rel.y * 0.004, -0.8, 0.6)
	look_idle = 0.0

func shake(p: float) -> void:
	trauma = clampf(maxf(trauma, p), 0.0, 1.0)

func _streaks(_dt: float) -> void:
	var c := cam.global_position
	var v := r_vel.z if cam_target() == rocket else k_vel.z
	var l := clampf(v * 0.05, 0.5, 18.0)
	var mmesh := streaks.multimesh
	for i in streak_p.size():
		var base: Vector3 = FLY_O + streak_p[i]
		var rel := base - c
		rel.x = wrapf(rel.x, -70.0, 70.0)
		rel.y = wrapf(rel.y, -45.0, 45.0)
		rel.z = wrapf(rel.z, -380.0, 40.0)
		var lat := Vector2(rel.x, rel.y)
		if lat.length() < 12.0: # not right across the lens
			lat = lat.normalized() * 12.0 if lat.length() > 0.01 else Vector2(12.0, 0.0)
			rel.x = lat.x; rel.y = lat.y
		mmesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1, 1, l)), c + rel))

## On this phone: while the flight is on the screen, the Earth is straight ahead and grows as they near it.
func _sky(on: bool) -> void:
	var sm: ShaderMaterial = m.world._sky_mat if m.world else null
	if sm == null: return
	if on:
		var near_k := clampf((r_loc.z if cam_target() == rocket else k_loc.z) / Rules.FLY_LEN, 0.0, 1.0)
		sm.set_shader_parameter("moon_dir", Vector3(0.0, 0.14, -1.0).normalized())
		sm.set_shader_parameter("disc_r", lerpf(0.13, 0.62, near_k * near_k))
		sm.set_shader_parameter("meteor_dir", Vector3(0.34, 0.24, -0.9).normalized())
		sm.set_shader_parameter("meteor_near", lerpf(0.25, 0.42, near_k))
		if not sky_set:
			sky_set = true
			var env: Environment = m.world.env
			if env:
				env.set_meta("fly_fog", [env.fog_enabled, env.volumetric_fog_enabled])
				env.fog_enabled = false
				env.volumetric_fog_enabled = false
	elif sky_set:
		sky_set = false
		sm.set_shader_parameter("moon_dir", NightWorld.MOON_EARTH.normalized())
		sm.set_shader_parameter("disc_r", 0.12)
		sm.set_shader_parameter("meteor_dir", NightWorld.MOON_METEOR.normalized())
		var env: Environment = m.world.env
		if env and env.has_meta("fly_fog"):
			var ff: Array = env.get_meta("fly_fog")
			env.fog_enabled = ff[0]; env.volumetric_fog_enabled = ff[1]
		if m.main_cam and m.get("ending") == null: m.main_cam.make_current()

func _sound(dt: float, on: bool) -> void:
	var f := _fl()
	var near := false
	if on: near = true
	elif int(f.st) == 2 and clk < LIFT + 2.0 and m.body.position.distance_to(NightWorld.MOON_ROCKET) < 300.0: near = true
	var boost := bool(f.b) and float(f.e) > 0.0
	var want := -8.0 if near else -60.0
	if not eng.playing and near: eng.play()
	eng.volume_db = lerpf(eng.volume_db, want, 1.0 - exp(-3.0 * dt))
	eng.pitch_scale = lerpf(eng.pitch_scale, (0.62 if not boost else 0.85) * (0.8 if float(f.dm) > 0.0 else 1.0), 1.0 - exp(-4.0 * dt))
	if not wind.playing and on: wind.play()
	wind.volume_db = lerpf(wind.volume_db, -20.0 if on else -60.0, 1.0 - exp(-3.0 * dt))
	wind.pitch_scale = 0.5
	if eng.volume_db < -58.0 and eng.playing and not near: eng.stop()
	if wind.volume_db < -58.0 and wind.playing and not on: wind.stop()

# ---------------- events ----------------
func on_event(e: Dictionary) -> void:
	match str(e.get("k", "")):
		"launch":
			r_loc = Vector3.ZERO; r_vel = Vector3(0, 0, 40.0)
			sent_land = false; sent_ram = false
			if m.body.position.distance_to(NightWorld.MOON_ROCKET) < 200.0 or me_mode() != "": shake(0.6)
		"mhit":
			var i := int(e.get("m", -1))
			if i < 0 or i >= met.size(): return
			gone[i] = true
			var p := to_world(meteor_at(i, clk)[0])
			var r := float(met[i][3])
			var who := str(e.get("n", ""))
			var on_k: bool = who == m.rules.killer
			# rock flying apart, a flash of fire, sparks off the ship
			NFDecor.burst(self, p, Vector3.UP, 40, 1.6, maxf(r * 0.35, 0.6), Vector2(r * 2.0, r * 6.0), 180.0, Vector3.ZERO,
				Color(0.55, 0.5, 0.45, 1.0), Color(0.2, 0.18, 0.16, 0.0), false, 1.5)
			NFDecor.burst(self, p, Vector3.UP, 30, 0.7, maxf(r * 0.6, 1.2), Vector2(r * 1.5, r * 4.0), 180.0, Vector3.ZERO,
				Color(1.0, 0.75, 0.35, 1.0), Color(1.0, 0.25, 0.05, 0.0), true, 2.2)
			var fl := OmniLight3D.new()
			fl.light_color = Color(1.0, 0.6, 0.25)
			fl.light_energy = 14.0
			fl.omni_range = 60.0 + r * 3.0
			add_child(fl)
			fl.global_position = p
			var tw := fl.create_tween()
			tw.tween_property(fl, "light_energy", 0.0, 0.6)
			tw.tween_callback(fl.queue_free)
			var mine: bool = (on_k and m.my_role == "killer") or (not on_k and m.rules.in_rocket(m.my_name))
			if mine or shown:
				if m.has_method("_sfx"): m._sfx("gen_boom", null, 0.0 if mine else -8.0, 0.8)
			if mine:
				shake(0.85)
				hit_flash = 1.0
				NFHaptics.pulse("hit")
				if not on_k: r_vel.z *= 0.6 # the blow knocks the speed out of it
				else: k_vel.z *= 0.6
		"kship":
			k_t = 0.0
			k_loc = Vector3(0, 0, -60.0)
			if m.world.kship_node and m.body.position.distance_to(m.world.kship_spot) < 200.0:
				NFDecor.burst(m.world, m.world.kship_spot, Vector3.UP, 50, 3.0, 3.0, Vector2(3.0, 10.0), 80.0, Vector3.ZERO,
					Color(0.8, 0.85, 0.9, 0.8), Color(0.4, 0.4, 0.45, 0.0), false, 3.0)
		"rland":
			landed = true
		"rlost":
			if str(e.get("why", "")) == "ram":
				var p2 := rocket_world()
				NFDecor.burst(self, p2, Vector3.UP, 90, 2.5, 4.0, Vector2(10.0, 40.0), 180.0, Vector3.ZERO,
					Color(1.0, 0.8, 0.4, 1.0), Color(0.5, 0.1, 0.02, 0.0), true, 4.0)
				if shown: shake(1.0)
				if m.has_method("_sfx") and shown: m._sfx("impact", null, 2.0)

# ---------------- the HUD ----------------
## The panel over the top while I am in it or watching it, and the alarms.
func draw_hud(ui: CanvasItem, vs: Vector2) -> void:
	var f := _fl()
	var st := int(f.st)
	var md := me_mode()
	var c := Vector2(vs.x / 2.0, 0.0)
	var font: Font = Net.font
	if md == "pad":
		_panel(ui, Rect2(c + Vector2(-260, 70), Vector2(520, 96)))
		var who := (f.who as Array).size()
		_txt(ui, font, c + Vector2(0, 108), "Lift-off in %d" % ceili(float(f.t)), 40, Color(1.0, 0.85, 0.4))
		var role := "You steer the rocket" if is_pilot() else ("You fire the boost" if is_boost() else "You're aboard")
		_txt(ui, font, c + Vector2(0, 148), "%s — %d aboard" % [role, who], 18, Color(0.85, 0.95, 1.0))
		return
	if st != 2 or not shown: return
	var me_k: bool = md == "kfly" or (m.spectating != "" and m.spectating == m.rules.killer)
	var z := k_loc.z if me_k else r_loc.z
	var left := maxf(Rules.FLY_LEN - z, 0.0)
	var t := float(f.t)
	var urgent := t < 30.0
	var col := Color(0.55, 0.85, 1.0) if not urgent else Color(1.0, 0.45 + 0.25 * sin(Time.get_ticks_msec() / 160.0), 0.3)
	var box := Rect2(c + Vector2(-250, 62), Vector2(500, 122))
	_panel(ui, box)
	_txt(ui, font, c + Vector2(0, 88), "Rocket — to the Earth" if me_k else "To the Earth", 17, Color(0.8, 0.9, 1.0))
	_txt(ui, font, c + Vector2(0, 132), "%.1f km" % (left / 1000.0), 44, col)
	_txt(ui, font, c + Vector2(0, 162), "%d:%02d" % [int(ceil(t)) / 60, int(ceil(t)) % 60], 24, col)
	# the strip: Moon on the left, Earth on the right, the rocket and her on it
	var a := c + Vector2(-230, 178)
	var b := c + Vector2(230, 178)
	ui.draw_line(a, b, Color(1, 1, 1, 0.2), 5.0, true)
	var fr := clampf(r_loc.z / Rules.FLY_LEN, 0.0, 1.0)
	ui.draw_line(a, a.lerp(b, fr), Color(0.5, 0.85, 1.0), 5.0, true)
	ui.draw_circle(a, 6.0, Color(0.75, 0.75, 0.75))
	ui.draw_circle(b, 8.0, Color(0.3, 0.55, 1.0))
	ui.draw_circle(a.lerp(b, fr), 7.0, Color(1, 1, 1))
	if k_on: ui.draw_circle(a.lerp(b, clampf(k_loc.z / Rules.FLY_LEN, 0.0, 1.0)), 6.0, Color(1.0, 0.2, 0.15))
	# the speed and the boost, bottom left of the middle
	var spd := k_vel.z if me_k else r_vel.z
	var sp := Vector2(vs.x / 2.0 - 250.0, vs.y - 96.0)
	_panel(ui, Rect2(sp - Vector2(10, 40), Vector2(190, 84)))
	_txt(ui, font, sp + Vector2(85, -10), "%d" % roundi(spd), 34, Color(1, 1, 1), 180.0)
	_txt(ui, font, sp + Vector2(85, 14), "speed (max %d)" % roundi(KILLER_MAX if me_k else ROCKET_MAX), 13, Color(0.75, 0.85, 0.95), 180.0)
	if not me_k:
		var e := float(f.e)
		var bar := Rect2(sp + Vector2(0, 26), Vector2(170, 10))
		ui.draw_rect(bar, Color(1, 1, 1, 0.15))
		ui.draw_rect(Rect2(bar.position, Vector2(bar.size.x * e, bar.size.y)), Color(0.35, 0.75, 1.0) if not bool(f.b) else Color(0.6, 0.9, 1.0))
	var dmg := float(f.kd) if me_k else float(f.dm)
	if dmg > 0.0:
		_txt(ui, font, c + Vector2(0, 214), "ENGINE DAMAGED", 24, Color(1.0, 0.35 + 0.25 * sin(Time.get_ticks_msec() / 90.0), 0.2))
	# the other ship: how far, and a bracket on it
	if k_on:
		var gap := r_loc.z - k_loc.z
		var msg := ""
		var mc := Color(1, 1, 1)
		if me_k:
			msg = "Rocket %d m ahead" % roundi(gap) if gap > 0.0 else "Rocket %d m behind" % roundi(-gap)
			mc = Color(1.0, 0.75, 0.4)
			_bracket(ui, rocket.global_position, Color(1.0, 0.75, 0.3), "ROCKET")
		else:
			msg = "The killer is %d m behind" % roundi(gap) if gap > 0.0 else "The killer is ahead"
			mc = Color(1.0, 0.4, 0.3) if gap < 400.0 else Color(1.0, 0.75, 0.6)
			if gap < 160.0: msg = "SHE'S RIGHT BEHIND YOU!"
			_bracket(ui, kship.global_position, Color(1.0, 0.25, 0.2), "KILLER")
		_txt(ui, font, c + Vector2(0, 240), msg, 22, mc)
	elif bool(f.ks) and not me_k:
		_txt(ui, font, c + Vector2(0, 240), "The killer is taking off after you!", 22, Color(1.0, 0.45, 0.3))
	# the big-meteor alarm
	if warn_t > 0.0 and warn_at != Vector3.INF:
		var on := fmod(Time.get_ticks_msec() / 1000.0, 0.4) < 0.24
		if on: _txt(ui, font, Vector2(vs.x / 2.0, vs.y * 0.47), "⚠ BIG METEOR AHEAD ⚠", 34, Color(1.0, 0.3, 0.2))
		_bracket(ui, warn_at, Color(1.0, 0.3, 0.2), "")
		ui.draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.1, 0.05, 0.10 * warn_t / 3.0 * (1.0 if on else 0.4)), false, 18.0)
	if hit_flash > 0.0: ui.draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.45, 0.2, 0.35 * hit_flash))
	# who does what
	var role := ""
	if md == "fly": role = "Steer with the stick — dodge the meteors" if is_pilot() and is_boost() else ("Steer with the stick — dodge the meteors" if is_pilot() else ("Boost when it's clear — %s steers" % str(f.pil) if is_boost() else "Passenger — %s steers" % str(f.pil)))
	elif md == "kfly": role = "Catch the rocket and ram it — stay out of its exhaust"
	if role != "": _txt(ui, font, Vector2(vs.x / 2.0, vs.y - 28.0), role, 16, Color(0.85, 0.9, 1.0))

func _panel(ui: CanvasItem, r: Rect2) -> void:
	ui.draw_rect(r, Color(0.02, 0.03, 0.06, 0.72))
	ui.draw_rect(r, Color(0.4, 0.6, 1.0, 0.55), false, 2.0)

func _txt(ui: CanvasItem, font: Font, at: Vector2, t: String, size: int, col: Color, width := 700.0) -> void:
	ui.draw_string_outline(font, at - Vector2(width / 2.0, 0), t, HORIZONTAL_ALIGNMENT_CENTER, width, size, 6, Color(0, 0, 0, 0.8))
	ui.draw_string(font, at - Vector2(width / 2.0, 0), t, HORIZONTAL_ALIGNMENT_CENTER, width, size, col)

## Corners round a point in the world on the screen (or an arrow at the edge if it is behind).
func _bracket(ui: CanvasItem, w: Vector3, col: Color, label: String) -> void:
	if not cam.current: return
	var vs := ui.get_viewport_rect().size
	var behind := cam.is_position_behind(w)
	var sp := cam.unproject_position(w)
	if behind or not Rect2(Vector2.ZERO, vs).has_point(sp):
		var mid := vs / 2.0
		var d := (sp - mid) * (-1.0 if behind else 1.0)
		if d.length() < 1.0: d = Vector2(0, 1)
		var e := mid + d.normalized() * minf(vs.x, vs.y) * 0.42
		var n := d.normalized()
		ui.draw_colored_polygon(PackedVector2Array([e + n * 16.0, e - n * 8.0 + n.orthogonal() * 10.0, e - n * 8.0 - n.orthogonal() * 10.0]), col)
		return
	var s := 22.0
	for k in 4:
		var dx := -1.0 if k % 2 == 0 else 1.0
		var dy := -1.0 if k < 2 else 1.0
		var cn := sp + Vector2(dx, dy) * s
		ui.draw_line(cn, cn - Vector2(dx * 9.0, 0), col, 3.0)
		ui.draw_line(cn, cn - Vector2(0, dy * 9.0), col, 3.0)
	if label != "": _txt(ui, Net.font, sp + Vector2(0, -30), label, 14, col, 200.0)

## The boost button for whoever has it (the second one aboard, or the pilot flying alone).
func buttons(vs: Vector2) -> Array:
	var md := me_mode()
	if md != "fly" or not is_boost(): return []
	var f := _fl()
	var on := bool(f.b)
	return [[Vector2(vs.x - 150.0, vs.y - 150.0), 70.0, "Boost off" if on else ("Boost" if float(f.e) > 0.1 else "Charging"), "fboost", float(f.e) > 0.1 or on, "nitro"]]

func press(id: String) -> void:
	if id == "fboost":
		var f := _fl()
		m._ev({"k": "boost", "on": not bool(f.b)})
		NFHaptics.pulse("tick")
