class_name NFEnding
extends Node3D
## «The Moon», stage 3: how it ends, played on every phone the moment the rules settle the flight
## (`rland` / `rlost`), far from everything (END_O) under its own camera and sky.
## Won: the rocket climbs, slips past the giant meteor, the survivors watch it fall toward the Earth,
## and they fly on past the planet — «HUMANITY SURVIVED».
## Lost (rammed or out of time): the meteor comes down through the air, hits, the shockwave runs over the
## planet, it cracks and breaks apart — «HUMANITY HAS FALLEN», held exactly LOSE_LEN before the numbers.
## His Blue Marble is cut into twelve pieces by tools/earth_split.py (every triangle kept): together they
## are the whole planet; apart they are what is left of it.

const END_O := Vector3(0.0, 60000.0, 0.0)
const R := 3000.0           # the Earth's radius here
const RM := 720.0           # the giant meteor's
const WIN_LEN := 14.0
const LOSE_LEN := 12.0      # the owner: exactly twelve seconds before the statistics
const IMPACT := 4.2         # seconds into the loss when it hits
## The same twelve directions as tools/earth_split.py: each piece of the planet flies out along its own.
const SEEDS := [Vector3(-0.4501, 0.7931, 0.4104), Vector3(0.5783, 0.7931, 0.1913), Vector3(-0.5783, -0.7931, -0.1913), Vector3(0.4501, -0.7931, -0.4104), Vector3(0.1257, -0.7978, 0.5897), Vector3(0.2050, 0.1825, 0.9616), Vector3(-0.2050, -0.1825, -0.9616), Vector3(-0.1257, 0.7978, -0.5897), Vector3(0.7298, 0.1901, -0.6567), Vector3(0.9341, -0.1901, 0.3021), Vector3(-0.9341, 0.1901, -0.3021), Vector3(-0.7298, -0.1901, 0.6567)]

var m: Node
var won := false
var t := 0.0
var done := false
var names: Array = []
var cam: Camera3D
var earth: Node3D
var pieces: Array = []      # [node, its direction]
var mats: Array = []
var atmo_mat: ShaderMaterial
var meteor: Node3D
var m_glow: ShaderMaterial
var m_trail: MeshInstance3D
var rocket: Node3D
var r_flames: Array = []
var fireball: MeshInstance3D
var fb_mat: ShaderMaterial
var sun: DirectionalLight3D
var debris: MultiMeshInstance3D
var debris_v: Array = []    # [start, velocity, spin axis, scale]
var hit_dir := Vector3(0.38, 0.46, 0.8).normalized()
var shake := 0.0
var flash := 0.0
var played := {}
var layer: CanvasLayer
var ui: Control
var hid_light: Light3D
var _cpos := Vector3.ZERO
var st := 0.0               # the defeat's story clock: it slows right down round the impact (real time stays 12 s)
var ring: MeshInstance3D    # the shockwave racing over the surface from the impact
var ring_mat: ShaderMaterial
var praxis: MeshInstance3D  # the great flat ring thrown out into space as the planet breaks
var praxis_mat: ShaderMaterial
var plume: MeshInstance3D   # the column of fire and rock blown back up out of the crater
var plume_mat: ShaderMaterial
const SLOW_A := 3.8         # real seconds: the slow motion starts
const SLOW_B := 5.6         # and ends
const SLOW := 0.3           # at this speed

func setup(main: Node, did_win: bool, who: Array) -> void:
	m = main
	won = did_win
	names = who
	name = "Ending"
	position = END_O
	_build_earth()
	_build_meteor()
	if won: _build_rocket()
	_build_fx()
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_energy = 2.4
	sun.shadow_enabled = false
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.55, -0.25, -0.8), Vector3.UP) # from the upper right, behind the camera
	cam = Camera3D.new()
	cam.far = 90000.0
	cam.near = 2.0
	cam.fov = 52.0
	cam.environment = _environment()
	add_child(cam)
	cam.make_current()
	# the Moon's earthshine and the map's lights stay out of it
	var w = m.world if m else null
	if w and w.get("moon") is Light3D:
		hid_light = w.moon
		hid_light.visible = false
	layer = CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.draw.connect(_draw_ui)
	layer.add_child(ui)
	_step(0.0)

func _environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm: ShaderMaterial
	if m and m.world and m.world._sky_mat:
		sm = (m.world._sky_mat as ShaderMaterial).duplicate() as ShaderMaterial
	else:
		sm = ShaderMaterial.new()
		sm.shader = load("res://shaders/sky.gdshader")
		sm.set_shader_parameter("space", 1.0)
		if ResourceLoader.exists("res://assets/sky/moon_stars.jpg"):
			sm.set_shader_parameter("night_tex", load("res://assets/sky/moon_stars.jpg"))
			sm.set_shader_parameter("has_night_tex", 1.0)
	# only the stars: the Earth and the meteor are real here
	sm.set_shader_parameter("moon_dir", Vector3(0.0, -1.0, 0.0))
	sm.set_shader_parameter("disc_r", 0.0005)
	sm.set_shader_parameter("meteor_near", 0.0)
	sm.set_shader_parameter("has_p2", 0.0)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.1, 0.12, 0.18)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.12
	e.glow_hdr_threshold = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 1.08
	return e

func _build_earth() -> void:
	earth = Node3D.new()
	earth.name = "Earth"
	add_child(earth)
	var ps: PackedScene = load("res://assets/props/space/earth_pieces.glb") if ResourceLoader.exists("res://assets/props/space/earth_pieces.glb") else null
	var shader: Shader = load("res://shaders/earth_break.gdshader")
	var seeds := PackedVector3Array(SEEDS)
	if ps:
		var root := ps.instantiate() as Node3D
		root.scale = Vector3.ONE * (R / 0.951)
		earth.add_child(root)
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var mesh_i := mi as MeshInstance3D
			var k := int(String(mesh_i.name).trim_prefix("piece")) if String(mesh_i.name).begins_with("piece") else -1
			var src := mesh_i.get_active_material(0) as BaseMaterial3D
			var sm := ShaderMaterial.new()
			sm.shader = shader
			if src:
				sm.set_shader_parameter("albedo_tex", src.albedo_texture)
				sm.set_shader_parameter("normal_tex", src.normal_texture)
				sm.set_shader_parameter("mr_tex", src.roughness_texture if src.roughness_texture else src.metallic_texture)
			sm.set_shader_parameter("seeds", seeds)
			sm.set_shader_parameter("hit_dir", hit_dir)
			mesh_i.material_override = sm
			mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mats.append(sm)
			# a piece drifts from where it sat in the planet
			var dir: Vector3 = SEEDS[k] if k >= 0 and k < SEEDS.size() else Vector3.UP
			var holder := Node3D.new()
			root.add_child(holder)
			mesh_i.reparent(holder, false)
			pieces.append([holder, dir])
	else: # no model: a plain blue ball
		var mi := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = R; sp.height = R * 2.0
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.2, 0.4, 0.9)
		sp.material = sm
		mi.mesh = sp
		earth.add_child(mi)
	# the air: a blue rim
	var am := MeshInstance3D.new()
	var asp := SphereMesh.new()
	asp.radius = R * 1.03; asp.height = R * 2.06; asp.radial_segments = 96; asp.rings = 48
	atmo_mat = ShaderMaterial.new()
	atmo_mat.shader = load("res://shaders/glow_shell.gdshader")
	atmo_mat.set_shader_parameter("col", Color(0.3, 0.55, 1.0))
	atmo_mat.set_shader_parameter("power", 1.4)
	atmo_mat.set_shader_parameter("rim", 2.5)
	asp.material = atmo_mat
	am.mesh = asp
	am.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	earth.add_child(am)

func _build_meteor() -> void:
	meteor = Node3D.new()
	meteor.name = "GiantMeteor"
	add_child(meteor)
	var ps: PackedScene = load("res://assets/props/space/giant_meteor.glb") if ResourceLoader.exists("res://assets/props/space/giant_meteor.glb") else null
	if ps:
		var mdl := ps.instantiate() as Node3D
		mdl.scale = Vector3.ONE * (RM / 0.94)
		meteor.add_child(mdl)
		for mi in mdl.find_children("*", "MeshInstance3D", true, false): (mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gm := MeshInstance3D.new()
	var gs := SphereMesh.new()
	gs.radius = RM * 1.18; gs.height = RM * 2.36
	m_glow = ShaderMaterial.new()
	m_glow.shader = load("res://shaders/glow_shell.gdshader")
	m_glow.set_shader_parameter("col", Color(1.0, 0.45, 0.12))
	m_glow.set_shader_parameter("power", 0.6)
	m_glow.set_shader_parameter("rim", 2.0)
	gs.material = m_glow
	gm.mesh = gs
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	meteor.add_child(gm)
	# its tail of fire, streaming back the way it came
	m_trail = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = RM * 0.95; cm.bottom_radius = RM * 0.1; cm.height = RM * 9.0; cm.radial_segments = 24; cm.rings = 1
	cm.cap_top = false; cm.cap_bottom = false
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/flame.gdshader")
	fm.set_shader_parameter("core", Color(1.0, 0.8, 0.5))
	fm.set_shader_parameter("tail", Color(1.0, 0.3, 0.05))
	fm.set_shader_parameter("power", 0.5)
	cm.material = fm
	m_trail.mesh = cm
	m_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m_trail)

func _build_rocket() -> void:
	rocket = Node3D.new()
	rocket.name = "Rocket"
	add_child(rocket)
	var body := Node3D.new()
	body.rotation.x = -PI / 2.0 # nose down -z
	rocket.add_child(body)
	if ResourceLoader.exists("res://assets/props/moon_rocket_ship.glb"):
		var mdl := (load("res://assets/props/moon_rocket_ship.glb") as PackedScene).instantiate() as Node3D
		mdl.position = Vector3(-0.15, -13.5, 0.5)
		body.add_child(mdl)
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/flame.gdshader")
	fm.set_shader_parameter("core", Color(0.6, 0.8, 1.0))
	fm.set_shader_parameter("tail", Color(1.0, 0.45, 0.1))
	fm.set_shader_parameter("power", 1.9)
	for k in 5:
		var a := PI / 4.0 + k * PI / 2.0
		var at := Vector3(0, 0, 12.6) if k == 4 else Vector3(cos(a) * 2.5, sin(a) * 2.5, 11.4)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var l := 30.0 if k == 4 else 20.0
		cm.top_radius = 1.6 if k == 4 else 1.0; cm.bottom_radius = 0.05; cm.height = l; cm.radial_segments = 16; cm.rings = 1
		cm.cap_top = false; cm.cap_bottom = false
		cm.material = fm
		mi.mesh = cm
		mi.rotation.x = -PI / 2.0
		mi.position = at + Vector3(0, 0, l / 2.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rocket.add_child(mi)
		r_flames.append(mi)
	var lt := OmniLight3D.new()
	lt.light_color = Color(1.0, 0.65, 0.35)
	lt.light_energy = 8.0
	lt.omni_range = 60.0
	lt.position = Vector3(0, 0, 20.0)
	rocket.add_child(lt)
	var key := OmniLight3D.new()
	key.light_color = Color(0.8, 0.85, 1.0)
	key.light_energy = 2.0
	key.omni_range = 40.0
	key.position = Vector3(8.0, 10.0, -6.0)
	rocket.add_child(key)

func _build_fx() -> void:
	fireball = MeshInstance3D.new()
	var fs := SphereMesh.new()
	fs.radius = 1.0; fs.height = 2.0; fs.radial_segments = 48; fs.rings = 24
	fb_mat = ShaderMaterial.new()
	fb_mat.shader = load("res://shaders/fireball.gdshader")
	var nt := NoiseTexture2D.new()
	var fnl := FastNoiseLite.new()
	fnl.frequency = 0.02
	nt.noise = fnl
	nt.seamless = true
	nt.width = 256; nt.height = 256
	fb_mat.set_shader_parameter("noise_tex", nt)
	fs.material = fb_mat
	fireball.mesh = fs
	fireball.visible = false
	fireball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fireball)
	# the planet's debris: rocks flying out of the cracks
	debris = MultiMeshInstance3D.new()
	var mmesh := MultiMesh.new()
	mmesh.transform_format = MultiMesh.TRANSFORM_3D
	var mt: Array = m.world._rock_mesh("moon_rock1") if (m and m.world and m.world.has_method("_rock_mesh")) else []
	if mt.is_empty():
		var bm := SphereMesh.new()
		bm.radius = 0.5; bm.height = 1.0
		mt = [bm, Transform3D()]
	mmesh.mesh = mt[0]
	var n := 110 if Gfx.weak else 220
	mmesh.instance_count = n
	mmesh.visible_instance_count = 0
	debris.multimesh = mmesh
	debris.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	debris.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(debris)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2001
	for i in n:
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		if d.dot(hit_dir) < -0.2: d = (d + hit_dir * 0.9).normalized() # most of it from the struck side
		var spd := rng.randf_range(220.0, 900.0)
		var sc := rng.randf_range(10.0, 70.0) * 2.0
		if not won and i % 5 == 0: # a fifth of it comes straight at the last camera, fast and big
			d = (CAM_END.normalized() + Vector3(rng.randfn(), rng.randfn(), rng.randfn()) * 0.12).normalized()
			spd = rng.randf_range(2600.0, 3900.0)
			sc *= 2.2
		debris_v.append([d * R * rng.randf_range(0.95, 1.02), d * spd, Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized(), sc])
	if not won: _build_blast(nt)

const CAM_END := Vector3(4300.0, 3100.0, 12500.0) # where the last shot of the defeat looks from

func _ring_quad(mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	pm.material = mat
	mi.mesh = pm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	mi.extra_cull_margin = 16000.0
	add_child(mi)
	return mi

## The defeat's blast: a shockwave ring over the surface, a plume out of the crater, and the great ring
## thrown out into space when the planet goes.
func _build_blast(nt: Texture2D) -> void:
	ring_mat = ShaderMaterial.new()
	ring_mat.shader = load("res://shaders/shock_ring.gdshader")
	ring_mat.set_shader_parameter("noise_tex", nt)
	ring = _ring_quad(ring_mat)
	var h := hit_dir * R
	ring.basis = Basis.looking_at(-hit_dir, Vector3.UP if absf(hit_dir.y) < 0.95 else Vector3.RIGHT) * Basis(Vector3(1, 0, 0), PI / 2.0)
	ring.position = h * 1.012
	praxis_mat = ShaderMaterial.new()
	praxis_mat.shader = load("res://shaders/shock_ring.gdshader")
	praxis_mat.set_shader_parameter("noise_tex", nt)
	praxis_mat.set_shader_parameter("col", Color(1.0, 0.45, 0.2))
	praxis_mat.set_shader_parameter("hot", Color(1.0, 0.9, 0.75))
	praxis = _ring_quad(praxis_mat)
	praxis.basis = Basis(Vector3(1, 0, 0), 0.32) * Basis(Vector3(0, 0, 1), -0.18) # nearly level, tipped toward the camera
	plume = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45; cm.bottom_radius = 1.0; cm.height = 1.0; cm.radial_segments = 32; cm.rings = 1 # (the top is at the crater: hot there, fading as it widens out)
	cm.cap_top = false; cm.cap_bottom = false
	plume_mat = ShaderMaterial.new()
	plume_mat.shader = load("res://shaders/flame.gdshader")
	plume_mat.set_shader_parameter("core", Color(1.0, 0.85, 0.55))
	plume_mat.set_shader_parameter("tail", Color(0.9, 0.25, 0.05))
	plume_mat.set_shader_parameter("power", 0.0)
	cm.material = plume_mat
	plume.mesh = cm
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plume.visible = false
	plume.extra_cull_margin = 16000.0
	add_child(plume)

## How fast the story runs at real time tt: full speed, then a slow stretch round the impact.
func _story_rate(tt: float) -> float:
	var a := smoothstep(SLOW_A - 0.25, SLOW_A + 0.15, tt)
	var b := 1.0 - smoothstep(SLOW_B - 0.15, SLOW_B + 0.3, tt)
	return lerpf(1.0, SLOW, a * b)

# ---------------- the timeline ----------------
func _process(dt: float) -> void:
	if done: return
	t += dt
	_step(dt)
	if t >= (WIN_LEN if won else LOSE_LEN):
		done = true

func _step(dt: float) -> void:
	if cam and not cam.current: cam.make_current()
	shake = maxf(shake - dt * 0.9, 0.0)
	flash = maxf(flash - dt * 1.6, 0.0)
	if won: _win(dt)
	else: _lose(dt)
	if shake > 0.0:
		var tt := Time.get_ticks_msec() / 1000.0
		cam.rotate_object_local(Vector3(1, 0, 0), shake * shake * 0.04 * sin(tt * 31.0))
		cam.rotate_object_local(Vector3(0, 0, 1), shake * shake * 0.05 * sin(tt * 23.0 + 1.1))
	ui.queue_redraw()

func _once(key: String) -> bool:
	if played.has(key): return false
	played[key] = true
	return true

func _sfx(n: String, db := 0.0, p := 1.0) -> void:
	if m and m.has_method("_sfx"): m._sfx(n, null, db, p)

## The camera: glide toward `at`, looking at `look` (a cut when it is far from where it was).
func _cam(at: Vector3, look: Vector3, dt: float, fov: float, k := 4.0) -> void:
	if dt <= 0.0 or k <= 0.0 or _cpos.distance_to(at) > 2500.0: _cpos = at # (k 0: held to what it follows)
	else: _cpos = _cpos.lerp(at, 1.0 - exp(-k * dt))
	cam.position = _cpos
	cam.look_at(to_global(look), Vector3.UP)
	cam.fov = lerpf(cam.fov, fov, 1.0 - exp(-3.0 * maxf(dt, 0.0001))) if dt > 0.0 else fov

# ---------------- won ----------------
func rocket_at(tt: float) -> Vector3:
	return Vector3(3500.0, 300.0 + 80.0 * tt + 6.0 * tt * tt, 14000.0 - 700.0 * tt - 30.0 * tt * tt)

func meteor_win(tt: float) -> Vector3:
	return Vector3(2900.0 - 60.0 * tt, 100.0 - 10.0 * tt, 10600.0 - 300.0 * tt)

func _win(dt: float) -> void:
	var rp := rocket_at(t)
	var rv := (rocket_at(t + 0.05) - rp) / 0.05
	rocket.position = rp
	rocket.basis = Basis.looking_at(rv.normalized(), Vector3.UP) # its nose (-z) along the way it goes
	for fl in r_flames: (fl as MeshInstance3D).scale = Vector3(1.0, randf_range(0.9, 1.1), 1.0)
	var mp := meteor_win(t)
	_place_meteor(mp, (meteor_win(t + 0.05) - mp) / 0.05, 0.25)
	m_trail.visible = false # out here it does not burn yet
	if t < 3.5: # beside it as it climbs, the rock ahead
		_cam(rp + Vector3(30.0 - t * 3.0, -10.0 + t, 62.0 - t * 4.0), rp + Vector3(-60.0, 24.0, -500.0), dt, 50.0, 0.0)
	elif t < 7.0: # right behind it: the near miss
		_cam(rp + Vector3(9.0, 5.0, 38.0), rp + Vector3(-40.0, 2.0, -300.0), dt, 58.0, 0.0)
		if t > 4.4 and _once("pass"):
			_sfx("car_pass", 4.0, 0.45)
			shake = 0.9
			NFHaptics.pulse("impact")
	elif t < 10.5: # off to one side: the meteor burning its way toward the Earth, the rocket ahead of it
		var k := (t - 7.0) / 3.5
		_cam(Vector3(7600.0, 1900.0 + 200.0 * k, 9800.0 - 400.0 * k), Vector3(1900.0, 200.0, 5600.0), dt, 40.0, 1.5)
	else: # by the planet's edge as they fly past it, into the dark
		var k2 := (t - 10.5) / 3.5
		_cam(rp + Vector3(50.0, 22.0, 120.0 + 260.0 * k2), rp + Vector3(-150.0, -60.0, -2500.0), dt, 52.0, 0.0)
		if t > 11.0 and _once("chime"): _sfx("chime", 0.0, 0.8)
	if t < 0.2 and _once("go"): _sfx("gen_boom", -4.0, 0.5)

# ---------------- lost ----------------
func meteor_lose(tt: float) -> Vector3:
	var come := (hit_dir * 0.75 + Vector3(0.45, 0.42, 0.05)).normalized()
	var h := hit_dir * (R + RM * 0.25)
	return h + come * maxf(IMPACT - tt, 0.0) * 2900.0

func _lose(dt: float) -> void:
	st += dt * _story_rate(t)
	var s := st # the story's own clock (slower round the impact)
	var h := hit_dir * R
	var come := (hit_dir * 0.75 + Vector3(0.45, 0.42, 0.05)).normalized()
	var tan := hit_dir.cross(come).normalized()
	var mp := meteor_lose(s)
	var mv := (meteor_lose(s + 0.05) - mp) / 0.05
	var mvn := mv.normalized() if mv.length() > 1.0 else -come
	_place_meteor(mp, mv, clampf((s - 2.0) / 2.0, 0.0, 1.0))
	meteor.visible = s < IMPACT + 0.12
	m_trail.visible = meteor.visible
	# the air glows orange where it comes through
	var entry := clampf((s - 2.6) / (IMPACT - 2.6), 0.0, 1.0) if s < IMPACT + 1.0 else maxf(1.0 - (s - IMPACT - 1.0) / 2.0, 0.0)
	atmo_mat.set_shader_parameter("col", Color(0.3, 0.55, 1.0).lerp(Color(1.0, 0.45, 0.15), entry * 0.7))
	atmo_mat.set_shader_parameter("hot_dir", hit_dir)
	atmo_mat.set_shader_parameter("hot", entry * 2.6)
	if t > 2.4 and _once("dive"): # the camera rides in behind it
		_sfx("car_pass", 4.0, 0.32)
		_sfx("thunder", 0.0, 0.42)
	if t > 2.4 and s < IMPACT: shake = maxf(shake, 0.25 + 0.35 * clampf((s - 2.4) / 1.8, 0.0, 1.0))
	var since := s - IMPACT
	if since >= 0.0 and _once("impact"):
		flash = 1.25 # a white-out
		shake = 1.0
		fireball.visible = true
		_sfx("impact", 6.0, 0.55)
		_sfx("gen_boom", 4.0, 0.32)
		_sfx("thunder", 2.0, 0.5)
		NFHaptics.pulse("impact")
	if since >= 0.0:
		var a := clampf(since / 3.2, 0.0, 1.0)
		fireball.position = h * (1.0 + 0.07 * a)
		fireball.scale = Vector3.ONE * lerpf(260.0, 2100.0, 1.0 - pow(1.0 - a, 2.5))
		fb_mat.set_shader_parameter("age", a)
		fireball.visible = a < 1.0
		for sm in mats:
			(sm as ShaderMaterial).set_shader_parameter("shock", clampf(since / 3.6, 0.0, 1.0) if since < 3.6 else -1.0)
			(sm as ShaderMaterial).set_shader_parameter("burn", clampf(since / 3.0, 0.0, 1.0))
			(sm as ShaderMaterial).set_shader_parameter("crack", clampf((since - 1.0) / 2.0, 0.0, 1.0))
			(sm as ShaderMaterial).set_shader_parameter("melt", clampf((since - 2.6) / 1.8, 0.0, 1.0))
		if since > 1.6: shake = maxf(shake, 0.5)
		# the shockwave over the surface: fast, then slowing, lifting off the curve as it goes
		if ring:
			var rk := clampf(since / 2.6, 0.0, 1.0)
			ring.visible = rk < 1.0
			var rr := lerpf(80.0, R * 0.95, 1.0 - pow(1.0 - rk, 2.2))
			ring.scale = Vector3.ONE * maxf(rr * 1.25, 1.0)
			ring_mat.set_shader_parameter("rad", 0.8)
			ring_mat.set_shader_parameter("width", 0.05 + 0.05 * rk)
			ring_mat.set_shader_parameter("alpha", (1.0 - rk) * 1.4)
		# the plume blown back up out of the crater
		if plume:
			var pk := clampf(since / 2.4, 0.0, 1.0)
			var pl := lerpf(200.0, R * 2.4, 1.0 - pow(1.0 - pk, 2.0))
			plume.visible = since < 4.5
			plume.basis = Basis.looking_at(-hit_dir, Vector3.UP if absf(hit_dir.y) < 0.95 else Vector3.RIGHT) * Basis(Vector3(1, 0, 0), -PI / 2.0)
			plume.basis = plume.basis.scaled(Vector3(R * 0.42 * (0.3 + 0.7 * pk), pl, R * 0.42 * (0.3 + 0.7 * pk)))
			plume.position = h + hit_dir * pl * 0.5
			plume_mat.set_shader_parameter("power", 0.75 * smoothstep(0.0, 0.3, since) * (1.0 - smoothstep(1.6, 4.0, since)))
	# it breaks apart, and a great ring of fire is thrown out into space
	var br := since - 3.0
	if br > 0.0:
		if _once("break"):
			_sfx("final", 3.0, 0.8)
			_sfx("impact", 2.0, 0.42)
			_sfx("gen_boom", 2.0, 0.26)
			shake = 1.0
			flash = maxf(flash, 0.7)
			NFHaptics.pulse("impact")
		for pc in pieces:
			var nd: Node3D = pc[0]
			var d: Vector3 = pc[1]
			nd.position = d * (br * br * 0.055 + br * 0.05) # in the model's own units (it is scaled to R)
			nd.rotation = Vector3(d.z, d.x, d.y) * br * 0.07
		atmo_mat.set_shader_parameter("power", maxf(1.4 - br * 0.8, 0.0))
		if praxis:
			var xk := clampf(br / 3.4, 0.0, 1.0)
			praxis.visible = xk < 1.0
			praxis.position = Vector3.ZERO
			var xr := lerpf(R * 1.05, R * 5.2, 1.0 - pow(1.0 - xk, 1.8))
			praxis.scale = Vector3.ONE * xr * 1.15
			praxis_mat.set_shader_parameter("rad", 0.86)
			praxis_mat.set_shader_parameter("width", 0.035 + 0.03 * xk)
			praxis_mat.set_shader_parameter("alpha", 1.6 * (1.0 - xk * xk))
		var mm := debris.multimesh
		var nshow := mini(int(br * 200.0), mm.instance_count)
		mm.visible_instance_count = nshow
		for i in nshow:
			var dv: Array = debris_v[i]
			var p: Vector3 = (dv[0] as Vector3) + (dv[1] as Vector3) * br
			var b := Basis((dv[2] as Vector3), br * 1.3 + float(i)).scaled(Vector3.ONE * float(dv[3]))
			mm.set_instance_transform(i, Transform3D(b, p))
	# the camera, five shots
	if t < 2.4: # 1. the blue planet, the fire coming at it from far off
		var k := clampf(t / 2.4, 0.0, 1.0)
		_cam(Vector3(3200.0, 4200.0, 16500.0).lerp(Vector3(3400.0, 3900.0, 13800.0), k), Vector3(2600.0, 2900.0, 1800.0), dt, 50.0, 1.0)
	elif t < SLOW_A: # 2. riding in behind it: the planet filling the frame, its fire streaming past
		var at := mp - mvn * RM * 4.2 + tan * RM * 1.5 + hit_dir.cross(tan).normalized() * RM * 0.5
		_cam(at, mp + mvn * RM * 6.0, dt, lerpf(58.0, 72.0, clampf((t - 2.4) / 1.4, 0.0, 1.0)), 0.0)
	elif t < SLOW_B: # 3. slow motion, from the side, low over the clouds: it goes in
		var k := clampf((t - SLOW_A) / (SLOW_B - SLOW_A), 0.0, 1.0)
		var at := h + hit_dir * lerpf(1300.0, 1500.0, k) + tan * lerpf(4600.0, 4300.0, k) - come * 600.0
		_cam(at, h + hit_dir * 350.0, dt, 46.0, 0.0)
	elif since < 3.0: # 4. pulling back and up from the blast: the ring over the surface, the plume
		var k := clampf((t - SLOW_B) / 3.0, 0.0, 1.0)
		var at := h + hit_dir * lerpf(2000.0, 7000.0, k) + tan * lerpf(5200.0, 9500.0, k) + hit_dir.cross(tan).normalized() * lerpf(0.0, 2500.0, k)
		_cam(at, h * lerpf(1.1, 0.6, k), dt, 50.0, 2.5)
	else: # 5. the planet comes apart, its ring and its rocks thrown out past the camera
		var k := clampf(br / 3.4, 0.0, 1.0)
		_cam(CAM_END * (1.0 + 0.18 * k), Vector3(300.0, 400.0, 0.0), dt, lerpf(50.0, 56.0, k), 1.4)

func _place_meteor(p: Vector3, v: Vector3, hot: float) -> void:
	meteor.position = p
	meteor.rotate_object_local(Vector3(0.3, 1.0, 0.2).normalized(), 0.004)
	m_glow.set_shader_parameter("power", 0.12 + 2.1 * hot * hot)
	m_glow.set_shader_parameter("rim", 4.0 - 2.0 * hot)
	m_glow.set_shader_parameter("hot", hot * 1.5)
	m_glow.set_shader_parameter("hot_dir", v.normalized())
	var back := -v.normalized()
	var l := RM * (5.0 + 6.0 * hot)
	m_trail.scale = Vector3(1.0, l / (RM * 9.0), 1.0)
	m_trail.basis = Basis.looking_at(back, Vector3.UP if absf(back.y) < 0.95 else Vector3.RIGHT) * Basis(Vector3(1, 0, 0), PI / 2.0) # the wide end at the rock
	m_trail.scale = Vector3(1.0, l / (RM * 9.0), 1.0)
	m_trail.position = p + back * (l * 0.5 + RM * 0.4)
	(m_trail.mesh.material as ShaderMaterial).set_shader_parameter("power", 0.05 + 0.17 * hot)

# ---------------- on the screen ----------------
func _draw_ui() -> void:
	var vs := ui.get_viewport_rect().size
	var bar := vs.y * 0.1 # the film's black bars
	ui.draw_rect(Rect2(0, 0, vs.x, bar), Color.BLACK)
	ui.draw_rect(Rect2(0, vs.y - bar, vs.x, bar), Color.BLACK)
	if flash > 0.0: ui.draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.95, 0.85, minf(flash, 1.0)))
	if not won and t > 2.4 and st < IMPACT: # the dive: heat at the edges of the frame
		var hk := clampf((st - 2.4) / (IMPACT - 2.4), 0.0, 1.0)
		for i in 6:
			var w := vs.x * (0.02 + 0.03 * float(i))
			var c := Color(1.0, 0.4, 0.1, 0.05 * hk)
			ui.draw_rect(Rect2(0, 0, w, vs.y), c)
			ui.draw_rect(Rect2(vs.x - w, 0, w, vs.y), c)
	var font: Font = Net.font
	var title := ""
	var tc := Color.WHITE
	var a := 0.0
	if won and t > 11.0:
		title = "HUMANITY SURVIVED"
		tc = Color(0.75, 0.9, 1.0)
		a = clampf((t - 11.0) / 1.2, 0.0, 1.0)
	elif not won and t > 9.2:
		title = "HUMANITY HAS FALLEN"
		tc = Color(1.0, 0.35, 0.25)
		a = clampf((t - 9.2) / 1.2, 0.0, 1.0)
	if title != "":
		var y := vs.y * 0.46
		ui.draw_string_outline(font, Vector2(0, y), title, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 64, 10, Color(0, 0, 0, 0.85 * a))
		ui.draw_string(font, Vector2(0, y), title, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 64, Color(tc, a))
		if won and not names.is_empty():
			var who := "Saved: " + ", ".join(PackedStringArray(names))
			ui.draw_string_outline(font, Vector2(0, y + 52), who, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 26, 6, Color(0, 0, 0, 0.8 * a))
			ui.draw_string(font, Vector2(0, y + 52), who, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 26, Color(1, 1, 1, a))

## The film is over: give the screen back.
func finish() -> void:
	if hid_light and is_instance_valid(hid_light): hid_light.visible = true
	queue_free()
