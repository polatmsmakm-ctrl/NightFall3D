extends Node3D
## NightFall game scene: menu -> world -> local player + other players, objectives, HUD, audio.
## Rules run on the server online (server/rules.js) and locally in trial mode (scripts/rules.gd).

const WALK := {"killer": 4.6, "survivor": 1.6}
const RUN := {"killer": 4.6, "survivor": 4.0}
const CROUCH_SPEED := 1.1
const CARRY_SPEED := 3.6
# ground speed each animation was authored for; playback is scaled to it so feet don't slide
const NATURAL := {"walk": 1.3, "run": 3.7, "crouchwalk": 1.0, "injured": 1.6}
const ACCEL := 20.0
const DECEL := 28.0
const SFX := {"gen_loop": "wav", "hit": "wav", "ding": "wav", "boom": "wav", "pallet": "wav", "hurt": "wav", "gate": "mp3",
	"creak": "wav", "click": "wav", "hatch": "wav",
	"heart": "mp3", "breath": "mp3", "steps_out": "mp3", "steps_in": "mp3", "gen_run": "mp3", "chase": "mp3", "ambient": "mp3"}
const TERROR_RADIUS := 24.0 # survivors start to feel the killer inside this distance

var menu: GameMenu
var world: NightWorld
var rules: Rules
var body: CharacterBody3D
var cshape: CollisionShape3D
var rig: CharacterRig
var cam_pivot: Node3D
var arm: SpringArm3D
var ui: Control
var minimap: Control
var results: PanelContainer
var started := false
var cfg := {}
var offline := false
var my_name := ""
var my_role := "killer"
var remotes := {} # name -> {node, rig, pos, yaw, anim, role, step}
var sounds := {}
var gen_audio: Array = [] # per generator: {hum, run}
var amb: AudioStreamPlayer
var chase_music: AudioStreamPlayer
var heart: AudioStreamPlayer
var breath: AudioStreamPlayer
var my_steps: AudioStreamPlayer
var chase_hold := 0.0
var los_t := 0.0
var marks: Array = []
var mark_i := 0

var yaw := 0.0
var pitch := -0.25
var stick_id := -1
var stick_origin := Vector2.ZERO
var stick_vec := Vector2.ZERO
var look_id := -1
var sprint := false
var crouch := false
var attack_t := 0.0
var attack_cd := 0.0
var hit_sent := false
var boost_t := 0.0
var send_t := 0.0
var step_t := 0.0
var mark_t := 0.0

var ctx := {} # button id -> what it would do right now
var hold := {} # running hold action: {btn, kind, touch, t, need, i, n}
var vault := {}
var skill := {}
var next_skill := 5.0
var boom_t := {}
var flash := ""
var flash_t := 0.0
var my_state := "ok"
var last_state := "ok"
var last_locker := -1
var was_powered := false
var danger := 0.0 # survivors: how close the killer is (0..1)
var noise := 0.0 # killer: loudest nearby survivor (0..1)
var noise_dir := 0.0
var flash_light: SpotLight3D
var light_on := false
var battery := 100.0 # percent; a full charge lasts about two and a half minutes
var door_cool := {}
var last_hatch := -1
var xp_saved := false
var lobby_scene: Node3D
var spectating := "" # who I am watching after escaping or dying
var big_map := false
var match_time := 0.0
var escape_banner := 0.0
var thrash := {} # name -> seconds of hard thrashing left (after a failed escape attempt)

func _ready() -> void:
	menu = GameMenu.new()
	add_child(menu)
	menu.start_game.connect(_start)
	Net.message.connect(_on_net)
	_build_lobby_scene()

var _dot_tex: ImageTexture

func _soft_dot() -> ImageTexture: # round, soft-edged sprite for fire / smoke / sparks (drawn once, ready immediately)
	if _dot_tex: return _dot_tex
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex

func _fire_layer(parent: Node3D, amount: int, life: float, radius: float, rise: float, size: float, colors: Array, additive: bool, speed := Vector2(0.2, 0.7), spread := 18.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = radius
	m.gravity = Vector3(0, rise, 0)
	m.direction = Vector3.UP
	m.spread = spread
	m.initial_velocity_min = speed.x; m.initial_velocity_max = speed.y
	m.scale_min = 0.6; m.scale_max = 1.3
	m.angle_min = 0.0; m.angle_max = 360.0
	var curve := Curve.new() # flames swell, then thin out as they rise
	curve.add_point(Vector2(0, 0.35)); curve.add_point(Vector2(0.25, 1.0)); curve.add_point(Vector2(1, 0.1 if additive else 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray(colors)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive: mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = _soft_dot()
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = mat
	p.draw_pass_1 = q
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p

## Start screen: a camp in a forest clearing at night. The survivors warm themselves at a real-looking fire,
## the killer waits between the trees. Fire crackle + the ambient track play here.
func _build_lobby_scene() -> void:
	lobby_scene = Node3D.new()
	add_child(lobby_scene)
	var kit := NightWorld.new() # borrow the world's materials and meshes (never added to the tree)
	kit._make_materials()
	var env := Environment.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sm.set_shader_parameter("moon_dir", Vector3(0.35, 0.33, -0.88).normalized())
	sm.set_shader_parameter("noise_tex", kit._sky_noise)
	var sky := Sky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.14, 0.19, 0.34)
	env.ambient_light_energy = 1.3
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.1, 0.17)
	env.fog_density = 0.022
	env.fog_sky_affect = 0.15
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	lobby_scene.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.basis = Basis.looking_at(-Vector3(0.35, 0.33, -0.88).normalized())
	moon.light_color = Color(0.5, 0.6, 0.95)
	moon.light_energy = 1.0
	moon.shadow_enabled = true
	lobby_scene.add_child(moon)
	# ground: grass tinted, with a bare trampled circle around the fire
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	var gm: StandardMaterial3D = kit._mat.ground.duplicate()
	gm.vertex_color_use_as_albedo = false
	gm.albedo_color = Color(0.42, 0.56, 0.34)
	pm.material = gm
	ground.mesh = pm
	lobby_scene.add_child(ground)
	var dirt := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 3.6; dm.bottom_radius = 3.9; dm.height = 0.04; dm.radial_segments = 28
	var dmat: StandardMaterial3D = kit._mat.ground.duplicate()
	dmat.vertex_color_use_as_albedo = false
	dmat.albedo_color = Color(0.75, 0.6, 0.42)
	dm.material = dmat
	dirt.mesh = dm
	dirt.position.y = 0.02
	lobby_scene.add_child(dirt)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	# forest all around, thicker behind the camp; a gap toward the camera
	for v in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = kit._tree_mesh(v, true)
		var list: Array[Transform3D] = []
		for i in 90:
			var ang := rng.randf() * TAU
			var dist := rng.randf_range(7.5, 46.0)
			var pos := Vector3(sin(ang) * dist, 0, -cos(ang) * dist)
			if pos.z > 3.0 and absf(pos.x) < 5.5: continue # keep the view open
			var sc := rng.randf_range(0.8, 1.3)
			list.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), pos))
		mm.instance_count = list.size()
		for i in list.size(): mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		lobby_scene.add_child(mmi)
	var grass := MultiMesh.new()
	grass.transform_format = MultiMesh.TRANSFORM_3D
	grass.mesh = kit._grass_mesh()
	var blades: Array[Transform3D] = []
	for i in 2600:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(3.9, 22.0)
		var sc := rng.randf_range(0.8, 1.5)
		blades.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(sin(ang) * dist, 0, -cos(ang) * dist)))
	grass.instance_count = blades.size()
	for i in blades.size(): grass.set_instance_transform(i, blades[i])
	var gi := MultiMeshInstance3D.new()
	gi.multimesh = grass
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lobby_scene.add_child(gi)
	# camp props: stone ring, sitting logs, tent, crate with a lantern, stump with an axe, backpacks
	var rock: Material = kit._mat.rock
	var wood: Material = kit._mat.wood
	for k in 11:
		var st := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = rng.randf_range(0.13, 0.2); sp.height = sp.radius * 1.5; sp.radial_segments = 8; sp.rings = 4
		sp.material = rock
		st.mesh = sp
		st.position = Vector3(sin(k * TAU / 11.0) * 0.62, 0.07, cos(k * TAU / 11.0) * 0.62)
		st.rotation.y = rng.randf() * TAU
		lobby_scene.add_child(st)
	for lg in [[Vector3(-2.3, 0.22, 1.9), 0.9], [Vector3(2.6, 0.22, 1.4), -0.7]]:
		var log := MeshInstance3D.new()
		var lc := CylinderMesh.new()
		lc.top_radius = 0.22; lc.bottom_radius = 0.24; lc.height = 2.2; lc.radial_segments = 10
		lc.material = kit._mat.bark
		log.mesh = lc
		log.rotation = Vector3(0, lg[1], PI / 2.0)
		log.position = lg[0]
		lobby_scene.add_child(log)
	var tent_mat := StandardMaterial3D.new()
	tent_mat.albedo_color = Color(0.2, 0.26, 0.18)
	tent_mat.roughness = 0.9
	tent_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tent := Node3D.new()
	tent.position = Vector3(-4.6, 0, -3.4)
	tent.rotation.y = 0.75
	for sx in [-1.0, 1.0]:
		var side := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.9, 0.05, 3.0)
		bm.material = tent_mat
		side.mesh = bm
		side.position = Vector3(sx * 0.62, 0.75, 0)
		side.rotation.z = sx * -0.9
		tent.add_child(side)
	lobby_scene.add_child(tent)
	var crate := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(0.7, 0.6, 0.7)
	cb.material = wood
	crate.mesh = cb
	crate.position = Vector3(3.4, 0.3, -1.6)
	crate.rotation.y = 0.4
	lobby_scene.add_child(crate)
	var lantern := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.16, 0.26, 0.16)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(1.0, 0.8, 0.45)
	lmat.emission_enabled = true
	lmat.emission = Color(1.0, 0.75, 0.4)
	lmat.emission_energy_multiplier = 3.0
	lb.material = lmat
	lantern.mesh = lb
	lantern.position = Vector3(3.4, 0.73, -1.6)
	lobby_scene.add_child(lantern)
	var ll := OmniLight3D.new()
	ll.position = Vector3(3.4, 0.9, -1.6)
	ll.light_color = Color(1.0, 0.78, 0.45)
	ll.light_energy = 0.9
	ll.omni_range = 4.0
	lobby_scene.add_child(ll)
	var stump := MeshInstance3D.new()
	var sc2 := CylinderMesh.new()
	sc2.top_radius = 0.32; sc2.bottom_radius = 0.38; sc2.height = 0.5; sc2.radial_segments = 12
	sc2.material = kit._mat.bark
	stump.mesh = sc2
	stump.position = Vector3(-3.6, 0.25, 0.6)
	lobby_scene.add_child(stump)
	var axe := Node3D.new()
	axe.position = Vector3(-3.6, 0.55, 0.6)
	axe.rotation = Vector3(0, 0.6, 0.5)
	var handle := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.05, 0.75, 0.05)
	hb.material = wood
	handle.mesh = hb
	handle.position.y = 0.3
	axe.add_child(handle)
	var head := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(0.26, 0.16, 0.04)
	ab.material = kit._mat.metal
	head.mesh = ab
	head.position = Vector3(0.1, 0.02, 0)
	axe.add_child(head)
	lobby_scene.add_child(axe)
	for bp in [[Vector3(-1.5, 0.2, 2.6), Color(0.25, 0.12, 0.08)], [Vector3(3.1, 0.2, 2.3), Color(0.1, 0.16, 0.24)]]:
		var bag := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.42, 0.4, 0.3)
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = bp[1]
		bb.material = bmat
		bag.mesh = bb
		bag.position = bp[0]
		bag.rotation.y = rng.randf() * TAU
		lobby_scene.add_child(bag)
	# the fire: charred logs on a glowing ember bed, layered flames, sparks, smoke, flickering light with shadows
	var char_mat := StandardMaterial3D.new()
	char_mat.albedo_color = Color(0.05, 0.035, 0.03)
	char_mat.emission_enabled = true
	char_mat.emission = Color(1.0, 0.3, 0.05)
	char_mat.emission_energy_multiplier = 0.5
	for k in 6:
		var log := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06; cyl.bottom_radius = 0.085; cyl.height = 0.95; cyl.radial_segments = 8
		cyl.material = char_mat
		log.mesh = cyl
		log.rotation = Vector3(1.0, k * TAU / 6.0, 0)
		log.position = Vector3(sin(k * TAU / 6.0) * 0.2, 0.3, cos(k * TAU / 6.0) * 0.2)
		lobby_scene.add_child(log)
	var embers := MeshInstance3D.new()
	var ec := CylinderMesh.new()
	ec.top_radius = 0.42; ec.bottom_radius = 0.48; ec.height = 0.08; ec.radial_segments = 16
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(0.2, 0.05, 0.02)
	emat.emission_enabled = true
	emat.emission = Color(1.0, 0.32, 0.05)
	emat.emission_energy_multiplier = 2.5
	ec.material = emat
	embers.mesh = ec
	embers.name = "Embers"
	embers.position.y = 0.06
	lobby_scene.add_child(embers)
	var fire_root := Node3D.new()
	fire_root.position = Vector3(0, 0.22, 0)
	lobby_scene.add_child(fire_root)
	_fire_layer(fire_root, 46, 0.75, 0.17, 1.5, 0.34, [Color(1.0, 0.5, 0.1, 0.0), Color(1.0, 0.36, 0.06, 0.42), Color(0.6, 0.06, 0.0, 0.0)], true, Vector2(0.15, 0.5)) # outer flames
	_fire_layer(fire_root, 30, 0.5, 0.1, 1.3, 0.2, [Color(1.0, 0.9, 0.6, 0.0), Color(1.0, 0.8, 0.35, 0.5), Color(1.0, 0.35, 0.05, 0.0)], true, Vector2(0.1, 0.4)) # bright core
	_fire_layer(fire_root, 22, 2.4, 0.2, 0.9, 0.04, [Color(1.0, 0.8, 0.4, 1.0), Color(1.0, 0.5, 0.1, 1.0), Color(1.0, 0.2, 0.0, 0.0)], true, Vector2(0.7, 2.0), 30.0) # sparks
	var smoke := _fire_layer(fire_root, 18, 4.5, 0.15, 0.45, 0.6, [Color(0.1, 0.1, 0.1, 0.0), Color(0.14, 0.14, 0.15, 0.16), Color(0.1, 0.1, 0.11, 0.0)], false, Vector2(0.3, 0.6), 10.0)
	smoke.position.y = 0.9
	var fire := OmniLight3D.new()
	fire.name = "Fire"
	fire.position = Vector3(0, 0.75, 0)
	fire.light_color = Color(1.0, 0.55, 0.2)
	fire.light_energy = 3.4
	fire.omni_range = 11.0
	fire.shadow_enabled = true
	lobby_scene.add_child(fire)
	# the cast: survivors around the fire, the killer watching from the tree line
	var seats := [["survivor1", -1.05, 2.1], ["survivor2", -0.38, 2.2], ["survivor3", 0.42, 2.2], ["survivor4", 1.1, 2.1]]
	for st in seats:
		var r := CharacterRig.new()
		lobby_scene.add_child(r)
		r.setup(st[0], ["campfire", "idle"])
		r.position = Vector3(sin(st[1]) * st[2], 0, -cos(st[1]) * st[2])
		r.rotation.y = atan2(-r.position.x, -r.position.z)
		r.play("campfire")
		r.player.seek(3.0 + absf(st[1]) * 2.3, true)
	var killer := CharacterRig.new()
	lobby_scene.add_child(killer)
	killer.setup("killer", ["idle"])
	killer.position = Vector3(1.6, 0, -7.4)
	killer.rotation.y = atan2(-killer.position.x, -killer.position.z)
	killer.play("idle")
	var rim := OmniLight3D.new() # faint red rim so his outline reads in the dark
	rim.position = Vector3(2.4, 2.2, -8.6)
	rim.light_color = Color(1.0, 0.15, 0.1)
	rim.light_energy = 1.4
	rim.omni_range = 5.0
	lobby_scene.add_child(rim)
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	lobby_scene.add_child(pivot)
	var cam := Camera3D.new()
	cam.position = Vector3(-2.1, 1.55, 6.0) # the camp sits right of centre: the menu column is on the left
	cam.rotation = Vector3(-0.06, -0.06, 0)
	cam.fov = 55.0
	cam.far = 300.0
	pivot.add_child(cam)
	cam.current = true
	# sound: the crackle the owner supplied, over the ambient track
	for snd in [["campfire", -4.0], ["ambient", -14.0]]:
		var a := AudioStreamPlayer.new()
		var stream: AudioStreamMP3 = load("res://assets/sfx/%s.mp3" % snd[0])
		stream.loop = true
		a.stream = stream
		a.volume_db = snd[1]
		lobby_scene.add_child(a)
		a.play()
	kit.free()

func _start(c: Dictionary) -> void:
	if started: return
	cfg = c
	offline = c.get("offline", false)
	my_name = str(c.me)
	menu.visible = false
	if lobby_scene:
		lobby_scene.queue_free()
		lobby_scene = null
	world = NightWorld.new()
	world.configure(str(c.map), int(c.get("seed", randi() % 1000000) if not offline else randi() % 1000000))
	add_child(world)
	world.build() # staged: terrain + buildings + objectives first, the rest over the next frames
	rules = Rules.new()
	rules.setup(world.gen_points.size(), world.gate_points.size(), world.pallet_points.size(), world.hatch_points.size(), c.players)
	for p in c.players:
		if str(p.name) == my_name:
			my_role = str(p.role)
			_build_player(str(p.char), world.spawn_point(my_role, int(p.slot)))
	_build_audio()
	for p in c.players:
		if str(p.name) != my_name: _add_remote(p)
	_build_marks()
	_build_ui()
	if not offline:
		var xz := func(v: Vector3) -> Array: return [snappedf(v.x, 0.1), snappedf(v.z, 0.1)]
		var lay := {"g": [], "h": [], "p": [], "x": []}
		for v in world.hatch_points: lay.x.append(xz.call(v))
		for v in world.gen_points: lay.g.append(xz.call(v))
		for v in world.hook_points: lay.h.append(xz.call(v))
		for v in world.pallet_points: lay.p.append(xz.call(v[0]))
		Net.send({"t": "layout", "d": lay})
	started = true

func _build_player(char_name: String, at: Vector3) -> void:
	body = CharacterBody3D.new()
	cshape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35; cap.height = 1.8
	cshape.shape = cap; cshape.position.y = 0.9
	body.add_child(cshape)
	rig = CharacterRig.new()
	body.add_child(rig)
	rig.setup(char_name)
	body.position = at
	body.floor_snap_length = 0.5
	body.floor_max_angle = deg_to_rad(50.0)
	add_child(body)
	world.follow = body
	cam_pivot = Node3D.new()
	cam_pivot.position.y = 1.6
	body.add_child(cam_pivot)
	arm = SpringArm3D.new() # keeps the camera from going through trees and walls
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	arm.shape = probe
	arm.margin = 0.15
	arm.add_excluded_object(body.get_rid())
	cam_pivot.add_child(arm)
	var cam := Camera3D.new()
	cam.far = 400.0
	arm.add_child(cam)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.93, 0.82)
	cam_pivot.add_child(lamp)
	if my_role == "killer": # first person
		arm.spring_length = 0.0
		arm.position.y = 0.2
		cam.fov = 80.0
		cam.near = 0.1
		rig.visible = false
		lamp.position = Vector3(0, 0.3, -0.5)
		lamp.light_energy = 0.8; lamp.omni_range = 11.0
	else: # third person
		arm.spring_length = 3.4
		arm.position.y = 0.3
		cam.fov = 70.0
		lamp.position = Vector3(0.6, 0.9, 1.6)
		lamp.light_energy = 0.45; lamp.omni_range = 7.0 # just enough to read your own character; the flashlight does the rest
		flash_light = _make_flashlight()
		flash_light.position = Vector3(0, 1.45, 0)
		body.add_child(flash_light)

func _make_flashlight() -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = Color(1.0, 0.95, 0.85)
	l.light_energy = 7.0
	l.spot_range = 24.0
	l.spot_angle = 26.0
	l.spot_attenuation = 0.7
	l.visible = false
	return l

func _add_remote(p: Dictionary) -> void:
	var node := Node3D.new()
	var r := CharacterRig.new()
	node.add_child(r)
	r.setup(str(p.char))
	node.position = world.spawn_point(str(p.role), int(p.slot))
	if p.get("dummy", false): # trial-mode practice target
		var gp: Vector3 = world.gen_points[0]
		node.position = gp + Vector3(1.8, 0.0, 1.2) if my_role == "killer" else body.position + Vector3(2.5, 0, 0)
		rules.s[str(p.name)].hp = "ok" if my_role == "killer" else "hurt"
	var tag := Label3D.new()
	tag.text = str(p.name)
	tag.font = Net.font
	tag.font_size = 48
	tag.pixel_size = 0.004
	tag.position.y = 2.25
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(1, 0.4, 0.4) if str(p.role) == "killer" else Color(0.75, 0.9, 1)
	tag.visible = str(p.role) == my_role # no name tags across teams
	node.add_child(tag)
	var glow := OmniLight3D.new() # faint light so other players are not pitch black
	glow.position = Vector3(0, 2.0, 0)
	glow.light_energy = 0.5; glow.omni_range = 3.5
	if str(p.role) == "killer": glow.light_color = Color(1, 0.25, 0.2)
	node.add_child(glow)
	var torch: SpotLight3D = null
	if str(p.role) == "survivor": # other survivors' flashlights are real lights: the killer can spot them
		torch = _make_flashlight()
		torch.position = Vector3(0, 1.45, 0.2)
		torch.rotation.y = PI
		r.add_child(torch)
	var steps := AudioStreamPlayer3D.new()
	steps.stream = sounds.steps_out
	steps.unit_size = 4.0
	steps.max_distance = 32.0
	node.add_child(steps)
	add_child(node)
	remotes[str(p.name)] = {"node": node, "rig": r, "pos": node.position, "yaw": 0.0, "anim": "idle", "role": str(p.role), "step": 0.0, "steps": steps, "torch": torch, "lit": false}

# ---------------- audio ----------------
func _loop_player(stream_name: String, db: float, autoplay := false) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.stream = sounds[stream_name]
	a.volume_db = db
	add_child(a)
	if autoplay: a.play()
	return a

func _build_audio() -> void:
	for n in SFX: sounds[n] = load("res://assets/sfx/%s.%s" % [n, SFX[n]])
	for n in ["heart", "breath", "steps_out", "steps_in", "gen_run", "chase", "ambient"]:
		(sounds[n] as AudioStreamMP3).loop = true
	var hum: AudioStreamWAV = sounds.gen_loop
	hum.loop_mode = AudioStreamWAV.LOOP_FORWARD
	hum.loop_begin = 0
	hum.loop_end = int(hum.get_length() * hum.mix_rate)
	amb = _loop_player("ambient", -13.0, true)
	chase_music = _loop_player("chase", -60.0)
	heart = _loop_player("heart", -60.0)
	breath = _loop_player("breath", -60.0)
	my_steps = _loop_player("steps_out", -60.0)
	for gp in world.gen_points:
		var pair := {}
		for kind in ["hum", "run"]:
			var a := AudioStreamPlayer3D.new()
			a.stream = sounds.gen_loop if kind == "hum" else sounds.gen_run
			a.position = gp + Vector3(0, 1, 0)
			a.unit_size = 5.0
			# the killer only hears a generator from close by (8 m); survivors hear it from far
			a.max_distance = 8.0 if my_role == "killer" else 45.0
			add_child(a)
			pair[kind] = a
		gen_audio.append(pair)

## Loop the right footstep recording for the ground under `at`; faster/louder when running, silent when still.
func _steps(a: Node, at: Vector3, moving: bool, running: bool, base_db: float) -> void:
	if not moving:
		if a.playing: a.stop()
		return
	var surf := world.surface_at(at)
	var want: AudioStream = sounds.steps_in if surf == "indoor" else sounds.steps_out
	if a.stream != want:
		a.stream = want
		a.play()
	elif not a.playing: a.play()
	a.pitch_scale = (1.25 if running else 0.9) * (0.82 if surf == "sand" else 1.0) # sand: duller, softer
	a.volume_db = base_db + (0.0 if running else -9.0) + (-4.0 if surf == "sand" else 0.0)

func _line_of_sight(to: Vector3) -> bool:
	var from := body.position + Vector3(0, 1.6, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to + Vector3(0, 1.2, 0))
	q.exclude = [body.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _sfx(n: String, at = null, db := 0.0, pitch_scale := 1.0) -> void:
	var a: Node
	if at == null:
		a = AudioStreamPlayer.new()
	else:
		a = AudioStreamPlayer3D.new()
		a.position = at
		a.unit_size = 6.0
		a.max_distance = 60.0
	a.stream = sounds[n]
	a.volume_db = db
	a.pitch_scale = pitch_scale
	add_child(a)
	a.finished.connect(a.queue_free)
	a.play()

# scratch marks: glowing traces running survivors leave behind; only the killer sees them
func _build_marks() -> void:
	if my_role != "killer": return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.25, 0.08)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.12)
	q.material = mat
	for i in 60:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		marks.append({"node": mi, "t": 0.0})

func _drop_mark(at: Vector3) -> void:
	var m: Dictionary = marks[mark_i]
	mark_i = (mark_i + 1) % marks.size()
	m.t = 7.0
	m.node.visible = true
	m.node.position = at + Vector3(randf_range(-0.4, 0.4), 0.06, randf_range(-0.4, 0.4))
	m.node.rotation = Vector3(-PI / 2.0, randf() * TAU, 0)
	m.node.scale = Vector3.ONE

# ---------------- networking ----------------
func _on_net(m: Dictionary) -> void:
	if not started: return
	match str(m.t):
		"st":
			var r = remotes.get(str(m.n))
			if r:
				r.pos = Vector3(m.p[0], m.p[1], m.p[2])
				r.yaw = float(m.p[3])
				r.anim = str(m.a)
				r.lit = int(m.get("f", 0)) == 1
		"ev":
			var d = m.get("d")
			if d is Dictionary and str(m.get("n", "?")) == "": # only the server referees
				if str(d.get("k", "")) == "gs": rules.apply(d)
				else: _on_event(d)
		"left":
			var r = remotes.get(str(m.name))
			if r:
				r.node.queue_free()
				remotes.erase(str(m.name))
		"room":
			if not offline and (str(m.get("code", "")) == "" or str(m.get("state", "")) == "lobby"):
				_to_menu()

## Send one of my inputs to the referee (the server, or the local rules in trial mode).
func _ev(d: Dictionary) -> void:
	if offline:
		for e in rules.handle(d, my_name): _on_event(e)
	else:
		Net.send({"t": "ev", "d": d})

func _pos_of(n: String) -> Vector3:
	if n == my_name: return body.position
	var r = remotes.get(n)
	return r.node.position if r else Vector3.ZERO

func _on_event(e: Dictionary) -> void:
	match str(e.get("k", "")):
		"boom":
			_sfx("boom", world.gen_points[int(e.i)], 6.0) # the killer has to locate it by ear: nothing shows on his map
			if my_role == "killer": _flash("سمعت انفجار مولد!")
		"hurt":
			_sfx("hit", _pos_of(str(e.n)), 2.0)
			_sfx("hurt", _pos_of(str(e.n)), 0.0)
			if str(e.n) == my_name:
				boost_t = 2.0
				_flash("انضربت! اهرب" if str(e.s) == "hurt" else "طحت")
			elif my_role == "killer": _flash("أصبت %s" % str(e.n))
		"hooked":
			_sfx("hurt", _pos_of(str(e.n)), 3.0, 0.8)
			_flash("%s %s" % [str(e.n), "انعلّق على الخطاف" if str(e.s) == "hooked" else "مات"])
		"rescued":
			if str(e.by) == str(e.n): _flash("%s فك نفسه من الخطاف!" % str(e.n))
			else: _flash("%s أنقذ %s" % [str(e.by), str(e.n)])
		"struggle":
			thrash[str(e.n)] = 1.4
			_sfx("hurt", _pos_of(str(e.n)), -2.0, 1.2)
			if str(e.n) == my_name: _flash("ما قدرت! راحت 8 ثواني")
		"grabbed": _flash("القاتل طلّع %s من الخزانة" % str(e.n))
		"empty":
			if my_role == "killer": _flash("الخزانة فاضية")
		"pallet": _sfx("pallet", world.pallet_points[int(e.i)][0], 4.0)
		"broke": _sfx("pallet", world.pallet_points[int(e.i)][0], 2.0, 0.7)
		"stun":
			if my_role == "killer": _flash("انصعقت!")
		"power":
			if my_role == "killer":
				boost_t = 3.5
				_flash("اندفاع!")

func _flash(t: String) -> void:
	flash = t
	flash_t = 2.5

func _to_menu() -> void:
	started = false
	get_tree().reload_current_scene.call_deferred()

func _leave() -> void:
	if offline: _to_menu()
	elif str(Net.room.get("host", "")) == my_name: Net.send({"t": "lobby"}) # host ends the round for everyone
	else: Net.send({"t": "leave"})

# ---------------- UI ----------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	ui.draw.connect(_draw_ui)
	minimap = Control.new()
	minimap.position = Vector2(16 + _safe().x, 44)
	minimap.size = Vector2(170, 170)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(minimap)
	minimap.draw.connect(_draw_minimap)
	var leave := Button.new()
	leave.text = "إنهاء الجولة" if (not offline and str(Net.room.get("host", "")) == my_name) else "خروج"
	leave.focus_mode = Control.FOCUS_NONE
	leave.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	leave.offset_left = -300; leave.offset_right = -152; leave.offset_top = 12; leave.offset_bottom = 64
	leave.pressed.connect(_leave)
	layer.add_child(leave)
	results = PanelContainer.new()
	results.visible = false
	results.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	results.grow_horizontal = Control.GROW_DIRECTION_BOTH
	results.grow_vertical = Control.GROW_DIRECTION_BOTH
	results.custom_minimum_size = Vector2(520, 0)
	layer.add_child(results)

func _show_results() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + side, 24)
	results.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	var escaped := 0
	for n in rules.s:
		if rules.s[n].hp == "escaped": escaped += 1
	var title := Label.new()
	if my_role == "killer": title.text = "انتهت الجولة — هرب %d من %d" % [escaped, rules.s.size()]
	else: title.text = "تم الهروب بنجاح!" if rules.hp(my_name) == "escaped" else "ما نجوت"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var stats := Label.new()
	stats.text = "مدة الجولة %d:%02d  •  المولدات %d/%d  •  هرب %d من %d" % [int(match_time) / 60, int(match_time) % 60, rules.done_count(), Rules.NEED, escaped, rules.s.size()]
	stats.add_theme_font_size_override("font_size", 20)
	stats.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.text_direction = Control.TEXT_DIRECTION_RTL
	v.add_child(stats)
	# ranking by points
	var names: Array = rules.score.keys()
	names.sort_custom(func(x, y): return rules.score[x] > rules.score[y])
	var rank := 1
	for n in names:
		var l := Label.new()
		var what := "القاتل"
		if rules.s.has(n): what = "هرب" if rules.s[n].hp == "escaped" else "مات"
		l.text = "%d. %s — %d نقطة (%s)" % [rank, n, roundi(rules.score[n]), what]
		l.text_direction = Control.TEXT_DIRECTION_RTL
		l.add_theme_font_size_override("font_size", 24)
		l.add_theme_color_override("font_color", Color(1, 0.85, 0.4) if n == my_name else (Color(1, 0.5, 0.45) if not rules.s.has(n) else Color(0.8, 0.9, 1)))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		rank += 1
	if not xp_saved: # points become experience; levels are kept on the phone
		xp_saved = true
		var before := Net.level()
		Net.xp += roundi(rules.score.get(my_name, 0.0))
		Net.save()
		var lv := Label.new()
		lv.text = "المستوى %d%s  •  الخبرة %d" % [Net.level(), "  (ترقية!)" if Net.level() > before else "", Net.xp]
		lv.add_theme_font_size_override("font_size", 22)
		lv.add_theme_color_override("font_color", Color(0.6, 1, 0.7))
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(lv)
	var b := Button.new()
	b.text = "رجوع"
	b.custom_minimum_size.y = 56
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(func():
		if not offline and str(Net.room.get("host", "")) == my_name: Net.send({"t": "lobby"})
		_to_menu())
	v.add_child(b)
	results.visible = true

## Screen margins (left, right) in UI units to stay clear of the notch / Dynamic Island.
func _safe() -> Vector2:
	var win := Vector2(DisplayServer.window_get_size())
	var area := DisplayServer.get_display_safe_area()
	var vs := get_viewport().get_visible_rect().size
	if win.x <= 0.0 or area.size.x <= 0: return Vector2.ZERO
	var k := vs.x / win.x
	return Vector2(maxf(area.position.x, 0.0) * k, maxf(win.x - float(area.position.x + area.size.x), 0.0) * k)

func _others_alive() -> Array:
	var out := []
	for n in remotes:
		if remotes[n].role == "survivor" and rules.hp(n) in Rules.LIVE: out.append(n)
	return out

## On-screen buttons. Each: center, radius, label, id, enabled.
func _buttons() -> Array:
	var s := get_viewport().get_visible_rect().size
	s.x -= _safe().y
	var out := []
	if spectating != "":
		if _others_alive().size() > 1: out.append([Vector2(s.x - 130, s.y - 120), 62.0, "التالي", "next", true])
		return out
	if my_role == "killer":
		out.append([Vector2(s.x - 115, s.y - 115), 62.0, "ضرب", "attack", attack_cd <= 0.0 and rules.carrying == ""])
		out.append([Vector2(s.x - 262, s.y - 92), 50.0, "اندفاع", "power", rules.power_cd <= 0.0 and rules.carrying == ""])
		var c = ctx.get("interact")
		out.append([Vector2(s.x - 215, s.y - 222), 48.0, c.label if c else "حمل", "interact", c != null])
	else:
		var c = ctx.get("interact")
		out.append([Vector2(s.x - 110, s.y - 110), 58.0, "ركض", "sprint", true])
		out.append([Vector2(s.x - 252, s.y - 88), 50.0, c.label if c else "تفاعل", "interact", c != null])
		out.append([Vector2(s.x - 88, s.y - 252), 44.0, "انحناء", "crouch", true])
		out.append([Vector2(s.x - 215, s.y - 215), 44.0, "قفز", "vault", ctx.has("vault")])
		out.append([Vector2(s.x - 375, s.y - 68), 40.0, "علاج", "heal", ctx.has("heal")])
		out.append([Vector2(s.x - 345, s.y - 170), 40.0, "حقيبة", "item", ctx.has("item")])
		out.append([Vector2(s.x - 88, s.y - 352), 40.0, "كشاف", "light", battery > 0.0])
	return out

func _text(pos: Vector2, t: String, size: int, col := Color.WHITE, width := 700.0) -> void:
	ui.draw_string_outline(Net.font, pos - Vector2(width / 2.0, 0), t, HORIZONTAL_ALIGNMENT_CENTER, width, size, 6, Color(0, 0, 0, 0.8))
	ui.draw_string(Net.font, pos - Vector2(width / 2.0, 0), t, HORIZONTAL_ALIGNMENT_CENTER, width, size, col)

func _draw_ui() -> void:
	var s := get_viewport().get_visible_rect().size
	var mid := s / 2.0
	# survivors: red edges pulse when the killer is close
	if my_role == "survivor" and danger > 0.0:
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * lerpf(5.0, 12.0, danger))
		ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0.8, 0.0, 0.0, danger * 0.16 * pulse)) # whole screen goes a little red
		for k in 4: # darker red toward the edges
			ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0.9, 0.03, 0.03, danger * 0.13 * pulse), false, 30.0 + k * 34.0)
	if stick_id >= 0:
		ui.draw_circle(stick_origin, 70, Color(1, 1, 1, 0.12))
		ui.draw_circle(stick_origin + stick_vec * 70, 32, Color(1, 1, 1, 0.35))
	for b in _buttons():
		var id: String = b[3]
		var on: bool = (id == "crouch" and crouch) or (id == "sprint" and sprint) or (id == "light" and light_on) or (not hold.is_empty() and hold.btn == id)
		var col := Color(0.9, 0.2, 0.2, 0.5) if on else Color(1, 1, 1, 0.17 if b[4] else 0.06)
		ui.draw_circle(b[0], b[1], col)
		ui.draw_arc(b[0], b[1], 0, TAU, 40, Color(1, 1, 1, 0.55 if b[4] else 0.2), 2.0)
		ui.draw_string(Net.font, b[0] + Vector2(-b[1], 8), b[2], HORIZONTAL_ALIGNMENT_CENTER, b[1] * 2.0, 21, Color(1, 1, 1, 1.0 if b[4] else 0.4))
		if id == "light": # battery ring
			ui.draw_arc(b[0], b[1] + 5.0, -PI / 2.0, -PI / 2.0 + TAU * battery / 100.0, 32, Color(1, 0.9, 0.4) if battery > 25.0 else Color(1, 0.3, 0.2), 4.0)
		if id == "power": # power indicator: ring refills during the cooldown
			var f := 1.0 - rules.power_cd / Rules.POWER_CD
			ui.draw_arc(b[0], b[1] + 5.0, -PI / 2.0, -PI / 2.0 + TAU * f, 40, Color(1, 0.5, 0.2) if f < 1.0 else Color(0.4, 1, 0.5), 5.0)
		if id == "attack" and attack_cd > 0.0:
			ui.draw_arc(b[0], b[1] + 5.0, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - attack_cd / 2.4), 40, Color(1, 1, 1, 0.7), 4.0)
	# objective
	var top := Vector2(mid.x, 46)
	if not rules.powered: _text(top, "المولدات %d / %d" % [rules.done_count(), Rules.NEED], 26, Color(1, 0.9, 0.6))
	elif my_role == "killer": _text(top, "البوابات انفتحت — امنعهم من الهرب", 24, Color(1, 0.5, 0.4))
	elif my_state in ["escaped", "dead"]: _text(top, "باقي %d من ربعك داخل" % _others_alive().size(), 24, Color(1, 0.9, 0.6))
	else: _text(top, "البوابات انفتحت — اركض لآخر طريق الخروج!", 26, Color(0.5, 1, 0.6))
	var sub := top + Vector2(0, 32)
	if my_role == "survivor":
		var me: Dictionary = rules.s.get(my_name, {})
		match my_state:
			"hurt": _text(sub, "مصاب", 22, Color(1, 0.5, 0.35))
			"down": _text(sub, "طايح — استنى أحد يعالجك (%d)" % int(me.t), 22, Color(1, 0.4, 0.35))
			"carried": _text(sub, "القاتل شايلك", 22, Color(1, 0.4, 0.35))
			"hooked": _text(sub, "معلّق على الخطاف — %d ث" % int(me.t), 22, Color(1, 0.4, 0.35))
			"dead": _text(sub, "متّ — تتفرج على %s" % spectating if spectating != "" else "متّ", 22, Color(1, 0.4, 0.35))
			"escaped": _text(sub, "هربت بنجاح — تتفرج على %s" % spectating if spectating != "" else "هربت بنجاح", 22, Color(0.5, 1, 0.6))
		if escape_banner > 0.0:
			_text(mid + Vector2(0, -40), "تم الهروب بنجاح!", 54, Color(0.5, 1, 0.6))
			_text(mid + Vector2(0, 10), "+150 نقطة — استنى ربعك يطلعون", 24, Color(0.85, 1, 0.9))
		if not me.is_empty() and me.locker >= 0: _text(sub + Vector2(0, 28), "مختبئ بالخزانة", 20, Color(0.7, 0.85, 1))
	else:
		# detection indicator: how loud the nearest running survivor is, and where
		var c := sub + Vector2(0, 8)
		ui.draw_circle(c, 20, Color(0, 0, 0, 0.5))
		ui.draw_arc(c, 20, 0, TAU, 32, Color(1, 1, 1, 0.4), 2.0)
		if noise > 0.02:
			ui.draw_circle(c, 6.0 + 12.0 * noise, Color(1, 0.3, 0.2, 0.4 + 0.5 * noise))
			var ang := -PI / 2.0 + noise_dir
			ui.draw_line(c + Vector2(cos(ang), sin(ang)) * 24.0, c + Vector2(cos(ang), sin(ang)) * 40.0, Color(1, 0.4, 0.3), 5.0)
			_text(c + Vector2(0, 52), "صوت ركض قريب", 18, Color(1, 0.6, 0.5))
		if rules.stun > 0.0: _text(mid + Vector2(0, -60), "مصعوق", 30, Color(1, 0.9, 0.3))
		if rules.carrying != "": _text(sub + Vector2(0, 84), "شايل %s — ودّه للخطاف" % rules.carrying, 20, Color(1, 0.7, 0.5))
		if attack_t > 0.55: # first person: show the swing
			ui.draw_arc(mid + Vector2(0, 120), 260, -PI * 0.75, -PI * 0.25, 24, Color(1, 1, 1, 0.35), 14.0)
	# team status
	var y := 252.0
	for n in rules.s:
		var p: Dictionary = rules.s[n]
		var mark: String = {"ok": "●", "hurt": "◐", "down": "▼", "carried": "▲", "hooked": "⚓", "dead": "✕", "escaped": "➜"}.get(p.hp, "?")
		var col: Color = {"ok": Color(0.7, 1, 0.7), "hurt": Color(1, 0.7, 0.3), "down": Color(1, 0.45, 0.3), "carried": Color(1, 0.45, 0.3),
			"hooked": Color(1, 0.3, 0.3), "dead": Color(0.6, 0.6, 0.6), "escaped": Color(0.5, 0.8, 1)}.get(p.hp, Color.WHITE)
		ui.draw_string(Net.font, Vector2(18 + _safe().x, y), "%s %s%s" % [mark, n, "  " + "I".repeat(p.hooks) if p.hooks > 0 else ""], HORIZONTAL_ALIGNMENT_LEFT, 240, 18, col)
		y += 24.0
	# hold progress + skill check
	if not hold.is_empty():
		var p := 0.0
		match hold.kind:
			"rep": p = rules.gens[hold.i].p
			"heal": p = rules.s[hold.n].heal if rules.s.has(hold.n) else 0.0
			_: p = hold.t / hold.need
		var bar := Rect2(mid.x - 180, s.y - 90, 360, 18)
		ui.draw_rect(bar, Color(0, 0, 0, 0.6))
		ui.draw_rect(Rect2(bar.position, Vector2(360 * clampf(p, 0.0, 1.0), 18)), Color(1, 0.85, 0.3))
		ui.draw_rect(bar, Color(1, 1, 1, 0.6), false, 2.0)
	if not skill.is_empty():
		var z: float = skill.zone
		ui.draw_circle(mid, 78, Color(0, 0, 0, 0.55))
		ui.draw_arc(mid, 64, 0, TAU, 48, Color(1, 1, 1, 0.5), 4.0)
		ui.draw_arc(mid, 64, (z - 0.07) * TAU - PI / 2.0, (z + 0.07) * TAU - PI / 2.0, 12, Color(0.3, 1, 0.4), 10.0)
		var ang: float = skill.t / 1.2 * TAU - PI / 2.0
		ui.draw_line(mid, mid + Vector2(cos(ang), sin(ang)) * 72, Color(1, 0.3, 0.3), 4.0)
		_text(mid + Vector2(0, 118), "اضغط الشاشة لما المؤشر بالأخضر", 20)
	if flash_t > 0.0: _text(Vector2(mid.x, s.y * 0.3), flash, 30, Color(1, 0.85, 0.5))

func _draw_minimap() -> void:
	var vs := get_viewport().get_visible_rect().size
	if big_map: # tapped: a large map in the middle of the screen with a legend
		var side := minf(vs.y - 120.0, 560.0)
		var origin := (vs - Vector2(side, side)) / 2.0 - minimap.position
		_draw_map(origin, side, true)
	else:
		_draw_map(Vector2.ZERO, 170.0, false)

func _map_text(pos: Vector2, t: String, size: int, col: Color) -> void:
	minimap.draw_string(Net.font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw_map(o: Vector2, side: float, big: bool) -> void:
	var k := side / (NightWorld.SIZE + NightWorld.ROAD_LEN * 2.0 + 8.0) if big else side / NightWorld.SIZE
	var c := o + Vector2(side, side) / 2.0
	var u := 1.0 if not big else 2.2 # marker scale
	minimap.draw_rect(Rect2(o, Vector2(side, side)), Color(0.02, 0.03, 0.05, 0.9 if big else 0.6))
	minimap.draw_rect(Rect2(o, Vector2(side, side)), Color(1, 1, 1, 0.5), false, 2.0)
	var wl := NightWorld.WALL * k
	minimap.draw_rect(Rect2(c - Vector2(wl, wl), Vector2(wl, wl) * 2.0), Color(0.1, 0.13, 0.1, 0.55) if world.map_id != "fareej" else Color(0.2, 0.17, 0.11, 0.55))
	if world.map_id == "fareej": # streets
		for st in [[-30.0, -47.0, 150.0, 7.0], [-30.0, 47.0, 150.0, 7.0], [-28.0, 0.0, 142.0, 8.0], [-13.0, 0.0, 7.0, 94.0]]:
			minimap.draw_rect(Rect2(c + Vector2(st[0] - st[2] / 2.0, st[1] - st[3] / 2.0) * k, Vector2(st[2], st[3]) * k), Color(0.32, 0.32, 0.34))
	for i in world.gate_points.size(): # escape roads + gates
		var p: Vector3 = world.gate_points[i][0]
		var out_dir := signf(p.z)
		var open: bool = rules.gates[i].open
		if big: minimap.draw_rect(Rect2(c + Vector2(-4.5, minf(p.z, p.z + out_dir * NightWorld.ROAD_LEN)) * k, Vector2(9.0, NightWorld.ROAD_LEN) * k), Color(0.3, 0.3, 0.3) if not open else Color(0.25, 0.5, 0.3))
		minimap.draw_rect(Rect2(c + Vector2(p.x, p.z) * k - Vector2(7, 3) * u, Vector2(14, 6) * u), Color(0.4, 1, 0.5) if open else Color(1, 0.3, 0.25))
	minimap.draw_rect(Rect2(c - Vector2(wl, wl), Vector2(wl, wl) * 2.0), Color(0.85, 0.85, 0.8, 0.8), false, 2.0 * u)
	for b in world.buildings:
		minimap.draw_set_transform(c + Vector2(b[0], b[1]) * k, -b[2], Vector2.ONE)
		var r := Rect2(-Vector2(b[3], b[4]) * k / 2.0, Vector2(b[3], b[4]) * k)
		minimap.draw_rect(r, Color(0.5, 0.46, 0.38))
		minimap.draw_rect(r, Color(0.8, 0.76, 0.66), false, 1.0)
		minimap.draw_line(Vector2(-1.0 * k, b[4] * k / 2.0), Vector2(1.0 * k, b[4] * k / 2.0), Color(0.1, 0.1, 0.1), 2.0) # door
	var mk: Dictionary = world.market
	minimap.draw_set_transform(c + Vector2(mk.pos.x, mk.pos.z) * k, -mk.yaw, Vector2.ONE)
	minimap.draw_rect(Rect2(-Vector2(mk.w, mk.d) * k / 2.0, Vector2(mk.w, mk.d) * k), Color(0.8, 0.25, 0.25))
	minimap.draw_rect(Rect2(Vector2(-mk.w / 2.0, mk.d / 2.0) * k, Vector2(mk.w, 13.0) * k), Color(0.25, 0.25, 0.27)) # parking
	minimap.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if big: _map_text(c + Vector2(mk.pos.x + 8.0, mk.pos.z + 3.0) * k, "السوق", 16, Color(1, 0.7, 0.7))
	for i in world.hook_points.size():
		var hp: Vector3 = world.hook_points[i]
		var used := rules.hook_user(i) != ""
		var hc := c + Vector2(hp.x, hp.z) * k
		var col := Color(1, 0.2, 0.2) if used else Color(0.75, 0.3, 0.3)
		minimap.draw_line(hc + Vector2(-3, -3) * u, hc + Vector2(3, 3) * u, col, 1.6 * u)
		minimap.draw_line(hc + Vector2(-3, 3) * u, hc + Vector2(3, -3) * u, col, 1.6 * u)
		if used: minimap.draw_arc(hc, 6.0 * u, 0, TAU, 16, Color(1, 0.3, 0.3), 1.5)
	for i in world.gen_points.size():
		var gp: Vector3 = world.gen_points[i]
		var g: Dictionary = rules.gens[i]
		var gc := c + Vector2(gp.x, gp.z) * k
		var sz := 7.0 * u
		minimap.draw_rect(Rect2(gc - Vector2(sz, sz) / 2.0, Vector2(sz, sz)), Color(0.1, 0.1, 0.1))
		if my_role == "survivor" or g.done: # survivors see repair progress fill up; the killer only sees finished ones
			minimap.draw_rect(Rect2(gc - Vector2(sz, sz) / 2.0 + Vector2(0, sz * (1.0 - g.p)), Vector2(sz, sz * g.p)), Color(0.4, 1, 0.5) if g.done else Color(1, 0.85, 0.2))
		minimap.draw_rect(Rect2(gc - Vector2(sz, sz) / 2.0, Vector2(sz, sz)), Color(0.4, 1, 0.5) if g.done else Color(1, 0.85, 0.2), false, 1.2)
	if rules.hatch >= 0 and my_role == "survivor":
		var hp2: Vector3 = world.hatch_points[rules.hatch]
		minimap.draw_circle(c + Vector2(hp2.x, hp2.z) * k, 5.0 * u, Color(0.5, 1, 0.7))
	for n in remotes: # survivors see their team; the killer never sees players here
		var r = remotes[n]
		if my_role == "survivor" and r.role == "survivor" and r.node.visible:
			var p: Vector3 = r.node.position
			minimap.draw_circle(c + Vector2(p.x, p.z) * k, 3.5 * u, Color(0.4, 0.8, 1))
			if big: _map_text(c + Vector2(p.x, p.z) * k + Vector2(8, 5), n, 15, Color(0.6, 0.85, 1))
	var me := c + Vector2(body.position.x, body.position.z) * k
	var f := Vector2(-sin(yaw), -cos(yaw))
	var sd := Vector2(-f.y, f.x)
	minimap.draw_colored_polygon(PackedVector2Array([me + f * 8.0 * u, me - f * 4.0 * u + sd * 5.0 * u, me - f * 4.0 * u - sd * 5.0 * u]),
		Color(1, 0.3, 0.3) if my_role == "killer" else Color(1, 1, 1))
	if big:
		var ly := o.y + side + 22.0
		var items := [["■", Color(1, 0.85, 0.2), "مولد"], ["■", Color(0.4, 1, 0.5), "مولد شغال"], ["✕", Color(0.75, 0.3, 0.3), "خطاف"], ["▬", Color(1, 0.3, 0.25), "بوابة"], ["■", Color(0.8, 0.25, 0.25), "السوق"]]
		var lx := o.x
		for it in items:
			_map_text(Vector2(lx, ly), it[0], 18, it[1])
			_map_text(Vector2(lx + 20, ly), it[2], 16, Color(0.9, 0.9, 0.9))
			lx += side / items.size()
	else:
		_map_text(o + Vector2(4, side + 16), "اضغط للتكبير", 13, Color(1, 1, 1, 0.45))

# ---------------- context: what each button would do right now ----------------
func _near(a: Vector3, b: Vector3, r: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() < r

func _update_ctx() -> void:
	ctx = {}
	if rules.over: return
	var pos := body.position
	if my_role == "survivor":
		var me: Dictionary = rules.s.get(my_name, {})
		if me.is_empty(): return
		if me.locker >= 0:
			ctx.interact = {"kind": "locker_out", "label": "اطلع", "i": me.locker}
			return
		if my_state == "hooked" and me.tries < Rules.MAX_TRIES:
			ctx.interact = {"kind": "struggle", "label": "فك نفسك"}
		if not (my_state in ["ok", "hurt"]): return
		for n in rules.s:
			var p: Dictionary = rules.s[n]
			if n == my_name: continue
			if p.hp == "hooked" and _near(pos, world.hook_points[p.hook_i], 2.9):
				ctx.interact = {"kind": "rescue", "label": "أنقذ", "n": n, "need": 1.5}
			if p.hp in ["hurt", "down"] and p.locker < 0 and _near(pos, _pos_of(n), 2.6):
				ctx.heal = {"kind": "heal", "n": n, "need": -1.0}
		if not ctx.has("interact"):
			for i in world.locker_points.size():
				if _near(pos, world.locker_points[i][0], 1.9) and rules.locker_user(i) == "":
					ctx.interact = {"kind": "locker_in", "label": "اختبئ", "i": i}
		if not ctx.has("interact"):
			for i in world.pallet_points.size():
				if rules.pallets[i] == 0 and _near(pos, world.pallet_points[i][0], 2.2):
					ctx.interact = {"kind": "pallet", "label": "اسقط", "i": i}
		if not ctx.has("interact") and not rules.powered:
			for i in world.gen_points.size():
				if not rules.gens[i].done and _near(pos, world.gen_points[i], 2.5):
					ctx.interact = {"kind": "rep", "label": "تصليح", "i": i, "need": -1.0}
		for w in world.window_points:
			if _near(pos, w[0], 1.7): ctx.vault = {"kind": "vault", "c": w[0], "n": w[1]}
		for i in world.pallet_points.size():
			var pp: Array = world.pallet_points[i]
			if rules.pallets[i] == 1 and _near(pos, pp[0], 1.7):
				ctx.vault = {"kind": "vault", "c": pp[0], "n": Basis(Vector3.UP, pp[1]) * Vector3(0, 0, 1)}
		if my_state == "hurt" and me.item: ctx.item = {"kind": "heal", "n": my_name, "need": -1.0}
		if rules.powered:
			for i in world.gate_points.size():
				if world.is_outside_gate(i, pos): _ev({"k": "escape"})
		if rules.hatch >= 0 and _near(pos, world.hatch_points[rules.hatch], 1.5): _ev({"k": "escape", "h": true})
	elif rules.stun <= 0.0:
		if rules.carrying != "":
			for i in world.hook_points.size():
				if rules.hook_user(i) == "" and _near(pos, world.hook_points[i], 3.2):
					ctx.interact = {"kind": "hook", "label": "علّق", "i": i}
			return
		for n in rules.s:
			if rules.s[n].hp == "down" and _near(pos, _pos_of(n), 2.7): ctx.interact = {"kind": "pickup", "label": "احمل", "n": n}
		if not ctx.has("interact"):
			for i in world.locker_points.size():
				if _near(pos, world.locker_points[i][0], 2.1): ctx.interact = {"kind": "search", "label": "فتّش", "i": i}
		if not ctx.has("interact"):
			for i in world.pallet_points.size():
				if rules.pallets[i] == 1 and _near(pos, world.pallet_points[i][0], 2.4):
					ctx.interact = {"kind": "break", "label": "اكسر", "i": i, "need": 2.0}
		if not ctx.has("interact"):
			for w in world.window_points:
				if _near(pos, w[0], 1.7): ctx.interact = {"kind": "vault", "label": "اقفز", "c": w[0], "n": w[1]}

# ---------------- actions ----------------
func _press(id: String, touch: int) -> void:
	match id:
		"sprint":
			sprint = not sprint
			if sprint: crouch = false
		"crouch":
			crouch = not crouch
			if crouch: sprint = false
		"next":
			var alive := _others_alive()
			if alive.size() > 0: spectating = alive[(alive.find(spectating) + 1) % alive.size()]
		"light":
			if battery > 0.0 or light_on:
				light_on = not light_on
				_sfx("click", null, -6.0)
		"attack":
			if attack_cd <= 0.0 and rules.stun <= 0.0 and rules.carrying == "":
				attack_t = 1.1
				attack_cd = 2.4
				hit_sent = false
				rig.play("attack", 2.0)
		"power": _ev({"k": "power"})
		"vault":
			if ctx.has("vault"): _start_vault(ctx.vault)
		_:
			var c = ctx.get(id)
			if c == null or not hold.is_empty(): return
			match str(c.kind):
				"struggle": _ev({"k": "struggle"})
				"locker_in": _ev({"k": "locker", "i": c.i, "on": true})
				"locker_out": _ev({"k": "locker", "i": c.i, "on": false})
				"pallet": _ev({"k": "pallet", "i": c.i})
				"pickup": _ev({"k": "pickup", "n": c.n})
				"hook": _ev({"k": "hook", "i": c.i})
				"search": _ev({"k": "search", "i": c.i})
				"vault": _start_vault(c)
				_:
					hold = {"btn": id, "kind": c.kind, "touch": touch, "t": 0.0, "need": float(c.get("need", -1.0)), "i": int(c.get("i", -1)), "n": str(c.get("n", ""))}
					if c.kind == "rep":
						next_skill = randf_range(3.0, 6.0)
						_ev({"k": "rep", "i": c.i, "on": true})
					elif c.kind == "heal": _ev({"k": "heal", "n": c.n, "on": true})

func _end_hold() -> void:
	if hold.is_empty(): return
	if hold.kind == "rep": _ev({"k": "rep", "i": hold.i, "on": false})
	elif hold.kind == "heal": _ev({"k": "heal", "n": hold.n, "on": false})
	hold = {}
	skill = {}

func _update_hold(delta: float) -> void:
	if hold.is_empty(): return
	var c = ctx.get(hold.btn)
	if c == null or str(c.kind) != hold.kind or int(c.get("i", -1)) != hold.i or str(c.get("n", "")) != hold.n or stick_vec.length() > 0.3:
		_end_hold()
		return
	if hold.need > 0.0: # timed action: fires when the bar fills
		hold.t += delta
		if hold.t >= hold.need:
			if hold.kind == "rescue": _ev({"k": "rescue", "n": hold.n})
			elif hold.kind == "break": _ev({"k": "break", "i": hold.i})
			hold = {}
	elif hold.kind == "rep":
		if skill.is_empty():
			next_skill -= delta
			if next_skill <= 0.0: skill = {"t": 0.0, "zone": randf_range(0.4, 0.85)}
		else:
			skill.t += delta
			if skill.t > 1.2:
				_ev({"k": "skill", "i": hold.i, "ok": false})
				_flash("فاتك! انفجر المولد")
				skill = {}
				next_skill = randf_range(4.0, 8.0)

func _skill_tap() -> void:
	var ok: bool = absf(float(skill.t) / 1.2 - float(skill.zone)) <= 0.07
	_ev({"k": "skill", "i": hold.i, "ok": ok})
	if ok: _sfx("ding")
	_flash("ممتاز!" if ok else "غلط! انفجر المولد")
	skill = {}
	next_skill = randf_range(4.0, 8.0)

func _start_vault(c: Dictionary) -> void:
	if not vault.is_empty() or attack_t > 0.0: return
	var center: Vector3 = c.c
	var normal: Vector3 = c.n
	var side := 1.0 if (body.position - center).dot(normal) >= 0.0 else -1.0
	var to := center - normal * side * 1.25
	to.y = center.y + 0.05
	vault = {"from": body.position, "to": to, "t": 0.0, "dur": 1.7 if my_role == "killer" else (0.7 if sprint else 1.0)}

func _input(e: InputEvent) -> void:
	if not started or rules.over: return
	if (e is InputEventScreenTouch or e is InputEventMouseButton) and e.pressed and Gfx.in_ui(e.position): return
	if Gfx.menu_open: return
	var half := get_viewport().get_visible_rect().size.x / 2.0
	if e is InputEventScreenTouch:
		if e.pressed:
			if big_map or Rect2(minimap.position, minimap.size).has_point(e.position): # tap the map to open / close it
				big_map = not big_map
				return
			if not skill.is_empty() and e.index != stick_id:
				_skill_tap()
				return
			for b in _buttons():
				if e.position.distance_to(b[0]) < b[1] + 8.0:
					_press(b[3], e.index)
					return
			if e.position.x < half and stick_id < 0:
				stick_id = e.index; stick_origin = e.position; stick_vec = Vector2.ZERO
			elif e.position.x >= half and look_id < 0:
				look_id = e.index
		else:
			if e.index == stick_id: stick_id = -1; stick_vec = Vector2.ZERO
			if e.index == look_id: look_id = -1
			if not hold.is_empty() and e.index == hold.touch: _end_hold()
	elif e is InputEventScreenDrag:
		if e.index == stick_id:
			stick_vec = ((e.position - stick_origin) / 70.0).limit_length(1.0)
			if stick_vec.length() < 0.12: stick_vec = Vector2.ZERO # dead zone
		elif e.index == look_id:
			yaw -= e.relative.x * 0.006
			pitch = clampf(pitch - e.relative.y * 0.004, -0.9, 0.5)
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * 0.003
		pitch = clampf(pitch - e.relative.y * 0.003, -0.9, 0.5)

## Hanging on the hook: lifted off the ground, legs kicking, body twisting; harder right after an escape attempt.
func me_locker() -> int:
	return rules.s[my_name].locker if rules.s.has(my_name) else -1

func _hook_pose(r: CharacterRig, n: String, dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0 + float(n.hash() % 100)
	var hard: float = 2.6 if thrash.get(n, 0.0) > 0.0 else 1.0
	r.position.y = lerpf(r.position.y, 0.62 + 0.04 * sin(t * 6.0 * hard), 1.0 - exp(-10.0 * dt))
	r.rotation = Vector3(0.07 * hard * sin(t * 3.3 * hard), 0.22 * hard * sin(t * 1.7 * hard), 0.1 * hard * sin(t * 4.6 * hard))
	r.play("hang", 1.0 * hard)

# ---------------- per-frame ----------------
func _process(dt: float) -> void:
	if lobby_scene:
		var tt := Time.get_ticks_msec() / 1000.0
		var fl := lobby_scene.get_node("Fire") as OmniLight3D
		var flick := 0.78 + 0.14 * sin(tt * 13.0) * sin(tt * 4.3) + 0.08 * sin(tt * 27.0)
		fl.light_energy = 3.4 * flick
		fl.position = Vector3(0.05 * sin(tt * 9.0), 0.75 + 0.05 * sin(tt * 7.0), 0.05 * cos(tt * 11.0)) # shadows dance
		(lobby_scene.get_node("Pivot") as Node3D).rotation.y = 0.1 * sin(tt * 0.13)
	if not started: return
	flash_t = maxf(flash_t - dt, 0.0)
	for i in boom_t.keys(): boom_t[i] = maxf(boom_t[i] - dt, 0.0)
	for n in thrash.keys(): thrash[n] = maxf(thrash[n] - dt, 0.0)
	ui.queue_redraw()
	minimap.queue_redraw()
	var kpos := _pos_of(rules.killer) if rules.killer != "" else Vector3.ZERO
	var w := 1.0 - exp(-12.0 * dt)
	noise = 0.0
	for n in remotes:
		var r = remotes[n]
		var st: String = rules.hp(n)
		var anim: String = r.anim
		var target: Vector3 = r.pos
		var lift := 0.0
		if st == "carried":
			target = kpos; lift = 0.25; anim = "carried"
		elif st == "hooked":
			target = world.hook_points[rules.s[n].hook_i] + Vector3(0, 0, 0.9)
		elif st == "dead" or (st == "down" and anim != "crawl"): anim = "dying"
		elif st == "hurt" and anim == "idle": anim = "injured"
		r.node.position = r.node.position.lerp(target, w)
		if st == "hooked":
			_hook_pose(r.rig, n, dt)
		else:
			r.rig.position.y = lerpf(r.rig.position.y, lift, w)
			r.rig.rotation = Vector3(0, lerp_angle(r.rig.rotation.y, r.yaw, w), 0)
			r.rig.play(anim)
		r.node.visible = st != "escaped" and not (rules.s.has(n) and rules.s[n].locker >= 0)
		if r.torch: r.torch.visible = r.lit and st in ["ok", "hurt"]
		# footsteps are 3D and depend on the ground; the killer also gets scratch marks and the detection indicator
		var moving: bool = r.node.visible and anim in ["run", "walk", "injured", "carry"]
		_steps(r.steps, r.node.position, moving, anim == "run", 4.0 if r.role == "killer" else 0.0)
		if anim == "run" and r.node.visible and my_role == "killer" and r.role == "survivor":
			r.step -= dt
			if r.step <= 0.0:
				r.step = 0.3
				_drop_mark(r.node.position)
			var to: Vector3 = r.node.position - body.position
			var lvl := clampf(1.0 - to.length() / 26.0, 0.0, 1.0)
			if lvl > noise:
				noise = lvl
				noise_dir = wrapf(atan2(to.x, -to.z) + yaw, -PI, PI)
	for m in marks:
		if m.t > 0.0:
			m.t -= dt
			m.node.scale = Vector3.ONE * clampf(m.t / 2.0, 0.0, 1.0)
			if m.t <= 0.0: m.node.visible = false
	# world visuals + sounds follow the rules state
	for i in rules.gens.size():
		var g: Dictionary = rules.gens[i]
		if g.done: world.set_gen_done(i)
		var hum: AudioStreamPlayer3D = gen_audio[i].hum
		var run: AudioStreamPlayer3D = gen_audio[i].run
		var ending: bool = g.p >= 0.85 and not g.done # about to start: engine sound + flickering lamps
		var want_hum: bool = g.p > 0.01 and g.p < 0.85
		if want_hum != hum.playing:
			if want_hum: hum.play()
			else: hum.stop()
		hum.pitch_scale = 0.75 + 0.45 * g.p
		hum.volume_db = -8.0 + 8.0 * g.p
		var want_run: bool = ending or g.done
		if want_run != run.playing:
			if want_run: run.play()
			else: run.stop()
		run.volume_db = 4.0 if ending else -7.0
		# the killer only notices the flicker from within 8 m
		if i < world.gen_nodes.size(): world.gen_nodes[i].blink = ending and (my_role != "killer" or body.position.distance_to(world.gen_points[i]) < 8.0)
	for i in rules.gates.size(): world.set_gate_state(i, rules.gates[i].open)
	if rules.hatch != last_hatch:
		last_hatch = rules.hatch
		world.set_hatch(rules.hatch)
		if rules.hatch >= 0:
			_sfx("hatch", world.hatch_points[rules.hatch], 8.0)
			_flash("انفتحت فتحة هروب! دوّر عليها" if my_role == "survivor" else "انفتحت فتحة هروب — لا تخليه يوصلها")
	world.set_market_dark(rules.killer != "" and world.in_market(kpos))
	# anyone passing a doorway makes it creak
	for n in door_cool.keys(): door_cool[n] = maxf(door_cool[n] - dt, 0.0)
	var walkers := [body.position]
	for n in remotes:
		if remotes[n].node.visible: walkers.append(remotes[n].node.position)
	for i in world.door_points.size():
		if door_cool.get(i, 0.0) > 0.0: continue
		for wp in walkers:
			if _near(wp, world.door_points[i][0], 0.8):
				door_cool[i] = 5.0
				_sfx("creak", world.door_points[i][0] + Vector3(0, 1.5, 0), 2.0, randf_range(0.85, 1.15))
				break
	for i in rules.pallets.size(): world.set_pallet_state(i, rules.pallets[i])
	if rules.powered and not was_powered:
		was_powered = true
		for g in world.gate_points: _sfx("gate", g[0] + Vector3(0, 3, 0), 8.0)
		_sfx("gate", null, -12.0)
		_flash("اشتغلت الكهرباء — البوابات انفتحت!")
	# survivors feel the killer coming: heartbeat inside the terror radius, heavy breathing when he is very close
	danger = 0.0
	var kdist := 999.0
	if my_role == "survivor" and rules.killer != "" and remotes.has(rules.killer) and my_state in ["ok", "hurt", "down", "hooked"]:
		kdist = body.position.distance_to(kpos)
		danger = clampf(1.0 - kdist / TERROR_RADIUS, 0.0, 1.0)
	var fade := 1.0 - exp(-4.0 * dt)
	if danger > 0.0 and not heart.playing: heart.play()
	heart.volume_db = lerpf(heart.volume_db, lerpf(-16.0, 4.0, danger) if danger > 0.0 else -60.0, fade)
	heart.pitch_scale = lerpf(0.92, 1.3, danger)
	if heart.playing and danger <= 0.0 and heart.volume_db < -50.0: heart.stop()
	var panting: bool = danger > 0.55
	if panting and not breath.playing: breath.play()
	breath.volume_db = lerpf(breath.volume_db, lerpf(-8.0, 3.0, (danger - 0.55) / 0.45) if panting else -60.0, fade)
	if breath.playing and not panting and breath.volume_db < -50.0: breath.stop()
	# chase music: the killer sees a survivor / a survivor is seen by the killer
	los_t -= dt
	if los_t <= 0.0:
		los_t = 0.2
		if my_role == "killer":
			var look := Vector3(-sin(yaw), 0, -cos(yaw))
			for n in remotes:
				var r = remotes[n]
				if r.role != "survivor" or not r.node.visible or not rules.free_now(n): continue
				var to: Vector3 = r.node.position - body.position
				if to.length() < 24.0 and look.dot(to.normalized()) > 0.35 and _line_of_sight(r.node.position): chase_hold = 6.0
		elif my_state in ["ok", "hurt"] and me_locker() < 0 and kdist < 18.0 and _line_of_sight(kpos):
			chase_hold = 6.0
	chase_hold = maxf(chase_hold - dt, 0.0)
	var chasing := chase_hold > 0.0 and not rules.over
	if chasing and not chase_music.playing: chase_music.play()
	chase_music.volume_db = lerpf(chase_music.volume_db, -6.0 if chasing else -60.0, 1.0 - exp(-2.5 * dt))
	if chase_music.playing and not chasing and chase_music.volume_db < -50.0: chase_music.stop()
	amb.volume_db = lerpf(amb.volume_db, -30.0 if chasing else -13.0, fade)
	if rules.over and not results.visible: _show_results()

func _physics_process(delta: float) -> void:
	if not started: return
	if offline:
		rules.tick(delta)
	match_time += delta
	escape_banner = maxf(escape_banner - delta, 0.0)
	my_state = rules.hp(my_name) if my_role == "survivor" else "ok"
	if my_state == "escaped" and last_state != "escaped": escape_banner = 4.0
	if offline and my_role == "survivor" and my_state in ["escaped", "dead"] and escape_banner <= 0.0 and last_state == my_state:
		rules.over = true # trial mode: the round is just me (after the banner has shown)
	# out of the round (escaped or dead): watch a teammate who is still inside
	if my_state in ["escaped", "dead"]:
		var alive := _others_alive()
		if not (spectating in alive): spectating = alive[0] if alive.size() > 0 else ""
	else: spectating = ""
	var me: Dictionary = rules.s.get(my_name, {})
	var locker: int = me.locker if not me.is_empty() else -1
	_update_ctx()
	_update_hold(delta)
	attack_t = maxf(attack_t - delta, 0.0)
	attack_cd = maxf(attack_cd - delta, 0.0)
	boost_t = maxf(boost_t - delta, 0.0)
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
	# states where I don't control my body
	var pinned := true
	if spectating != "":
		body.position = _pos_of(spectating)
		rig.visible = false
	elif my_state == "carried":
		body.position = _pos_of(rules.killer)
		rig.position.y = 0.25
		rig.play("carried")
	elif my_state == "hooked":
		body.position = world.hook_points[me.hook_i] + Vector3(0, 0, 0.9)
		_hook_pose(rig, my_name, delta)
	elif locker >= 0:
		body.position = world.locker_points[locker][0]
	elif not vault.is_empty():
		vault.t += delta
		var f: float = clampf(vault.t / vault.dur, 0.0, 1.0)
		var p: Vector3 = (vault.from as Vector3).lerp(vault.to, f)
		p.y += sin(f * PI) * 1.15
		body.position = p
		var dv: Vector3 = (vault.to as Vector3) - (vault.from as Vector3)
		rig.rotation.y = atan2(dv.x, dv.z)
		rig.play("vault", 1.17 / float(vault.dur))
		if f >= 1.0: vault = {}
	else:
		pinned = false
	if my_state != "carried" and my_state != "hooked": rig.position.y = 0.0
	if last_state == "hooked" and my_state != "hooked": rig.rotation = Vector3.ZERO
	if last_locker >= 0 and locker < 0 and my_state in ["ok", "hurt"]: # stepped out of a locker
		var lp: Array = world.locker_points[last_locker]
		body.position = lp[0] + Basis(Vector3.UP, lp[1]) * Vector3(0, 0, 1.1)
	last_locker = locker
	if my_role == "survivor": rig.visible = locker < 0 and my_state != "escaped" and spectating == ""
	cshape.disabled = pinned or my_state in ["dead", "escaped"]
	if pinned:
		body.velocity = Vector3.ZERO
	else:
		_move(delta)
	if flash_light: # flashlight follows where I look; the battery drains while it is on
		if light_on:
			battery = maxf(battery - delta * 100.0 / 150.0, 0.0)
			if battery <= 0.0 or not (my_state in ["ok", "hurt"]) or locker >= 0: light_on = false
		flash_light.visible = light_on
		flash_light.rotation = Vector3(pitch * 0.7 + 0.05, yaw, 0)
		if light_on and battery < 12.0: flash_light.light_energy = 7.0 * (0.4 + 0.6 * absf(sin(Time.get_ticks_msec() / 90.0))) # dying battery flickers
		else: flash_light.light_energy = 7.0
	var spd := Vector2(body.velocity.x, body.velocity.z).length()
	_steps(my_steps, body.position, not pinned and spd > 0.4 and not crouch and body.is_on_floor(), spd > 2.6, -8.0)
	last_state = my_state
	if not offline and spectating == "" and my_state != "escaped": # spectators stop reporting a position
		send_t -= delta
		if send_t <= 0.0:
			send_t = 1.0 / 15.0
			var p := body.position
			Net.send({"t": "st", "p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(rig.rotation.y, 0.01)], "a": rig.current, "f": 1 if light_on else 0})

func _move(delta: float) -> void:
	var frozen: bool = rules.over or my_state in ["dead", "escaped"] or not hold.is_empty() or (my_role == "killer" and rules.stun > 0.0)
	var move := stick_vec
	if move == Vector2.ZERO:
		move = Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))).limit_length(1.0)
	if frozen: move = Vector2.ZERO
	var speed: float = RUN[my_role] if (sprint or my_role == "killer") else WALK[my_role]
	if crouch: speed = CROUCH_SPEED
	if my_state == "down": speed = 0.45 # crawling
	if my_role == "killer" and rules.carrying != "": speed = CARRY_SPEED
	if boost_t > 0.0: speed *= 1.5
	var dir := Basis(Vector3.UP, yaw) * Vector3(move.x, 0, move.y)
	var target := dir.normalized() * speed * clampf(move.length() * 1.3, 0.0, 1.0) if move.length() > 0.05 else Vector3.ZERO
	if my_role == "killer": rig.rotation.y = yaw + PI # first person: the body faces where I look
	if attack_t > 0.75: # short lunge at the start of the swing
		target = Basis(Vector3.UP, rig.rotation.y) * Vector3(0, 0, 1) * 6.4
	elif attack_t > 0.0:
		target *= 0.3 # recovery slowdown after a swing
	var grounded := body.is_on_floor()
	var rate := (ACCEL if target != Vector3.ZERO else DECEL) * (1.0 if grounded else 0.3)
	var hv := Vector3(body.velocity.x, 0, body.velocity.z).move_toward(target, rate * delta)
	body.velocity.x = hv.x
	body.velocity.z = hv.z
	body.velocity.y = -2.0 if grounded else body.velocity.y - 22.0 * delta
	body.move_and_slide()
	var flat := Vector2(body.velocity.x, body.velocity.z)
	var v := flat.length()
	if my_role != "killer" and v > 0.25:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(flat.x, flat.y), 12.0 * delta)
	# killer hit check during the swing
	if my_role == "killer" and attack_t > 0.45 and attack_t < 0.95 and not hit_sent:
		var fwd := Basis(Vector3.UP, rig.rotation.y) * Vector3(0, 0, 1)
		for n in remotes:
			var r = remotes[n]
			if r.role != "survivor" or not rules.free_now(n): continue
			var to: Vector3 = r.node.position - body.position
			to.y = 0.0
			if to.length() < 2.5 and (to.length() < 0.7 or fwd.dot(to.normalized()) > 0.45):
				hit_sent = true
				_ev({"k": "hit", "n": n})
				break
	# animation
	if my_state == "dead":
		rig.play("dying")
	elif my_state == "down":
		if v > 0.1: rig.play("crawl", 1.0)
		elif rig.current != "crawl": rig.play("dying")
		else: rig.play("crawl", 0.0001)
	elif attack_t > 0.0:
		pass # the swing plays through
	elif not hold.is_empty():
		var tp := body.position
		match hold.kind:
			"rep": tp = world.gen_points[hold.i]
			"heal":
				if hold.n != my_name: tp = _pos_of(hold.n)
			"rescue": tp = world.hook_points[rules.s[hold.n].hook_i] if rules.s[hold.n].hook_i >= 0 else tp
			"break": tp = world.pallet_points[hold.i][0]
		if tp != body.position and my_role != "killer":
			rig.rotation.y = lerp_angle(rig.rotation.y, atan2(tp.x - body.position.x, tp.z - body.position.z), 10.0 * delta)
		rig.play("repair" if hold.kind in ["rep", "heal"] else "hide")
	elif crouch:
		if v > 0.25: rig.play("crouchwalk", clampf(v / NATURAL.crouchwalk, 0.5, 1.6))
		else: rig.play("hide")
	elif v > 0.25:
		if my_role == "killer" and rules.carrying != "":
			rig.play("carry", clampf(v / 1.4, 0.8, 2.6))
		elif v > 2.6:
			rig.play("run", clampf(v / NATURAL.run, 0.7, 1.7))
		elif my_state == "hurt": rig.play("injured", clampf(v / NATURAL.injured, 0.6, 1.6))
		else: rig.play("walk", clampf(v / NATURAL.walk, 0.6, 1.7))
	else:
		rig.play("idle")
