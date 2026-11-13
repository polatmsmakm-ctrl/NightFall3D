class_name NightWorld
extends Node3D
## Procedural night map: sky, terrain, forest, grass, abandoned buildings, particles.
## Everything is generated in code (no downloaded assets). Built in stages so the app stays responsive.

const SIZE := 240.0
const CELL := 2.0
const HALF := SIZE / 2.0
const TREE_CHUNK := 50.0
const GRASS_CHUNK := 20.0
const GRASS_PER_CHUNK := 700
const WALL := HALF - 8.0 # perimeter wall line; the exit gates are set into it
const ROAD_LEN := 60.0 # the escape road behind each gate; you are out when you reach its end

# each: x, z, yaw, width, depth, wall height
const FOREST_BUILDINGS := [
	[18.0, -16.0, 0.3, 7.0, 6.0, 3.0],
	[-26.0, 10.0, 1.2, 6.0, 5.0, 2.8],
	[30.0, 28.0, -0.6, 9.0, 7.0, 3.4],
	[-12.0, -40.0, 0.0, 6.0, 6.0, 2.8],
	[-44.0, -30.0, 2.0, 7.0, 5.0, 3.0],
	[46.0, -42.0, 0.9, 6.0, 5.0, 2.8],
	[2.0, 50.0, -1.3, 8.0, 6.0, 3.2],
	[-74.0, 60.0, 0.7, 7.0, 6.0, 3.0],
	[-70.0, -78.0, 2.6, 8.0, 6.0, 3.2],
	[66.0, 76.0, -0.4, 6.0, 5.0, 2.8],
	[72.0, -74.0, 1.1, 7.0, 6.0, 3.0],
]

var map_id := "forest"
var buildings: Array = []
var tree_count := 450
var tree_plan: Array = [] # [x, y, z, variant, scale, yaw]
var fog_density := 0.016
var gen_points: Array[Vector3] = []
var gate_points: Array = [] # [Vector3, yaw]
var hook_points: Array[Vector3] = []
var locker_points: Array = [] # [Vector3, yaw]
var pallet_points: Array = [] # [Vector3 door center, yaw]
var window_points: Array = [] # [Vector3 center, Vector3 outward normal]
var pallet_nodes: Array = []
var market := {} # {pos, yaw, w, d}: the strip mall (restaurant, supermarket, laundry)
const DIWAN := Vector2(26.0, -66.0) # which fareej house is «ديوان راشد الشمري»
const MARKET_W := 27.0
const MARKET_D := 10.0
var door_points: Array = [] # [Vector3, yaw] every doorway
var hatch_points: Array[Vector3] = []
var hatch_nodes: Array = []
var relief := 1.0 # terrain height multiplier (0 = flat)
var grass_per_chunk := GRASS_PER_CHUNK
var market_lights: Array = []
var market_dark := false
var market_t := 0.0
var gen_nodes: Array = []
var gate_nodes: Array = []
var noise := FastNoiseLite.new()
var sites: Array = [] # [x, z, flat height, radius]
var moon_dir := Vector3(0.3, 0.32, -0.9).normalized()
var moon: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _blood := false
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

func _local(b: Array, v: Vector3) -> Vector3: # building-local point -> world
	return Vector3(b[0], _raw_h(b[0], b[1]) + 0.1, b[1]) + Basis(Vector3.UP, b[2]) * v

func _shuffled(n: int, rng: RandomNumberGenerator) -> Array:
	var idx := range(n)
	for i in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = idx[i]; idx[i] = idx[j]; idx[j] = tmp
	return idx

## Streets and other strips that must stay clear (only the fareej map has them).
func on_street(x: float, z: float, pad := 0.0) -> bool:
	if map_id != "fareej": return false
	return absf(absf(z) - 47.0) < 4.0 + pad or absf(z) < 4.5 + pad or (absf(x + 13.0) < 4.0 + pad and absf(z) < 47.0)

func _random_site(rng: RandomNumberGenerator, pad: float, lo: float, hi: float) -> Vector2:
	for k in 200:
		var p := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(lo, hi)
		if absf(p.x) > WALL - 8.0 or absf(p.y) > WALL - 8.0: continue
		if not in_site(p.x, p.y, pad) and not on_street(p.x, p.y, 1.0): return p
	return Vector2(lo, lo)

## `seed` shuffles where the generators, hooks, pallets, hatches are, so every round plays differently.
## Everyone in a room gets the same seed from the server, so they all build the same layout.
func configure(id: String, seed := 1) -> void:
	map_id = id
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	if id == "village":
		noise.seed = 4242
		tree_count = 250
		fog_density = 0.011
		moon_dir = Vector3(-0.45, 0.36, -0.8).normalized()
		var lay := RandomNumberGenerator.new()
		lay.seed = 11
		for i in range(-2, 3):
			for j in range(-1, 2):
				if (i == 0 and j == 0) or (i == 2 and j == 0): continue # centre spawn, and the market's plot
				buildings.append([i * 28.0 + lay.randf_range(-4, 4), j * 31.0 + lay.randf_range(-4, 4),
					lay.randf() * TAU, lay.randf_range(6.0, 9.0), lay.randf_range(5.0, 7.0), lay.randf_range(2.8, 3.4)])
	elif id == "fareej": # a Kuwaiti neighbourhood: walled houses on streets around the market, flat sandy ground
		noise.seed = 77
		relief = 0.0
		tree_count = 90
		grass_per_chunk = 60
		fog_density = 0.009
		moon_dir = Vector3(0.5, 0.4, 0.76).normalized()
		for hx in [-78.0, -52.0, -26.0, 0.0, 26.0]:
			buildings.append([hx, -66.0, 0.0, 10.0, 8.0, 3.4])
			buildings.append([hx, 66.0, PI, 10.0, 8.0, 3.4])
		for hx in [-78.0, -52.0, -34.0]:
			buildings.append([hx, -27.0, PI, 10.0, 8.0, 3.4])
			buildings.append([hx, 27.0, 0.0, 10.0, 8.0, 3.4])
		sites.append([16.0, 27.0, 0.0, 9.5]) # the mosque
		sites.append([9.0, -11.0, 0.0, 3.0]) # the flag
	else:
		noise.seed = 1337
		buildings = FOREST_BUILDINGS.duplicate(true)
	sites.append([0.0, 0.0, _raw_h(0.0, 0.0), 6.0])
	for b in buildings:
		sites.append([b[0], b[1], _raw_h(b[0], b[1]), maxf(b[3], b[4]) * (1.05 if id == "fareej" else 0.75) + 1.0])
	# the market: a big flat plot on the east side, shop fronts facing the middle of the map
	var mh := _raw_h(56.0, 2.0)
	sites.append([56.0, 2.0, mh, 21.0])
	market = {"pos": Vector3(62.0, mh, 2.0), "yaw": -PI / 2.0, "w": MARKET_W, "d": MARKET_D}
	var mrot := Basis(Vector3.UP, market.yaw)
	var mbase: Vector3 = market.pos + Vector3(0, 0.15, 0)
	# 7 generators out of all the possible spots (beside a front door, or on the market's parking)
	var gen_spots: Array[Vector3] = []
	for b in buildings: gen_spots.append(_local(b, Vector3(-b[3] / 2.0 + 1.2, 0, b[4] / 2.0 + 1.5)))
	gen_spots.append(mbase + mrot * Vector3(-11.5, -0.05, MARKET_D / 2.0 + 4.6))
	gen_spots.append(mbase + mrot * Vector3(11.5, -0.05, MARKET_D / 2.0 + 4.6))
	var order := _shuffled(gen_spots.size(), rng)
	for k in 7: gen_points.append(gen_spots[order[k]])
	# doorways, and 9 pallets out of them
	for b in buildings: door_points.append([_local(b, Vector3(0, 0, b[4] / 2.0)), b[2]])
	door_points.append([mbase + mrot * Vector3(0, 0, -MARKET_D / 2.0), market.yaw])
	order = _shuffled(door_points.size(), rng)
	for k in mini(9, door_points.size()): pallet_points.append(door_points[order[k]])
	# lockers and vault windows: the first 8 buildings, plus the market
	for bi in mini(buildings.size(), 8):
		var b: Array = buildings[bi]
		locker_points.append([_local(b, Vector3(b[3] / 2.0 - 0.75, 0, -b[4] / 2.0 + 0.6)), b[2]])
		window_points.append([_local(b, Vector3(-b[3] / 2.0, 0, 0)), Basis(Vector3.UP, b[2]) * Vector3(-1, 0, 0)])
	locker_points.append([mbase + mrot * Vector3(12.6, 0, -4.3), market.yaw])
	locker_points.append([mbase + mrot * Vector3(-12.6, 0, -4.3), market.yaw])
	window_points.append([mbase + mrot * Vector3(-MARKET_W / 2.0, 0, 1.0), mrot * Vector3(-1, 0, 0)])
	# 2 exit gates on opposite edges
	for g in [[0.0, -WALL, 0.0], [0.0, WALL, PI]]:
		sites.append([g[0], g[1], _raw_h(g[0], g[1]), 8.0])
		gate_points.append([Vector3(g[0], _raw_h(g[0], g[1]), g[1]), g[2]])
	# 9 hooks and 5 possible hatches: anywhere free
	for hi in 9:
		var hp := _random_site(rng, 3.5, 22.0, 100.0)
		sites.append([hp.x, hp.y, _raw_h(hp.x, hp.y), 2.5])
		hook_points.append(Vector3(hp.x, _raw_h(hp.x, hp.y), hp.y))
	for hi in 5:
		var hp := _random_site(rng, 3.0, 30.0, 100.0)
		sites.append([hp.x, hp.y, _raw_h(hp.x, hp.y), 2.2])
		hatch_points.append(Vector3(hp.x, _raw_h(hp.x, hp.y), hp.y))
	_plan_trees()

func _plan_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var tries := 0
	while tree_plan.size() < tree_count and tries < 9000:
		tries += 1
		var x := rng.randf_range(-HALF + 4.0, HALF - 4.0)
		var z := rng.randf_range(-HALF + 4.0, HALF - 4.0)
		if in_site(x, z, 2.5): continue
		if absf(absf(x) - WALL) < 2.2 or absf(absf(z) - WALL) < 2.2: continue # keep the wall clear
		if on_street(x, z, 1.5): continue
		var edge := maxf(absf(x), absf(z)) / HALF
		if rng.randf() > lerpf(0.35, 1.0, edge): continue
		tree_plan.append([x, height(x, z), z, rng.randi() % 2, rng.randf_range(0.8, 1.25), rng.randf() * TAU])
		tree_positions.append(Vector3(x, height(x, z), z))

## What the ground is at a position: "indoor" (floors, pavement), "sand" (the bare yards around buildings) or "grass".
func surface_at(pos: Vector3) -> String:
	var ml: Vector3 = Basis(Vector3.UP, market.yaw).inverse() * (pos - market.pos)
	if absf(ml.x) < MARKET_W / 2.0 + 2.0 and ml.z > -MARKET_D / 2.0 - 0.3 and ml.z < MARKET_D / 2.0 + 16.0: return "indoor"
	for b in buildings:
		var bl: Vector3 = Basis(Vector3.UP, b[2]).inverse() * (pos - Vector3(b[0], pos.y, b[1]))
		if absf(bl.x) < b[3] / 2.0 + 0.3 and absf(bl.z) < b[4] / 2.0 + 0.3: return "indoor"
	if on_street(pos.x, pos.z): return "indoor" # asphalt
	return "sand" if (map_id == "fareej" or in_site(pos.x, pos.z, 0.0)) else "grass"

func _sandiness(x: float, z: float) -> float:
	if map_id == "fareej": return 1.0
	var v := 0.0
	for st in sites:
		var d := Vector2(x - st[0], z - st[1]).length()
		v = maxf(v, 1.0 - smoothstep(st[3] - 1.5, st[3] + 3.0, d))
	return v

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
	return (noise.get_noise_2d(x, z) * 2.4 + noise.get_noise_2d(x * 3.0 + 50.0, z * 3.0) * 0.35) * relief

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
	if map_id == "fareej": _build_fareej()
	else: _build_buildings()
	_build_objectives()
	_build_extras()
	_build_market()
	await get_tree().process_frame
	_build_scatter()
	_build_trees()
	await get_tree().process_frame
	_build_rocks()
	await _build_grass()
	_build_particles()
	_build_probe()
	for l in find_children("*", "OmniLight3D", true, false): # far lights cost nothing
		l.distance_fade_enabled = true
		l.distance_fade_begin = 45.0
		l.distance_fade_length = 12.0
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
	_mat.ground = _pbr(Color(0.12, 0.12, 0.11), Color(0.34, 0.32, 0.28), 0.02, Vector3(0.12, 0.12, 0.12), 1.0)
	_mat.ground.vertex_color_use_as_albedo = true # grass green / sand yellow painted per vertex
	_mat.wood = _pbr(Color(0.07, 0.05, 0.035), Color(0.2, 0.15, 0.1), 0.03, Vector3(1.4, 0.12, 1.4), 0.85)
	_mat.metal = _pbr(Color(0.12, 0.06, 0.04), Color(0.3, 0.3, 0.32), 0.015, Vector3(0.5, 0.5, 0.5), 0.55, 0.8)
	_mat.concrete = _pbr(Color(0.2, 0.2, 0.19), Color(0.42, 0.42, 0.4), 0.03, Vector3(0.4, 0.4, 0.4), 0.9)
	_mat.bark = _pbr(Color(0.03, 0.022, 0.016), Color(0.11, 0.085, 0.06), 0.04, Vector3(2.0, 0.25, 2.0), 0.95)
	_mat.rock = _pbr(Color(0.07, 0.07, 0.075), Color(0.22, 0.22, 0.21), 0.02, Vector3(0.5, 0.5, 0.5), 0.9)
	var fol := ShaderMaterial.new()
	fol.shader = load("res://shaders/foliage.gdshader")
	fol.set_shader_parameter("noise_tex", _sky_noise)
	_mat.foliage = fol
	var pm := ShaderMaterial.new()
	pm.shader = load("res://shaders/palm.gdshader")
	pm.set_shader_parameter("noise_tex", _sky_noise)
	_mat.palm = pm
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
	_sky_mat = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.2, 0.32)
	env.ambient_light_energy = 0.8 # dark: survivors carry flashlights
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
	var grid := PackedFloat32Array()
	grid.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			grid[j * (n + 1) + i] = height(-HALF + i * CELL, -HALF + j * CELL)
	var hgt := func(i: int, j: int) -> float: return grid[clampi(j, 0, n) * (n + 1) + clampi(i, 0, n)]
	var body := StaticBody3D.new()
	body.name = "Terrain"
	var faces := PackedVector3Array()
	var per := 20 # cells per chunk side
	for cj in range(0, n, per):
		for ci in range(0, n, per):
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var cols := PackedColorArray()
			var idx := PackedInt32Array()
			for j in per + 1:
				for i in per + 1:
					var gi := ci + i
					var gj := cj + j
					verts.append(Vector3(-HALF + gi * CELL, hgt.call(gi, gj), -HALF + gj * CELL))
					cols.append(Color(0.42, 0.56, 0.34).lerp(Color(1.0, 0.86, 0.6), _sandiness(-HALF + gi * CELL, -HALF + gj * CELL)))
					norms.append(Vector3(hgt.call(gi - 1, gj) - hgt.call(gi + 1, gj), 2.0 * CELL, hgt.call(gi, gj - 1) - hgt.call(gi, gj + 1)).normalized())
			for j in per:
				for i in per:
					var a := j * (per + 1) + i
					var b := a + 1
					var c := a + per + 1
					var d := c + 1
					idx.append_array(PackedInt32Array([a, b, c, b, d, c]))
					for k in [a, b, c, b, d, c]: faces.append(verts[k])
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = norms
			arr[Mesh.ARRAY_COLOR] = cols
			arr[Mesh.ARRAY_INDEX] = idx
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			mesh.surface_set_material(0, _mat.ground)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)
	for k in 4: # invisible map border; the two gate sides leave an opening for the escape road
		for part in ([-1.0, 1.0] if k % 2 == 0 else [0.0]):
			var w := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			var length := SIZE if part == 0.0 else HALF - 5.0
			bs.size = Vector3(length, 30.0, 2.0)
			w.shape = bs
			w.rotation.y = k * PI / 2.0
			w.position = Vector3(part * (5.0 + length / 2.0), 5.0, HALF - 1.0).rotated(Vector3.UP, k * PI / 2.0)
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
	var dark := _flat(Color(0.05, 0.05, 0.05), 0.6, 0.4)
	for lp in locker_points:
		var body := StaticBody3D.new()
		body.position = lp[0]
		body.rotation.y = lp[1]
		_box(body, Vector3(1.1, 2.1, 0.75), Vector3(0, 1.05, 0), red)
		for dx in [-0.27, 0.27]: # two door leaves with vents and handles
			_mesh_box(body, Vector3(0.5, 1.95, 0.04), Vector3(dx, 1.05, 0.385), _flat(Color(0.4, 0.09, 0.07), 0.55, 0.5))
			for vy in [0.45, 0.55, 0.65, 1.6, 1.7, 1.8]:
				_mesh_box(body, Vector3(0.3, 0.035, 0.02), Vector3(dx, vy, 0.41), dark)
			_mesh_box(body, Vector3(0.04, 0.22, 0.05), Vector3(dx * 0.26, 1.1, 0.42), _mat.metal)
		_mesh_box(body, Vector3(1.3, 0.06, 0.95), Vector3(0, 2.2, 0.0), _mat.metal, Vector3(0.12, 0, 0)) # tin roof
		add_child(body)
	for pp in pallet_points:
		var root := Node3D.new()
		root.position = pp[0]
		root.rotation.y = pp[1]
		var up := Node3D.new()
		for k in 5:
			_mesh_box(up, Vector3(0.2, 1.5, 0.05), Vector3(0.87 + k * 0.24, 0.8, -0.26), _mat.wood, Vector3(0.12, 0, 0))
		for ky in [0.25, 0.8, 1.35]:
			_mesh_box(up, Vector3(1.2, 0.12, 0.06), Vector3(1.35, ky, -0.33 + (ky - 0.8) * 0.12), _mat.wood, Vector3(0.12, 0, 0))
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
		_box(body, Vector3(1.7, 0.2, 1.0), Vector3(0, 0.12, 0), _mat.concrete) # base
		_box(body, Vector3(1.45, 0.75, 0.8), Vector3(0, 0.6, 0), _mat.metal) # engine block
		_mesh_box(body, Vector3(1.2, 0.22, 0.6), Vector3(-0.05, 1.08, 0), _flat(Color(0.5, 0.08, 0.06), 0.5, 0.5)) # red valve cover
		for k in 4: # pistons
			var pc := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.09; cyl.bottom_radius = 0.11; cyl.height = 0.42; cyl.radial_segments = 10
			cyl.material = _mat.metal
			pc.mesh = cyl
			pc.rotation.x = 0.5
			pc.position = Vector3(-0.5 + k * 0.3, 1.32, 0.12)
			body.add_child(pc)
		for wx in [-0.55, 0.55]: # wheels
			var wh := MeshInstance3D.new()
			var wc := CylinderMesh.new()
			wc.top_radius = 0.26; wc.bottom_radius = 0.26; wc.height = 0.16
			wc.material = _flat(Color(0.03, 0.03, 0.03))
			wh.mesh = wc
			wh.rotation.x = PI / 2.0
			wh.position = Vector3(wx, 0.36, 0.5)
			body.add_child(wh)
		_mesh_box(body, Vector3(0.5, 0.16, 0.12), Vector3(0.3, 0.75, 0.43), _flat(Color(0.2, 0.9, 0.3), 0.4, 0.0, 1.5)) # fuel gauge
		_box(body, Vector3(0.14, 3.0, 0.14), Vector3(-0.72, 1.5, -0.25), _mat.metal) # cable pole
		_mesh_box(body, Vector3(0.05, 1.3, 0.05), Vector3(-0.5, 1.75, -0.1), _flat(Color(0.5, 0.4, 0.1)), Vector3(0.2, 0, -0.35))
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
		light.light_energy = 0.7 # dim work light; goes bright when the generator is done
		light.omni_range = 11.0
		body.add_child(light)
		add_child(body)
		gen_nodes.append({"light": light, "mat": lamp_mat, "done": false, "blink": false})
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
		# the escape road: a long walled lane behind the gate (local -z is "out")
		var road_mat := _flat(Color(0.07, 0.065, 0.06), 0.8)
		var lane_w := 9.0
		var z_mid := -(8.0 + ROAD_LEN) / 2.0
		_box(body, Vector3(lane_w, 1.0, ROAD_LEN + 8.0), Vector3(0, gy - 0.48, z_mid - 0.5), road_mat)
		for sx in [-1.0, 1.0]:
			_box(body, Vector3(0.6, 9.0, ROAD_LEN + 2.0), Vector3(sx * (lane_w / 2.0 + 0.3), gy + 3.5, -(ROAD_LEN + 2.0) / 2.0 - 0.7), _mat.concrete)
		_box(body, Vector3(lane_w + 1.2, 9.0, 0.6), Vector3(0, gy + 3.5, -ROAD_LEN - 4.0), _mat.concrete) # dead end behind the finish
		for i in int(ROAD_LEN / 12.0): # lamps down the lane, alternating sides, dimmer the further you go
			var lz := -8.0 - i * 12.0
			var sx := -1.0 if i % 2 == 0 else 1.0
			_mesh_box(body, Vector3(0.12, 4.0, 0.12), Vector3(sx * (lane_w / 2.0 - 0.3), gy + 2.0, lz), _mat.metal)
			_mesh_box(body, Vector3(0.3, 0.12, 0.3), Vector3(sx * (lane_w / 2.0 - 0.5), gy + 4.0, lz), _flat(Color(1.0, 0.85, 0.55), 0.5, 0.0, 3.0))
			var ll := OmniLight3D.new()
			ll.position = Vector3(sx * (lane_w / 2.0 - 0.9), gy + 3.6, lz)
			ll.light_color = Color(1.0, 0.82, 0.55)
			ll.light_energy = 1.6
			ll.omni_range = 9.0
			body.add_child(ll)
			flicker.append(ll)
		for i in 9: # dashed centre line
			_mesh_box(body, Vector3(0.16, 0.02, 2.4), Vector3(0, gy + 0.03, -5.0 - i * 6.5), _flat(Color(0.7, 0.65, 0.3)))
		# the finish: a bright arch you run into
		var finish := _flat(Color(0.8, 1.0, 0.85), 0.5, 0.0, 4.0)
		_mesh_box(body, Vector3(lane_w, 0.5, 0.3), Vector3(0, gy + 4.6, -ROAD_LEN), finish)
		for sx in [-1.0, 1.0]: _mesh_box(body, Vector3(0.4, 4.8, 0.3), Vector3(sx * (lane_w / 2.0 - 0.2), gy + 2.4, -ROAD_LEN), finish)
		_sign_text(body, "الخروج", Vector3(0, gy + 5.6, -ROAD_LEN + 0.1), 110, Color(0.6, 1.0, 0.7))
		var fl := OmniLight3D.new()
		fl.position = Vector3(0, gy + 3.0, -ROAD_LEN + 1.5)
		fl.light_color = Color(0.7, 1.0, 0.8)
		fl.light_energy = 5.0
		fl.omni_range = 18.0
		body.add_child(fl)

## True when a position has reached the end of a gate's escape road.
func is_outside_gate(i: int, pos: Vector3) -> bool:
	var gp: Vector3 = gate_points[i][0]
	var outward := Vector3(gp.x, 0, gp.z).normalized()
	var rel := pos - gp
	var out_d := rel.dot(outward)
	var lateral := absf(rel.dot(outward.cross(Vector3.UP)))
	return out_d > ROAD_LEN - 1.5 and lateral < 5.5

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
			tw.tween_property(door, "position:x", sx * (g.open_w * 0.75 + 0.2), 4.6).set_trans(Tween.TRANS_SINE)
			k += 1

# ---------------- the market (strip mall) ----------------
func _flat(c: Color, rough := 0.8, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough; m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m

func _sign_text(parent: Node3D, text: String, pos: Vector3, size: int, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Net.font
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = col
	l.outline_size = 0
	l.position = pos
	parent.add_child(l)

func _wall_with_gap(parent: Node3D, along_x: bool, fixed: float, from: float, to: float, gap_a: float, gap_b: float, y0: float, h: float, gap_low: float, gap_high: float, mat: Material, thick := 0.3) -> void:
	# a wall from `from` to `to` with an opening between gap_a..gap_b, from height gap_low up to gap_high
	var parts := [[from, gap_a, y0, h], [gap_b, to, y0, h], [gap_a, gap_b, y0 + gap_high, h - gap_high]]
	if gap_low > 0.0: parts.append([gap_a, gap_b, y0, gap_low])
	for pt in parts:
		var length: float = pt[1] - pt[0]
		if length <= 0.01 or pt[3] <= 0.01: continue
		var mid: float = (pt[0] + pt[1]) / 2.0
		var size := Vector3(length, pt[3], thick) if along_x else Vector3(thick, pt[3], length)
		var pos := Vector3(mid, pt[2] + pt[3] / 2.0, fixed) if along_x else Vector3(fixed, pt[2] + pt[3] / 2.0, mid)
		_box(parent, size, pos, mat, length > 3.0 and pt[3] > 3.0)

func _build_market() -> void:
	var W := MARKET_W
	var D := MARKET_D
	var H := 4.5
	var y0 := 0.15
	var body := StaticBody3D.new()
	body.name = "Market"
	body.position = market.pos
	body.rotation.y = market.yaw
	var beige := _flat(Color(0.62, 0.56, 0.47))
	var white := _flat(Color(0.8, 0.8, 0.78))
	var tile := _flat(Color(0.55, 0.55, 0.52), 0.35)
	var asphalt := _flat(Color(0.045, 0.045, 0.05), 0.3)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.6, 0.8, 0.95, 0.16)
	glass.roughness = 0.05
	var frame := _flat(Color(0.1, 0.12, 0.2), 0.4, 0.6)
	# ground: floor slab, sidewalk, parking with lines, striped curb
	_box(body, Vector3(W + 0.6, 0.3, D + 0.6), Vector3(0, 0, 0), tile)
	_box(body, Vector3(W + 2.0, 0.24, 3.0), Vector3(0, -0.02, D / 2.0 + 1.5), tile)
	_box(body, Vector3(W + 4.0, 0.12, 13.0), Vector3(0, -0.02, D / 2.0 + 9.5), asphalt)
	for i in 14:
		_mesh_box(body, Vector3((W + 2.0) / 14.0, 0.26, 0.3), Vector3(-(W + 2.0) / 2.0 + (i + 0.5) * (W + 2.0) / 14.0, 0.0, D / 2.0 + 3.1),
			_flat(Color(0.95, 0.75, 0.05) if i % 2 == 0 else Color(0.05, 0.05, 0.05)))
	for i in 7:
		_mesh_box(body, Vector3(0.14, 0.02, 5.0), Vector3(-W / 2.0 + 1.5 + i * (W - 3.0) / 6.0, 0.05, D / 2.0 + 6.5), white)
	# shell
	_wall_with_gap(body, true, -D / 2.0, -W / 2.0, W / 2.0, -0.7, 0.7, y0, H, 0.0, 2.2, beige) # back wall, door behind the supermarket
	_wall_with_gap(body, false, -W / 2.0, -D / 2.0, D / 2.0, 0.3, 1.7, y0, H, 1.0, 2.1, beige) # restaurant side: vault window
	_box(body, Vector3(0.3, H, D), Vector3(W / 2.0, y0 + H / 2.0, 0), beige, true)
	for px in [-W / 6.0, W / 6.0]: # partitions, each with a doorway near the back
		_wall_with_gap(body, false, px, -D / 2.0, D / 2.0, -3.6, -2.2, y0, H, 0.0, 2.2, white, 0.25)
	_box(body, Vector3(W + 1.0, 0.3, D + 1.0), Vector3(0, y0 + H + 0.15, 0), beige)
	_mesh_box(body, Vector3(W + 1.4, 0.5, 0.7), Vector3(0, y0 + H + 0.45, D / 2.0 + 0.2), beige)
	for cx in [-W / 2.0, -W / 6.0, W / 6.0, W / 2.0]:
		_box(body, Vector3(0.7, H, 0.7), Vector3(cx, y0 + H / 2.0, D / 2.0), beige)
	# shop fronts: glass with a 2 m doorway, sign board above
	var signs := [
		{"col": Color(0.03, 0.03, 0.03), "lines": [["ساس", 0.25, 92, Color(1, 0.95, 0.8)], ["مطعم", -0.45, 40, Color(1, 0.95, 0.8)]]},
		{"col": Color(0.85, 0.03, 0.08), "lines": [["فرع غرب عبدالله مبارك", 0.42, 44, Color.WHITE], ["قطعة 4", -0.02, 44, Color.WHITE]]},
		{"col": Color(0.02, 0.1, 0.65), "lines": [["مصبغة غرب عبدالله مبارك", 0.0, 46, Color.WHITE]]},
	]
	for k in 3:
		var cx := -W / 3.0 + k * W / 3.0
		var shop_w := W / 3.0 - 0.7
		var side := (shop_w - 2.0) / 2.0
		for sx in [-1.0, 1.0]:
			_box(body, Vector3(side, 2.7, 0.08), Vector3(cx + sx * (1.0 + side / 2.0), y0 + 1.35, D / 2.0), glass)
		_mesh_box(body, Vector3(shop_w, 0.16, 0.16), Vector3(cx, y0 + 2.78, D / 2.0), frame)
		for fx in [-1.0, 1.0]: _mesh_box(body, Vector3(0.1, 2.7, 0.12), Vector3(cx + fx, y0 + 1.35, D / 2.0), frame)
		_box(body, Vector3(shop_w, H - 2.86, 0.2), Vector3(cx, y0 + 2.86 + (H - 2.86) / 2.0, D / 2.0), beige)
		var sg: Dictionary = signs[k]
		_mesh_box(body, Vector3(shop_w - 0.2, 1.5, 0.25), Vector3(cx, y0 + 3.6, D / 2.0 + 0.35), _flat(sg.col, 0.5, 0.0, 0.5))
		for ln in sg.lines:
			_sign_text(body, ln[0], Vector3(cx, y0 + 3.6 + ln[1], D / 2.0 + 0.49), ln[2], ln[3])
		if k == 1: # supermarket: white strip under the red board
			_mesh_box(body, Vector3(shop_w - 0.2, 0.42, 0.27), Vector3(cx, y0 + 3.06, D / 2.0 + 0.35), _flat(Color(0.95, 0.95, 0.95), 0.5, 0.0, 0.6))
			_sign_text(body, "سوبر ماركت", Vector3(cx, y0 + 3.06, D / 2.0 + 0.5), 30, Color(0.85, 0.03, 0.08))
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(cx, y0 + 3.7, 0.5)
		lamp.light_color = [Color(1.0, 0.72, 0.4), Color(1.0, 0.98, 0.92), Color(0.75, 0.88, 1.0)][k]
		lamp.light_energy = 1.5
		lamp.omni_range = 10.0
		body.add_child(lamp)
		market_lights.append([lamp, 1.5])
		var glow := OmniLight3D.new() # light the signs spill on the sidewalk and parking
		glow.position = Vector3(cx, y0 + 3.0, D / 2.0 + 2.5)
		glow.light_color = [Color(1.0, 0.8, 0.5), Color(1.0, 0.25, 0.2), Color(0.3, 0.45, 1.0)][k]
		glow.light_energy = 2.6
		glow.omni_range = 11.0
		body.add_child(glow)
		market_lights.append([glow, 2.6])
	_mesh_box(body, Vector3(W / 3.0 - 0.9, 0.08, 1.7), Vector3(-W / 3.0, y0 + 2.75, D / 2.0 + 1.0), _flat(Color(0.75, 0.2, 0.1)), Vector3(0.22, 0, 0)) # awning
	# restaurant: tables, chairs, counter
	var wood := _flat(Color(0.35, 0.2, 0.1), 0.6)
	for t in [Vector2(-11.2, 2.4), Vector2(-8.2, 2.6), Vector2(-11.0, -0.4), Vector2(-7.8, -0.2)]:
		_box(body, Vector3(1.0, 0.8, 1.0), Vector3(t.x, y0 + 0.4, t.y), wood)
		for c in [Vector2(-0.85, 0), Vector2(0.85, 0)]:
			_mesh_box(body, Vector3(0.42, 0.45, 0.42), Vector3(t.x + c.x, y0 + 0.23, t.y + c.y), _flat(Color(0.5, 0.25, 0.12)))
			_mesh_box(body, Vector3(0.08, 0.5, 0.42), Vector3(t.x + c.x * 1.24, y0 + 0.7, t.y + c.y), _flat(Color(0.5, 0.25, 0.12)))
	_box(body, Vector3(5.0, 1.1, 0.7), Vector3(-9.6, y0 + 0.55, -3.6), wood)
	# supermarket: three shelf rows with products, checkout
	var product_cols := [Color(0.85, 0.15, 0.1), Color(0.1, 0.45, 0.85), Color(0.95, 0.75, 0.1), Color(0.15, 0.65, 0.25), Color(0.9, 0.45, 0.1)]
	for sx in [-2.7, 0.0, 2.7]:
		_box(body, Vector3(0.7, 1.9, 5.2), Vector3(sx, y0 + 0.95, -0.9), _flat(Color(0.82, 0.82, 0.8), 0.5))
		for lv in 3:
			for seg in 4:
				var pc: Color = product_cols[(lv * 4 + seg + int(sx * 3.0 + 9.0)) % product_cols.size()]
				_mesh_box(body, Vector3(0.78, 0.38, 1.15), Vector3(sx, y0 + 0.45 + lv * 0.6, -2.85 + seg * 1.3), _flat(pc, 0.6, 0.0, 0.15))
	_box(body, Vector3(1.8, 1.0, 0.8), Vector3(-2.6, y0 + 0.5, 3.4), _flat(Color(0.25, 0.27, 0.32), 0.5))
	# laundry: washing machines, clothes rail, counter
	for i in 4:
		var mx := 6.0 + i * 1.05
		_box(body, Vector3(0.9, 1.05, 0.8), Vector3(mx, y0 + 0.53, -4.3), _flat(Color(0.85, 0.87, 0.9), 0.4))
		var port := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.26; cyl.bottom_radius = 0.26; cyl.height = 0.06
		cyl.material = _flat(Color(0.1, 0.15, 0.22), 0.1, 0.5)
		port.mesh = cyl
		port.rotation.x = PI / 2.0
		port.position = Vector3(mx, y0 + 0.6, -3.88)
		body.add_child(port)
	_mesh_box(body, Vector3(3.2, 0.06, 0.06), Vector3(6.6, y0 + 1.9, 1.5), frame)
	var cloth_cols := [Color(0.8, 0.8, 0.85), Color(0.2, 0.3, 0.6), Color(0.6, 0.15, 0.15), Color(0.15, 0.4, 0.3), Color(0.85, 0.75, 0.5), Color(0.3, 0.3, 0.3)]
	for i in 6:
		_mesh_box(body, Vector3(0.42, 0.95, 0.08), Vector3(5.3 + i * 0.5, y0 + 1.4, 1.5), _flat(cloth_cols[i]), Vector3(0, 0.25, 0))
	_box(body, Vector3(2.4, 1.0, 0.7), Vector3(10.8, y0 + 0.5, 2.6), _flat(Color(0.2, 0.3, 0.55), 0.5))
	add_child(body)

# ---------------- scattered props: wrecks, barrels, crates, fences, street lamps, dumpsters ----------------
func _free_spot(rng: RandomNumberGenerator, pad: float) -> Vector3:
	for k in 60:
		var x := rng.randf_range(-WALL + 8.0, WALL - 8.0)
		var z := rng.randf_range(-WALL + 8.0, WALL - 8.0)
		if in_site(x, z, pad) or near_tree(x, z, pad + 1.0) or on_street(x, z, pad): continue
		return Vector3(x, height(x, z), z)
	return Vector3.INF

func _car(at: Vector3, yaw: float, col: Color, parent: Node3D = null) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.rotation.y = yaw
	var paint := _flat(col, 0.45, 0.5)
	_box(body, Vector3(1.8, 0.7, 4.2), Vector3(0, 0.7, 0), paint)
	_box(body, Vector3(1.6, 0.62, 2.1), Vector3(0, 1.35, -0.2), _flat(col.darkened(0.35), 0.3, 0.6))
	var tire := _flat(Color(0.03, 0.03, 0.03))
	for wx in [-0.9, 0.9]:
		for wz in [-1.35, 1.35]:
			var wh := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.36; cyl.bottom_radius = 0.36; cyl.height = 0.24
			cyl.material = tire
			wh.mesh = cyl
			wh.rotation.z = PI / 2.0
			wh.position = Vector3(wx, 0.36, wz)
			body.add_child(wh)
	(parent if parent else self).add_child(body)

func _lamp_post(at: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.rotation.y = yaw
	_box(body, Vector3(0.16, 4.6, 0.16), Vector3(0, 2.3, 0), _mat.metal)
	_mesh_box(body, Vector3(0.1, 0.1, 1.2), Vector3(0, 4.5, 0.55), _mat.metal)
	_mesh_box(body, Vector3(0.3, 0.1, 0.5), Vector3(0, 4.42, 1.0), _flat(Color(1.0, 0.85, 0.55), 0.5, 0.0, 3.0))
	var l := OmniLight3D.new()
	l.position = Vector3(0, 4.1, 1.0)
	l.light_color = Color(1.0, 0.82, 0.55)
	l.light_energy = 2.6
	l.omni_range = 13.0
	body.add_child(l)
	add_child(body)

func _build_scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404 if map_id == "forest" else 505
	var car_cols := [Color(0.3, 0.1, 0.08), Color(0.12, 0.16, 0.22), Color(0.35, 0.33, 0.28), Color(0.1, 0.2, 0.14), Color(0.4, 0.4, 0.42)]
	# parked cars and lamps at the market
	var mrot := Basis(Vector3.UP, market.yaw)
	for c in [[-9.0, 11.0, 0.05, 1], [3.5, 11.5, -0.04, 4], [10.5, 14.5, 1.4, 0]]:
		_car(market.pos + mrot * Vector3(c[0], 0.05, c[1]), market.yaw + c[2], car_cols[c[3]])
	for lx in [-12.0, 12.0]:
		_lamp_post(market.pos + mrot * Vector3(lx, 0, MARKET_D / 2.0 + 15.5), market.yaw + PI)
	# wrecked cars
	for i in 5:
		var p := _free_spot(rng, 3.5)
		if p == Vector3.INF: continue
		_car(p, rng.randf() * TAU, car_cols[i % car_cols.size()].darkened(0.3))
	# street lamps
	for i in 5:
		var p := _free_spot(rng, 1.5)
		if p != Vector3.INF: _lamp_post(p, rng.randf() * TAU)
	# barrels (three of them burning), crates, dumpsters, fence runs
	var rust := _flat(Color(0.3, 0.14, 0.08), 0.7, 0.5)
	for i in 16:
		var p := _free_spot(rng, 1.2)
		if p == Vector3.INF: continue
		var body := StaticBody3D.new()
		body.position = p
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.32; cyl.bottom_radius = 0.32; cyl.height = 0.95; cyl.radial_segments = 12
		cyl.material = rust
		mi.mesh = cyl
		mi.position.y = 0.47
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.34; sh.height = 0.95
		cs.shape = sh
		cs.position.y = 0.47
		body.add_child(cs)
		if i < 3:
			_mesh_box(body, Vector3(0.4, 0.06, 0.4), Vector3(0, 0.95, 0), _flat(Color(1.0, 0.45, 0.1), 0.5, 0.0, 5.0))
			var l := OmniLight3D.new()
			l.position = Vector3(0, 1.4, 0)
			l.light_color = Color(1.0, 0.5, 0.2)
			l.light_energy = 1.6
			l.omni_range = 8.0
			body.add_child(l)
			flicker.append(l)
		add_child(body)
	for i in 10:
		var p := _free_spot(rng, 1.8)
		if p == Vector3.INF: continue
		var body := StaticBody3D.new()
		body.position = p
		body.rotation.y = rng.randf() * TAU
		_box(body, Vector3(0.95, 0.95, 0.95), Vector3(0, 0.47, 0), _mat.wood)
		if rng.randf() < 0.6: _box(body, Vector3(0.95, 0.95, 0.95), Vector3(1.05, 0.47, 0.1), _mat.wood)
		if rng.randf() < 0.5: _box(body, Vector3(0.9, 0.9, 0.9), Vector3(0.4, 1.4, 0.0), _mat.wood, false, Vector3(0, 0.4, 0))
		add_child(body)
	var green := _flat(Color(0.08, 0.2, 0.12), 0.6, 0.4)
	for i in 4:
		var p := _free_spot(rng, 2.2)
		if p == Vector3.INF: continue
		var body := StaticBody3D.new()
		body.position = p
		body.rotation.y = rng.randf() * TAU
		_box(body, Vector3(2.0, 1.3, 1.1), Vector3(0, 0.65, 0), green)
		_mesh_box(body, Vector3(2.05, 0.08, 1.15), Vector3(0, 1.34, 0), _flat(Color(0.05, 0.05, 0.05)))
		add_child(body)
	for i in 8:
		var p := _free_spot(rng, 5.0)
		if p == Vector3.INF: continue
		var body := StaticBody3D.new()
		body.position = p
		body.rotation.y = rng.randf() * TAU
		for sgm in rng.randi_range(2, 4):
			var ox := sgm * 3.0
			_box(body, Vector3(3.0, 1.25, 0.14), Vector3(ox, 0.6, 0), _mat.wood)
			_mesh_box(body, Vector3(0.18, 1.5, 0.2), Vector3(ox - 1.5, 0.75, 0), _mat.wood)
		add_child(body)

# ---------------- hatch, market blackout ----------------
func _build_extras() -> void:
	for hp in hatch_points: # all hidden until the rules open one
		var root := Node3D.new()
		root.position = hp
		_mesh_box(root, Vector3(1.9, 0.12, 1.9), Vector3(0, 0.06, 0), _mat.metal)
		_mesh_box(root, Vector3(1.5, 0.05, 1.5), Vector3(0, 0.13, 0), _flat(Color(0.01, 0.01, 0.01)))
		_mesh_box(root, Vector3(1.6, 0.1, 1.6), Vector3(0, 0.9, -0.85), _mat.metal, Vector3(1.25, 0, 0)) # lid standing open
		var l := OmniLight3D.new()
		l.position = Vector3(0, 0.8, 0)
		l.light_color = Color(0.5, 1.0, 0.7)
		l.light_energy = 2.0
		l.omni_range = 7.0
		root.add_child(l)
		root.visible = false
		add_child(root)
		hatch_nodes.append(root)

func set_hatch(i: int) -> void:
	for k in hatch_nodes.size(): hatch_nodes[k].visible = k == i

func in_market(pos: Vector3) -> bool:
	var ml: Vector3 = Basis(Vector3.UP, market.yaw).inverse() * (pos - market.pos)
	return absf(ml.x) < MARKET_W / 2.0 and absf(ml.z) < MARKET_D / 2.0

## The market's lights die when the killer walks in, and come back a moment after he leaves.
# the moon (disc, glow, moonlight, fog) fades to blood red once the gates are powered
func set_blood_moon(on: bool) -> void:
	if on == _blood or _sky_mat == null: return
	_blood = on
	var tw := create_tween().set_parallel(true)
	var d := 4.0
	tw.tween_method(func(v: float): _sky_mat.set_shader_parameter("blood", v), 0.0 if on else 1.0, 1.0 if on else 0.0, d)
	tw.tween_property(moon, "light_color", Color(1.0, 0.42, 0.36) if on else Color(0.55, 0.65, 0.95), d)
	tw.tween_property(env, "ambient_light_color", Color(0.26, 0.15, 0.17) if on else Color(0.16, 0.2, 0.32), d)
	tw.tween_property(env, "fog_light_color", Color(0.14, 0.05, 0.05) if on else Color(0.07, 0.09, 0.14), d)

func set_market_dark(dark: bool) -> void:
	if dark == market_dark: return
	market_dark = dark
	market_t = 1.2 # flicker for a moment before settling

# ---------------- the fareej: walled Kuwaiti houses, streets, a small mosque ----------------
func _build_fareej() -> void:
	var plaster := [_flat(Color(0.72, 0.66, 0.54)), _flat(Color(0.78, 0.74, 0.66)), _flat(Color(0.64, 0.56, 0.46)), _flat(Color(0.7, 0.7, 0.68))]
	var dark_glass := _flat(Color(0.03, 0.05, 0.08), 0.1, 0.6)
	var door_wood := _flat(Color(0.25, 0.14, 0.07), 0.6)
	var idx := 0
	for b in buildings:
		var w: float = b[3]; var d: float = b[4]; var H: float = b[5]
		var mat: StandardMaterial3D = plaster[idx % plaster.size()]
		var diwan: bool = absf(b[0] - DIWAN.x) < 0.1 and absf(b[1] - DIWAN.y) < 0.1 # the owner's lit-up diwaniya
		if diwan: mat = _flat(Color(0.7, 0.62, 0.5), 0.9)
		var y0 := 0.1
		var body := StaticBody3D.new()
		body.name = "Diwan" if diwan else "House%d" % idx
		body.position = Vector3(b[0], _raw_h(b[0], b[1]), b[1])
		body.rotation.y = b[2]
		_box(body, Vector3(w + 0.4, 0.3, d + 0.4), Vector3(0, -0.05, 0), _mat.concrete)
		_box(body, Vector3(w, H, 0.25), Vector3(0, y0 + H / 2.0, -d / 2.0), mat, true)
		_box(body, Vector3(0.25, H, d), Vector3(w / 2.0, y0 + H / 2.0, 0), mat, true)
		_wall_with_gap(body, false, -w / 2.0, -d / 2.0, d / 2.0, -0.7, 0.7, y0, H, 1.0, 2.1, mat, 0.25) # vault window
		_wall_with_gap(body, true, d / 2.0, -w / 2.0, w / 2.0, -0.65, 0.65, y0, H, 0.0, 2.2, mat, 0.25) # front door
		_wall_with_gap(body, false, 1.6, -d / 2.0, d / 2.0, 0.4, 1.7, y0, H, 0.0, 2.2, mat, 0.2) # inner wall with a doorway
		_mesh_box(body, Vector3(1.5, 0.12, 0.3), Vector3(0, y0 + 2.26, d / 2.0), door_wood)
		_box(body, Vector3(w + 0.5, 0.25, d + 0.5), Vector3(0, y0 + H + 0.12, 0), mat)
		for side in [[0.0, d / 2.0 + 0.15, w + 0.5, 0.2], [0.0, -d / 2.0 - 0.15, w + 0.5, 0.2], [w / 2.0 + 0.15, 0.0, 0.2, d + 0.5], [-w / 2.0 - 0.15, 0.0, 0.2, d + 0.5]]:
			_mesh_box(body, Vector3(side[2], 0.6, side[3]), Vector3(side[0], y0 + H + 0.5, side[1]), mat) # roof parapet
		# upper floor block (not enterable), windows, water tank, AC unit
		_mesh_box(body, Vector3(w * 0.55, 2.7, d * 0.7), Vector3(-w * 0.2, y0 + H + 1.6, -d * 0.1), mat)
		_mesh_box(body, Vector3(w * 0.6, 0.2, d * 0.75), Vector3(-w * 0.2, y0 + H + 3.05, -d * 0.1), mat)
		for wx in [-w * 0.34, -w * 0.06]:
			if not diwan: _mesh_box(body, Vector3(1.0, 1.1, 0.08), Vector3(wx, y0 + H + 1.7, -d * 0.1 + d * 0.35), dark_glass)
		var tank := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.6; cyl.bottom_radius = 0.6; cyl.height = 1.3; cyl.radial_segments = 12
		cyl.material = _flat(Color(0.85, 0.85, 0.82), 0.5)
		tank.mesh = cyl
		tank.position = Vector3(w * 0.3, y0 + H + 0.9, -d * 0.25)
		body.add_child(tank)
		if not diwan: _mesh_box(body, Vector3(0.9, 0.6, 0.5), Vector3(w * 0.3, y0 + H + 0.55, d * 0.2), _flat(Color(0.6, 0.6, 0.6), 0.5, 0.4))
		# compound wall with a gate opening in front
		var cw := w / 2.0 + 3.0
		var cd := d / 2.0 + 3.0
		_box(body, Vector3(cw * 2.0, 2.2, 0.2), Vector3(0, 1.1, -cd), mat, true)
		_box(body, Vector3(0.2, 2.2, cd * 2.0), Vector3(cw, 1.1, 0), mat, true)
		_box(body, Vector3(0.2, 2.2, cd * 2.0), Vector3(-cw, 1.1, 0), mat, true)
		_wall_with_gap(body, true, cd, -cw, cw, -1.4, 1.4, 0.0, 2.2, 0.0, 2.2, mat, 0.2)
		for gx in [-1.55, 1.55]: _mesh_box(body, Vector3(0.35, 2.6, 0.35), Vector3(gx, 1.3, cd), mat)
		if idx % 2 == 0: _car(Vector3(w / 2.0 + 1.55, 0.05, 0.3), 0.04, [Color(0.75, 0.75, 0.78), Color(0.1, 0.1, 0.12), Color(0.35, 0.05, 0.05)][idx % 3], body)
		if diwan: _build_diwan(body, mat, w, d, H, y0, cw, cd)
		elif idx % 3 == 0:
			var l := OmniLight3D.new()
			l.position = Vector3(-1.5, y0 + H - 0.5, 0)
			l.light_color = Color(1.0, 0.75, 0.45)
			l.light_energy = 1.6
			l.omni_range = 7.0
			body.add_child(l)
			flicker.append(l)
		add_child(body)
		idx += 1
	# streets
	var asphalt := _flat(Color(0.05, 0.05, 0.055), 0.4)
	var paint := _flat(Color(0.75, 0.7, 0.3))
	for st in [[-30.0, -47.0, 150.0, 7.0], [-30.0, 47.0, 150.0, 7.0], [-28.0, 0.0, 142.0, 8.0], [-13.0, 0.0, 7.0, 94.0]]:
		_mesh_box(self, Vector3(st[2], 0.08, st[3]), Vector3(st[0], 0.02, st[1]), asphalt)
		if st[2] > st[3]:
			for k in int(st[2] / 8.0):
				_mesh_box(self, Vector3(3.0, 0.02, 0.18), Vector3(st[0] - st[2] / 2.0 + 4.0 + k * 8.0, 0.07, st[1]), paint)
	for lx in [-90.0, -60.0, -30.0, 0.0, 30.0]:
		_lamp_post(Vector3(lx + 13.0, 0, -51.5), 0.0)
		_lamp_post(Vector3(lx, 0, 51.5), PI)
	# the flag of Kuwait on a tall pole, lit from below, waving
	var fp := StaticBody3D.new()
	fp.position = Vector3(9.0, 0, -11.0)
	_box(fp, Vector3(1.6, 0.5, 1.6), Vector3(0, 0.25, 0), _mat.concrete)
	_box(fp, Vector3(0.16, 13.0, 0.16), Vector3(0, 6.5, 0), _flat(Color(0.75, 0.75, 0.78), 0.3, 0.8))
	var ball := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.2; bsm.height = 0.4
	bsm.material = _flat(Color(0.85, 0.7, 0.25), 0.3, 0.9)
	ball.mesh = bsm
	ball.position = Vector3(0, 13.15, 0)
	fp.add_child(ball)
	var flag := MeshInstance3D.new()
	var fm := PlaneMesh.new()
	fm.orientation = PlaneMesh.FACE_Z
	fm.size = Vector2(5.0, 2.5)
	fm.subdivide_width = 28
	fm.subdivide_depth = 6
	var fsm := ShaderMaterial.new()
	fsm.shader = load("res://shaders/flag.gdshader")
	fm.material = fsm
	flag.mesh = fm
	flag.position = Vector3(2.58, 11.6, 0)
	flag.extra_cull_margin = 2.0
	fp.add_child(flag)
	var fspot := SpotLight3D.new()
	fspot.position = Vector3(2.5, 1.0, 5.0)
	fspot.rotation = Vector3(1.12, 0, 0)
	fspot.light_energy = 8.0
	fspot.spot_range = 20.0
	fspot.spot_angle = 22.0
	fp.add_child(fspot)
	add_child(fp)
	# mosque
	var cream := _flat(Color(0.82, 0.78, 0.66))
	var green := _flat(Color(0.1, 0.38, 0.25), 0.4, 0.3)
	var mq := StaticBody3D.new()
	mq.position = Vector3(16.0, 0, 27.0)
	_box(mq, Vector3(11.0, 5.5, 9.0), Vector3(0, 2.75, 0), cream, true)
	_mesh_box(mq, Vector3(11.6, 0.4, 9.6), Vector3(0, 5.6, 0), cream)
	_mesh_box(mq, Vector3(1.8, 3.0, 0.2), Vector3(0, 1.5, -4.55), _flat(Color(0.2, 0.12, 0.06)))
	var dome := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 3.0; sph.height = 4.6; sph.is_hemisphere = false
	sph.material = green
	dome.mesh = sph
	dome.position = Vector3(0, 6.6, 0)
	mq.add_child(dome)
	var tower := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.75; tc.bottom_radius = 1.0; tc.height = 15.0; tc.radial_segments = 12
	tc.material = cream
	tower.mesh = tc
	tower.position = Vector3(-4.3, 7.5, 3.3)
	mq.add_child(tower)
	var tcs := CollisionShape3D.new()
	var tsh := CylinderShape3D.new()
	tsh.radius = 1.0; tsh.height = 15.0
	tcs.shape = tsh
	tcs.position = tower.position
	mq.add_child(tcs)
	_mesh_box(mq, Vector3(2.4, 0.3, 2.4), Vector3(-4.3, 11.5, 3.3), cream)
	var cap := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = 0.0; cc.bottom_radius = 0.9; cc.height = 2.2
	cc.material = green
	cap.mesh = cc
	cap.position = Vector3(-4.3, 16.1, 3.3)
	mq.add_child(cap)
	var ml := OmniLight3D.new()
	ml.position = Vector3(-4.3, 12.4, 3.3)
	ml.light_color = Color(0.4, 1.0, 0.6)
	ml.light_energy = 2.5
	ml.omni_range = 14.0
	mq.add_child(ml)
	add_child(mq)

# ---------------- the diwaniya: warm facade lighting, glowing sign, pergola, palms ----------------
var _lobe: ImageTexture
var _wash_mats := {}

func _lobe_tex() -> ImageTexture: # a wall-washer's beam: a bright point at the bottom edge fanning out upward
	if _lobe: return _lobe
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		var t := 1.0 - (y + 0.5) / n # 0 at the lamp, 1 at the far end
		var wd := 0.1 + 0.8 * t
		for x in n:
			var u := ((x + 0.5) / n - 0.5) * 2.0
			var v := exp(-2.2 * (u / wd) * (u / wd)) * pow(1.0 - t, 1.5) * smoothstep(1.0, 0.75, absf(u))
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	_lobe = ImageTexture.create_from_image(img)
	return _lobe

func _wash_mat(energy: float) -> StandardMaterial3D:
	if _wash_mats.has(energy): return _wash_mats[energy]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = _lobe_tex()
	m.albedo_color = Color(1.0, 0.58, 0.24) * (energy * 0.6)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	_wash_mats[energy] = m
	return m

func _beam(parent: Node3D, at: Vector3, basis: Basis, width: float, length: float, energy: float) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(width, length)
	qm.material = _wash_mat(energy)
	q.mesh = qm
	q.basis = basis
	q.position = at + basis * Vector3(0, length / 2.0, 0)
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(q)

func _sconce(parent: Node3D, at: Vector3, yaw: float, width: float, up: float, down: float, energy := 1.0, mirror := 0.0) -> void:
	# a slim up/down wall light on a wall facing `yaw` (0 = +z); `mirror` > 0 also paints its reflection on the ground in front
	var bs := Basis(Vector3.UP, yaw)
	var n := bs * Vector3(0, 0, 1)
	_mesh_box(parent, Vector3(0.09, 0.3, 0.09), at + n * 0.06, _flat(Color(0.2, 0.14, 0.09), 0.4, 0.5), Vector3(0, yaw, 0))
	var cap := _flat(Color(1.0, 0.72, 0.4), 0.5, 0.0, 4.0)
	_mesh_box(parent, Vector3(0.07, 0.02, 0.07), at + n * 0.06 + Vector3(0, 0.16, 0), cap, Vector3(0, yaw, 0))
	_mesh_box(parent, Vector3(0.07, 0.02, 0.07), at + n * 0.06 - Vector3(0, 0.16, 0), cap, Vector3(0, yaw, 0))
	if up > 0.0: _beam(parent, at + n * 0.06 + Vector3(0, 0.1, 0), bs, width, up, energy)
	if down > 0.0: _beam(parent, at + n * 0.06 - Vector3(0, 0.1, 0), bs * Basis(Vector3(0, 0, 1), PI), width, down, energy)
	if mirror > 0.0: _beam(parent, Vector3(at.x, 0.1, at.z) + n * 0.35, bs * Basis(Vector3.RIGHT, PI / 2.0), width * 0.4, mirror, energy * 1.05)

func _warm_light(parent: Node3D, at: Vector3, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.position = at
	l.light_color = Color(1.0, 0.68, 0.36)
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.0
	parent.add_child(l)

func _warm_spot(parent: Node3D, at: Vector3, target: Vector3, energy: float, rng: float, angle: float) -> void:
	var l := SpotLight3D.new()
	l.position = at
	l.basis = Basis.looking_at(target - at, Vector3.FORWARD if absf((target - at).normalized().y) > 0.95 else Vector3.UP)
	l.light_color = Color(1.0, 0.68, 0.36)
	l.light_energy = energy
	l.spot_range = rng
	l.spot_angle = angle
	l.distance_fade_enabled = true
	l.distance_fade_begin = 55.0
	l.distance_fade_length = 12.0
	parent.add_child(l)

func _shrub(parent: Node3D, at: Vector3, r: float, mesh: Mesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at + Vector3(0, r * 0.75, 0)
	mi.scale = Vector3(r, r * 1.15, r)
	parent.add_child(mi)

func _build_diwan(body: StaticBody3D, mat: StandardMaterial3D, w: float, d: float, H: float, y0: float, cw: float, cd: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 26
	var wood := _flat(Color(0.16, 0.09, 0.05), 0.55)
	var led := _flat(Color(1.0, 0.7, 0.36), 0.5, 0.0, 3.2)
	var stone := _flat(Color(0.34, 0.31, 0.27), 0.7)
	var front := cd + 0.1 # outer face of the compound wall
	# ---- gate portal: tall pillars with a lintel, dark double doors standing open, a lit doorstep
	for gx in [-1.78, 1.78]:
		_box(body, Vector3(0.5, 3.2, 0.55), Vector3(gx, 1.6, cd), mat)
		_mesh_box(body, Vector3(0.62, 0.12, 0.67), Vector3(gx, 3.26, cd), mat)
		_box(body, Vector3(0.07, 2.5, 1.25), Vector3(signf(gx) * 1.36, 1.25, cd - 0.72), wood) # door leaf, swung inward
		_mesh_box(body, Vector3(0.03, 0.9, 0.04), Vector3(signf(gx) * 1.31, 1.2, cd - 1.2), _flat(Color(0.7, 0.55, 0.3), 0.3, 0.8))
	_mesh_box(body, Vector3(3.1, 0.4, 0.45), Vector3(0, 2.95, cd), mat)
	_mesh_box(body, Vector3(3.0, 0.035, 0.035), Vector3(0, 2.74, cd + 0.2), led)
	_mesh_box(body, Vector3(3.4, 0.07, 1.3), Vector3(0, 0.035, front + 0.75), stone)
	_mesh_box(body, Vector3(3.4, 0.03, 0.04), Vector3(0, 0.03, front + 1.42), led)
	# ---- compound wall: up/down sconces, plants and little ground uplights along its foot, a slatted corner panel
	for sx in [-6.9, -4.3, -2.35, 2.35, 4.3, 6.9]:
		_sconce(body, Vector3(sx, 1.3, front), 0.0, 1.5 if absf(sx) > 3.0 else 0.75, 0.88, 1.15, 1.0, 5.0)
	var bush := SphereMesh.new()
	bush.radius = 1.0; bush.height = 2.0; bush.radial_segments = 8; bush.rings = 4
	bush.material = _flat(Color(0.09, 0.16, 0.06), 0.9)
	var rock := SphereMesh.new()
	rock.radius = 1.0; rock.height = 1.3; rock.radial_segments = 7; rock.rings = 3
	rock.material = _mat.rock
	for sgn in [-1.0, 1.0]:
		var x := 2.75
		var k := 0
		while x < cw - 0.5:
			if k % 3 == 2:
				_mesh_box(body, Vector3(0.09, 0.07, 0.09), Vector3(sgn * x, 0.09, front + 0.22), led)
				_beam(body, Vector3(sgn * x, 0.12, front + 0.06), Basis(), 0.9, 1.1, 0.85)
			elif k % 3 == 0: _shrub(body, Vector3(sgn * x, 0.05, front + 0.45), rng.randf_range(0.28, 0.42), bush)
			else:
				_shrub(body, Vector3(sgn * x, 0.05, front + 0.4), rng.randf_range(0.2, 0.3), bush)
				_shrub(body, Vector3(sgn * x + 0.3, -0.05, front + 0.6), rng.randf_range(0.14, 0.2), rock)
			x += rng.randf_range(0.55, 0.75)
			k += 1
		# potted shrub beside the gate
		var pot := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.3; pc.bottom_radius = 0.2; pc.height = 0.5; pc.radial_segments = 10
		pc.material = _flat(Color(0.18, 0.12, 0.08), 0.35, 0.5)
		pot.mesh = pc
		pot.position = Vector3(sgn * 2.25, 0.3, front + 0.75)
		body.add_child(pot)
		_shrub(body, Vector3(sgn * 2.25, 0.5, front + 0.75), 0.36, bush)
	for k in 5: _mesh_box(body, Vector3(0.09, 2.3, 0.07), Vector3(cw - 0.75 + k * 0.16, 1.15, front + 0.03), wood)
	# ---- polished forecourt down to the street (catches the lights)
	_mesh_box(body, Vector3(cw * 2.0 + 1.0, 0.05, 8.3), Vector3(0, 0.03, front + 4.15), _flat(Color(0.08, 0.08, 0.09), 0.25, 0.1))
	# ---- ground floor facade: light line under the roof, sconces, lit front door
	_mesh_box(body, Vector3(w + 0.4, 0.035, 0.035), Vector3(0, y0 + H - 0.03, d / 2.0 + 0.16), led)
	for sx in [-3.9, -1.25, 1.25, 3.9]:
		_sconce(body, Vector3(sx, 2.15, d / 2.0 + 0.125), 0.0, 1.3, 1.2, 1.6, 0.9)
	# ---- upper floor: curtained windows glowing from inside, sconces between them, light line under the roof
	var uf := -d * 0.1 + d * 0.35 # front face of the upper block
	var curtain := [_flat(Color(1.0, 0.62, 0.3), 0.8, 0.0, 1.5), _flat(Color(0.85, 0.48, 0.2), 0.8, 0.0, 1.1)]
	for wx in [-w * 0.34, -w * 0.06]:
		_mesh_box(body, Vector3(1.16, 1.36, 0.06), Vector3(wx, y0 + H + 1.7, uf + 0.02), wood)
		for c in 5: _mesh_box(body, Vector3(0.2, 1.2, 0.03), Vector3(wx - 0.4 + c * 0.2, y0 + H + 1.7, uf + 0.05), curtain[c % 2] if c != 2 else _flat(Color(0.35, 0.2, 0.1), 0.8, 0.0, 0.5))
	for sx in [-w * 0.2 - 2.25, -w * 0.2, -w * 0.2 + 2.25]:
		_sconce(body, Vector3(sx, y0 + H + 1.45, uf), 0.0, 0.95, 1.05, 1.05, 0.9)
	_mesh_box(body, Vector3(w * 0.6, 0.035, 0.035), Vector3(-w * 0.2, y0 + H + 2.93, uf + 0.16), led)
	# ---- the sign block with the diwaniya's name in back-lit letters
	var sb := Vector3(w * 0.26, y0 + H + 1.5, d / 2.0 - 1.2) # flush with the facade, so the roof edge never hides the name
	_mesh_box(body, Vector3(4.6, 2.5, 3.0), sb, mat)
	_mesh_box(body, Vector3(4.9, 0.16, 3.3), sb + Vector3(0, 1.33, 0), mat)
	_mesh_box(body, Vector3(4.7, 0.035, 0.035), sb + Vector3(0, 1.23, 1.6), led)
	var lbl := Label3D.new()
	lbl.text = "ديوان\nراشد الشمري"
	lbl.font = Net.font
	lbl.font_size = 64
	lbl.pixel_size = 0.01
	lbl.line_spacing = -22.0
	lbl.modulate = Color(1.0, 0.74, 0.36)
	lbl.outline_size = 10
	lbl.outline_modulate = Color(0.75, 0.35, 0.08, 0.45)
	lbl.position = sb + Vector3(0.25, 0.1, 1.53)
	body.add_child(lbl)
	_sconce(body, sb + Vector3(-1.95, 0.0, 1.5), 0.0, 0.7, 0.9, 0.9, 0.9)
	# ---- pergola in the yard, glowing from underneath
	for px in [-cw + 0.45, -w / 2.0 - 0.45]:
		for pz in [1.7, cd - 0.6]: _box(body, Vector3(0.14, 2.85, 0.14), Vector3(px, 1.42, pz), wood)
		_mesh_box(body, Vector3(0.12, 0.16, cd - 1.6), Vector3(px, 2.92, (1.7 + cd - 0.6) / 2.0), wood)
	for k in 10: _mesh_box(body, Vector3(cw - w / 2.0 - 0.5, 0.05, 0.12), Vector3(-(cw + w / 2.0) / 2.0, 3.02, 1.8 + k * 0.5), wood)
	_sconce(body, Vector3(-cw + 0.1, 1.5, 4.0), PI / 2.0, 1.6, 1.0, 1.3, 1.0)
	var pot2 := MeshInstance3D.new()
	var pc2 := CylinderMesh.new()
	pc2.top_radius = 0.32; pc2.bottom_radius = 0.22; pc2.height = 0.55; pc2.radial_segments = 10
	pc2.material = _flat(Color(0.18, 0.12, 0.08), 0.35, 0.5)
	pot2.mesh = pc2
	pot2.position = Vector3(-cw + 0.7, 0.3, 5.9)
	body.add_child(pot2)
	_shrub(body, Vector3(-cw + 0.7, 0.75, 5.9), 0.55, bush)
	# ---- two date palms flanking the house, lit from the ground
	var palm := _palm_mesh(0, true)
	var trunk := _pbr(Color(0.14, 0.1, 0.06), Color(0.42, 0.32, 0.2), 0.05, Vector3(1.5, 0.6, 1.5), 0.9)
	for sgn in [-1.0, 1.0]:
		var pp := Vector3(sgn * (cw + 1.5), 0.0, 4.2)
		var mi := MeshInstance3D.new()
		mi.mesh = palm
		mi.position = pp
		mi.rotation.y = 1.3 * sgn
		mi.scale = Vector3.ONE * (0.82 if sgn < 0.0 else 0.78)
		mi.set_surface_override_material(0, trunk)
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.4; cyl.height = 6.0
		cs.shape = cyl
		cs.position = pp + Vector3(0, 3.0, 0)
		body.add_child(cs)
		_mesh_box(body, Vector3(0.16, 0.08, 0.16), pp + Vector3(0, 0.06, 0.8), led)
		_warm_spot(body, pp + Vector3(0, 0.15, 0.85), pp + Vector3(0, 6.5, 0.0), 5.0, 12.0, 28.0)
		_warm_light(body, pp + Vector3(0, 4.3, 1.0), 3.0, 7.5) # the crown, as if lit from the ground
	# ---- real lights (no shadows): gate, the two wall runs, sign, yard, pergola, inside
	_warm_light(body, Vector3(0, 2.2, front + 1.6), 0.7, 7.0)
	for sgn in [-1.0, 1.0]: _warm_spot(body, Vector3(sgn * 4.9, 3.2, front + 4.0), Vector3(sgn * 4.9, 0.4, front), 1.3, 10.0, 60.0)
	_warm_light(body, sb + Vector3(0, 0.2, 3.0), 0.6, 5.5)
	_warm_light(body, Vector3(0.0, 2.7, d / 2.0 + 1.5), 0.55, 7.0)
	_warm_light(body, Vector3(-(cw + w / 2.0) / 2.0, 2.2, 4.0), 0.6, 5.0)
	_warm_light(body, Vector3(-1.5, y0 + H - 0.5, 0), 1.2, 7.0)

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

func _frond(sf: SurfaceTool, origin: Vector3, yaw: float, elev: float, length: float, droop: float, half_w: float, segs: int) -> void:
	# one feather frond: a ribbon that leaves the crown at `elev` and bends down along its length
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var rows := []
	var p := origin
	for i in segs + 1:
		var s := float(i) / segs
		rows.append([p, half_w * pow(sin(PI * (0.07 + 0.9 * s)), 0.7), s])
		var pitch := elev - droop * pow(s, 1.3)
		p += (fwd * cos(pitch) + Vector3.UP * sin(pitch)) * (length / segs)
	for i in segs:
		var a: Array = rows[i]; var b: Array = rows[i + 1]
		for sgn in [-1.0, 1.0]:
			var a0: Vector3 = a[0]; var b0: Vector3 = b[0]
			var a1: Vector3 = a0 + side * (a[1] * sgn) + Vector3.UP * (a[1] * 0.3)
			var b1: Vector3 = b0 + side * (b[1] * sgn) + Vector3.UP * (b[1] * 0.3)
			var ue: float = 0.5 + 0.5 * sgn
			var quad := [[a0, Vector2(0.5, a[2])], [b0, Vector2(0.5, b[2])], [b1, Vector2(ue, b[2])], [a0, Vector2(0.5, a[2])], [b1, Vector2(ue, b[2])], [a1, Vector2(ue, a[2])]]
			if sgn < 0.0: quad.reverse()
			for v in quad:
				sf.set_uv(v[1])
				sf.add_vertex(v[0])

func _palm_mesh(variant: int, hi: bool) -> ArrayMesh:
	# date palm: ringed trunk, crown boss, three tiers of feather fronds
	var rng := RandomNumberGenerator.new()
	rng.seed = 300 + variant
	var hgt := rng.randf_range(6.5, 9.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 9 if hi else 1
	for i in rings: # each ring flares upward like the cut frond bases of a real trunk
		var seg := CylinderMesh.new()
		seg.height = (hgt + 0.3) / rings
		seg.bottom_radius = 0.24 if hi else 0.3
		seg.top_radius = 0.33 if hi else 0.26
		seg.radial_segments = 8 if hi else 5
		seg.rings = 1
		st.append_from(seg, 0, Transform3D(Basis(Vector3.UP, i * 0.4), Vector3(0, -0.3 + seg.height * (i + 0.5), 0)))
	var boss := CylinderMesh.new()
	boss.height = 0.8; boss.bottom_radius = 0.3; boss.top_radius = 0.46
	boss.radial_segments = 8 if hi else 5; boss.rings = 1
	st.append_from(boss, 0, Transform3D(Basis(), Vector3(0, hgt + 0.25, 0)))
	var mesh := st.commit()
	mesh.surface_set_material(0, _mat.bark)
	var sf := SurfaceTool.new()
	sf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, hgt + 0.55, 0)
	var segs := 6 if hi else 3
	# [count, elevation from, elevation to, droop]
	var tiers := [[8, 0.85, 1.25, 1.5], [8, 0.4, 0.7, 1.5], [6, -0.05, 0.2, 1.2]] if hi else [[5, 0.8, 1.1, 1.5], [5, 0.2, 0.5, 1.4]]
	for tr in tiers:
		var cnt: int = tr[0]
		var off := rng.randf() * TAU
		for i in cnt:
			_frond(sf, top, off + i * TAU / cnt + rng.randf_range(-0.18, 0.18), rng.randf_range(tr[1], tr[2]), rng.randf_range(3.4, 4.4), tr[3] * rng.randf_range(0.9, 1.1), 0.62, segs)
	sf.generate_normals()
	sf.commit(mesh)
	mesh.surface_set_material(1, _mat.palm)
	return mesh

func _build_trees() -> void:
	var meshes := []
	for v in 2:
		if map_id == "fareej": meshes.append([_palm_mesh(v, true), _palm_mesh(v, false)])
		else: meshes.append([_tree_mesh(v, true), _tree_mesh(v, false)])
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
	mm.instance_count = 100
	for i in 100:
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
			for i in grass_per_chunk:
				var x := center.x + rng.randf_range(-GRASS_CHUNK / 2.0, GRASS_CHUNK / 2.0)
				var z := center.z + rng.randf_range(-GRASS_CHUNK / 2.0, GRASS_CHUNK / 2.0)
				if in_site(x, z, -1.0) or on_street(x, z, 0.5): continue
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
	market_t = maxf(market_t - _dt, 0.0)
	for ml in market_lights: # blackout while the killer is inside; a rare stutter otherwise
		var base: float = ml[1]
		if market_t > 0.0: ml[0].light_energy = base if sin(t * 43.0) > 0.1 else 0.0
		elif market_dark: ml[0].light_energy = 0.0
		else: ml[0].light_energy = base * (0.25 if (sin(t * 0.37) > 0.985 and sin(t * 31.0) > 0.0) else 1.0)
	for g in gen_nodes: # a generator about to start: its lamps stutter on and off
		if g.done: continue
		if g.blink:
			var on := sin(t * 19.0) > -0.2 and sin(t * 7.3) > -0.6
			g.light.light_energy = 2.4 if on else 0.15
			g.mat.emission_energy_multiplier = 4.0 if on else 0.0
		elif g.mat.emission_energy_multiplier > 0.0:
			g.light.light_energy = 0.7
			g.mat.emission_energy_multiplier = 0.0
	if follow and dust:
		dust.global_position = follow.global_position + Vector3(0, 2.0, 0)
		leaves.global_position = follow.global_position + Vector3(0, 7.0, 0)
