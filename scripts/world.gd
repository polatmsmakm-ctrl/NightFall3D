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
var theme := "normal" # normal / snow / halloween
var tents := 0        # how many of the first `buildings` entries are bedouin tents (rubkhali)
var animals: Array = [] # desert horses and camels: {node, path, i, speed, bob, stand}
var wrecks := 0     # Land Cruiser wrecks placed (rubkhali)
var garage_tiles: Array = []  # the car-park modules: {c, r, origin, pieces}
var garage_solids: Array = [] # world rectangles [x0, x1, z0, z1] you cannot walk through
var garage_panels: Array = [] # the ceiling strip materials, so the blackout can kill them
var garage_detail: Array = [] # the small yellow kerb/wheel-stop geometry, dropped on low quality
var garage_barriers: Array = [] # [pos, yaw] of the concrete barriers you vault over
var garage_cars := 0          # parked cars, counted for the headless test
var ao_blobs: Array = []      # [pos, radius] soft ground shadows, drawn as one MultiMesh
var ao_mm: MultiMeshInstance3D
var models_used := 0          # how many props were drawn from a real model this round
var fortress_parts := 0       # sections of the owner's fortress wall around the map
var campfires := 0            # burning barrels that became the owner's campfire
var campfire_points: Array = [] # where they burn (tests and screenshots look at them)
var tent_models := 0          # bedouin tents drawn with the owner's crimson tent
var car_models := 0           # cars drawn with the owner's Land Cruiser (the garage counts as one MultiMesh)
const CAR_SCALE := 0.9        # 1.8 x 4.3 m, the size of the old car boxes and their collision
var drive_car: NFCar          # the one car the killer can drive (placed at the end of build())
## Every parked car on the map (market, the random ones, fareej driveways, the car park's bays):
## the killer can take any of them. There is still only one NFCar: getting into a parked car swaps
## the two (`take_parked`), so the driving car takes that spot and the parked one takes its place.
## Each entry: {"node": StaticBody3D} or {"mm": MultiMesh, "mi": index, "hull": CollisionShape3D,
## "at": Vector3, "yaw": float} for the car park, where the bays are one MultiMesh.
var parked := []
var beach_palms := 0          # palms placed on the beach map
var beach_props := 0          # wet-sand patches and shells
var _models := {}             # name -> PackedScene or null
var pumpkins := 0   # halloween dressing
var webs := 0
var snow_caps := 0
var buildings: Array = []
var tree_count := 450
var tree_plan: Array = [] # [x, y, z, variant, scale, yaw]
var fog_density := 0.016
var fog_base := 0.016 # what the map settled on, after the theme and the weather
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
var amb_lights: Array = [] # [light, base energy, is a house light, flickers, current dim 0..1]
var blackout := false      # the blackout event has the lights out
var _amb_base := 0.8       # ambient energy before a blackout dims it
var _last_model: Node3D    # the model the last successful _swap_model put in
var hook_hang_y := 0.62    # how high a hooked survivor hangs: the gallows model's hook is lower
const HOOK_POST_Z := -1.46 # the gallows' post stands behind the hook point, its hook in front of it
const GATE_HALF := 7.35    # half the width of the gate model, pillars and fences included
const WALL_SEG := 16.0     # one fortress section, end pillar to end pillar
var _moon_base := 1.1      # moonlight before the moon starts to fall
var _exp_base := 1.0       # exposure before the player's «السطوع»
var fog_boost := 0.0       # 0..1: the heavy-fog event
var killer_at := Vector3(9999, 0, 9999) # fed by main.gd so lights can shy away from him
var door_nodes: Array = [] # one per door_point: {hinge, yaw, shut} (null where there is no leaf)
var grass_nodes: Array[MultiMeshInstance3D] = []
var grass_counts: Array[int] = []
var ready_done := false
const BUILD_STEPS := 5 # stages of build(); the loading screen shows build_step / BUILD_STEPS
var build_step := 0
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
		if map_id == "beach" and p.y > BEACH_SHORE - 10.0: continue # keep it out of the water
		if not in_site(p.x, p.y, pad) and not on_street(p.x, p.y, 1.0): return p
	return Vector2(lo, lo)

## `seed` shuffles where the generators, hooks, pallets, hatches are, so every round plays differently.
## Everyone in a room gets the same seed from the server, so they all build the same layout.
func configure(id: String, seed := 1, th := "normal") -> void:
	map_id = id
	theme = th
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
	elif id == "rubkhali": # the Empty Quarter: dunes, bedouin tents, mud houses, a dust storm
		noise.seed = 909
		noise.frequency = 0.0062 # long dune waves instead of small bumps
		noise.fractal_octaves = 3
		relief = 3.0
		tree_count = 85     # palm clusters around the camps
		grass_per_chunk = 45 # dry tufts
		fog_density = 0.021  # the storm: you cannot see far
		moon_dir = Vector3(0.32, 0.6, -0.73).normalized() # the sun, high and behind the dust
		var camps := [[-62.0, -38.0, 0.4], [-20.0, -72.0, 1.9], [44.0, -58.0, -0.8], [70.0, 22.0, 2.6], [-74.0, 44.0, 0.9], [18.0, 74.0, -2.2]]
		for t in camps: buildings.append([t[0], t[1], t[2], 9.0, 7.0, 2.6]) # بيت شعر
		tents = camps.size()
		for h in [[-40.0, 8.0, 0.2], [26.0, -20.0, 1.2], [-8.0, 52.0, -0.5], [62.0, -86.0, 0.8], [-86.0, -8.0, 1.6]]:
			buildings.append([h[0], h[1], h[2], 8.0, 6.5, 3.2]) # mud house
	elif id == "beach": # «الشاطئ»: a lagoon, palms and beach huts, with the sea on the north side
		noise.seed = 616
		noise.frequency = 0.009
		relief = 1.1
		tree_count = 0        # the palms come from the model, not the procedural tree mesh
		grass_per_chunk = 45  # beach grass up on the dry sand
		fog_density = 0.011
		moon_dir = Vector3(-0.3, 0.38, 0.87).normalized() # the moon over the water
		var hut := RandomNumberGenerator.new()
		hut.seed = 2211
		for h in [[-74.0, -30.0], [-38.0, -58.0], [6.0, -44.0], [52.0, -62.0], [78.0, -18.0],
				[-60.0, 14.0], [34.0, 8.0], [-10.0, 24.0]]:
			buildings.append([h[0], h[1], hut.randf() * TAU, hut.randf_range(7.0, 9.5),
				hut.randf_range(6.0, 7.5), 3.0]) # beach huts
	elif id == "garage": # «المواقف»: the car park under an apartment block, all concrete and columns
		noise.seed = 2026
		relief = 0.0
		tree_count = 0
		grass_per_chunk = 0
		fog_density = 0.016  # damp basement air, thin enough that the far strip lights still read
		moon_dir = Vector3(0.3, 0.5, -0.81).normalized()
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
	if theme == "snow": grass_per_chunk = int(grass_per_chunk * 0.5) # snow buries most of it
	if Gfx.strong and Gfx.effects >= 2: grass_per_chunk = int(grass_per_chunk * 1.6) # thicker on strong devices
	if id == "garage": # the car park lays out its own floor, so none of the outdoor plan applies
		_plan_garage(rng)
		return
	sites.append([0.0, 0.0, _raw_h(0.0, 0.0), 6.0])
	for b in buildings:
		sites.append([b[0], b[1], _raw_h(b[0], b[1]), maxf(b[3], b[4]) * (1.05 if id == "fareej" else 0.75) + 1.0])
	# the market: a big flat plot on the east side, shop fronts facing the middle of the map
	var mz: float = -34.0 if id == "beach" else 2.0 # on the beach it sits back from the water
	var mh := _raw_h(56.0, mz)
	sites.append([56.0, mz, mh, 21.0])
	market = {"pos": Vector3(62.0, mh, mz), "yaw": -PI / 2.0, "w": MARKET_W, "d": MARKET_D}
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
	if map_id == "garage": return "indoor" # bare concrete everywhere
	if map_id == "beach": return "sand"
	var ml: Vector3 = Basis(Vector3.UP, market.yaw).inverse() * (pos - market.pos)
	if absf(ml.x) < MARKET_W / 2.0 + 2.0 and ml.z > -MARKET_D / 2.0 - 0.3 and ml.z < MARKET_D / 2.0 + 16.0: return "indoor"
	for b in buildings:
		var bl: Vector3 = Basis(Vector3.UP, b[2]).inverse() * (pos - Vector3(b[0], pos.y, b[1]))
		if absf(bl.x) < b[3] / 2.0 + 0.3 and absf(bl.z) < b[4] / 2.0 + 0.3: return "indoor"
	if on_street(pos.x, pos.z): return "indoor" # asphalt
	return "sand" if (map_id in ["fareej", "rubkhali"] or in_site(pos.x, pos.z, 0.0)) else "grass"

func _sandiness(x: float, z: float) -> float:
	if map_id in ["fareej", "rubkhali", "beach"]: return 1.0
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
	var h := (noise.get_noise_2d(x, z) * 2.4 + noise.get_noise_2d(x * 3.0 + 50.0, z * 3.0) * 0.35) * relief
	if map_id == "beach": # the sand slopes down into the lagoon on the north side
		h -= smoothstep(BEACH_SHORE - 16.0, BEACH_SHORE + 44.0, z) * 3.4
	return h

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
	build_step = 1
	await get_tree().process_frame
	if map_id == "fareej": _build_fareej()
	elif map_id == "rubkhali": _build_rubkhali()
	elif map_id == "garage": _build_garage()
	elif map_id == "beach": _build_beach()
	else: _build_buildings()
	_build_objectives()
	_build_extras()
	_build_doors()
	if map_id != "garage": _build_market()
	build_step = 2
	await get_tree().process_frame
	if map_id != "garage": _build_scatter() # the garage parks its own cars
	_build_theme_props()
	if map_id == "rubkhali": _build_animals()
	_build_trees()
	build_step = 3
	await get_tree().process_frame
	if map_id != "garage":
		_build_rocks()
		await _build_grass()
	build_step = 4
	_build_blobs()
	_build_particles()
	_build_probe()
	await get_tree().physics_frame # the colliders have to be in the physics space before the
	await get_tree().physics_frame # killer's car looks for a clear spot among them
	_place_drive_car()
	for l in find_children("*", "OmniLight3D", true, false): # far lights cost nothing
		l.distance_fade_enabled = true
		l.distance_fade_begin = 45.0
		l.distance_fade_length = 12.0
	Gfx.changed.connect(_apply_quality)
	_apply_quality()
	build_step = BUILD_STEPS
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

## A procedural PBR surface: large-scale colour and shape from one noise, plus a fine detail
## normal on a second UV so a wall still has grain when your face is against it. The detail
## layer is the cheapest way to get close-up quality without real texture files.
func _pbr(c1: Color, c2: Color, freq: float, uv: Vector3, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex(freq, 512, false, _grad(c1, c2))
	m.normal_enabled = true
	m.normal_texture = _noise_tex(freq, 512, true)
	m.normal_scale = 1.35
	m.roughness = rough
	m.roughness_texture = _noise_tex(freq * 2.0, 256, false, _grad(Color(0.55, 0.55, 0.55), Color.WHITE))
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.metallic = metal
	m.uv1_triplanar = true; m.uv1_world_triplanar = true; m.uv1_scale = uv
	m.detail_enabled = true # fine grain, five times tighter than the base noise
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1
	m.detail_albedo = _noise_tex(freq * 7.0, 256, false, _grad(Color(c1.r, c1.g, c1.b, 0.0), Color(c2.r, c2.g, c2.b, 0.22)))
	m.detail_normal = _noise_tex(freq * 7.0, 256, true)
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
	if map_id == "rubkhali": # dry straw tufts
		gr.set_shader_parameter("base_col", Color(0.14, 0.12, 0.06))
		gr.set_shader_parameter("tip_col", Color(0.45, 0.37, 0.18))
	if theme == "snow":
		gr.set_shader_parameter("base_col", Color(0.26, 0.29, 0.34))
		gr.set_shader_parameter("tip_col", Color(0.55, 0.61, 0.71))
		fol.set_shader_parameter("tint", Color(1.6, 1.8, 2.1))
	elif theme == "halloween":
		gr.set_shader_parameter("base_col", Color(0.07, 0.05, 0.02))
		gr.set_shader_parameter("tip_col", Color(0.22, 0.13, 0.04))
		fol.set_shader_parameter("tint", Color(1.3, 0.85, 0.5))
	_mat.grass = gr
	# desert surfaces
	_mat.mud = _pbr(Color(0.26, 0.2, 0.14), Color(0.58, 0.47, 0.34), 0.03, Vector3(0.35, 0.35, 0.35), 0.95)
	_mat.cloth = _pbr(Color(0.035, 0.03, 0.028), Color(0.13, 0.115, 0.1), 0.05, Vector3(0.6, 0.6, 0.6), 1.0)
	_mat.sand_rock = _pbr(Color(0.16, 0.13, 0.09), Color(0.42, 0.35, 0.25), 0.02, Vector3(0.5, 0.5, 0.5), 0.95)

# ---------------- environment ----------------
## Register a light that the blackout, the flicker and the killer can all touch.
## `house` lights go out when he walks up to them.
func _amb_light(l: OmniLight3D, house := false, flick := true) -> void:
	amb_lights.append([l, l.light_energy, house, flick, 1.0])
	NFLook.halo(l)
	if flick: flicker.append(l)

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
	if map_id == "garage": # concrete under strip lights, not moonlit grass
		env.ambient_light_color = Color(0.24, 0.25, 0.27)
		env.ambient_light_energy = 1.12
		env.fog_light_color = Color(0.09, 0.095, 0.1)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.09, 0.14)
	if map_id == "rubkhali": env.fog_light_color = Color(0.3, 0.22, 0.13) # sand in the air
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
	match theme:
		"fog": # a night the killer can hide in: you see a few metres and then nothing
			env.ambient_light_color = Color(0.17, 0.19, 0.24)
			env.ambient_light_energy = 0.95
			env.fog_light_color = Color(0.1, 0.11, 0.13)
			env.fog_density = fog_density * 3.1
			env.fog_height_density = 0.3
			env.adjustment_saturation = 0.72
			env.adjustment_contrast = 1.05
		"snow":
			env.ambient_light_color = Color(0.23, 0.27, 0.38)
			env.ambient_light_energy = 1.0
			env.fog_light_color = Color(0.2, 0.24, 0.32)
			env.fog_density = fog_density * 1.5
			env.adjustment_saturation = 0.72
		"halloween":
			env.ambient_light_color = Color(0.2, 0.11, 0.06)
			env.ambient_light_energy = 0.55
			env.fog_light_color = Color(0.15, 0.06, 0.02)
			env.fog_density = fog_density * 1.5
			env.adjustment_saturation = 1.05
	if map_id == "rubkhali": # «الربع الخالي» plays in daylight: a sandstorm with the sun in it
		_sky_mat.set_shader_parameter("sun", 1.0)
		env.ambient_light_color = Color(0.72, 0.6, 0.44)
		env.ambient_light_energy = 1.5
		env.fog_light_color = Color(0.76, 0.6, 0.38)
		env.fog_density = fog_density * 1.3   # the storm is what hides the killer here, not the dark
		env.fog_sky_affect = 0.5 # the sun still burns through the dust
		env.fog_sun_scatter = 0.5
		env.fog_height_density = 0.05
		env.adjustment_contrast = 1.04
		env.adjustment_saturation = 0.92
		env.tonemap_white = 8.0
		env.glow_hdr_threshold = 1.5
	# lighter nights (the owner asked for it): the dark is still there, but the map reads
	if map_id != "rubkhali":
		env.ambient_light_energy *= 2.0
		env.fog_density *= 0.65
		env.adjustment_brightness = 1.08
		_exp_base = 1.32
	if NFLook.hd(): # the volumetric fog carries the near air now; the flat fog only paints the distance
		env.fog_density *= 0.8
	_apply_look()
	if not Gfx.look_changed.is_connected(_apply_look): Gfx.look_changed.connect(_apply_look)
	_amb_base = env.ambient_light_energy
	fog_base = env.fog_density
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	moon = DirectionalLight3D.new()
	moon.basis = Basis.looking_at(-moon_dir)
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.light_energy = 1.1
	if map_id == "rubkhali": moon.light_color = Color(0.78, 0.72, 0.6) # dusty moonlight
	match theme:
		"fog":
			moon.light_color = Color(0.6, 0.68, 0.88)
			moon.light_energy = 0.75 # the fog eats the moonlight
		"snow":
			moon.light_color = Color(0.72, 0.82, 1.0)
			moon.light_energy = 1.35
		"halloween":
			moon.light_color = Color(1.0, 0.6, 0.3)
			moon.light_energy = 0.45 # the pumpkins should be the light, not the sky
	if map_id == "rubkhali": # hard noon light through the dust
		moon.light_color = Color(1.0, 0.91, 0.74)
		moon.light_energy = 2.4
	else: moon.light_energy *= 1.4 # lighter nights
	_moon_base = moon.light_energy
	moon.shadow_enabled = true
	moon.directional_shadow_blend_splits = true
	NFLook.soft_sun(moon, 0.8 if map_id == "rubkhali" else 0.5)
	add_child(moon)

# ---------------- terrain ----------------
## How shaded a patch of ground is by whatever stands on it: walls, houses, tents, the market.
## Baked into the terrain's vertex colours while the mesh is built, so it costs nothing to draw
## and it survives the seed changing every round (a real lightmap bake cannot: the maps have no
## saved scene to bake, they are generated from the host's seed when the round starts).
func _ground_ao(x: float, z: float) -> float:
	var dark := 0.0
	for st in sites:
		var d := Vector2(x - st[0], z - st[1]).length()
		var r: float = st[3]
		if d < r + 4.0: dark = maxf(dark, (1.0 - smoothstep(r * 0.55, r + 4.0, d)) * 0.55)
	for b in ao_blobs:
		var p: Vector3 = b[0]
		var br: float = b[1] * 2.2
		var d2 := Vector2(x - p.x, z - p.z).length()
		if d2 < br: dark = maxf(dark, (1.0 - smoothstep(br * 0.25, br, d2)) * 0.4)
	return clampf(dark, 0.0, 0.7)

## A soft dark patch on the ground under something solid. They are collected while the map is
## built and drawn at the end as one MultiMesh: contact shadows for the price of one draw call.
func _blob(at: Vector3, radius: float) -> void:
	ao_blobs.append([at, radius])

func _build_blobs() -> void:
	if ao_blobs.is_empty(): return
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	q.orientation = PlaneMesh.FACE_Y
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = NFUI.soft_dot()
	m.albedo_color = Color(0.02, 0.02, 0.03, 0.5)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.render_priority = -1
	q.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = ao_blobs.size()
	for i in ao_blobs.size():
		var at: Vector3 = ao_blobs[i][0]
		var r: float = ao_blobs[i][1]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(r, 1.0, r)),
			Vector3(at.x, height(at.x, at.z) + 0.035, at.z)))
	ao_mm = MultiMeshInstance3D.new()
	ao_mm.multimesh = mm
	ao_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ao_mm.name = "GroundShadows"
	add_child(ao_mm)

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
					var wx := -HALF + gi * CELL
					var wz := -HALF + gj * CELL
					var gcol := Color(0.42, 0.56, 0.34).lerp(Color(1.0, 0.86, 0.6), _sandiness(wx, wz))
					if map_id == "rubkhali": gcol = Color(0.86, 0.71, 0.46)
					elif map_id == "garage": gcol = Color(0.17, 0.17, 0.18) # bare concrete under the slab
					if theme == "snow": gcol = gcol.lerp(Color(0.92, 0.95, 1.0), 0.88)
					elif theme == "halloween": gcol = gcol.lerp(Color(0.5, 0.33, 0.14), 0.45)
					cols.append(gcol.darkened(_ground_ao(wx, wz))) # shade under walls and buildings
					
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

# ---------------- real models instead of the boxes ----------------
## Drop a GLB into assets/props and the map draws it instead of the boxes built in code:
## car.glb, lamp.glb, generator.glb, hook.glb, locker.glb. **The collision never changes** —
## the code-built shapes stay exactly where they are and only the visible meshes are hidden —
## so a new model can make the map look better but can never break a round. Nothing happens
## until the file exists.
func _model(name: String) -> PackedScene:
	if not _models.has(name):
		var path := "res://assets/props/%s.glb" % name
		_models[name] = load(path) if ResourceLoader.exists(path) else null
	return _models[name]

func _swap_model(body: Node3D, name: String, yaw := 0.0, scale := 1.0) -> bool:
	var ps: PackedScene = _model(name)
	if ps == null: return false
	for ch in body.get_children():
		if ch is MeshInstance3D: (ch as MeshInstance3D).visible = false
	var n: Node3D = (ps.instantiate() as Node3D)
	n.rotation.y = yaw
	n.scale = Vector3(scale, scale, scale)
	body.add_child(n)
	models_used += 1
	_last_model = n
	return true

## The glow of a prop from tools/prop_bake.py: its baked glow map times `col`, at `energy`.
## With `own` every mesh of this instance gets its own copy, so one gate (or generator) can
## change colour without the others. Returns the material, or null when the model has no glow map.
static func prop_glow(root: Node, col: Color, energy: float, own := false) -> StandardMaterial3D:
	var mat: StandardMaterial3D = null
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		if m == null or m.get_texture(BaseMaterial3D.TEXTURE_EMISSION) == null: continue
		if own:
			if mat == null: mat = m.duplicate() as StandardMaterial3D
			(mi as MeshInstance3D).set_surface_override_material(0, mat)
		else: mat = m
		mat.emission_enabled = true
		mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY # glow map x colour, not + colour
		mat.emission = col
		mat.emission_energy_multiplier = energy
	return mat

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
		_snow_cap(body, Vector3(w + 1.0, 0.1, d + 1.0), Vector3(0, y0 + hgt + 0.3, 0), Vector3(0, 0, 0.1))
		if idx % 3 == 0: # a weak flickering lamp inside some buildings (no shadows)
			var l := OmniLight3D.new()
			l.position = Vector3(0, y0 + hgt - 0.5, 0)
			l.light_color = Color(1.0, 0.62, 0.3)
			l.light_energy = 1.6
			l.omni_range = 7.0
			body.add_child(l)
			_amb_light(l, true)
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
		_blob(hp, 1.3)
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
		if _swap_model(body, "hook"): # the gallows: its hook hangs where the old one did, the post behind
			hook_hang_y = 0.43
			for ch in body.get_children():
				if ch is CollisionShape3D: (ch as CollisionShape3D).position = Vector3(0, 2.6, HOOK_POST_Z)
			for ch in body.get_children():
				if ch is CollisionShape3D: ((ch as CollisionShape3D).shape as BoxShape3D).size = Vector3(0.5, 5.2, 0.5)
			l.position = Vector3(0, 2.9, 0.9)
			prop_glow(_last_model, Color(1.0, 0.75, 0.45), 2.5)
		add_child(body)
	var dark := _flat(Color(0.05, 0.05, 0.05), 0.6, 0.4)
	for lp in locker_points:
		_blob(lp[0], 1.2)
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
		_swap_model(body, "locker")
		add_child(body)
	for pp in pallet_points:
		_blob(pp[0], 1.3)
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
		_blob(gp, 1.9)
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
		var modelled := _swap_model(body, "generator")
		if modelled: # its own lamp and beacons light up when it is done, like the bulbs did
			var gm := prop_glow(_last_model, Color(1.0, 0.85, 0.5), 0.0, true)
			if gm: lamp_mat = gm
		for z in ([] if modelled else [0.3, -0.3]):
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
		if modelled: light.position = Vector3(-0.55, 2.2, 0.35) # beside the model's own work lamp
		body.add_child(light)
		add_child(body)
		gen_nodes.append({"light": light, "mat": lamp_mat, "done": false, "blink": false})
	# perimeter wall: tall, runs the whole edge of the map, so the only way out is through a gate
	var top := 12.0 if map_id == "rubkhali" else 9.0 # dunes are high; keep the wall above them
	var bottom := -9.0 if map_id == "rubkhali" else -7.0
	var wall_h := top - bottom
	var wall_y := (top + bottom) / 2.0
	var sides := StaticBody3D.new()
	sides.name = "PerimeterWall"
	for sx in [-1.0, 1.0]:
		_box(sides, Vector3(1.4, wall_h, WALL * 2.0 + 1.4), Vector3(sx * WALL, wall_y, 0), _mat.concrete, true)
	add_child(sides)
	_build_fortress(sides)
	var open_w := 7.0 # gate opening width
	var open_h := 6.0
	for g in gate_points:
		var gy: float = g[0].y
		# a gate up on a roof needs a taller wall around it than one standing on the ground
		var gtop: float = maxf(top, gy + open_h + 1.5)
		var gh := gtop - bottom
		var gmid := (gtop + bottom) / 2.0
		var body := StaticBody3D.new()
		body.position = Vector3(g[0].x, 0, g[0].z)
		body.rotation.y = g[1]
		var seg := WALL - open_w / 2.0
		for sx in [-1.0, 1.0]:
			_box(body, Vector3(seg, gh, 1.4), Vector3(sx * (open_w / 2.0 + seg / 2.0), gmid, 0), _mat.concrete, true)
			_box(body, Vector3(1.8, gtop + 1.5 - bottom, 2.0), Vector3(sx * (open_w / 2.0 + 0.9), (gtop + 1.5 + bottom) / 2.0, 0), _mat.concrete) # gate towers
		_box(body, Vector3(open_w, gtop - (gy + open_h), 1.4), Vector3(0, (gtop + gy + open_h) / 2.0, 0), _mat.concrete)
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
		var gate_ps := _model("gate")
		if gate_ps: # the modelled gate: its frame on the wall line, its two leaves riding the sliding doors
			for ch in body.get_children():
				if ch is MeshInstance3D: (ch as MeshInstance3D).visible = false
			for door in doors:
				for ch in door.get_children():
					if ch is MeshInstance3D: (ch as MeshInstance3D).visible = false
			var gn := gate_ps.instantiate() as Node3D
			gn.position = Vector3(0, gy, 0)
			body.add_child(gn)
			models_used += 1
			var gmat := prop_glow(gn, Color(1.0, 0.15, 0.1), 2.0, true) # the EXIT sign and the beacons: red, then green
			if gmat: sign_mat = gmat
			for k in 2: # moved by hand: the gate is not in the scene yet, so there is no global transform
				var leaf := gn.find_child("leaf_l" if k == 0 else "leaf_r", true, false) as Node3D
				if leaf == null: continue
				var t := leaf.transform
				var up := leaf.get_parent() as Node3D
				while up != null and up != gn:
					t = up.transform * t
					up = up.get_parent() as Node3D
				t = (doors[k] as Node3D).transform.affine_inverse() * gn.transform * t
				leaf.owner = null # it leaves the gate scene for the door body
				leaf.get_parent().remove_child(leaf)
				(doors[k] as Node3D).add_child(leaf)
				leaf.transform = t
		if gy > bottom + 0.1: # wall the opening off underneath a raised gate
			_box(body, Vector3(open_w, gy - bottom, 1.4), Vector3(0, (gy + bottom) / 2.0, 0), _mat.concrete)
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
			_amb_light(ll)
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

## The owner's fortress wall along the whole perimeter, inside face toward the map: one MultiMesh
## per side (so the sides behind you are culled), each section standing on the lowest ground under
## it, and the gate sides stopping at the gate model's fences. The old concrete stays as collision.
func _build_fortress(sides: Node3D) -> void:
	var ps := _model("wall")
	if ps == null: return
	var inst := ps.instantiate()
	var src: MeshInstance3D = null
	for c in inst.find_children("*", "MeshInstance3D", true, false): src = c
	if src == null:
		inst.free()
		return
	var mesh: Mesh = src.mesh
	prop_glow(src, Color(1.0, 0.62, 0.3), 2.2)
	if mesh.surface_get_material(0) == null: mesh.surface_set_material(0, src.get_active_material(0))
	inst.free()
	for ch in sides.get_children():
		if ch is MeshInstance3D: (ch as MeshInstance3D).visible = false
	var big := 1.35 if map_id == "rubkhali" else 1.0 # the dunes are high: so is the wall
	var step := WALL_SEG * 0.96 * big                 # end pillars overlap
	var runs := [] # [start point, unit direction along the run, length, yaw facing inward]
	runs.append([Vector3(WALL + 0.4, 0, -WALL), Vector3(0, 0, 1), WALL * 2.0, -PI / 2.0])
	runs.append([Vector3(-WALL - 0.4, 0, -WALL), Vector3(0, 0, 1), WALL * 2.0, PI / 2.0])
	for zs in [-1.0, 1.0]:
		var z: float = zs * (WALL + 0.4)
		var yaw := 0.0 if zs < 0.0 else PI
		var gx := INF
		for g in gate_points:
			if absf(absf((g[0] as Vector3).z) - WALL) < 2.0 and signf((g[0] as Vector3).z) == zs and _model("gate"): gx = (g[0] as Vector3).x
		if gx == INF:
			runs.append([Vector3(-WALL, 0, z), Vector3(1, 0, 0), WALL * 2.0, yaw])
		else:
			runs.append([Vector3(gx + GATE_HALF, 0, z), Vector3(1, 0, 0), WALL - gx - GATE_HALF, yaw])
			runs.append([Vector3(gx - GATE_HALF, 0, z), Vector3(-1, 0, 0), WALL + gx - GATE_HALF, yaw])
	for r in runs:
		var n := int(ceil(float(r[2]) / step))
		if n <= 0: continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = n
		var dir: Vector3 = r[1]
		for i in n:
			var c: Vector3 = (r[0] as Vector3) + dir * (step * (i + 0.5))
			var low := INF
			for k in 5: # stand on the lowest ground under the section, so no gap shows beneath it
				var p: Vector3 = c + dir * (step * (k / 4.0 - 0.5))
				low = minf(low, _raw_h(p.x, p.z))
			var b := Basis(Vector3.UP, float(r[3])).scaled(Vector3(big, big, big))
			mm.set_instance_transform(i, Transform3D(b, Vector3(c.x, low - 0.3, c.z)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		fortress_parts += n

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

## A lit sign. `yaw` turns it to face the way people come from — a Label3D faces -z, so a sign
## read from the +z side is mirrored unless it is turned round.
func _sign_text(parent: Node3D, text: String, pos: Vector3, size: int, col: Color, yaw := 0.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Net.font
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = col
	l.outline_size = 0
	l.position = pos
	l.rotation.y = yaw
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
		var z := rng.randf_range(-WALL + 8.0, (BEACH_SHORE + 4.0) if map_id == "beach" else (WALL - 8.0))
		if in_site(x, z, pad) or near_tree(x, z, pad + 1.0) or on_street(x, z, pad): continue
		return Vector3(x, height(x, z), z)
	return Vector3.INF

func _car(at: Vector3, yaw: float, col: Color, parent: Node3D = null) -> void:
	_blob(at, 2.5)
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
	if _swap_model(body, "car", 0.0, CAR_SCALE): car_models += 1
	(parent if parent else self).add_child(body)
	if parent == null: parked.append({"node": body}) # (a fareej driveway car is walled in: it stays put)

func _lamp_post(at: Vector3, yaw: float) -> void:
	_blob(at, 0.9)
	var body := StaticBody3D.new()
	body.position = at
	body.rotation.y = yaw
	_box(body, Vector3(0.16, 4.6, 0.16), Vector3(0, 2.3, 0), _mat.metal)
	_mesh_box(body, Vector3(0.1, 0.1, 1.2), Vector3(0, 4.5, 0.55), _mat.metal)
	_mesh_box(body, Vector3(0.3, 0.1, 0.5), Vector3(0, 4.42, 1.0), _flat(Color(1.0, 0.85, 0.55), 0.5, 0.0, 3.0))
	_swap_model(body, "lamp")
	var l := OmniLight3D.new()
	l.position = Vector3(0, 4.1, 1.0)
	l.light_color = Color(1.0, 0.82, 0.55)
	l.light_energy = 2.6
	l.omni_range = 13.0
	body.add_child(l)
	_amb_light(l)
	add_child(body)

func _build_scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404 if map_id == "forest" else 505
	if map_id == "rubkhali":
		_build_desert_scatter(rng)
		return
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
			_amb_light(l)
			if _swap_model(body, "campfire", rng.randf() * TAU): # a campfire on the ground in place of the barrel
				sh.radius = 0.62; sh.height = 0.5
				cs.position.y = 0.25
				l.position.y = 0.9
				prop_glow(_last_model, Color(1.0, 0.62, 0.3), 2.6)
				campfires += 1
				campfire_points.append(p)
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

## Cover out in the dunes: wrecks, ruined walls, boulders, thorn bushes, old fences.
func _build_desert_scatter(rng: RandomNumberGenerator) -> void:
	for i in 7: # dead Land Cruisers
		var p := _free_spot(rng, 4.0)
		if p != Vector3.INF: _wreck(p, rng.randf() * TAU, rng)
	var mud: Material = _mat.mud
	for i in 11: # ruined compound walls: the best line-of-sight breakers out here
		var p := _free_spot(rng, 5.0)
		if p == Vector3.INF: continue
		var body := StaticBody3D.new()
		body.position = p
		body.rotation.y = rng.randf() * TAU
		var segs := rng.randi_range(2, 5)
		var ox := 0.0
		for k in segs:
			var length := rng.randf_range(2.4, 4.2)
			var h := rng.randf_range(1.3, 2.6)
			if rng.randf() < 0.25: # a gap you can run through
				ox += length
				continue
			_box(body, Vector3(length, h, 0.45), Vector3(ox + length / 2.0, h / 2.0, 0), mud, h > 2.0)
			_snow_cap(body, Vector3(length, h, 0.45), Vector3(ox + length / 2.0, h / 2.0, 0))
			ox += length
		add_child(body)
	for i in 16: # boulders big enough to hide behind
		var p := _free_spot(rng, 2.5)
		if p == Vector3.INF: continue
		var body := StaticBody3D.new()
		body.position = p
		body.rotation.y = rng.randf() * TAU
		var r := rng.randf_range(0.9, 1.8)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r; sm.height = r * rng.randf_range(1.2, 1.8); sm.radial_segments = 9; sm.rings = 5
		sm.material = _mat.sand_rock
		mi.mesh = sm
		mi.position.y = r * 0.35
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = r * 0.9
		cs.shape = sh
		cs.position.y = r * 0.35
		body.add_child(cs)
		add_child(body)
	for i in 22: # camel thorn
		var p := _free_spot(rng, 1.0)
		if p == Vector3.INF: continue
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(0.35, 0.7); sm.height = sm.radius * 1.1; sm.radial_segments = 7; sm.rings = 3
		sm.material = _flat(Color(0.18, 0.16, 0.08), 0.95)
		mi.mesh = sm
		mi.position = p + Vector3(0, sm.radius * 0.35, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	for i in 7: # fence runs left from old corrals
		var p := _free_spot(rng, 5.0)
		if p == Vector3.INF: continue
		var body := StaticBody3D.new()
		body.position = p
		body.rotation.y = rng.randf() * TAU
		for sgm in rng.randi_range(2, 4):
			var ox2 := sgm * 3.0
			_box(body, Vector3(3.0, 1.25, 0.14), Vector3(ox2, 0.6, 0), _mat.wood)
			_mesh_box(body, Vector3(0.18, 1.5, 0.2), Vector3(ox2 - 1.5, 0.75, 0), _mat.wood)
		add_child(body)
	for i in 4: # a couple of crates near the camps
		var p := _free_spot(rng, 1.5)
		if p == Vector3.INF: continue
		var body := StaticBody3D.new()
		body.position = p
		body.rotation.y = rng.randf() * TAU
		_box(body, Vector3(0.95, 0.95, 0.95), Vector3(0, 0.47, 0), _mat.wood)
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

## Every doorway gets a leaf that starts open, so the map plays as it always has until
## somebody swings one shut. Tent fronts have no door.
func _build_doors() -> void:
	var leaf := _flat(Color(0.26, 0.15, 0.08), 0.75)
	for i in door_points.size():
		var dp: Array = door_points[i]
		if map_id == "rubkhali" and i < tents: # the tents are open at the front
			door_nodes.append(null)
			continue
		var taken := false # a doorway that already holds a pallet keeps the pallet
		for pp in pallet_points:
			if (pp[0] as Vector3).distance_to(dp[0]) < 0.5:
				taken = true
				break
		if taken:
			door_nodes.append(null)
			continue
		var yaw: float = dp[1]
		var hinge := Node3D.new()
		hinge.position = (dp[0] as Vector3) + Basis(Vector3.UP, yaw) * Vector3(-0.63, 0, 0)
		var body := StaticBody3D.new()
		_box(body, Vector3(1.24, 2.1, 0.07), Vector3(0.62, 1.07, 0), leaf)
		_mesh_box(body, Vector3(0.09, 0.09, 0.2), Vector3(1.1, 1.05, 0.12), _mat.metal) # handle
		hinge.add_child(body)
		hinge.rotation.y = yaw - 1.75 # open
		add_child(hinge)
		door_nodes.append({"hinge": hinge, "yaw": yaw, "shut": false})

func set_door(i: int, shut: bool) -> void:
	if i < 0 or i >= door_nodes.size(): return
	var d = door_nodes[i]
	if d == null or bool(d.shut) == shut: return
	d.shut = shut
	var tw := create_tween()
	tw.tween_property(d.hinge, "rotation:y", float(d.yaw) if shut else float(d.yaw) - 1.75, 0.45).set_trans(Tween.TRANS_SINE)

## The blackout event: every street and house light goes dark, and the night closes in.
func set_blackout(on: bool) -> void:
	if on == blackout: return
	blackout = on
	if env == null: return
	var tw := create_tween()
	tw.tween_property(env, "ambient_light_energy", (0.45 if on else 1.0) * _amb_base, 1.2)
	for m in garage_panels: # the strip lights go dead with everything else
		tw.parallel().tween_property(m, "emission_energy_multiplier", 0.05 if on else 3.2, 1.0)
	if map_id == "rubkhali": # broad daylight: what hits you is a wall of sand, not the dark
		tw.parallel().tween_property(env, "fog_density", fog_base * (2.3 if on else 1.0), 1.2)

## The heavy-fog event, 0..1.
func set_fog(level: float) -> void:
	if env == null: return
	fog_boost = clampf(level, 0.0, 1.0)
	env.fog_density = fog_base * lerpf(1.0, 3.4, fog_boost)

func set_killer_at(p: Vector3) -> void:
	killer_at = p

## Where the call to prayer comes from: the minaret on the fareej, otherwise far out on the edge.
func adhan_point() -> Vector3:
	if map_id == "fareej": return Vector3(-4.3, 13.0, 30.3)
	var p := Vector2(-HALF + 26.0, HALF - 26.0)
	return Vector3(p.x, height(p.x, p.y) + 12.0, p.y)

func set_hatch(i: int) -> void:
	for k in hatch_nodes.size(): hatch_nodes[k].visible = k == i

func in_market(pos: Vector3) -> bool:
	if market.is_empty(): return false
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
	var sun_map: bool = map_id == "rubkhali" # out there it is the sun that turns on you
	tw.tween_property(moon, "light_color", (Color(1.0, 0.36, 0.2) if sun_map else Color(1.0, 0.42, 0.36)) if on
		else (Color(1.0, 0.91, 0.74) if sun_map else Color(0.55, 0.65, 0.95)), d)
	tw.tween_property(env, "ambient_light_color", (Color(0.44, 0.21, 0.14) if sun_map else Color(0.3, 0.17, 0.19)) if on
		else (Color(0.72, 0.6, 0.44) if sun_map else Color(0.16, 0.2, 0.32)), d)
	tw.tween_property(env, "fog_light_color", (Color(0.42, 0.15, 0.08) if sun_map else Color(0.14, 0.05, 0.05)) if on
		else (Color(0.76, 0.6, 0.38) if sun_map else Color(0.07, 0.09, 0.14)), d)

## The player's «السطوع» on top of the map's own exposure.
func _apply_look() -> void:
	if env: env.tonemap_exposure = _exp_base * Gfx.brightness

# 0..1: the moon swells as it falls toward the map (drives the sky shader and the moonlight)
func set_moon_near(v: float) -> void:
	if _sky_mat == null: return
	_sky_mat.set_shader_parameter("near", clampf(v, 0.0, 1.0))
	if _blood and v > 0.03: moon.light_energy = _moon_base + 2.2 * v * v

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
		_snow_cap(body, Vector3(w + 0.5, 0.25, d + 0.5), Vector3(0, y0 + H + 0.12, 0))
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
			_amb_light(l, true)
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
		if map_id in ["fareej", "rubkhali"]: meshes.append([_palm_mesh(v, true), _palm_mesh(v, false)])
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
	if map_id == "rubkhali": # the storm: coarse sand blowing past, not quiet dust motes
		pm.emission_box_extents = Vector3(16, 6, 16)
		pm.gravity = Vector3(2.6, -0.35, 1.1)
		pm.initial_velocity_min = 1.4; pm.initial_velocity_max = 3.4
		q.size = Vector2(0.16, 0.035) # streaks, not dots: they read as blowing sand
		dm.albedo_color = Color(0.88, 0.76, 0.52, 0.34)
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
	if theme == "snow": # the falling-leaves system becomes snow
		lp.gravity = Vector3(0.35, -0.75, 0.15)
		lp.initial_velocity_min = 0.05; lp.initial_velocity_max = 0.3
		lp.angular_velocity_min = -40.0; lp.angular_velocity_max = 40.0
		lp.scale_min = 0.6; lp.scale_max = 1.6
		lq.size = Vector2(0.07, 0.07)
		lm.albedo_color = Color(0.97, 0.98, 1.0)
		lm.albedo_texture = NFUI.soft_dot()
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	elif theme == "halloween":
		lm.albedo_color = Color(0.45, 0.17, 0.03)
	leaves.lifetime = 9.0 if theme == "snow" else 7.0
	leaves.preprocess = leaves.lifetime
	leaves.visibility_aabb = AABB(Vector3(-22, -14, -22), Vector3(44, 26, 44))
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	leaves.emitting = map_id != "garage" # nothing falls from the sky under a concrete slab
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
## Which high-end look this map gets (NFLook.apply).
func look_kind() -> String:
	if map_id == "rubkhali": return "day"
	if map_id == "garage": return "garage"
	return "fog" if theme == "fog" else "night"

func _apply_quality() -> void:
	var fx := Gfx.eff_effects()
	var sh := Gfx.eff_shadows()
	env.glow_enabled = fx >= 1
	NFLook.apply(env, look_kind())
	if dust:
		var da: int = [40, 90, 160][fx]
		if map_id == "rubkhali": da = [90, 170, 280][fx] # the storm needs grains, not motes
		if dust.amount != da: dust.amount = da
		var la: int = ([40, 90, 170][fx]) if theme == "snow" else [12, 25, 45][fx]
		if leaves.amount != la: leaves.amount = la
	var factor: float = [0.4, 0.7, 1.0][fx]
	var rng: float = [22.0, 30.0, 38.0][fx]
	if Gfx.maxed(): rng = 62.0 # strong devices: the grass runs out much further away
	for i in grass_nodes.size():
		grass_nodes[i].multimesh.visible_instance_count = int(grass_counts[i] * factor)
		grass_nodes[i].visibility_range_end = rng + GRASS_CHUNK * 0.7
	for mi in garage_detail: # the yellow kerbs and wheel stops are the only heavy geometry down there
		(mi as MultiMeshInstance3D).visible = fx >= 1
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if sh == 0 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = [30.0, 50.0, 70.0][sh]
	if Gfx.maxed(): # four cascades: crisp shadows close by and shadows twice as far out
		moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		moon.directional_shadow_max_distance = 100.0 # the fog swallows anything further

func _process(_dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if not animals.is_empty(): _step_animals(_dt)
	for i in amb_lights.size():
		var e: Array = amb_lights[i]
		var l: OmniLight3D = e[0]
		var want := 0.0 if blackout else 1.0
		# a house light shies away when the killer is almost on top of it
		if want > 0.0 and bool(e[2]) and killer_at.distance_to(l.global_position) < 25.0: want = 0.12
		e[4] = move_toward(float(e[4]), want, _dt * 2.5)
		var f := 1.0
		if bool(e[3]): f = 0.75 + 0.25 * noise.get_noise_1d(t * 220.0 + i * 50.0) + 0.1 * sin(t * 13.0 + i)
		l.light_energy = float(e[1]) * f * float(e[4])
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

# ---------------- the Empty Quarter: bedouin tents, mud houses, wrecks, animals ----------------
## A thin white slab on top of a roof while the snow theme is on.
func _snow_cap(parent: Node3D, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	if theme != "snow": return
	snow_caps += 1
	_mesh_box(parent, Vector3(size.x, 0.1, size.z), pos + Vector3(0, size.y / 2.0 + 0.05, 0), _flat(Color(0.93, 0.96, 1.0), 0.75), rot)

## بيت شعر: a long dark woven tent, open at the front, with a locker and a rug inside.
func _build_tent(body: StaticBody3D, w: float, d: float, H: float, y0: float) -> void:
	var cloth: Material = _mat.cloth
	var ridge := H + 1.1
	_box(body, Vector3(w + 0.6, 0.18, d + 0.6), Vector3(0, y0 - 0.09, 0), _flat(Color(0.75, 0.62, 0.42), 0.95)) # sand floor pad
	_box(body, Vector3(w, H, 0.14), Vector3(0, y0 + H / 2.0, -d / 2.0), cloth, true)                 # back
	_box(body, Vector3(0.14, H, d), Vector3(w / 2.0, y0 + H / 2.0, 0), cloth, true)                  # right
	_wall_with_gap(body, false, -w / 2.0, -d / 2.0, d / 2.0, -0.7, 0.7, y0, H, 0.9, 2.0, cloth, 0.14) # left, with a gap to vault
	for sx in [-1.0, 1.0]: # the front stays open, just two poles and a short valance
		_mesh_box(body, Vector3(0.14, ridge, 0.14), Vector3(sx * (w / 2.0 - 0.2), y0 + ridge / 2.0, d / 2.0), _mat.wood)
	_mesh_box(body, Vector3(w, 0.5, 0.1), Vector3(0, y0 + H + 0.75, d / 2.0), cloth)
	_mesh_box(body, Vector3(0.16, ridge + 0.3, 0.16), Vector3(0, y0 + (ridge + 0.3) / 2.0, 0), _mat.wood) # centre pole
	for sz in [-1.0, 1.0]: # two sloping roof panels meeting at the ridge
		_box(body, Vector3(w + 0.5, 0.1, d / 2.0 + 0.6), Vector3(0, y0 + (ridge + H) / 2.0 - 0.1, sz * (d / 4.0 + 0.1)),
			cloth, true, Vector3(sz * -0.42, 0, 0))
	_snow_cap(body, Vector3(w + 0.5, 0.1, d / 2.0), Vector3(0, y0 + ridge - 0.35, 0))
	# rug, cushions and a cold fire pit
	_mesh_box(body, Vector3(w - 1.6, 0.04, d - 2.2), Vector3(0, y0 + 0.03, 0.3), _flat(Color(0.33, 0.1, 0.08), 0.95))
	for cx in [-1.6, -0.5, 0.6, 1.7]:
		_mesh_box(body, Vector3(0.75, 0.3, 0.5), Vector3(cx, y0 + 0.15, -d / 2.0 + 0.9), _flat(Color(0.42, 0.15, 0.1), 0.9))
	var pit := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.55; pc.bottom_radius = 0.6; pc.height = 0.18; pc.radial_segments = 10
	pc.material = _mat.rock
	pit.mesh = pc
	pit.position = Vector3(0, y0 + 0.09, d / 2.0 - 1.3)
	body.add_child(pit)
	var ember := OmniLight3D.new() # a few embers left: just enough to read the inside
	ember.position = Vector3(0, y0 + 0.5, d / 2.0 - 1.3)
	ember.light_color = Color(1.0, 0.5, 0.2)
	ember.light_energy = 1.1
	ember.omni_range = 6.0
	body.add_child(ember)
	_amb_light(ember, true)
	if _swap_model(body, "tent"): # the owner's crimson tent over the same walls (collision unchanged)
		_last_model.position.y = y0 - 0.05
		prop_glow(_last_model, Color(1.0, 0.45, 0.3), 2.0) # its lanterns
		ember.position.y = y0 + 1.6
		ember.light_energy = 1.6
		tent_models += 1

## A small mud-brick house: thick walls, one door, one window to vault, a flat roof.
func _build_mud_house(body: StaticBody3D, w: float, d: float, H: float, y0: float) -> void:
	var mud: Material = _mat.mud
	_box(body, Vector3(w + 0.5, 0.3, d + 0.5), Vector3(0, y0 - 0.15, 0), mud)
	_box(body, Vector3(w, H, 0.4), Vector3(0, y0 + H / 2.0, -d / 2.0), mud, true)
	_box(body, Vector3(0.4, H, d), Vector3(w / 2.0, y0 + H / 2.0, 0), mud, true)
	_wall_with_gap(body, false, -w / 2.0, -d / 2.0, d / 2.0, -0.7, 0.7, y0, H, 1.0, 2.1, mud, 0.4)
	_wall_with_gap(body, true, d / 2.0, -w / 2.0, w / 2.0, -0.65, 0.65, y0, H, 0.0, 2.2, mud, 0.4)
	_box(body, Vector3(w + 0.6, 0.3, d + 0.6), Vector3(0, y0 + H + 0.15, 0), mud)
	for side in [[0.0, d / 2.0 + 0.2, w + 0.6, 0.25], [0.0, -d / 2.0 - 0.2, w + 0.6, 0.25], [w / 2.0 + 0.2, 0.0, 0.25, d + 0.6], [-w / 2.0 - 0.2, 0.0, 0.25, d + 0.6]]:
		_mesh_box(body, Vector3(side[2], 0.5, side[3]), Vector3(side[0], y0 + H + 0.55, side[1]), mud)
	_snow_cap(body, Vector3(w + 0.6, 0.3, d + 0.6), Vector3(0, y0 + H + 0.15, 0))
	for k in 5: # palm-trunk beams poking out under the roof, like a real mud house
		_mesh_box(body, Vector3(0.16, 0.16, d + 1.4), Vector3(-w / 2.0 + 0.9 + k * (w - 1.8) / 4.0, y0 + H - 0.1, 0), _mat.bark)
	_mesh_box(body, Vector3(1.5, 0.16, 0.5), Vector3(0, y0 + 2.3, d / 2.0), _mat.bark) # door lintel
	var l := OmniLight3D.new()
	l.position = Vector3(0, y0 + H - 0.6, 0)
	l.light_color = Color(1.0, 0.72, 0.4)
	l.light_energy = 1.4
	l.omni_range = 7.0
	body.add_child(l)
	_amb_light(l, true)

## A campfire out in front of a bedouin tent, on the sand (the open front faces +z).
func _desert_fire(tent: Node3D, d: float) -> void:
	var at: Vector3 = tent.position + Basis(Vector3.UP, tent.rotation.y) * Vector3(0.6, 0, d / 2.0 + 4.2) # clear of the guy ropes
	at.y = _raw_h(at.x, at.z)
	var body := StaticBody3D.new()
	body.position = at
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.62; sh.height = 0.5
	cs.shape = sh
	cs.position.y = 0.25
	body.add_child(cs)
	var l := OmniLight3D.new()
	l.position = Vector3(0, 0.9, 0)
	l.light_color = Color(1.0, 0.5, 0.2)
	l.light_energy = 1.6
	l.omni_range = 8.0
	body.add_child(l)
	_amb_light(l)
	if _swap_model(body, "campfire", float(campfires) * 2.1):
		prop_glow(_last_model, Color(1.0, 0.62, 0.3), 2.6)
		campfires += 1
		campfire_points.append(at)
	add_child(body)

func _build_rubkhali() -> void:
	var idx := 0
	for b in buildings:
		var w: float = b[3]; var d: float = b[4]; var H: float = b[5]
		var body := StaticBody3D.new()
		body.name = ("Tent%d" % idx) if idx < tents else ("MudHouse%d" % idx)
		body.position = Vector3(b[0], _raw_h(b[0], b[1]), b[1])
		body.rotation.y = b[2]
		if idx < tents: _build_tent(body, w, d, H, 0.1)
		else: _build_mud_house(body, w, d, H, 0.1)
		add_child(body)
		if idx < 3 and idx < tents: _desert_fire(body, d) # the first three tents keep a fire going outside
		idx += 1

## A dead Land Cruiser, half swallowed by the dune it stopped on.
func _wreck(at: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	_blob(at, 2.8)
	wrecks += 1
	var body := StaticBody3D.new()
	body.position = at - Vector3(0, 0.42, 0) # sunk into the sand
	body.rotation = Vector3(rng.randf_range(-0.07, 0.07), yaw, rng.randf_range(-0.1, 0.1))
	var paint := _flat(Color(0.52, 0.47, 0.38).darkened(rng.randf_range(0.0, 0.25)), 0.85, 0.2)
	var dark := _flat(Color(0.02, 0.02, 0.025), 0.4)
	_box(body, Vector3(2.0, 1.0, 4.8), Vector3(0, 0.85, 0), paint)       # chassis
	_box(body, Vector3(1.9, 1.0, 2.9), Vector3(0, 1.8, -0.2), paint)     # cabin
	_mesh_box(body, Vector3(1.75, 0.75, 0.06), Vector3(0, 1.8, 1.24), dark)  # broken glass
	_mesh_box(body, Vector3(0.06, 0.7, 2.6), Vector3(0.96, 1.8, -0.2), dark)
	_mesh_box(body, Vector3(0.06, 0.7, 2.6), Vector3(-0.96, 1.8, -0.2), dark)
	_mesh_box(body, Vector3(1.8, 0.1, 2.4), Vector3(0, 2.35, -0.2), _mat.metal) # roof rack
	for rx in [-0.8, 0.8]:
		_mesh_box(body, Vector3(0.08, 0.22, 2.4), Vector3(rx, 2.45, -0.2), _mat.metal)
	_mesh_box(body, Vector3(2.0, 0.22, 0.3), Vector3(0, 1.05, 2.45), _mat.metal) # bumper
	var tire := _flat(Color(0.04, 0.04, 0.04), 0.9)
	var k := 0
	for wx in [-0.95, 0.95]:
		for wz in [-1.5, 1.5]:
			k += 1
			if k == 2 or (k == 3 and rng.randf() < 0.5): continue # missing wheels, lying in the sand
			var wh := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.42; cyl.bottom_radius = 0.42; cyl.height = 0.3; cyl.radial_segments = 10
			cyl.material = tire
			wh.mesh = cyl
			wh.rotation.z = PI / 2.0
			wh.position = Vector3(wx, 0.42, wz)
			body.add_child(wh)
	_snow_cap(body, Vector3(1.9, 1.0, 2.9), Vector3(0, 1.8, -0.2))
	if _swap_model(body, "car", 0.0, 1.0): # the owner's Land Cruiser, half buried like the wreck was
		_last_model.position.y = 0.12
		car_models += 1
	add_child(body)

## Low-poly animal built as a single merged mesh: one draw call, no bones, no collision.
func _animal_mesh(kind: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var camel := kind == "camel"
	var hide := _flat(Color(0.52, 0.38, 0.22) if camel else Color(0.3, 0.19, 0.11), 0.95)
	var add := func(size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
		var bm := BoxMesh.new()
		bm.size = size
		st.append_from(bm, 0, Transform3D(Basis.from_euler(rot), pos))
	var leg_y: float = 1.15 if camel else 0.78
	var body_y: float = leg_y + (0.55 if camel else 0.42)
	add.call(Vector3(0.78, 1.0, 2.3) if camel else Vector3(0.68, 0.84, 2.0), Vector3(0, body_y, 0))
	if camel: # hump
		var hm := SphereMesh.new()
		hm.radius = 0.52; hm.height = 0.85; hm.radial_segments = 10; hm.rings = 5
		st.append_from(hm, 0, Transform3D(Basis(), Vector3(0, body_y + 0.6, -0.1)))
	add.call(Vector3(0.42, 1.25, 0.42) if camel else Vector3(0.4, 0.8, 0.5),
		Vector3(0, body_y + (0.75 if camel else 0.5), 1.0), Vector3(-0.5 if camel else -0.75, 0, 0))
	add.call(Vector3(0.34, 0.34, 0.75) if camel else Vector3(0.32, 0.4, 0.8),
		Vector3(0, body_y + (1.35 if camel else 0.85), 1.5 if camel else 1.35), Vector3(0.35, 0, 0))
	for lx in [-0.3, 0.3]:
		for lz in [-0.8, 0.85]:
			add.call(Vector3(0.2, leg_y, 0.22), Vector3(lx, leg_y / 2.0, lz))
	add.call(Vector3(0.12, 0.7, 0.12), Vector3(0, body_y + 0.1, -1.15), Vector3(0.6, 0, 0)) # tail
	var mesh := st.commit()
	mesh.surface_set_material(0, hide)
	return mesh

func _build_animals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 616
	var meshes := {"horse": _animal_mesh("horse"), "camel": _animal_mesh("camel")}
	for i in 9:
		var kind := "camel" if i % 3 == 0 else "horse"
		var start := _free_spot(rng, 4.0)
		if start == Vector3.INF: continue
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[kind]
		mi.position = start
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = 95.0 # the storm hides them long before this
		add_child(mi)
		var path: Array[Vector3] = [start]
		var p := Vector2(start.x, start.z)
		for k in 3: # a small loop of waypoints around where it started
			p += Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(9.0, 20.0)
			p.x = clampf(p.x, -WALL + 10.0, WALL - 10.0)
			p.y = clampf(p.y, -WALL + 10.0, WALL - 10.0)
			path.append(Vector3(p.x, height(p.x, p.y), p.y))
		var stand: bool = kind == "camel" and rng.randf() < 0.5
		animals.append({"node": mi, "path": path, "i": 1, "speed": rng.randf_range(0.7, 1.15),
			"bob": rng.randf() * TAU, "stand": stand, "yaw": rng.randf() * TAU})
		mi.rotation.y = animals[-1].yaw

## Horses and camels plod between their waypoints. No sound, no collision: they are scenery.
func _step_animals(dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for a in animals:
		var mi: MeshInstance3D = a.node
		var base: float = height(mi.position.x, mi.position.z)
		if a.stand:
			mi.position.y = base + 0.02 * sin(t * 0.7 + a.bob)
			mi.rotation.y = a.yaw + 0.05 * sin(t * 0.3 + a.bob)
			continue
		var target: Vector3 = a.path[a.i]
		var to := Vector3(target.x - mi.position.x, 0, target.z - mi.position.z)
		if to.length() < 1.2:
			a.i = (a.i + 1) % a.path.size()
			continue
		var want := atan2(to.x, to.z)
		a.yaw = lerp_angle(a.yaw, want, 1.6 * dt)
		mi.rotation.y = a.yaw
		var step: Vector3 = Vector3(sin(a.yaw), 0, cos(a.yaw)) * float(a.speed) * dt
		mi.position += step
		mi.position.y = base + 0.06 * absf(sin(t * 3.4 + a.bob)) # plodding bob
		mi.rotation.x = 0.03 * sin(t * 3.4 + a.bob)

# ---------------- snow and halloween dressing ----------------
## A carved pumpkin with a candle inside.
func _pumpkin(at: Vector3, yaw: float) -> void:
	pumpkins += 1
	var root := Node3D.new()
	root.position = at
	root.rotation.y = yaw
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.34; sm.height = 0.5; sm.radial_segments = 12; sm.rings = 6
	sm.material = _flat(Color(0.75, 0.28, 0.04), 0.75)
	body.mesh = sm
	body.position.y = 0.25
	root.add_child(body)
	_mesh_box(root, Vector3(0.07, 0.18, 0.07), Vector3(0, 0.54, 0), _flat(Color(0.18, 0.22, 0.08), 0.9))
	var face := _flat(Color(1.0, 0.55, 0.12), 0.4, 0.0, 6.0) # the carving glows
	_mesh_box(root, Vector3(0.1, 0.1, 0.06), Vector3(-0.12, 0.3, 0.3), face, Vector3(0, 0, 0.6))
	_mesh_box(root, Vector3(0.1, 0.1, 0.06), Vector3(0.12, 0.3, 0.3), face, Vector3(0, 0, -0.6))
	_mesh_box(root, Vector3(0.26, 0.07, 0.06), Vector3(0, 0.16, 0.31), face)
	var l := OmniLight3D.new()
	l.position = Vector3(0, 0.3, 0.15)
	l.light_color = Color(1.0, 0.5, 0.12)
	l.light_energy = 1.0
	l.omni_range = 4.5
	root.add_child(l)
	_amb_light(l)
	add_child(root)

## A cobweb: two translucent triangles tucked into a corner.
func _cobweb(at: Vector3, yaw: float, size: float) -> void:
	webs += 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.86, 0.9, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for tri in [[Vector3.ZERO, Vector3(size, 0, 0), Vector3(0, -size, 0)], [Vector3.ZERO, Vector3(0, -size, 0), Vector3(0, 0, size)]]:
		for v in tri:
			st.set_uv(Vector2(0.5, 0.5))
			st.add_vertex(v)
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _build_theme_props() -> void:
	if theme != "halloween": return
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	for b in buildings: # a lit pumpkin beside every front door, and webs under the eaves
		var front := _local(b, Vector3(b[3] / 2.0 - 1.0, 0, b[4] / 2.0 + 0.9))
		_pumpkin(front, b[2] + rng.randf_range(-0.4, 0.4))
		_cobweb(_local(b, Vector3(-b[3] / 2.0 + 0.3, b[5] - 0.3, b[4] / 2.0 - 0.3)), b[2], 1.1)
		_cobweb(_local(b, Vector3(b[3] / 2.0 - 0.3, b[5] - 0.3, b[4] / 2.0 - 0.3)), b[2] + PI / 2.0, 0.9)
	for i in 10: # pumpkins out in the open, marking paths
		var p := _free_spot(rng, 1.5)
		if p == Vector3.INF: continue
		_pumpkin(p, rng.randf() * TAU)
	for hp in hook_points: # webs on the hooks
		_cobweb(hp + Vector3(0, 3.0, 0), rng.randf() * TAU, 1.0)

# ---------------- «الشاطئ»: the lagoon beach ----------------
## The model (assets/maps/beach.glb, de-quantized by tools/dequant_glb.py) is a five-metre
## diorama: one palm, a wet-sand tile, a lagoon tile, shells and a creeper. The map keeps the
## palms, the shells and the wet sand and builds everything else — the sand, the sea, the huts —
## the way the other maps do. Each piece of the model becomes one MultiMesh, so a hundred palms
## cost fifteen draw calls.
const BEACH_SHORE := 42.0   # where the dry sand gives way to the water
const BEACH_WATER := -0.55  # the surface of the lagoon

func _beach_group(name: String) -> Array:
	var out := []
	var src := (load("res://assets/maps/beach.glb") as PackedScene).instantiate()
	for g in src.find_children("*", "Node3D", true, false):
		if not str(g.name).begins_with(name): continue
		for mi in g.find_children("*", "MeshInstance3D", true, false):
			out.append([(mi as MeshInstance3D).mesh, g.transform.affine_inverse() * (mi as MeshInstance3D).transform])
		break
	src.queue_free()
	return out

## Drop one piece of the model at every transform given, as one MultiMesh per sub-mesh.
func _beach_scatter(group: String, places: Array, shadow := false) -> void:
	var parts := _beach_group(group)
	for part in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = places.size()
		for i in places.size():
			mm.set_instance_transform(i, (places[i] as Transform3D) * (part[1] as Transform3D))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.name = "Beach_%s_%d" % [group, parts.find(part)]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

func _build_beach() -> void:
	_build_buildings() # the huts, the doors, the lockers: same bones as every other map
	var rng := RandomNumberGenerator.new()
	rng.seed = 8899
	# ---- the lagoon ----
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.06, 0.22, 0.26, 0.78)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.metallic = 0.35
	water.roughness = 0.08
	water.normal_enabled = true
	water.normal_texture = _noise_tex(0.08, 256, true)
	water.normal_scale = 0.45
	water.uv1_scale = Vector3(0.06, 0.06, 0.06)
	water.uv1_triplanar = true
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE, SIZE)
	pm.material = water
	sea.mesh = pm
	sea.position = Vector3(0, BEACH_WATER, BEACH_SHORE + SIZE / 2.0 - 10.0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	var deep := StaticBody3D.new() # you can wade in, you cannot swim out
	deep.name = "Lagoon"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(SIZE, 14.0, 4.0)
	cs.shape = bs
	cs.position = Vector3(0, 5.0, BEACH_SHORE + 9.0) # wade in knee-deep, no further
	deep.add_child(cs)
	add_child(deep)
	# ---- palms: clusters on the dry sand, a few leaning over the water ----
	var palms := []
	for i in 90:
		var p := _free_spot(rng, 2.6)
		if p == Vector3.INF: continue
		if p.z > BEACH_SHORE + 2.0: continue
		var sc: float = rng.randf_range(0.85, 1.35)
		palms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)),
			Vector3(p.x, height(p.x, p.z) - 0.1, p.z)))
	_beach_scatter("002-coconut-palm", palms, true)
	beach_palms = palms.size()
	# ---- shells along the shoreline (the model's wet-sand tile is a flat pale square: it reads
	# as a sheet of paper on the beach, so the shoreline is the foam line below instead) ----
	var shells := []
	for i in 46:
		var x := rng.randf_range(-WALL + 10.0, WALL - 10.0)
		var z: float = BEACH_SHORE + rng.randf_range(-14.0, 4.0)
		shells.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.8)),
			Vector3(x, height(x, z) + 0.07, z)))
	_beach_scatter("004-shell-scatter", shells)
	beach_props = shells.size()
	# ---- a line of foam where the water meets the sand ----
	var foam := _flat(Color(0.75, 0.86, 0.88, 0.5), 0.4)
	foam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in 26:
		var fx: float = -WALL + 8.0 + i * (WALL * 2.0 - 16.0) / 25.0
		var fz: float = BEACH_SHORE - 1.5 + sin(fx * 0.05) * 2.5
		_mesh_box(self, Vector3(10.0, 0.06, 1.6), Vector3(fx, BEACH_WATER + 0.12, fz), foam)

# ---------------- «المواقف»: the car park under the apartment block ----------------
## assets/maps/carpark.glb is one 30 x 20 m module with a 3 m ceiling, split into named
## pieces by tools/split_glb.py (CC0 model by Innerscene Corp). The map repeats the module
## in a grid and leaves a wall or a stair core out here and there, so the bays join into one
## floor you can run around. Everything is scaled up 1.4 so a hook, a car and a running
## survivor all fit under the slab.
const GAR_W := 30.0   # module size in the model's own units
const GAR_D := 20.0
const GAR_H := 3.0
const GAR_S := 1.4    # scale applied to the whole thing
const GAR_COLS := 5
const GAR_ROWS := 7
const GAR_COL_X := [7.5, 15.0, 22.5, 30.0] # the columns inside a module
const GAR_COL_Z := [-9.0, -15.0]
const GAR_BAY_Z := [-17.6, -6.5]           # the two rows of parking bays
const GAR_AISLE_Z := -12.0                 # the driving aisle between them
const GAR_ROOF := GAR_H * GAR_S + 0.5      # the walking surface on top of the slab (4.7 m)
const GAR_RAMP_X := [78.0, 93.0]           # the car ramp up to the roof, in world metres
const GAR_RAMP_Z := [-14.0, 14.0]

## The world position of a module's own origin (its north-west corner, floor level).
func _gar_origin(c: int, r: int) -> Vector3:
	return Vector3(-GAR_W * GAR_S * GAR_COLS / 2.0 + c * GAR_W * GAR_S, 0.0,
		-GAR_D * GAR_S * GAR_ROWS / 2.0 + (r + 1) * GAR_D * GAR_S)

## A point given in module coordinates -> the world.
func _gar(c: int, r: int, mx: float, mz: float, my := 0.0) -> Vector3:
	return _gar_origin(c, r) + Vector3(mx, my, mz) * GAR_S

func _gar_solid(c: int, r: int, x0: float, x1: float, z0: float, z1: float) -> void:
	var a := _gar(c, r, x0, z0)
	var b := _gar(c, r, x1, z1)
	garage_solids.append([minf(a.x, b.x), maxf(a.x, b.x), minf(a.z, b.z), maxf(a.z, b.z)])

## Nothing solid within `pad` of this spot (and inside the floor, not out by the wall).
func _gar_free(x: float, z: float, pad: float) -> bool:
	var ex: float = GAR_W * GAR_S * GAR_COLS / 2.0
	var ez: float = GAR_D * GAR_S * GAR_ROWS / 2.0
	if absf(x) > ex - pad or absf(z) > ez - pad: return false
	for s in garage_solids:
		if x > s[0] - pad and x < s[1] + pad and z > s[2] - pad and z < s[3] + pad: return false
	return true

## Take `n` spots out of `src` ([pos, yaw] rows): `gap` is how far they must stay from
## everything placed so far, `spread` how far they must stay from each other.
func _gar_pick(src: Array, n: int, spread: float, taken: Array, rng: RandomNumberGenerator, gap := 5.0) -> Array:
	var out := []
	for i in _shuffled(src.size(), rng):
		if out.size() >= n: break
		var e: Array = src[i]
		var ok := true
		for q in taken:
			if (q as Vector3).distance_to(e[0]) < gap:
				ok = false
				break
		if ok:
			for q in out:
				if (q[0] as Vector3).distance_to(e[0]) < spread:
					ok = false
					break
		if ok:
			taken.append(e[0])
			out.append(e)
	return out

## Which module has which pieces, and where the generators, hooks, lockers, pallets,
## hatches and vault barriers go. All of it comes from the room seed, like every other map.
func _plan_garage(rng: RandomNumberGenerator) -> void:
	garage_tiles.clear()
	garage_solids.clear()
	for r in GAR_ROWS:
		for c in GAR_COLS:
			var pieces := ["aisle", "paint", "cols", "detail"]
			var core: bool = c == 0 or (c * 3 + r * 2) % 7 == 3 # the west side plus a few inside
			if core: pieces.append_array(["core", "doors", "lift"])
			if r > 0 and (c + r) % 3 == 0: pieces.append("wall_s")
			# the model's "north_block" is its own ramp to the next storey: a slope that runs up
			# into the slab, walled in and solid. Nobody could ever climb it, so it is never placed;
			# the only way up is the real ramp to the roof (_build_garage_roof).
			garage_tiles.append({"c": c, "r": r, "pieces": pieces})
			for x in GAR_COL_X:
				for z in GAR_COL_Z: _gar_solid(c, r, x - 0.25, x + 0.25, z - 0.25, z + 0.25)
			if core: _gar_solid(c, r, -0.3, 5.1, -20.0, 0.0)
			if "wall_s" in pieces: _gar_solid(c, r, -0.3, 30.3, -20.35, -19.9)
	# the ramp up to the roof is a road, not a parking bay: keep everything off it before the
	# candidate spots are worked out
	garage_solids.append([GAR_RAMP_X[0] - 3.0, GAR_RAMP_X[1] + 3.0, GAR_RAMP_Z[0] - 8.0, GAR_RAMP_Z[1] + 4.0])
	# candidate spots: down the aisles, in the bays, and flat against a stair core
	var aisle := []
	var bays := []
	var walls := []
	for t in garage_tiles:
		var c: int = t.c
		var r: int = t.r
		for k in 5:
			var p := _gar(c, r, 4.0 + k * 5.5, GAR_AISLE_Z)
			if _gar_free(p.x, p.z, 1.6): aisle.append([p, PI / 2.0])
		for b in GAR_BAY_Z:
			for k in 6:
				var p := _gar(c, r, 2.5 + k * 5.0, b)
				if _gar_free(p.x, p.z, 1.8): bays.append([p, 0.0])
		if "core" in t.pieces:
			for k in 3:
				var p := _gar(c, r, 6.2, -3.5 - k * 6.5)
				if _gar_free(p.x, p.z, 1.0): walls.append([p, -PI / 2.0])
	var taken: Array = []
	for e in _gar_pick(bays + aisle, 6, 34.0, taken, rng, 6.0): gen_points.append(e[0])
	# the last generator is on the roof, out in the open, where everyone can see you working
	var roof_spots := [Vector3(-52.0, GAR_ROOF, -40.0), Vector3(46.0, GAR_ROOF, 44.0),
		Vector3(-60.0, GAR_ROOF, 52.0), Vector3(30.0, GAR_ROOF, -56.0)]
	gen_points.append(roof_spots[rng.randi() % roof_spots.size()])
	for e in _gar_pick(aisle, 9, 24.0, taken, rng, 6.0): hook_points.append(e[0])
	for e in _gar_pick(walls + bays, 10, 14.0, taken, rng, 5.0): locker_points.append(e)
	for e in _gar_pick(aisle, 9, 18.0, taken, rng, 5.0): pallet_points.append(e)
	for e in _gar_pick(bays, 5, 44.0, taken, rng, 5.0): hatch_points.append(e[0])
	# concrete crash barriers you can vault: the only vault spots down here
	for e in _gar_pick(aisle, 8, 22.0, taken, rng, 5.0):
		garage_barriers.append(e)
		window_points.append([e[0] + Vector3(0, 0.55, 0), Vector3(0, 0, 1).rotated(Vector3.UP, e[1])])
	# one hook on the roof, so a survivor downed up there does not have to be carried all the
	# way back down the ramp
	hook_points.append(Vector3(gen_points[6].x + 18.0, GAR_ROOF, gen_points[6].z - 14.0))
	# the gates: one on the ground floor as always, and one **on the roof** — the road out of
	# the building runs off the top of the slab
	gate_points.append([Vector3(0.0, 0.0, -WALL), 0.0])
	gate_points.append([Vector3(0.0, GAR_ROOF, WALL), PI])

func _build_garage() -> void:
	var src := (load("res://assets/maps/carpark.glb") as PackedScene).instantiate()
	var piece := {}
	for ch in src.get_children():
		if ch is MeshInstance3D: piece[str(ch.name)] = (ch as MeshInstance3D).mesh
	src.free()
	var lift := {"aisle": 0.012, "paint": 0.02, "detail": 0.004} # keep the paint off the slab
	var shadowed := ["core", "cols", "wall_s"]
	# one MultiMesh per piece per row of modules: a handful of draw calls, and a row is small
	# enough that the mobile renderer's eight lights per object still land where they should
	for r in GAR_ROWS:
		var rows := {}
		for t in garage_tiles:
			if int(t.r) != r: continue
			for name in t.pieces:
				if not rows.has(name): rows[name] = []
				rows[name].append(t)
		for name in rows:
			if not piece.has(name): continue
			var list: Array = rows[name]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = piece[name]
			mm.instance_count = list.size()
			for i in list.size():
				var t: Dictionary = list[i]
				mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(GAR_S, GAR_S, GAR_S)),
					_gar_origin(int(t.c), int(t.r)) + Vector3(0, float(lift.get(name, 0.0)), 0)))
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if name in shadowed else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			if name == "detail": garage_detail.append(mi)
	_build_garage_shell()
	_build_garage_lights()
	_build_garage_props()

## Collision for the columns, cores and walls, the slab overhead, and the outside wall.
func _build_garage_shell() -> void:
	var ceil_y := GAR_H * GAR_S
	for r in GAR_ROWS:
		var body := StaticBody3D.new()
		body.name = "GarageRow%d" % r
		for t in garage_tiles:
			if int(t.r) != r: continue
			var c: int = int(t.c)
			for x in GAR_COL_X:
				for z in GAR_COL_Z: _gar_block(body, c, r, x - 0.2, x + 0.2, z - 0.2, z + 0.2)
			if "core" in t.pieces: _gar_block(body, c, r, -0.25, 5.0, -20.0, 0.0)
			if "wall_s" in t.pieces: _gar_block(body, c, r, -0.2, 30.2, -20.25, -20.0)
		add_child(body)
	# the slab overhead, one strip per row so it is lit by that row's lamps. It is also the
	# roof you can walk on, so the strips the ramp comes up through are left open.
	var slab := StaticBody3D.new()
	slab.name = "GarageCeiling"
	var w: float = GAR_W * GAR_S * GAR_COLS
	var d: float = GAR_D * GAR_S
	for r in GAR_ROWS:
		var zc: float = -GAR_D * GAR_S * GAR_ROWS / 2.0 + (r + 0.5) * d
		if zc + d / 2.0 > GAR_RAMP_Z[0] and zc - d / 2.0 < GAR_RAMP_Z[1]: # the hole for the ramp
			var left: float = GAR_RAMP_X[0] - 1.0 + w / 2.0
			var right: float = w / 2.0 - (GAR_RAMP_X[1] + 1.0)
			_box(slab, Vector3(left, 0.5, d), Vector3(-w / 2.0 + left / 2.0, ceil_y + 0.25, zc), _mat.concrete, true)
			_box(slab, Vector3(right, 0.5, d), Vector3(w / 2.0 - right / 2.0, ceil_y + 0.25, zc), _mat.concrete, true)
			continue
		_box(slab, Vector3(w, 0.5, d), Vector3(0, ceil_y + 0.25, zc), _mat.concrete, true)
	add_child(slab)
	_build_garage_roof(w)
	# the outside wall of the level, with the two openings that lead to the gates
	var sides := StaticBody3D.new()
	sides.name = "GarageWall"
	var ex: float = w / 2.0
	var ez: float = GAR_D * GAR_S * GAR_ROWS / 2.0
	for sx in [-1.0, 1.0]:
		_box(sides, Vector3(0.5, ceil_y, ez * 2.0), Vector3(sx * ex, ceil_y / 2.0, 0), _mat.concrete, true)
	for sz in [-1.0, 1.0]:
		_wall_with_gap(sides, true, sz * ez, -ex, ex, -5.5, 5.5, 0.0, ceil_y, 0.0, ceil_y, _mat.concrete, 0.5)
	add_child(sides)

## The roof: the ramp up, the parapet round the edge, the bridge out to the gate, and the
## lamps along it. The slab itself is the floor up here (built in _build_garage_shell).
func _build_garage_roof(w: float) -> void:
	var ex: float = w / 2.0
	var ez: float = GAR_D * GAR_S * GAR_ROWS / 2.0
	var road := _flat(Color(0.16, 0.16, 0.17), 0.85)
	var body := StaticBody3D.new()
	body.name = "GarageRoof"
	# ---- the ramp: a long slope from the floor up through the hole in the slab ----
	var x0: float = GAR_RAMP_X[0]
	var x1: float = GAR_RAMP_X[1]
	# the slope starts four metres further back and a little under the floor, so you walk onto
	# it instead of stepping up onto a lip, and it lands exactly flush with the roof
	var z_foot: float = GAR_RAMP_Z[0] - 4.0
	var z_top: float = GAR_RAMP_Z[1]
	var y_foot := -0.6
	var run: float = z_top - z_foot
	var rise: float = GAR_ROOF - y_foot
	var slope := atan2(rise, run) # about nine degrees: a car ramp, you keep your speed on it
	var length := sqrt(run * run + rise * rise)
	var mid := Vector3((x0 + x1) / 2.0, (y_foot + GAR_ROOF) / 2.0 - 0.3, (z_foot + z_top) / 2.0)
	_box(body, Vector3(x1 - x0, 0.6, length), mid, road, false, Vector3(-slope, 0, 0))
	for sx in [-1.0, 1.0]: # kerbs, so you cannot walk off the side of the ramp
		_box(body, Vector3(0.5, 1.2, length), mid + Vector3(sx * (x1 - x0) / 2.0, 0.7, 0), _mat.concrete, false, Vector3(-slope, 0, 0))
	_mesh_box(body, Vector3(x1 - x0 - 1.0, 0.03, 0.5), Vector3(mid.x, 0.06, z_foot + 5.0), _flat(Color(0.75, 0.62, 0.1), 0.6)) # the yellow line at the foot
	# ---- the parapet round the roof, with the gaps the ramp and the bridge need ----
	for sx in [-1.0, 1.0]:
		_box(body, Vector3(0.45, 1.15, ez * 2.0), Vector3(sx * ex, GAR_ROOF + 0.57, 0), _mat.concrete)
	_wall_with_gap(body, true, -ez, -ex, ex, -1.0, 1.0, GAR_ROOF, 1.15, 0.0, 1.15, _mat.concrete, 0.45)
	_wall_with_gap(body, true, ez, -ex, ex, -5.0, 5.0, GAR_ROOF, 1.15, 0.0, 1.15, _mat.concrete, 0.45) # the way out
	# ---- the bridge from the roof to the gate ----
	var span: float = WALL - ez
	_box(body, Vector3(10.0, 0.6, span + 1.0), Vector3(0, GAR_ROOF - 0.3, ez + span / 2.0), road)
	for sx in [-1.0, 1.0]:
		_box(body, Vector3(0.4, 1.1, span), Vector3(sx * 5.0, GAR_ROOF + 0.55, ez + span / 2.0), _mat.concrete)
	for i in 4: # lamps along the bridge and the roof edge
		var lz: float = ez + 3.0 + i * (span / 4.0)
		_mesh_box(body, Vector3(0.14, 3.2, 0.14), Vector3(-4.4, GAR_ROOF + 1.6, lz), _mat.metal)
		_mesh_box(body, Vector3(0.4, 0.14, 0.5), Vector3(-4.4, GAR_ROOF + 3.2, lz + 0.3), _flat(Color(1.0, 0.85, 0.55), 0.5, 0.0, 3.0))
		var l := OmniLight3D.new()
		l.position = Vector3(-4.2, GAR_ROOF + 3.0, lz + 0.5)
		l.light_color = Color(1.0, 0.82, 0.55)
		l.light_energy = 2.2
		l.omni_range = 14.0
		l.shadow_enabled = false
		body.add_child(l)
		_amb_light(l)
	# a lamp at the top of the ramp and one at the bottom, so the way up reads at night
	for at in [Vector3((x0 + x1) / 2.0 - 9.0, 0.0, z_foot - 1.5), Vector3((x0 + x1) / 2.0 - 9.0, GAR_ROOF, z_top + 2.0)]:
		var l2 := OmniLight3D.new()
		l2.position = at + Vector3(0, 3.4, 0)
		l2.light_color = Color(0.95, 0.85, 0.6)
		l2.light_energy = 2.4
		l2.omni_range = 16.0
		l2.shadow_enabled = false
		body.add_child(l2)
		_amb_light(l2)
		_mesh_box(body, Vector3(0.14, 3.4, 0.14), at + Vector3(0, 1.7, 0), _mat.metal)
	# lamps spread over the deck, so the roof is somewhere you can see and be seen
	var deck := [Vector3(-70, 0, -62), Vector3(-24, 0, 34), Vector3(28, 0, -30), Vector3(64, 0, 58),
		Vector3(-78, 0, 44), Vector3(10, 0, 72)]
	for at in deck:
		var p := Vector3(at.x, GAR_ROOF, at.z)
		_mesh_box(body, Vector3(0.16, 4.0, 0.16), p + Vector3(0, 2.0, 0), _mat.metal)
		_mesh_box(body, Vector3(0.5, 0.14, 0.6), p + Vector3(0, 3.95, 0.3), _flat(Color(1.0, 0.85, 0.55), 0.5, 0.0, 3.0))
		var dl := OmniLight3D.new()
		dl.position = p + Vector3(0, 3.7, 0.4)
		dl.light_color = Color(1.0, 0.84, 0.6)
		dl.light_energy = 3.0
		dl.omni_range = 24.0
		dl.shadow_enabled = false
		body.add_child(dl)
		_amb_light(dl)
		_blob(p, 1.0)
	add_child(body)
	# the sign faces the driver coming up the ramp (they are looking toward +z)
	_sign_text(body, "السطح", Vector3((x0 + x1) / 2.0, 3.2, z_foot - 2.0), 90, Color(1.0, 0.85, 0.4), PI)

## The killer's car: on the garage it waits on the roof at the top of the ramp, everywhere else
## it is parked a few metres from where the killer starts, nose toward the middle of the map.
## Every phone runs the same search over the same seeded map, so they all put it in the same spot.
var gar_hulls := []

## Where parked car i stands, and which way it faces.
func parked_at(i: int) -> Vector3:
	var e: Dictionary = parked[i]
	return (e.node as Node3D).global_position if e.has("node") else e.at

func parked_yaw(i: int) -> float:
	var e: Dictionary = parked[i]
	return (e.node as Node3D).global_rotation.y if e.has("node") else e.yaw

## The parked car nearest to p within r metres (and 3 m up or down), or -1.
func nearest_parked(p: Vector3, r: float) -> int:
	var best := -1
	var bd := r
	for i in parked.size():
		var q := parked_at(i)
		if absf(q.y - p.y) > 3.0: continue
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		if d < bd:
			bd = d
			best = i
	return best

## The killer takes parked car i: the driving car moves into its spot and the parked car into the
## driving car's (so a car is left wherever she last parked). Every phone runs the same swap.
func take_parked(i: int) -> void:
	if drive_car == null or i < 0 or i >= parked.size(): return
	var to := parked_at(i)
	var to_yaw := parked_yaw(i)
	var from := drive_car.global_position
	var from_yaw := drive_car.rotation.y
	var e: Dictionary = parked[i]
	if e.has("node"):
		(e.node as Node3D).global_transform = Transform3D(Basis(Vector3.UP, from_yaw), from)
	else:
		(e.mm as MultiMesh).set_instance_transform(int(e.mi), Transform3D(Basis(Vector3.UP, from_yaw).scaled(Vector3.ONE * CAR_SCALE), from))
		(e.hull as CollisionShape3D).transform = Transform3D(Basis(Vector3.UP, from_yaw), from + Vector3(0, 0.8, 0))
		e.at = from
		e.yaw = from_yaw
	drive_car.put(to, to_yaw)

func _place_drive_car() -> void:
	var cands: Array = []
	if map_id == "garage":
		var rx: float = (GAR_RAMP_X[0] + GAR_RAMP_X[1]) / 2.0
		var top: float = GAR_RAMP_Z[1]
		for e in [[0.0, 9.0], [-7.0, 9.0], [7.0, 11.0], [0.0, 15.0], [-12.0, 14.0], [-20.0, 9.0], [-30.0, 20.0]]:
			cands.append([Vector3(rx + e[0], GAR_ROOF, top + e[1]), PI]) # nose toward the ramp, ready to drive down
	else:
		var k := spawn_point("killer", 0)
		var yaw := atan2(-k.x, -k.z)
		for ring in [6.0, 8.0, 10.0, 13.0, 16.0, 20.0, 25.0, 31.0, 38.0]:
			for a in 16:
				var p: Vector2 = Vector2(k.x, k.z) + Vector2.from_angle(a * TAU / 16.0) * ring
				cands.append([Vector3(p.x, height(p.x, p.y), p.y), yaw])
	var keep: Array = [] # stay clear of the objectives
	keep.append_array(gen_points)
	keep.append_array(hatch_points)
	keep.append_array(hook_points)
	for e in locker_points: keep.append(e[0])
	for e in pallet_points: keep.append(e[0])
	var pick: Array = []
	for c in cands:
		var p: Vector3 = c[0]
		if map_id != "garage":
			if absf(p.x) > WALL - 12.0 or absf(p.z) > WALL - 12.0: continue
			if map_id == "beach" and p.z > BEACH_SHORE - 6.0: continue
		var crowded := false
		for q in keep:
			if Vector2((q as Vector3).x - p.x, (q as Vector3).z - p.z).length() < 4.5 and absf((q as Vector3).y - p.y) < 3.0: crowded = true
		if crowded: continue
		# the nose toward the middle if the way is clear, otherwise the first heading that is:
		# the killer should be able to drive straight off, not reverse out from against a tree
		for turn in [0.0, 0.8, -0.8, 1.6, -1.6, 2.4, -2.4, PI]:
			var yaw: float = c[1] + turn
			if _car_room(p, yaw) and _car_lane(p, yaw):
				pick = [p, yaw]
				break
		if not pick.is_empty(): break
	if pick.is_empty():
		for c in cands:
			if _car_room(c[0], c[1]):
				pick = c
				break
	if pick.is_empty(): pick = cands[0]
	drive_car = NFCar.new()
	drive_car.name = "KillerCar"
	drive_car.position = pick[0] + Vector3(0, 0.05, 0)
	drive_car.rotation.y = pick[1]
	add_child(drive_car)
	var dust_col: Color = {"rubkhali": Color(0.78, 0.64, 0.45), "beach": Color(0.8, 0.72, 0.58),
		"forest": Color(0.36, 0.3, 0.24)}.get(map_id, Color(0.6, 0.54, 0.46))
	drive_car.setup(_model("car_drive") if _model("car_drive") else _model("car"), CAR_SCALE, _model("cabin"),
		dust_col, map_id != "garage") # the detailed one, wheels on axles; no dust off the car park's concrete

## Nothing solid in a car-sized box over this spot. The box starts 0.35 m above the ground, so
## ground that rises more than that under the car (a dune, a kerb, a step) counts as in the way.
func _car_room(p: Vector3, yaw: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.6, 2.0, 5.4)
	q.shape = bs
	q.transform = Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 0.35 + 1.0, 0))
	q.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

## Ten metres of open ground in front of the car (trees, rocks, walls and steep ground all count).
func _car_lane(p: Vector3, yaw: float) -> bool:
	var f := Vector3(sin(yaw), 0.0, cos(yaw))
	var mid := p + f * 8.0
	var gy := height(mid.x, mid.z) if map_id != "garage" else p.y
	var q := PhysicsShapeQueryParameters3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, 1.6, 10.0)
	q.shape = bs
	q.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, maxf(gy, p.y) + 0.7 + 0.8, mid.z))
	q.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

## The mesh of assets/props/car.glb with its material on the surface, for instancing (null if absent).
func _car_mesh() -> Mesh:
	var ps := _model("car")
	if ps == null: return null
	var inst := ps.instantiate()
	var src: MeshInstance3D = null
	for c in inst.find_children("*", "MeshInstance3D", true, false): src = c
	var m: Mesh = null
	if src:
		m = src.mesh
		if m.surface_get_material(0) == null: m.surface_set_material(0, src.get_active_material(0))
	inst.free()
	return m

## An empty coloured MultiMesh of one box, for the parked cars.
func _gar_cars(size: Vector3, mat: Material) -> MultiMesh:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bm
	return mm

func _gar_block(body: StaticBody3D, c: int, r: int, x0: float, x1: float, z0: float, z1: float) -> void:
	var a := _gar(c, r, x0, z0)
	var b := _gar(c, r, x1, z1)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(absf(b.x - a.x), GAR_H * GAR_S, absf(b.z - a.z))
	cs.shape = bs
	cs.position = Vector3((a.x + b.x) / 2.0, GAR_H * GAR_S / 2.0, (a.z + b.z) / 2.0)
	body.add_child(cs)

## Fluorescent strips under the slab: a glowing tube over most modules, a dead one here and
## there, and all of them go out with the blackout.
func _build_garage_lights() -> void:
	var tube := _flat(Color(0.86, 0.95, 1.0), 0.4, 0.0, 3.2)
	var dead := _flat(Color(0.3, 0.32, 0.33), 0.6)
	var y: float = GAR_H * GAR_S - 0.18
	for t in garage_tiles:
		var c: int = int(t.c)
		var r: int = int(t.r)
		var lit: bool = (c * 5 + r * 3) % 10 != 7 # one module in ten is dark: enough to hide in
		for k in 2:
			var at := _gar(c, r, 8.0 + k * 13.0, GAR_AISLE_Z, 0.0)
			at.y = y
			var strip := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(3.6, 0.12, 0.34)
			bm.material = tube if lit else dead
			strip.mesh = bm
			strip.position = at
			strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(strip)
		if not lit: continue
		garage_panels.append(tube)
		var l := OmniLight3D.new()
		l.position = _gar(c, r, 14.0, GAR_AISLE_Z) + Vector3(0, y - 0.2, 0)
		l.light_color = Color(0.82, 0.92, 1.0)
		l.light_energy = 3.3
		l.omni_range = 23.0
		l.shadow_enabled = false
		add_child(l)
		_amb_light(l)

## Parked cars in the bays, and the crash barriers survivors vault over. The cars are three
## MultiMeshes (body, cabin, wheels) with a colour per instance, so a hundred of them cost
## three draw calls; their collision is one box each.
func _build_garage_props() -> void:
	var cols := [Color(0.3, 0.1, 0.08), Color(0.12, 0.16, 0.22), Color(0.35, 0.33, 0.28),
		Color(0.1, 0.2, 0.14), Color(0.4, 0.4, 0.42), Color(0.22, 0.22, 0.24)]
	var spots := []
	var n := 0
	for t in garage_tiles:
		var c: int = int(t.c)
		var r: int = int(t.r)
		for bi in GAR_BAY_Z.size():
			for k in 12:
				n += 1
				if (c * 7 + r * 5 + k * 3 + bi) % 9 != 0: continue # most bays are empty at night
				var p := _gar(c, r, 1.25 + k * 2.5, GAR_BAY_Z[bi])
				if not _gar_free(p.x, p.z, 1.5): continue
				var busy := false
				for g in gen_points:
					if g.distance_to(p) < 4.0: busy = true
				for h in hook_points:
					if h.distance_to(p) < 4.0: busy = true
				for e in pallet_points:
					if (e[0] as Vector3).distance_to(p) < 3.0: busy = true
				if busy: continue
				spots.append([p, (0.0 if bi == 0 else PI) + ((n % 5) - 2) * 0.02, cols[n % cols.size()]])
	garage_cars = spots.size()
	for sp in spots: _blob(sp[0], 2.5)
	for t in garage_tiles: # every column gets its contact shadow
		for x in GAR_COL_X:
			for z in GAR_COL_Z: _blob(_gar(int(t.c), int(t.r), x, z), 0.9)
	var paint := _flat(Color(1, 1, 1), 0.45, 0.5)
	paint.vertex_color_use_as_albedo = true
	var glass := _flat(Color(1, 1, 1), 0.3, 0.6)
	glass.vertex_color_use_as_albedo = true
	var tire := _flat(Color(0.03, 0.03, 0.03))
	var body_mm := _gar_cars(Vector3(1.8, 0.7, 4.2), paint)
	var cabin_mm := _gar_cars(Vector3(1.6, 0.62, 2.1), glass)
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.36; wheel.bottom_radius = 0.36; wheel.height = 0.24
	wheel.radial_segments = 8; wheel.rings = 0 # eighty cars: keep the wheels cheap
	wheel.material = tire
	var wheel_mm := MultiMesh.new()
	wheel_mm.transform_format = MultiMesh.TRANSFORM_3D
	wheel_mm.mesh = wheel
	wheel_mm.instance_count = spots.size() * 4
	body_mm.instance_count = spots.size()
	cabin_mm.instance_count = spots.size()
	var hulls := StaticBody3D.new()
	hulls.name = "ParkedCars"
	for i in spots.size():
		var at: Vector3 = spots[i][0]
		var yaw: float = spots[i][1]
		var col: Color = spots[i][2]
		var b3 := Basis(Vector3.UP, yaw)
		body_mm.set_instance_transform(i, Transform3D(b3, at + Vector3(0, 0.7, 0)))
		body_mm.set_instance_color(i, col)
		cabin_mm.set_instance_transform(i, Transform3D(b3, at + b3 * Vector3(0, 1.35, -0.2)))
		cabin_mm.set_instance_color(i, col.darkened(0.35))
		var w := 0
		for wx in [-0.9, 0.9]:
			for wz in [-1.35, 1.35]:
				wheel_mm.set_instance_transform(i * 4 + w, Transform3D(b3 * Basis(Vector3.BACK, PI / 2.0), at + b3 * Vector3(wx, 0.36, wz)))
				w += 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.9, 1.6, 4.3)
		cs.shape = bs
		cs.transform = Transform3D(b3, at + Vector3(0, 0.8, 0))
		hulls.add_child(cs)
		gar_hulls.append(cs)
	add_child(hulls)
	var model_mesh := _car_mesh()
	if model_mesh: # the owner's Land Cruiser in every bay: one MultiMesh instead of the three box ones
		var car_mm := MultiMesh.new()
		car_mm.transform_format = MultiMesh.TRANSFORM_3D
		car_mm.mesh = model_mesh
		car_mm.instance_count = spots.size()
		for i in spots.size():
			var b3 := Basis(Vector3.UP, float(spots[i][1])).scaled(Vector3(CAR_SCALE, CAR_SCALE, CAR_SCALE))
			car_mm.set_instance_transform(i, Transform3D(b3, spots[i][0]))
		var cmi := MultiMeshInstance3D.new()
		cmi.multimesh = car_mm
		cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cmi)
		car_models += 1
		for i in spots.size(): # every bay's car can be taken
			parked.append({"mm": car_mm, "mi": i, "hull": gar_hulls[i], "at": spots[i][0], "yaw": float(spots[i][1])})
		return
	for mm in [body_mm, cabin_mm, wheel_mm]:
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	var barrier := _flat(Color(0.38, 0.37, 0.35), 0.9)
	for b in garage_barriers:
		var body := StaticBody3D.new()
		body.position = b[0]
		body.rotation.y = b[1]
		_box(body, Vector3(3.2, 0.95, 0.45), Vector3(0, 0.47, 0), barrier)
		_mesh_box(body, Vector3(3.3, 0.12, 0.6), Vector3(0, 0.98, 0), _flat(Color(0.75, 0.62, 0.1), 0.6))
		add_child(body)
