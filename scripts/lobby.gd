class_name NFLobby
extends Node3D
## Start screen: a camp in a forest clearing at night. The survivors warm themselves at a real-looking
## fire, the killer waits between the trees. While the character page is open the chosen character
## stands in front of the fire and the camera moves in on them. In a room the people around the fire
## are the real players with their own characters and names.

const STAND := Vector3(-0.17, 0.0, 3.0)      # where the selected character stands (right of centre on screen)
const CAM_IDLE := [Vector3(-2.1, 1.55, 6.0), Vector3(-0.06, -0.06, 0.0)]
const CAM_CHAR := [Vector3(-1.5, 1.45, 5.2), Vector3(-0.14, -0.2, 0.0)]
const EMOTES := ["wave", "dance", "clap"]            # relayed as {t:"emote", k:0..2}
const EMOTE_TEXT := ["تلويح", "رقص", "تصفيق"]
const EMOTE_ICON := ["hand", "note", "clap"]
const SEATS := [[-1.05, 2.1], [-0.38, 2.2], [0.42, 2.2], [1.1, 2.1], [-1.78, 2.3], [1.82, 2.3]]
const KILLER_AT := Vector3(1.6, 0.0, -7.4)
## Where she shows herself between the trees while nobody plays the killer: each time she comes
## back it is from the next spot, and the later ones are nearer the fire.
## (all of them right of the menu column, clear of the seats and the hook)
const STALK := [Vector3(1.6, 0.0, -7.4), Vector3(4.6, 0.0, -8.2), Vector3(-0.8, 0.0, -8.0), Vector3(6.2, 0.0, -5.4),
	Vector3(2.8, 0.0, -5.6), Vector3(-1.6, 0.0, -5.2), Vector3(3.6, 0.0, -4.2)]
const HOOK_AT := Vector3(4.9, 0.0, -0.2)

var stock: Array[Node3D] = []     # the shipped cast, shown when we are not in a room
var cast := {}                  # other players in the room: name -> {rig, tag}
var me_rig: CharacterRig
var me_char := ""
var me_name := ""
var _emoting := {} # rig -> seconds left before going back to idle
var me_label: Label3D
var fire: OmniLight3D
var sky_mat: ShaderMaterial
var env: Environment
var moon: DirectionalLight3D
var fire_mul := 1.0
var period := "night"
var misty := false
var pivot: Node3D
var cam: Camera3D
var key_light: OmniLight3D
var fill_light: OmniLight3D   # the cool side that opens the shadows
var back_light: OmniLight3D   # the rim behind the character
var focused := false
var _focus := 0.0
var _slide := 0.0
var _slide_from := Vector3.ZERO
var _dot_tex: ImageTexture
var stalker: CharacterRig         # the killer of the shipped cast
var stalk_rim: OmniLight3D
var _stalk_t := 6.0
var _stalk_i := 0
var _stalk_seen := true
var _trees: Array[MultiMeshInstance3D] = []
var _grass: MultiMeshInstance3D
var _ground_mat: StandardMaterial3D
var _dirt_mat: StandardMaterial3D
var _dress: Node3D                # what the picked map adds to the camp
var map_id := "?"
var intro := 1.0                  # 0 -> 1 while the opening shot comes down from the moon
static var intro_done := false    # once per launch, not after every round
var hook_arm: Node3D
var gallows: Node3D             # the owner's gallows, when it replaces the hook
var shade: MeshInstance3D         # something crossing behind the trees
var _shade_t := 11.0
var _shade_dir := 1.0
var _grav := Vector3.ZERO
var _tilt := Vector2.ZERO
var blood := false                # the last round was a wipe: the camp sits under a blood moon

func _soft_dot() -> ImageTexture: # shared with the other particle systems
	return NFUI.soft_dot()

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

## The weather the room (or the trial-mode menu) has picked.
static func weather() -> String:
	if Net.in_room(): return str(Net.room.get("theme", "normal"))
	return last_theme

static var last_theme := "normal" # the trial-mode pick, so the camp can follow it too

func _ready() -> void:
	var kit := NightWorld.new() # borrow the world's materials and meshes (never added to the tree)
	kit._make_materials()
	env = Environment.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	if ResourceLoader.exists("res://assets/sky/moon.jpg"): # the owner's moon
		sm.set_shader_parameter("moon_tex", load("res://assets/sky/moon.jpg"))
		sm.set_shader_parameter("has_moon_tex", 1.0)
	if ResourceLoader.exists("res://assets/sky/milkyway.jpg"): # the owner's night sky photograph
		sm.set_shader_parameter("night_tex", load("res://assets/sky/milkyway.jpg"))
		sm.set_shader_parameter("has_night_tex", 1.0)
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
	NFLook.apply(env, "camp") # occlusion round the fire, its light in the mist, bloom
	Gfx.changed.connect(func() -> void: NFLook.apply(env, "camp"))
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sky_mat = sm
	moon = DirectionalLight3D.new()
	moon.basis = Basis.looking_at(-Vector3(0.35, 0.33, -0.88).normalized())
	moon.light_color = Color(0.5, 0.6, 0.95)
	moon.light_energy = 1.0
	moon.shadow_enabled = true
	NFLook.soft_sun(moon, 0.5)
	add_child(moon)
	# ground: grass tinted, with a bare trampled circle around the fire
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	var gm: StandardMaterial3D = kit._mat.ground.duplicate()
	gm.vertex_color_use_as_albedo = false
	gm.albedo_color = Color(0.42, 0.56, 0.34)
	pm.material = gm
	ground.mesh = pm
	add_child(ground)
	var dirt := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 3.6; dm.bottom_radius = 3.9; dm.height = 0.04; dm.radial_segments = 28
	var dmat: StandardMaterial3D = kit._mat.ground.duplicate()
	dmat.vertex_color_use_as_albedo = false
	dmat.albedo_color = Color(0.75, 0.6, 0.42)
	dm.material = dmat
	dirt.mesh = dm
	dirt.position.y = 0.02
	add_child(dirt)
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
		add_child(mmi)
		_trees.append(mmi)
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
	add_child(gi)
	_grass = gi
	_ground_mat = gm
	_dirt_mat = dmat
	# camp props: stone ring, sitting logs, tent, crate with a lantern, stump with an axe, backpacks
	var rock: Material = kit._mat.rock
	var wood: Material = kit._mat.wood
	var camp_fire: PackedScene = kit._model("campfire") # the owner's campfire, when it is there
	for k in (0 if camp_fire else 11):
		var st := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = rng.randf_range(0.13, 0.2); sp.height = sp.radius * 1.5; sp.radial_segments = 8; sp.rings = 4
		sp.material = rock
		st.mesh = sp
		st.position = Vector3(sin(k * TAU / 11.0) * 0.62, 0.07, cos(k * TAU / 11.0) * 0.62)
		st.rotation.y = rng.randf() * TAU
		add_child(st)
	for lg in [[Vector3(-2.3, 0.22, 1.9), 0.9], [Vector3(2.6, 0.22, 1.4), -0.7]]:
		var log := MeshInstance3D.new()
		var lc := CylinderMesh.new()
		lc.top_radius = 0.22; lc.bottom_radius = 0.24; lc.height = 2.2; lc.radial_segments = 10
		lc.material = kit._mat.bark
		log.mesh = lc
		log.rotation = Vector3(0, lg[1], PI / 2.0)
		log.position = lg[0]
		add_child(log)
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
	add_child(tent)
	var crate := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(0.7, 0.6, 0.7)
	cb.material = wood
	crate.mesh = cb
	crate.position = Vector3(3.4, 0.3, -1.6)
	crate.rotation.y = 0.4
	add_child(crate)
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
	add_child(lantern)
	var ll := OmniLight3D.new()
	ll.position = Vector3(3.4, 0.9, -1.6)
	ll.light_color = Color(1.0, 0.78, 0.45)
	ll.light_energy = 0.9
	ll.omni_range = 4.0
	add_child(ll)
	var stump := MeshInstance3D.new()
	var sc2 := CylinderMesh.new()
	sc2.top_radius = 0.32; sc2.bottom_radius = 0.38; sc2.height = 0.5; sc2.radial_segments = 12
	sc2.material = kit._mat.bark
	stump.mesh = sc2
	stump.position = Vector3(-3.6, 0.25, 0.6)
	add_child(stump)
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
	add_child(axe)
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
		add_child(bag)
	# the fire: charred logs on a glowing ember bed, layered flames, sparks, smoke, flickering light
	var char_mat := StandardMaterial3D.new()
	char_mat.albedo_color = Color(0.05, 0.035, 0.03)
	char_mat.emission_enabled = true
	char_mat.emission = Color(1.0, 0.3, 0.05)
	char_mat.emission_energy_multiplier = 0.5
	for k in (0 if camp_fire else 6):
		var log2 := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06; cyl.bottom_radius = 0.085; cyl.height = 0.95; cyl.radial_segments = 8
		cyl.material = char_mat
		log2.mesh = cyl
		log2.rotation = Vector3(1.0, k * TAU / 6.0, 0)
		log2.position = Vector3(sin(k * TAU / 6.0) * 0.2, 0.3, cos(k * TAU / 6.0) * 0.2)
		add_child(log2)
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
	add_child(embers)
	if camp_fire:
		embers.visible = false
		var cf := camp_fire.instantiate() as Node3D
		cf.rotation.y = 0.6
		add_child(cf)
		NightWorld.prop_glow(cf, Color(1.0, 0.62, 0.3), 2.8)
	var fire_root := Node3D.new()
	fire_root.position = Vector3(0, 0.22, 0)
	add_child(fire_root)
	if camp_fire == null: _fire_layer(fire_root, 46, 0.75, 0.17, 1.5, 0.34, [Color(1.0, 0.5, 0.1, 0.0), Color(1.0, 0.36, 0.06, 0.42), Color(0.6, 0.06, 0.0, 0.0)], true, Vector2(0.15, 0.5)) # outer flames (the model has its own)
	_fire_layer(fire_root, 30, 0.5, 0.1, 1.3, 0.2, [Color(1.0, 0.9, 0.6, 0.0), Color(1.0, 0.8, 0.35, 0.5), Color(1.0, 0.35, 0.05, 0.0)], true, Vector2(0.1, 0.4)) # bright core
	_fire_layer(fire_root, 22, 2.4, 0.2, 0.9, 0.04, [Color(1.0, 0.8, 0.4, 1.0), Color(1.0, 0.5, 0.1, 1.0), Color(1.0, 0.2, 0.0, 0.0)], true, Vector2(0.7, 2.0), 30.0) # sparks
	var smoke := _fire_layer(fire_root, 18, 4.5, 0.15, 0.45, 0.6, [Color(0.1, 0.1, 0.1, 0.0), Color(0.14, 0.14, 0.15, 0.16), Color(0.1, 0.1, 0.11, 0.0)], false, Vector2(0.3, 0.6), 10.0)
	smoke.position.y = 0.9
	fire = OmniLight3D.new()
	fire.name = "Fire"
	fire.position = Vector3(0, 0.75, 0)
	fire.light_color = Color(1.0, 0.55, 0.2)
	fire.light_energy = 3.4
	fire.omni_range = 11.0
	fire.shadow_enabled = true
	NFLook.halo(fire, 2.5) # the fire glows in the camp's mist
	add_child(fire)
	# the shipped cast: survivors around the fire, the killer watching from the tree line
	for i in 4:
		var st2: Array = SEATS[i]
		var r := CharacterRig.new()
		add_child(r)
		r.setup(["survivor1", "survivor2", "survivor5", "survivor6"][i], ["campfire", "idle"])
		r.position = Vector3(sin(st2[0]) * st2[1], 0, -cos(st2[0]) * st2[1])
		r.rotation.y = atan2(-r.position.x, -r.position.z)
		r.play("campfire")
		r.player.seek(3.0 + absf(st2[0]) * 2.3, true)
		stock.append(r)
	var killer := CharacterRig.new()
	add_child(killer)
	killer.setup("killer", ["idle"])
	killer.position = KILLER_AT
	killer.rotation.y = atan2(-killer.position.x, -killer.position.z)
	killer.play("idle")
	stalker = killer
	var rim := OmniLight3D.new() # faint red rim so his outline reads in the dark
	rim.position = Vector3(2.4, 2.2, -8.6)
	rim.light_color = Color(1.0, 0.15, 0.1)
	rim.light_energy = 2.2
	rim.omni_range = 4.0
	add_child(rim)
	stalk_rim = rim
	# the stand is lit the way a photographer would do it: a warm key in front and to one side,
	# a cool fill on the other to open the shadows, and a hard rim behind to cut the character
	# out of the dark. It is three small lights and it is what makes the model read.
	key_light = OmniLight3D.new()
	key_light.position = STAND + Vector3(0.95, 2.05, 1.75)
	key_light.light_color = Color(1.0, 0.88, 0.74)
	key_light.light_energy = 2.4
	key_light.omni_range = 6.5
	key_light.light_specular = 1.1
	NFLook.shadows_on(key_light) # the character's own shadow on the ground in front of the fire
	add_child(key_light)
	fill_light = OmniLight3D.new()
	fill_light.position = STAND + Vector3(-1.5, 1.5, 1.3)
	fill_light.light_color = Color(0.55, 0.68, 1.0)
	fill_light.light_energy = 0.9
	fill_light.omni_range = 6.0
	fill_light.shadow_enabled = false
	add_child(fill_light)
	back_light = OmniLight3D.new()
	back_light.position = STAND + Vector3(-0.6, 2.3, -1.5)
	back_light.light_color = Color(0.9, 0.95, 1.0)
	back_light.light_energy = 2.6
	back_light.omni_range = 5.0
	back_light.shadow_enabled = false
	add_child(back_light)
	pivot = Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	cam = Camera3D.new()
	cam.position = CAM_IDLE[0] # the camp sits right of centre: the menu column is on the left
	cam.rotation = CAM_IDLE[1]
	cam.fov = 55.0
	cam.far = 300.0
	pivot.add_child(cam)
	cam.current = true
	# sound: the crackle the owner supplied, over the ambient track
	for snd in [["campfire", -4.0], ["ambient", -14.0]]:
		var a := AudioStreamPlayer.new()
		a.bus = Aud.MUSIC
		var stream: AudioStreamMP3 = load("res://assets/sfx/%s.mp3" % snd[0])
		stream.loop = true
		a.stream = stream
		a.volume_db = snd[1]
		add_child(a)
		a.play()
	_build_air()
	_build_hook(kit)
	_build_owner_models()
	set_map("forest")
	_time_of_day()
	kit.free()
	_place_stalker()
	Gfx.look_changed.connect(_apply_look)
	if not intro_done and DisplayServer.get_name() != "headless":
		intro_done = true
		intro = 0.0

## Tests and screenshots pretend it is this hour (and force the mist on or off); -1 = normal.
static var force_hour := -1
static var force_mist := -1

## The camp is **always night** — it is a horror game and the owner asked for it. The mist comes
## from the weather the host picked for the round (ضباب), so the start screen already shows you
## what you are about to play. force_hour is only for the tests and the screenshots.
func _time_of_day() -> void:
	var h: int = force_hour if force_hour >= 0 else 21
	if h >= 5 and h < 8: period = "dawn"
	elif h >= 8 and h < 17: period = "day"
	elif h >= 17 and h < 20: period = "dusk"
	else: period = "night"
	misty = (force_mist == 1) if force_mist >= 0 else (weather() == "fog")
	var sky_day := 0.0
	var sky_warm := 0.0
	var moon_col := Color(0.5, 0.6, 0.95)
	var moon_e := 1.0
	var amb := Color(0.14, 0.19, 0.34)
	var amb_e := 1.3
	var fog := Color(0.07, 0.1, 0.17)
	var fog_d := 0.022
	match period:
		"dawn":
			sky_day = 0.4; sky_warm = 0.95
			moon_col = Color(1.0, 0.72, 0.5); moon_e = 1.5
			amb = Color(0.3, 0.26, 0.3); amb_e = 1.5
			fog = Color(0.4, 0.3, 0.28); fog_d = 0.03
			fire_mul = 0.75
		"day":
			sky_day = 1.0; sky_warm = 0.12
			moon_col = Color(1.0, 0.95, 0.86); moon_e = 2.4
			amb = Color(0.5, 0.56, 0.66); amb_e = 1.7
			fog = Color(0.6, 0.66, 0.74); fog_d = 0.012
			fire_mul = 0.45
		"dusk":
			sky_day = 0.3; sky_warm = 1.0
			moon_col = Color(1.0, 0.6, 0.36); moon_e = 1.2
			amb = Color(0.3, 0.22, 0.26); amb_e = 1.4
			fog = Color(0.35, 0.22, 0.2); fog_d = 0.032
			fire_mul = 0.9
	if misty: # a low fog bank over the clearing
		fog_d *= 2.4
		fog = fog.lerp(Color(0.62, 0.64, 0.68), 0.45)
	sky_mat.set_shader_parameter("day", sky_day)
	sky_mat.set_shader_parameter("warm", sky_warm)
	moon.light_color = moon_col
	moon.light_energy = moon_e * 0.6 # the owner: softer moonlight
	env.ambient_light_color = amb
	env.ambient_light_energy = amb_e * 1.25 # lighter, like the maps
	env.tonemap_exposure = 1.1 * Gfx.brightness
	env.fog_light_color = fog
	env.fog_density = fog_d
	# a round nobody got out of leaves its moon over the camp until one goes better
	blood = bool(Net.last_round.get("wipe", false)) and period == "night"
	sky_mat.set_shader_parameter("blood", 1.0 if blood else 0.0)
	if blood:
		moon.light_color = Color(1.0, 0.32, 0.26)
		moon.light_energy = 0.75
		env.ambient_light_color = Color(0.3, 0.1, 0.12)
		env.fog_light_color = fog.lerp(Color(0.3, 0.05, 0.05), 0.6)

# ---------------- the chosen character in front of the fire ----------------
func _tag(text: String, col: Color, y: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Net.font
	l.font_size = 52
	l.pixel_size = 0.0035
	l.position.y = y
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = col
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 0.85)
	return l

## Put `char_id` on the stand; `dir` (-1 / +1) slides it in from that side.
func preview(char_id: String, label := "", dir := 0.0) -> void:
	if char_id == me_char and me_rig: return
	me_char = char_id
	if me_rig:
		me_rig.queue_free()
		me_rig = null
	if char_id == "": return
	me_rig = CharacterRig.new()
	add_child(me_rig)
	me_rig.setup(char_id, ["idle", "campfire"] + EMOTES, true) # the one you are looking at, in detail
	me_rig.play("idle")
	_slide_from = STAND + Vector3(dir * 1.9, 0.0, 0.35)
	_slide = 1.0 if dir != 0.0 else 0.0
	me_rig.position = _slide_from if dir != 0.0 else STAND
	me_rig.rotation.y = atan2(CAM_IDLE[0].x - STAND.x, CAM_IDLE[0].z - STAND.z)
	me_label = _tag(label, Color(1, 0.88, 0.6), 2.15)
	me_rig.add_child(me_label)

func hide_preview() -> void:
	me_char = ""
	if me_rig:
		me_rig.queue_free()
		me_rig = null

## Camera moves in on the stand while the character page is open.
func focus(on: bool) -> void:
	focused = on

# ---------------- the people around the fire ----------------
## `players` is the room list ([{name, role, char}]); empty shows the shipped cast again.
func set_cast(players: Array, me: String) -> void:
	me_name = me
	var want := {}
	var seat := 0
	for p in players:
		var n := str(p.get("name", ""))
		if n == "" or n == me: continue
		var role := str(p.get("role", "survivor"))
		var cid := str(p.get("char", "survivor1"))
		want[n] = {"char": cid, "role": role, "seat": seat}
		if role != "killer": seat += 1
		if seat >= SEATS.size(): break
	for n in cast.keys():
		if not want.has(n) or cast[n].char != want[n].char:
			cast[n].rig.queue_free()
			cast.erase(n)
	for n in want:
		if cast.has(n): # still here: only move them if somebody left and freed a seat
			if int(cast[n].seat) != int(want[n].seat) and str(want[n].role) != "killer":
				cast[n].seat = int(want[n].seat)
				var st3: Array = SEATS[int(want[n].seat) % SEATS.size()]
				cast[n].rig.position = Vector3(sin(st3[0]) * st3[1], 0, -cos(st3[0]) * st3[1])
				cast[n].rig.rotation.y = atan2(-cast[n].rig.position.x, -cast[n].rig.position.z)
			continue
		var d: Dictionary = want[n]
		var r := CharacterRig.new()
		add_child(r)
		var killer: bool = d.role == "killer"
		r.setup(str(d.char), (["idle"] if killer else ["campfire", "idle"]) + EMOTES)
		if killer:
			r.position = KILLER_AT
			r.rotation.y = atan2(-r.position.x, -r.position.z)
			r.play("idle")
		else:
			var st: Array = SEATS[int(d.seat) % SEATS.size()]
			r.position = Vector3(sin(st[0]) * st[1], 0, -cos(st[0]) * st[1])
			r.rotation.y = atan2(-r.position.x, -r.position.z)
			r.play("campfire")
			r.player.seek(2.0 + float(d.seat) * 1.7, true)
		var tag_col := Color(1, 0.45, 0.45) if killer else Color(0.78, 0.92, 1.0)
		if str(d.role) == "friend": tag_col = Color(0.55, 1.0, 0.6) # online, not in a room: tap to invite
		r.add_child(_tag(n, tag_col, 2.2))
		cast[n] = {"rig": r, "char": str(d.char), "seat": int(d.seat), "killer": killer}
	var in_room := not players.is_empty()
	for s in stock: s.visible = not in_room
	if in_room: _stalk_t = minf(_stalk_t, 0.5) # settle who the killer is right away

## Play a campfire emote. `who` is the player's name; mine is the one standing at the fire.
func emote(who: String, k: int) -> void:
	k = clampi(k, 0, EMOTES.size() - 1)
	var r: CharacterRig = null
	if who == me_name or who == "": r = me_rig
	elif cast.has(who): r = cast[who].rig
	if r == null or not is_instance_valid(r): return
	if not r.player.has_animation(EMOTES[k]): return
	r.play(EMOTES[k])
	_emoting[r] = float(CharacterRig.EMOTES.get(EMOTES[k], 3.0)) * (2.0 if EMOTES[k] != "dance" else 1.0) + 0.2 # then back to sitting / standing

func _tick_emotes(dt: float) -> void:
	for r in _emoting.keys():
		if not is_instance_valid(r):
			_emoting.erase(r)
			continue
		_emoting[r] -= dt
		if _emoting[r] <= 0.0:
			_emoting.erase(r)
			r.play("idle" if r == me_rig else ("campfire" if r.player.has_animation("campfire") else "idle"))

# ---------------- the camp is alive ----------------
func _mat_flat(col: Color, glow := 0.0, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = glow
	return m

func _bx(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	mi.rotation.y = yaw
	parent.add_child(mi)
	return mi

func _cy(parent: Node3D, top: float, bottom: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 10
	c.material = mat
	mi.mesh = c
	mi.position = pos
	parent.add_child(mi)
	return mi

## Slow particles that hang in a box of air: the ground mist and the fireflies.
func _drift(amount: int, life: float, extents: Vector3, at: Vector3, size: float, colors: Array, additive: bool, speed: Vector2) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = extents
	m.gravity = Vector3.ZERO
	m.direction = Vector3(1, 0.15, 0.3)
	m.spread = 180.0
	m.initial_velocity_min = speed.x
	m.initial_velocity_max = speed.y
	m.scale_min = 0.7
	m.scale_max = 1.4
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
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
	p.position = at
	p.visibility_aabb = AABB(-extents - Vector3(4, 4, 4), extents * 2.0 + Vector3(8, 8, 8))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

func _build_air() -> void:
	# a low mist that creeps over the clearing, and fireflies in the grass
	_drift(22, 10.0, Vector3(10.0, 0.12, 8.0), Vector3(0, 0.3, -2.0), 3.4,
		[Color(0.5, 0.56, 0.66, 0.0), Color(0.5, 0.56, 0.66, 0.06), Color(0.5, 0.56, 0.66, 0.0)], false, Vector2(0.08, 0.3))
	_drift(18, 6.0, Vector3(9.0, 0.5, 7.0), Vector3(0, 0.9, -3.0), 0.07,
		[Color(0.7, 1.0, 0.35, 0.0), Color(0.8, 1.0, 0.4, 1.0), Color(0.7, 1.0, 0.35, 0.0)], true, Vector2(0.1, 0.35))
	# and now and then something tall walks past behind the trees
	var dark := _mat_flat(Color(0.008, 0.008, 0.012))
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shade = _bx(self, Vector3(0.62, 2.05, 0.3), Vector3(-30, 1.02, -13.5), dark)
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shade.visible = false

## A hook at the edge of the camp, swinging a little. It carries blood if I died last round.
func _build_hook(kit: NightWorld) -> void:
	var root := Node3D.new()
	root.position = HOOK_AT
	root.rotation.y = -0.5
	add_child(root)
	var gallows_ps: PackedScene = kit._model("hook")
	if gallows_ps: # the owner's gallows, a size down for the camp; it does not swing
		var g := gallows_ps.instantiate() as Node3D
		g.scale = Vector3(0.62, 0.62, 0.62)
		g.position.z = -0.9 * 0.62 # its hook over the hook point, the post behind it
		root.add_child(g)
		gallows = g
		NightWorld.prop_glow(g, Color(1.0, 0.75, 0.45), 2.5)
		if str(Net.last_round.get("res", "")) == "dead":
			_cy(root, 0.42, 0.46, 0.012, Vector3(0, 0.05, 0), _mat_flat(Color(0.2, 0.005, 0.005), 0.0, 0.25))
		return
	_cy(root, 0.08, 0.11, 3.1, Vector3(0, 1.55, 0), kit._mat.bark)
	_bx(root, Vector3(1.15, 0.1, 0.1), Vector3(-0.5, 3.0, 0), kit._mat.wood)
	hook_arm = Node3D.new()
	hook_arm.position = Vector3(-0.98, 2.95, 0)
	root.add_child(hook_arm)
	var died := str(Net.last_round.get("res", "")) == "dead"
	var steel: Material = _mat_flat(Color(0.32, 0.01, 0.01), 0.0, 0.35) if died else kit._mat.metal
	_bx(hook_arm, Vector3(0.03, 0.75, 0.03), Vector3(0, -0.38, 0), kit._mat.metal)
	_bx(hook_arm, Vector3(0.05, 0.3, 0.05), Vector3(0, -0.88, 0), steel)
	_bx(hook_arm, Vector3(0.2, 0.05, 0.05), Vector3(0.08, -1.03, 0), steel)
	_bx(hook_arm, Vector3(0.05, 0.14, 0.05), Vector3(0.16, -0.97, 0), steel)
	if died: # what was left under it
		_cy(root, 0.42, 0.46, 0.012, Vector3(-0.98, 0.05, 0), _mat_flat(Color(0.2, 0.005, 0.005), 0.0, 0.25))

## The owner's models around the fire: the quiet nun crouched at the edge of the light, ravens on
## the ground and in the glowing lantern tree, the outpost and the great tree far behind.
var owner_models := 0
func _prop(name: String, at: Vector3, yaw := 0.0, k := 1.0, parent: Node3D = null) -> Node3D:
	var path := "res://assets/props/%s.glb" % name
	if not ResourceLoader.exists(path): return null
	var n := (load(path) as PackedScene).instantiate() as Node3D
	n.position = at
	n.rotation.y = yaw
	n.scale = Vector3(k, k, k)
	(parent if parent else self).add_child(n)
	owner_models += 1
	return n

func _build_owner_models() -> void:
	var nun := _prop("nun", Vector3(-4.6, 0.0, -2.6), atan2(4.6, 2.6) + PI)
	if nun: # a cold light on her face, nothing else: she is only just there
		var l := OmniLight3D.new()
		l.light_color = Color(0.55, 0.65, 1.0)
		l.light_energy = 0.7
		l.omni_range = 2.6
		l.position = Vector3(0.0, 1.3, 0.9)
		nun.add_child(l)
	_prop("raven", Vector3(2.9, 0.0, 0.6), -2.2, 0.9)
	var tree := _prop("lantern_tree", Vector3(-7.6, 0.0, -6.4), 0.6, 1.1)
	if tree:
		NightWorld.prop_glow(tree, Color(0.85, 0.97, 1.0), 2.4)
		var tl := OmniLight3D.new()
		tl.light_color = Color(0.55, 0.88, 1.0)
		tl.light_energy = 1.4
		tl.omni_range = 6.0
		tl.position = Vector3(0, 1.6, 0)
		tree.add_child(tl)
		_prop("raven", Vector3(0.6, 1.25, 0.2), 1.0, 0.8, tree)
	_prop("outpost", Vector3(15.0, 0.0, -24.0), -0.7)
	var big := _prop("world_tree", Vector3(-26.0, -0.5, -46.0), 0.3)
	if big:
		for gi in big.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Dress the camp for the map the room (or the trial menu) has picked.
func set_map(id: String) -> void:
	if id == map_id: return
	map_id = id
	if _dress and is_instance_valid(_dress): _dress.queue_free()
	_dress = Node3D.new()
	add_child(_dress)
	var woods := id in ["forest", "village"]
	for t in _trees: t.visible = woods
	_grass.visible = woods
	var gcol := Color(0.42, 0.56, 0.34)
	var dcol := Color(0.75, 0.6, 0.42)
	match id:
		"rubkhali":
			gcol = Color(0.86, 0.7, 0.46); dcol = Color(0.9, 0.76, 0.52)
			_palms(5)
			for dn in [[Vector3(-12, -0.6, -19), 8.0], [Vector3(6, -0.8, -24), 10.0], [Vector3(19, -0.5, -14), 7.0]]:
				var dune := MeshInstance3D.new()
				var sp := SphereMesh.new()
				sp.radius = float(dn[1]); sp.height = float(dn[1]) * 0.55; sp.radial_segments = 20; sp.rings = 8
				sp.material = _mat_flat(Color(0.8, 0.64, 0.4), 0.3)
				dune.mesh = sp
				dune.position = dn[0]
				_dress.add_child(dune)
		"beach":
			gcol = Color(0.88, 0.78, 0.56); dcol = Color(0.92, 0.82, 0.6)
			_palms(7)
			var sea := MeshInstance3D.new()
			var pl := PlaneMesh.new()
			pl.size = Vector2(220, 90)
			var sm := _mat_flat(Color(0.02, 0.07, 0.12), 0.0, 0.12)
			sm.metallic = 0.4
			pl.material = sm
			sea.mesh = pl
			sea.position = Vector3(0, 0.03, -57.0)
			_dress.add_child(sea)
			_bx(_dress, Vector3(220, 0.03, 0.55), Vector3(0, 0.04, -12.2), _mat_flat(Color(0.75, 0.82, 0.86), 0.25)) # the foam line
		"fareej":
			gcol = Color(0.62, 0.54, 0.42); dcol = Color(0.7, 0.6, 0.46)
			var clay := _mat_flat(Color(0.7, 0.6, 0.44), 0.32)
			for seg in [[-13.0, 12.0], [9.5, 13.0]]: # the neighbourhood wall, with a way in
				_bx(_dress, Vector3(float(seg[1]), 3.2, 0.5), Vector3(float(seg[0]), 1.6, -11.5), clay)
			_bx(_dress, Vector3(6.5, 3.8, 5.0), Vector3(8.5, 1.9, -16.5), clay)
			var lit := _mat_flat(Color(1.0, 0.78, 0.42), 2.2)
			_bx(_dress, Vector3(0.9, 1.1, 0.06), Vector3(7.2, 2.2, -13.97), lit)
			_bx(_dress, Vector3(0.9, 1.1, 0.06), Vector3(9.8, 2.2, -13.97), lit)
			_cy(_dress, 0.85, 1.0, 12.0, Vector3(-7.5, 6.0, -18.0), clay)      # the minaret
			_cy(_dress, 1.35, 1.35, 0.35, Vector3(-7.5, 9.6, -18.0), clay)
			_cy(_dress, 0.0, 0.8, 2.2, Vector3(-7.5, 13.1, -18.0), _mat_flat(Color(0.2, 0.5, 0.36)))
			_bx(_dress, Vector3(0.5, 1.0, 0.5), Vector3(-7.5, 10.4, -18.0), _mat_flat(Color(0.4, 1.0, 0.6), 2.5))
		"garage":
			gcol = Color(0.34, 0.34, 0.35); dcol = Color(0.4, 0.4, 0.41)
			var conc := _mat_flat(Color(0.3, 0.3, 0.31), 0.45)
			_bx(_dress, Vector3(44, 0.4, 24), Vector3(0, 3.7, -17.0), conc) # the slab overhead
			for cx in [-10.5, -3.5, 3.5, 10.5]:
				for cz in [-7.0, -14.0, -21.0]:
					_bx(_dress, Vector3(0.6, 3.5, 0.6), Vector3(cx, 1.75, cz), conc)
			var tube := _mat_flat(Color(0.85, 0.95, 1.0), 2.6)
			for tz in [-9.5, -16.5]:
				for tx in [-7.0, 0.0, 7.0]:
					_bx(_dress, Vector3(2.2, 0.06, 0.18), Vector3(tx, 3.46, tz), tube)
			_bx(_dress, Vector3(1.8, 1.25, 4.2), Vector3(-6.8, 0.63, -11.0), _mat_flat(Color(0.12, 0.13, 0.16), 0.0, 0.4), 0.05)
			_bx(_dress, Vector3(1.8, 1.25, 4.2), Vector3(6.6, 0.63, -17.5), _mat_flat(Color(0.25, 0.06, 0.06), 0.0, 0.4), -0.08)
		"kuwait": # the Gulf Road: palms, the towers over the water, warm street lights
			gcol = Color(0.3, 0.3, 0.3); dcol = Color(0.36, 0.34, 0.32)
			_palms(6)
			var tw2 := _prop("kw_towers", Vector3(16.0, -0.5, -70.0), -PI / 2.0, 0.55, _dress)
			if tw2: NightWorld.prop_glow(tw2, Color(0.5, 0.7, 1.0), 1.5)
			var bl2 := OmniLight3D.new()
			bl2.light_color = Color(0.35, 0.6, 1.0)
			bl2.light_energy = 3.0
			bl2.omni_range = 18.0
			bl2.position = Vector3(16.0, 25.0, -70.0)
			_dress.add_child(bl2)
			var sea2 := MeshInstance3D.new()
			var pl2 := PlaneMesh.new()
			pl2.size = Vector2(220, 90)
			var sm2 := _mat_flat(Color(0.02, 0.05, 0.1), 0.0, 0.1)
			sm2.metallic = 0.45
			pl2.material = sm2
			sea2.mesh = pl2
			sea2.position = Vector3(0, 0.03, -62.0)
			_dress.add_child(sea2)
		"city": # City Life: towers with lit windows and neon behind the trees
			gcol = Color(0.2, 0.2, 0.23); dcol = Color(0.26, 0.26, 0.29)
			var conc2 := _mat_flat(Color(0.09, 0.09, 0.11), 0.2)
			var win := _mat_flat(Color(1.0, 0.82, 0.5), 1.6)
			var neon := [Color(1.0, 0.2, 0.7), Color(0.2, 0.9, 1.0), Color(0.7, 0.3, 1.0)]
			var tw := [[Vector3(-14, 0, -24), 6.0, 26.0], [Vector3(-4, 0, -30), 7.0, 38.0], [Vector3(8, 0, -26), 6.0, 30.0], [Vector3(18, 0, -20), 5.0, 22.0]]
			for i in tw.size():
				var t: Array = tw[i]
				var h: float = t[2]
				_bx(_dress, Vector3(t[1], h, t[1]), (t[0] as Vector3) + Vector3(0, h / 2.0, 0), conc2)
				for k in 7: # rows of lit windows on the face toward the camp
					_bx(_dress, Vector3(t[1] * 0.8, 0.35, 0.05), (t[0] as Vector3) + Vector3(0, 3.0 + k * h / 8.0, t[1] / 2.0 + 0.03), win)
				_bx(_dress, Vector3(t[1] * 0.7, 0.5, 0.06), (t[0] as Vector3) + Vector3(0, h * 0.55, t[1] / 2.0 + 0.06), _mat_flat(neon[i % 3], 3.0))
		"village":
			var plank := _mat_flat(Color(0.2, 0.17, 0.14), 0.35)
			for hs in [[Vector3(-10, 0, -14), 0.3], [Vector3(4, 0, -17), -0.15], [Vector3(12, 0, -10), 0.8]]:
				var house := Node3D.new()
				house.position = hs[0]
				house.rotation.y = float(hs[1])
				_dress.add_child(house)
				_bx(house, Vector3(5.0, 3.0, 4.4), Vector3(0, 1.5, 0), plank)
				var roof := MeshInstance3D.new()
				var pr := PrismMesh.new()
				pr.size = Vector3(5.6, 1.8, 5.0)
				pr.material = _mat_flat(Color(0.1, 0.08, 0.08))
				roof.mesh = pr
				roof.position.y = 3.9
				house.add_child(roof)
				_bx(house, Vector3(0.8, 0.9, 0.06), Vector3(-1.2, 1.7, 2.23), _mat_flat(Color(0.9, 0.6, 0.25), 1.2))
	if id in ["fareej", "garage", "village", "city"]: # one warm (or strip-white) light on what the map added
		var o := OmniLight3D.new()
		o.light_color = Color(0.85, 0.92, 1.0) if id == "garage" else Color(1.0, 0.72, 0.42)
		o.light_energy = 2.4
		o.omni_range = 14.0
		o.position = Vector3(1.0, 3.0, -12.5)
		_dress.add_child(o)
	# his grass clumps round the clearing: green in the woods, dry on sand
	var clump := "grass_dry" if id in ["rubkhali", "beach", "fareej"] else ("" if id in ["garage", "city"] else "grass_green")
	if clump != "":
		var rg := RandomNumberGenerator.new()
		rg.seed = 99
		for i in 16:
			var a := rg.randf() * TAU
			var r := rg.randf_range(4.5, 11.0)
			var at := Vector3(cos(a) * r, 0.0, sin(a) * r - 3.0)
			if at.z > 1.0 and absf(at.x) < 4.0: continue # keep the stand and the seats clear
			_prop(clump, at, rg.randf() * TAU, rg.randf_range(0.8, 1.4), _dress)
	_ground_mat.albedo_color = gcol
	_dirt_mat.albedo_color = dcol

func _palms(n: int) -> void:
	var spots := [Vector3(-6.2, 0, -6.4), Vector3(5.8, 0, -8.0), Vector3(-3.0, 0, -10.5), Vector3(8.4, 0, -3.6),
		Vector3(-8.8, 0, -1.8), Vector3(2.2, 0, -11.5), Vector3(11.0, 0, -8.5)]
	var trunk := _mat_flat(Color(0.3, 0.22, 0.14), 0.3)
	var leaf := _mat_flat(Color(0.14, 0.3, 0.12), 0.35)
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in mini(n, spots.size()):
		var palm := Node3D.new()
		palm.position = spots[i]
		palm.rotation = Vector3(0.05 * sin(i * 2.1), i * 1.7, 0.07 * cos(i * 1.3))
		_dress.add_child(palm)
		var h := 3.8 + 0.5 * sin(i * 3.3)
		_cy(palm, 0.11, 0.17, h, Vector3(0, h / 2.0, 0), trunk)
		for k in 8:
			var frond := Node3D.new()
			frond.position.y = h
			frond.rotation = Vector3(0.0, k * TAU / 8.0, 0.0)
			palm.add_child(frond)
			var blade := _bx(frond, Vector3(0.3, 0.03, 1.9), Vector3(0, -0.28, 0.9), leaf)
			blade.rotation.x = 0.42

## The player's «السطوع» on the camp as well.
func _apply_look() -> void:
	if env: env.tonemap_exposure = 1.1 * Gfx.brightness

## Which player stands under this point of the screen ("" if none): the menu uses it for a tap.
func pick(at: Vector2) -> String:
	var best := ""
	var bd := 85.0
	for n in cast:
		var r: Node3D = cast[n].rig
		if not is_instance_valid(r) or not r.visible: continue
		var p: Vector3 = r.global_position + Vector3(0, 1.0, 0)
		if cam.is_position_behind(p): continue
		var d: float = cam.unproject_position(p).distance_to(at)
		if d < bd:
			bd = d
			best = str(n)
	return best

func _place_stalker() -> void:
	var p: Vector3 = STALK[_stalk_i]
	var t: Vector3 = CAM_IDLE[0]
	stalker.position = p
	stalker.rotation.y = atan2(t.x - p.x, t.z - p.z) # she looks at whoever holds the phone
	stalk_rim.position = p + Vector3(-0.5, 1.9, 1.3) # in front of her, low and red: her face reads from the fire

## Nobody plays the killer here, so she is never quite where she was: gone for a few seconds,
## then back between other trees, and nearer the longer the menu stays open.
func _tick_stalker(dt: float) -> void:
	if stalker == null or not is_instance_valid(stalker): return
	var played := false
	for n in cast:
		if bool(cast[n].get("killer", false)): played = true
	if played: # a real player is the killer in this room: she stands where the room puts her
		stalker.visible = false
		stalk_rim.visible = false
		return
	_stalk_t -= dt
	if _stalk_t <= 0.0:
		if _stalk_seen:
			_stalk_seen = false
			_stalk_t = randf_range(2.0, 4.5)
		else:
			_stalk_seen = true
			_stalk_t = randf_range(5.0, 9.0)
			if randf() < 0.75: _stalk_i = mini(_stalk_i + 1, STALK.size() - 1)
			else: _stalk_i = randi() % STALK.size()
			_place_stalker()
	stalker.visible = _stalk_seen
	stalk_rim.visible = _stalk_seen

func _tick_air(dt: float, tt: float) -> void:
	if hook_arm: hook_arm.rotation = Vector3(0.05 * sin(tt * 0.7), 0.0, 0.12 * sin(tt * 1.1))
	if shade == null: return
	_shade_t -= dt
	if shade.visible:
		shade.position.x += _shade_dir * dt * 3.2
		shade.position.y = 1.02 + 0.04 * absf(sin(tt * 5.0))
		if absf(shade.position.x) > 16.0: shade.visible = false
	elif _shade_t <= 0.0:
		_shade_t = randf_range(16.0, 30.0)
		_shade_dir = 1.0 if randf() < 0.5 else -1.0
		shade.position.x = -15.5 * _shade_dir
		shade.visible = map_id in ["forest", "village"] # it needs trees to pass behind

func _process(dt: float) -> void:
	_tick_emotes(dt)
	_tick_stalker(dt)
	var tt := Time.get_ticks_msec() / 1000.0
	var flick := 0.78 + 0.14 * sin(tt * 13.0) * sin(tt * 4.3) + 0.08 * sin(tt * 27.0)
	fire.light_energy = 3.4 * flick * fire_mul
	fire.position = Vector3(0.05 * sin(tt * 9.0), 0.75 + 0.05 * sin(tt * 7.0), 0.05 * cos(tt * 11.0)) # shadows dance
	_tick_air(dt, tt)
	pivot.rotation.y = 0.1 * sin(tt * 0.13) * (1.0 - _focus)
	var want := 1.0 if focused else 0.0
	if absf(_focus - want) > 0.001: _focus = move_toward(_focus, want, dt * 1.6)
	var e: float = _focus * _focus * (3.0 - 2.0 * _focus) # smoothstep
	var cp: Vector3 = (CAM_IDLE[0] as Vector3).lerp(CAM_CHAR[0], e)
	var cr: Vector3 = (CAM_IDLE[1] as Vector3).lerp(CAM_CHAR[1], e)
	if intro < 1.0: # the opening shot: down from the moon onto the camp
		intro = minf(intro + dt / 2.8, 1.0)
		var up: float = 1.0 - intro
		up = up * up * (3.0 - 2.0 * up)
		cp += Vector3(0.6, 8.5, 3.5) * up
		cr.x += 0.66 * up
		cr.y -= 0.3 * up
	# the picture leans a little with the phone (against a slow average, so any grip is "level")
	var g := Input.get_gravity()
	if g.length() > 1.0:
		g = g.normalized()
		if _grav == Vector3.ZERO: _grav = g
		_grav = _grav.lerp(g, minf(dt * 0.35, 1.0))
		var lean := g - _grav
		_tilt = _tilt.lerp(Vector2(clampf(lean.y * 0.5, -0.05, 0.05), clampf(lean.z * 0.4, -0.035, 0.035)), minf(dt * 5.0, 1.0))
	cr.y += _tilt.x
	cr.x += _tilt.y
	cam.position = cp
	cam.rotation = cr
	key_light.light_energy = lerpf(0.9, 2.6, _focus) # all three come up as the camera moves in
	fill_light.light_energy = lerpf(0.25, 1.0, _focus)
	back_light.light_energy = lerpf(0.4, 2.8, _focus)
	if _slide > 0.0 and me_rig:
		_slide = maxf(_slide - dt * 3.4, 0.0)
		var k: float = 1.0 - _slide
		me_rig.position = _slide_from.lerp(STAND, k * k * (3.0 - 2.0 * k))
