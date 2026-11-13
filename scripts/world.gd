class_name NightWorld
extends Node3D
## Procedural night map: sky, terrain, forest, grass, abandoned buildings, particles.
## Everything is generated in code (no downloaded assets). Built in stages so the app stays responsive.

const SIZE := 200.0
const CELL := 2.0
const HALF := SIZE / 2.0
const TREE_CHUNK := 50.0
const GRASS_CHUNK := 20.0
const GRASS_PER_CHUNK := 700
const WALL := HALF - 8.0 # perimeter wall line; the exit gates are set into it

# each: x, z, yaw, width, depth, wall height
const FOREST_BUILDINGS := [
	[18.0, -16.0, 0.3, 7.0, 6.0, 3.0],
	[-26.0, 10.0, 1.2, 6.0, 5.0, 2.8],
	[30.0, 28.0, -0.6, 9.0, 7.0, 3.4],
	[-12.0, -40.0, 0.0, 6.0, 6.0, 2.8],
	[-44.0, -30.0, 2.0, 7.0, 5.0, 3.0],
	[46.0, -42.0, 0.9, 6.0, 5.0, 2.8],
	[2.0, 50.0, -1.3, 8.0, 6.0, 3.2],
]

var map_id := "forest"
var buildings: Array = []
var tree_count := 320
var tree_plan: Array = [] # [x, y, z, variant, scale, yaw]
var fog_density := 0.016
var gen_points: Array[Vector3] = []
var gate_points: Array = [] # [Vector3, yaw]
var hook_points: Array[Vector3] = []
var locker_points: Array = [] # [Vector3, yaw]
var pallet_points: Array = [] # [Vector3 door center, yaw]
var window_points: Array = [] # [Vector3 center, Vector3 outward normal]
var pallet_nodes: Array = []
var gen_nodes: Array = []
var gate_nodes: Array = []
var noise := FastNoiseLite.new()
var sites: Array = [] # [x, z, flat height, radius]
var moon_dir := Vector3(0.3, 0.32, -0.9).normalized()
var moon: DirectionalLight3D
var env: Environment
var follow: Node3D
var dust: GPUParticles3D
var leaves: GPUParticles3D
var flicker: Array[OmniLight3D] = []
var grass_nodes: Array[MultiMeshInstance3D] = []
var grass_counts: Array[int] = []
var ready_done := false
var tree_positions: Array[Vector3] = []
var _sky_noise: NoiseTexture2D
var _mat := {}

func configure(id: String) -> void:
	map_id = id
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	if id == "village":
		noise.seed = 4242
		tree_count = 170
		fog_density = 0.011
		moon_dir = Vector3(-0.45, 0.36, -0.8).normalized()
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for i in range(-2, 3):
			for j in range(-1, 2):
				if i == 0 and j == 0: continue
				buildings.append([i * 24.0 + rng.randf_range(-4, 4), j * 26.0 + rng.randf_range(-4, 4),
					rng.randf() * TAU, rng.randf_range(6.0, 9.0), rng.randf_range(5.0, 7.0), rng.randf_range(2.8, 3.4)])
	else:
		noise.seed = 1337
		buildings = FOREST_BUILDINGS.duplicate(true)
	sites.append([0.0, 0.0, _raw_h(0.0, 0.0), 6.0])
	for b in buildings:
		sites.append([b[0], b[1], _raw_h(b[0], b[1]), maxf(b[3], b[4]) * 0.75 + 1.0])
	# 7 generators, each beside the front door of a building
	var step := maxi(1, buildings.size() / 7)
	for gi in 7:
		var b: Array = buildings[(gi * step) % buildings.size()]
		var lx: float = -b[3] / 2.0 + 1.2
		var lz: float = b[4] / 2.0 + 1.5
		var gx: float = b[0] + lx * cos(b[2]) + lz * sin(b[2])
		var gz: float = b[1] - lx * sin(b[2]) + lz * cos(b[2])
		gen_points.append(Vector3(gx, _raw_h(b[0], b[1]) + 0.1, gz))
	# each of the first 8 buildings: a locker inside, a pallet at the door, a vault window on the left wall
	for bi in mini(buildings.size(), 8):
		var b: Array = buildings[bi]
		var base := Vector3(b[0], _raw_h(b[0], b[1]) + 0.1, b[1])
		var rot := Basis(Vector3.UP, b[2])
		locker_points.append([base + rot * Vector3(b[3] / 2.0 - 0.75, 0, -b[4] / 2.0 + 0.6), b[2]])
		pallet_points.append([base + rot * Vector3(0, 0, b[4] / 2.0), b[2]])
		window_points.append([base + rot * Vector3(-b[3] / 2.0, 0, 0), rot * Vector3(-1, 0, 0)])
	# 6 hooks on a ring between the buildings
	for hi in 6:
		var ang := hi * TAU / 6.0 + 0.5
		var hp := Vector2.from_angle(ang) * 38.0
		var tries := 0
		while in_site(hp.x, hp.y, 3.5) and tries < 20:
			tries += 1
			ang += 0.17
			hp = Vector2.from_angle(ang) * (38.0 + tries * 1.5)
		sites.append([hp.x, hp.y, _raw_h(hp.x, hp.y), 2.5])
		hook_points.append(Vector3(hp.x, _raw_h(hp.x, hp.y), hp.y))
	# 2 exit gates on opposite edges
	for g in [[0.0, -WALL, 0.0], [0.0, WALL, PI]]:
		sites.append([g[0], g[1], _raw_h(g[0], g[1]), 8.0])
		gate_points.append([Vector3(g[0], _raw_h(g[0], g[1]), g[1]), g[2]])
	_plan_trees()

func _plan_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var tries := 0
	while tree_plan.size() < tree_count and tries < 6000:
		tries += 1
		var x := rng.randf_range(-HALF + 4.0, HALF - 4.0)
		var z := rng.randf_range(-HALF + 4.0, HALF - 4.0)
		if in_site(x, z, 2.5): continue
		if absf(absf(x) - WALL) < 2.2 or absf(absf(z) - WALL) < 2.2: continue # keep the wall clear
		var edge := maxf(absf(x), absf(z)) / HALF
		if rng.randf() > lerpf(0.35, 1.0, edge): continue
		tree_plan.append([x, height(x, z), z, rng.randi() % 2, rng.randf_range(0.8, 1.25), rng.randf() * TAU])
		tree_positions.append(Vector3(x, height(x, z), z))

func near_tree(x: float, z: float, r: float) -> bool:
	for t in tree_positions:
		if Vector2(t.x - x, t.z - z).length() < r: return true
	return false

func spawn_point(role: String, slot: int) -> Vector3:
	var p := Vector2.ZERO
	if role == "killer":
		p = Vector2(-52.0, 52.0)
		var k := 0
		while (near_tree(p.x, p.y, 2.0) or in_site(p.x, p.y, 1.0)) and k < 40:
			k += 1
			p += Vector2(2.5, -1.5)
	else:
		p = Vector2.from_angle(slot * TAU / 7.0) * 3.0
	return Vector3(p.x, height(p.x, p.y) + 0.3, p.y)

func _raw_h(x: float, z: float) -> float:
	return noise.get_noise_2d(x, z) * 2.4 + noise.get_noise_2d(x * 3.0 + 50.0, z * 3.0) * 0.35

func height(x: float, z: float) -> float:
	var h := _raw_h(x, z)
	for s in sites:
		var d := Vector2(x - s[0], z - s[1]).length()
		if d < s[3] + 7.0:
			h = lerpf(s[2], h, smoothstep(s[3], s[3] + 7.0, d))
	return h

func in_site(x: float, z: float, pad := 0.0) -> bool:
	for s in sites:
		if Vector2(x - s[0], z - s[1]).length() < s[3] + pad: return true
	return false

func build() -> void:
	_make_materials()
	_build_environment()
	_build_terrain()
	await get_tree().process_frame
	_build_buildings()
	_build_objectives()
	await get_tree().process_frame
	_build_trees()
	await get_tree().process_frame
	_build_rocks()
	await _build_grass()
	_build_particles()
	_build_probe()
	Gfx.changed.connect(_apply_quality)
	_apply_quality()
	ready_done = true

# ---------------- materials (procedural PBR: albedo + normal + roughness) ----------------
func _noise_tex(freq: float, size: int, normal := false, ramp: Gradient = null) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	var nz := FastNoiseLite.new()
	nz.frequency = freq; nz.fractal_octaves = 5; nz.seed = 3
	t.noise = nz; t.width = size; t.height = size
	t.seamless = true; t.generate_mipmaps = true
	t.as_normal_map = normal; t.bump_strength = 6.0
	if ramp: t.color_ramp = ramp
	return t

func _grad(a: Color, b: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a); g.set_color(1, b)
	return g

func _pbr(c1: Color, c2: Color, freq: float, uv: Vector3, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex(freq, 512, false, _grad(c1, c2))
	m.normal_enabled = true
	m.normal_texture = _noise_tex(freq, 512, true)
	m.roughness = rough
	m.roughness_texture = _noise_tex(freq * 2.0, 256, false, _grad(Color(0.7, 0.7, 0.7), Color.WHITE))
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.metallic = metal
	m.uv1_triplanar = true; m.uv1_world_triplanar = true; m.uv1_scale = uv
	return m

func _make_materials() -> void:
	_sky_noise = _noise_tex(0.02, 512)
	_mat.ground = _pbr(Color(0.05, 0.065, 0.04), Color(0.15, 0.13, 0.085), 0.02, Vector3(0.12, 0.12, 0.12), 1.0)
	_mat.wood = _pbr(Color(0.07, 0.05, 0.035), Color(0.2, 0.15, 0.1), 0.03, Vector3(1.4, 0.12, 1.4), 0.85)
	_mat.metal = _pbr(Color(0.12, 0.06, 0.04), Color(0.3, 0.3, 0.32), 0.015, Vector3(0.5, 0.5, 0.5), 0.55, 0.8)
	_mat.concrete = _pbr(Color(0.2, 0.2, 0.19), Color(0.42, 0.42, 0.4), 0.03, Vector3(0.4, 0.4, 0.4), 0.9)
	_mat.bark = _pbr(Color(0.03, 0.022, 0.016), Color(0.11, 0.085, 0.06), 0.04, Vector3(2.0, 0.25, 2.0), 0.95)
	_mat.rock = _pbr(Color(0.07, 0.07, 0.075), Color(0.22, 0.22, 0.21), 0.02, Vector3(0.5, 0.5, 0.5), 0.9)
	var fol := ShaderMaterial.new()
	fol.shader = load("res://shaders/foliage.gdshader")
	fol.set_shader_parameter("noise_tex", _sky_noise)
	_mat.foliage = fol
	var gr := ShaderMaterial.new()
	gr.shader = load("res://shaders/grass.gdshader")
	_mat.grass = gr

# ---------------- environment ----------------
func _build_environment() -> void:
	env = Environment.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sm.set_shader_parameter("moon_dir", moon_dir)
	sm.set_shader_parameter("noise_tex", _sky_noise)
	var sky := Sky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.2, 0.32)
	env.ambient_light_energy = 1.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.09, 0.14)
	env.fog_density = fog_density
	env.fog_sky_affect = 0.25
	env.fog_sun_scatter = 0.15
	env.fog_height = 2.0
	env.fog_height_density = 0.12
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	moon = DirectionalLight3D.new()
	moon.basis = Basis.looking_at(-moon_dir)
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.light_energy = 1.1
	moon.shadow_enabled = true
	moon.directional_shadow_blend_splits = true
	add_child(moon)

# ---------------- terrain ----------------
func _build_terrain() -> void:
	var n := int(SIZE / CELL)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in n + 1:
		for i in n + 1:
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			verts.append(Vector3(x, height(x, z), z))
			norms.append(Vector3(height(x - 1.0, z) - height(x + 1.0, z), 2.0, height(x, z - 1.0) - height(x, z + 1.0)).normalized())
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			idx.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, _mat.ground)
	var body := StaticBody3D.new()
	body.name = "Terrain"
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	for k in 4: # invisible map border
		var w := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(SIZE, 30.0, 2.0)
		w.shape = bs
		w.rotation.y = k * PI / 2.0
		w.position = Vector3(0, 5.0, HALF - 1.0).rotated(Vector3.UP, k * PI / 2.0)
		body.add_child(w)
	add_child(body)

# ---------------- buildings ----------------
func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, occlude := false, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos; mi.rotation = rot
	parent.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos; cs.rotation = rot
	parent.add_child(cs)
	if occlude:
		var oc := OccluderInstance3D.new()
		var bo := BoxOccluder3D.new()
		bo.size = size * 0.96
		oc.occluder = bo
		oc.position = pos; oc.rotation = rot
		parent.add_child(oc)

func _build_buildings() -> void:
	var idx := 0
	for b in buildings:
		var w: float = b[3]; var d: float = b[4]; var hgt: float = b[5]
		var t := 0.2
		var body := StaticBody3D.new()
		body.name = "Building%d" % idx
		body.position = Vector3(b[0], _raw_h(b[0], b[1]), b[1])
		body.rotation.y = b[2]
		_box(body, Vector3(w + 0.6, 1.2, d + 0.6), Vector3(0, -0.5, 0), _mat.concrete)
		var y0 := 0.1
		_box(body, Vector3(w, hgt, t), Vector3(0, y0 + hgt / 2.0, -d / 2.0), _mat.wood, true) # back
		_box(body, Vector3(t, hgt, d), Vector3(w / 2.0, y0 + hgt / 2.0, 0), _mat.wood, true) # right
		# left wall with a window gap
		var seg := (d - 1.4) / 2.0
		_box(body, Vector3(t, hgt, seg), Vector3(-w / 2.0, y0 + hgt / 2.0, -d / 2.0 + seg / 2.0), _mat.wood)
		_box(body, Vector3(t, hgt, seg), Vector3(-w / 2.0, y0 + hgt / 2.0, d / 2.0 - seg / 2.0), _mat.wood)
		_box(body, Vector3(t, 1.0, 1.4), Vector3(-w / 2.0, y0 + 0.5, 0), _mat.wood)
		_box(body, Vector3(t, hgt - 2.1, 1.4), Vector3(-w / 2.0, y0 + 2.1 + (hgt - 2.1) / 2.0, 0), _mat.wood)
		# front wall with a door gap
		var fw := (w - 1.3) / 2.0
		_box(body, Vector3(fw, hgt, t), Vector3(-w / 2.0 + fw / 2.0, y0 + hgt / 2.0, d / 2.0), _mat.wood)
		_box(body, Vector3(fw, hgt, t), Vector3(w / 2.0 - fw / 2.0, y0 + hgt / 2.0, d / 2.0), _mat.wood)
		_box(body, Vector3(1.3, hgt - 2.2, t), Vector3(0, y0 + 2.2 + (hgt - 2.2) / 2.0, d / 2.0), _mat.wood)
		# leaning sheet-metal roof
		_box(body, Vector3(w + 1.0, 0.1, d + 1.0), Vector3(0, y0 + hgt + 0.3, 0), _mat.metal, false, Vector3(0, 0, 0.1))
		if idx % 3 == 0: # a weak flickering lamp inside some buildings (no shadows)
			var l := OmniLight3D.new()
			l.position = Vector3(0, y0 + hgt - 0.5, 0)
			l.light_color = Color(1.0, 0.62, 0.3)
			l.light_energy = 1.6
			l.omni_range = 7.0
			body.add_child(l)
			flicker.append(l)
		add_child(body)
		idx += 1

# ---------------- objectives: generators + exit gates ----------------
func _emissive(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.05, 0.05)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.0
	return m

func _mesh_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos; mi.rotation = rot
	parent.add_child(mi)
	return mi

func _build_props() -> void:
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.32, 0.07, 0.06)
	red.roughness = 0.6; red.metallic = 0.5
	for hp in hook_points:
		var body := StaticBody3D.new()
		body.position = hp
		_box(body, Vector3(0.28, 3.4, 0.28), Vector3(0, 1.7, 0), _mat.wood)
		_mesh_box(body, Vector3(0.2, 0.2, 1.1), Vector3(0, 3.2, 0.45), _mat.wood)
		_mesh_box(body, Vector3(0.08, 0.5, 0.08), Vector3(0, 2.85, 0.9), _mat.metal)
		_mesh_box(body, Vector3(0.08, 0.08, 0.3), Vector3(0, 2.6, 0.78), _mat.metal)
		var l := OmniLight3D.new()
		l.position = Vector3(0, 3.0, 0.9)
		l.light_color = Color(1.0, 0.2, 0.15)
		l.light_energy = 0.8; l.omni_range = 5.0
		body.add_child(l)
		add_child(body)
	for lp in locker_points:
		var body := StaticBody3D.new()
		body.position = lp[0]
		body.rotation.y = lp[1]
		_box(body, Vector3(1.0, 2.1, 0.7), Vector3(0, 1.05, 0), red)
		_mesh_box(body, Vector3(0.04, 1.9, 0.04), Vector3(0, 1.05, 0.36), _mat.metal)
		add_child(body)
	for pp in pallet_points:
		var root := Node3D.new()
		root.position = pp[0]
		root.rotation.y = pp[1]
		var up := Node3D.new()
		_mesh_box(up, Vector3(1.2, 1.5, 0.14), Vector3(1.35, 0.8, -0.3), _mat.wood, Vector3(0.12, 0, 0))
		root.add_child(up)
		var down := StaticBody3D.new()
		_box(down, Vector3(1.3, 0.14, 1.3), Vector3(0, 0.85, 0), _mat.wood)
		_box(down, Vector3(1.3, 0.8, 0.14), Vector3(0, 0.42, 0), _mat.wood)
		down.visible = false
		for ch in down.get_children():
			if ch is CollisionShape3D: ch.disabled = true
		root.add_child(down)
		add_child(root)
		pallet_nodes.append({"up": up, "down": down, "state": 0})

func set_pallet_state(i: int, state: int) -> void: # 0 standing, 1 dropped, 2 broken
	if i >= pallet_nodes.size(): return
	var p: Dictionary = pallet_nodes[i]
	if p.state == state: return
	p.state = state
	p.up.visible = state == 0
	p.down.visible = state == 1
	for ch in p.down.get_children():
		if ch is CollisionShape3D: ch.set_deferred("disabled", state != 1)

func _build_objectives() -> void:
	_build_props()
	for gp in gen_points:
		var body := StaticBody3D.new()
		body.position = gp
		_box(body, Vector3(1.5, 0.9, 0.8), Vector3(0, 0.55, 0), _mat.metal)
		_box(body, Vector3(0.7, 0.45, 0.6), Vector3(-0.3, 1.2, 0), _mat.concrete)
		_box(body, Vector3(0.08, 1.6, 0.08), Vector3(0.6, 1.8, 0.3), _mat.metal)
		_box(body, Vector3(0.08, 1.6, 0.08), Vector3(0.6, 1.8, -0.3), _mat.metal)
		var lamp_mat := _emissive(Color(1.0, 0.85, 0.5))
		for z in [0.3, -0.3]:
			var bulb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.14; sm.height = 0.28
			sm.material = lamp_mat
			bulb.mesh = sm
			bulb.position = Vector3(0.6, 2.65, z)
			body.add_child(bulb)
		var light := OmniLight3D.new()
		light.position = Vector3(0.6, 2.8, 0)
		light.light_color = Color(1.0, 0.85, 0.5)
		light.light_energy = 0.0
		light.omni_range = 11.0
		body.add_child(light)
		add_child(body)
		gen_nodes.append({"light": light, "mat": lamp_mat, "done": false})
	# perimeter wall: tall, runs the whole edge of the map, so the only way out is through a gate
	var top := 9.0
	var bottom := -7.0
	var wall_h := top - bottom
	var wall_y := (top + bottom) / 2.0
	var sides := StaticBody3D.new()
	sides.name = "PerimeterWall"
	for sx in [-1.0, 1.0]:
		_box(sides, Vector3(1.4, wall_h, WALL * 2.0 + 1.4), Vector3(sx * WALL, wall_y, 0), _mat.concrete, true)
	add_child(sides)
	var open_w := 7.0 # gate opening width
	var open_h := 6.0
	for g in gate_points:
		var gy: float = g[0].y
		var body := StaticBody3D.new()
		body.position = Vector3(g[0].x, 0, g[0].z)
		body.rotation.y = g[1]
		var seg := WALL - open_w / 2.0
		for sx in [-1.0, 1.0]:
			_box(body, Vector3(seg, wall_h, 1.4), Vector3(sx * (open_w / 2.0 + seg / 2.0), wall_y, 0), _mat.concrete, true)
			_box(body, Vector3(1.8, top + 1.5 - bottom, 2.0), Vector3(sx * (open_w / 2.0 + 0.9), (top + 1.5 + bottom) / 2.0, 0), _mat.concrete) # gate towers
		_box(body, Vector3(open_w, top - (gy + open_h), 1.4), Vector3(0, (top + gy + open_h) / 2.0, 0), _mat.concrete)
		var doors := []
		for sx in [-1.0, 1.0]:
			var door := StaticBody3D.new()
			door.position = Vector3(sx * open_w / 4.0, gy, 0)
			_box(door, Vector3(open_w / 2.0, open_h, 0.35), Vector3(0, open_h / 2.0, 0), _mat.metal)
			_box(door, Vector3(open_w / 2.0 - 0.3, 0.25, 0.5), Vector3(0, open_h * 0.33, 0), _mat.wood)
			_box(door, Vector3(open_w / 2.0 - 0.3, 0.25, 0.5), Vector3(0, open_h * 0.7, 0), _mat.wood)
			body.add_child(door)
			doors.append(door)
		var sign_mat := _emissive(Color(1.0, 0.15, 0.1))
		sign_mat.emission_energy_multiplier = 2.0
		var sign := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(open_w - 1.0, 0.5, 0.2)
		bm.material = sign_mat
		sign.mesh = bm
		sign.position = Vector3(0, gy + open_h + 0.7, 0.8)
		body.add_child(sign)
		var light := OmniLight3D.new()
		light.position = Vector3(0, gy + open_h - 0.5, 3.0)
		light.light_color = Color(1.0, 0.15, 0.1)
		light.light_energy = 2.0
		light.omni_range = 16.0
		body.add_child(light)
		for sx in [-1.0, 1.0]: # lamps on the towers so the wall and gate read clearly at night
			var tl := OmniLight3D.new()
			tl.position = Vector3(sx * (open_w / 2.0 + 0.9), gy + 5.0, 2.6)
			tl.light_color = Color(1.0, 0.8, 0.55)
			tl.light_energy = 2.2
			tl.omni_range = 15.0
			body.add_child(tl)
		add_child(body)
		gate_nodes.append({"doors": doors, "light": light, "mat": sign_mat, "state": 0, "open_w": open_w})

## True when a position is past an open gate (outside the wall).
func is_outside_gate(i: int, pos: Vector3) -> bool:
	var gp: Vector3 = gate_points[i][0]
	var outward := Vector3(gp.x, 0, gp.z).normalized()
	var rel := pos - gp
	var out_d := rel.dot(outward)
	var lateral := absf(rel.dot(outward.cross(Vector3.UP)))
	return out_d > 1.6 and lateral < 3.4

func set_gen_done(i: int) -> void:
	if i >= gen_nodes.size(): return
	var g: Dictionary = gen_nodes[i]
	if g.done: return
	g.done = true
	g.light.light_energy = 2.2
	g.mat.emission_energy_multiplier = 4.0

func set_gate_state(i: int, open: bool) -> void:
	if i >= gate_nodes.size(): return
	var g: Dictionary = gate_nodes[i]
	var state := 2 if open else 0
	if g.state == state: return
	g.state = state
	var c: Color = Color(0.3, 1.0, 0.4) if open else Color(1.0, 0.15, 0.1)
	g.light.light_color = c
	g.light.light_energy = 3.0 if open else 2.0
	g.mat.emission = c
	if open: # the two door leaves slide apart into the wall
		var k := 0
		for door in g.doors:
			for ch in door.get_children():
				if ch is CollisionShape3D: ch.set_deferred("disabled", true)
			var sx := -1.0 if k == 0 else 1.0
			var tw := create_tween()
			tw.tween_property(door, "position:x", sx * (g.open_w * 0.75 + 0.2), 3.0).set_trans(Tween.TRANS_SINE)
			k += 1

# ---------------- trees (MultiMesh + 2 LOD levels per chunk) ----------------
func _tree_mesh(variant: int, hi: bool) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + variant
	var hgt := rng.randf_range(8.0, 12.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.06; trunk.bottom_radius = 0.28; trunk.height = hgt
	trunk.radial_segments = 10 if hi else 5
	trunk.rings = 2 if hi else 1
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, hgt / 2.0 - 0.4, 0)))
	var mesh := st.commit()
	mesh.surface_set_material(0, _mat.bark)
	var sf := SurfaceTool.new()
	sf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var layers := 7 if hi else 4
	for i in layers:
		var f := float(i) / float(layers - 1)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = lerpf(2.6, 0.7, f) * rng.randf_range(0.85, 1.1)
		cone.height = lerpf(3.2, 1.8, f)
		cone.radial_segments = 9 if hi else 6
		cone.rings = 1
		cone.cap_bottom = false
		var bs := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.06, 0.06))
		sf.append_from(cone, 0, Transform3D(bs, Vector3(0, lerpf(hgt * 0.32, hgt - 0.6, f), 0)))
	sf.commit(mesh)
	mesh.surface_set_material(1, _mat.foliage)
	return mesh

func _build_trees() -> void:
	var meshes := []
	for v in 2: meshes.append([_tree_mesh(v, true), _tree_mesh(v, false)])
	var buckets := {} # "cx_cz_variant" -> Array[Transform3D]
	var body := StaticBody3D.new()
	body.name = "TreeTrunks"
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.42; trunk_shape.height = 6.0
	for t in tree_plan:
		var x: float = t[0]; var y: float = t[1]; var z: float = t[2]
		var cx := int(floor((x + HALF) / TREE_CHUNK))
		var cz := int(floor((z + HALF) / TREE_CHUNK))
		var key := "%d_%d_%d" % [cx, cz, t[3]]
		if not buckets.has(key): buckets[key] = []
		var center := Vector3((cx + 0.5) * TREE_CHUNK - HALF, 0, (cz + 0.5) * TREE_CHUNK - HALF)
		var sc: float = t[4]
		var bs := Basis(Vector3.UP, t[5]).scaled(Vector3(sc, sc, sc))
		buckets[key].append(Transform3D(bs, Vector3(x, y, z) - center))
		var cs := CollisionShape3D.new()
		cs.shape = trunk_shape
		cs.position = Vector3(x, y + 2.0, z)
		body.add_child(cs)
	add_child(body)
	for key in buckets:
		var parts: PackedStringArray = key.split("_")
		var center := Vector3((int(parts[0]) + 0.5) * TREE_CHUNK - HALF, 0, (int(parts[1]) + 0.5) * TREE_CHUNK - HALF)
		var list: Array = buckets[key]
		for lod in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[int(parts[2])][lod]
			mm.instance_count = list.size()
			for i in list.size(): mm.set_instance_transform(i, list[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.position = center
			if lod == 0: mmi.visibility_range_end = 70.0
			else:
				mmi.visibility_range_begin = 70.0
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)

func _build_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var sm := SphereMesh.new()
	sm.radius = 0.5; sm.height = 0.8; sm.radial_segments = 10; sm.rings = 5
	sm.material = _mat.rock
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sm
	mm.instance_count = 70
	for i in 70:
		var x := rng.randf_range(-HALF + 6.0, HALF - 6.0)
		var z := rng.randf_range(-HALF + 6.0, HALF - 6.0)
		var bs := Basis.from_euler(Vector3(rng.randf() * 0.5, rng.randf() * TAU, rng.randf() * 0.5)).scaled(
			Vector3(rng.randf_range(0.5, 1.8), rng.randf_range(0.4, 1.0), rng.randf_range(0.5, 1.6)))
		mm.set_instance_transform(i, Transform3D(bs, Vector3(x, height(x, z) + 0.05, z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)

# ---------------- grass (MultiMesh chunks, wind in shader) ----------------
func _grass_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for b in 5:
		var bs := Basis(Vector3.UP, rng.randf() * TAU)
		var off := Vector3(rng.randf_range(-0.22, 0.22), 0, rng.randf_range(-0.22, 0.22))
		var h := rng.randf_range(0.4, 0.75)
		var lean := rng.randf_range(0.0, 0.18)
		var p := [Vector3(-0.03, 0, 0), Vector3(0.03, 0, 0), Vector3(-0.022, h * 0.5, lean * 0.4),
			Vector3(0.022, h * 0.5, lean * 0.4), Vector3(0, h, lean)]
		var uvy := [0.0, 0.0, 0.5, 0.5, 1.0]
		for k in [0, 1, 2, 1, 3, 2, 2, 3, 4]:
			st.set_uv(Vector2(0.5, uvy[k]))
			st.add_vertex(bs * p[k] + off)
	var m := st.commit()
	m.surface_set_material(0, _mat.grass)
	return m

func _build_grass() -> void:
	var mesh := _grass_mesh()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var n := int(SIZE / GRASS_CHUNK)
	for cz in n:
		for cx in n:
			var center := Vector3((cx + 0.5) * GRASS_CHUNK - HALF, 0, (cz + 0.5) * GRASS_CHUNK - HALF)
			center.y = height(center.x, center.z)
			var list: Array[Transform3D] = []
			for i in GRASS_PER_CHUNK:
				var x := center.x + rng.randf_range(-GRASS_CHUNK / 2.0, GRASS_CHUNK / 2.0)
				var z := center.z + rng.randf_range(-GRASS_CHUNK / 2.0, GRASS_CHUNK / 2.0)
				if in_site(x, z, -1.0): continue
				var sc := rng.randf_range(0.8, 1.5)
				var bs := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc))
				list.append(Transform3D(bs, Vector3(x, height(x, z), z) - center))
			if list.is_empty(): continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = list.size()
			for i in list.size(): mm.set_instance_transform(i, list[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.position = center
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			grass_nodes.append(mmi)
			grass_counts.append(list.size())
		await get_tree().process_frame

# ---------------- particles ----------------
func _build_particles() -> void:
	dust = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(12, 3, 12)
	pm.gravity = Vector3(0.15, -0.03, 0.05)
	pm.initial_velocity_min = 0.05; pm.initial_velocity_max = 0.2
	pm.spread = 180.0
	dust.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.02)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.8, 0.85, 1.0, 0.14)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = dm
	dust.draw_pass_1 = q
	dust.lifetime = 8.0; dust.preprocess = 8.0
	dust.visibility_aabb = AABB(Vector3(-20, -8, -20), Vector3(40, 16, 40))
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dust)
	leaves = GPUParticles3D.new()
	var lp := ParticleProcessMaterial.new()
	lp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	lp.emission_box_extents = Vector3(14, 0.5, 14)
	lp.gravity = Vector3(0.7, -1.1, 0.25)
	lp.initial_velocity_min = 0.2; lp.initial_velocity_max = 0.8
	lp.spread = 180.0
	lp.angle_min = 0.0; lp.angle_max = 360.0
	lp.angular_velocity_min = -160.0; lp.angular_velocity_max = 160.0
	lp.scale_min = 0.7; lp.scale_max = 1.3
	leaves.process_material = lp
	var lq := QuadMesh.new()
	lq.size = Vector2(0.12, 0.07)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.2, 0.11, 0.04)
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	lm.roughness = 0.9
	lm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	lq.material = lm
	leaves.draw_pass_1 = lq
	leaves.lifetime = 7.0; leaves.preprocess = 7.0
	leaves.visibility_aabb = AABB(Vector3(-22, -12, -22), Vector3(44, 20, 44))
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(leaves)

func _build_probe() -> void:
	var p := ReflectionProbe.new()
	p.size = Vector3(SIZE, 40.0, SIZE)
	p.position = Vector3(0, 8.0, 0)
	p.update_mode = ReflectionProbe.UPDATE_ONCE
	p.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	p.max_distance = 120.0
	add_child(p)

# ---------------- quality ----------------
func _apply_quality() -> void:
	var fx := Gfx.eff_effects()
	var sh := Gfx.eff_shadows()
	env.glow_enabled = fx >= 1
	if dust:
		var da: int = [40, 90, 160][fx]
		if dust.amount != da: dust.amount = da
		var la: int = [12, 25, 45][fx]
		if leaves.amount != la: leaves.amount = la
	var factor: float = [0.4, 0.7, 1.0][fx]
	var rng: float = [22.0, 30.0, 38.0][fx]
	for i in grass_nodes.size():
		grass_nodes[i].multimesh.visible_instance_count = int(grass_counts[i] * factor)
		grass_nodes[i].visibility_range_end = rng + GRASS_CHUNK * 0.7
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if sh == 0 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = [30.0, 50.0, 70.0][sh]

func _process(_dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in flicker.size():
		flicker[i].light_energy = 1.6 * (0.75 + 0.25 * noise.get_noise_1d(t * 220.0 + i * 50.0) + 0.1 * sin(t * 13.0 + i))
	if follow and dust:
		dust.global_position = follow.global_position + Vector3(0, 2.0, 0)
		leaves.global_position = follow.global_position + Vector3(0, 7.0, 0)
