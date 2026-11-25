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
const ROAD_LEN := 600.0 # the escape road behind each gate, from the gate to the last gate at its end
const LANE_W := 12.0    # wide enough for two cars: hers can come up beside theirs
const MAP_ROAD := 60.0  # how much of each road the big map draws past the gate
const ESC_AT := 16.0    # the survivors' escape car waits this far past the gate
const ESC_TOP := 14.0   # its top speed (50 km/h): the killer's second gear is 19.5, so she can catch it
const ROAD_HOOKS := 9   # hooks along each road, one every 60 m (after the map's own, so those keep their numbers)

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
var esc_cars := []            # the survivors' escape car behind each gate (NFCar, same order as gate_points)
var road_hook0 := 0           # hook_points from here on stand along the escape roads
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
var rain: GPUParticles3D   # the «مطر» weather's streaks (follow the camera like the leaves)
var decals := 0            # how many were laid (tests look)
var fire_fx := 0           # campfires with real flames
var _bolt_t := 0.0         # seconds to the next lightning
var _bolt := 0.0           # the flash, 1 -> 0
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
	if map_id == "kuwait": # the highway and the car park by the sea
		return absf(x) < KW_ROAD_HALF + 0.5 + pad or (x > KW_PARK.x - pad and x < KW_PARK.y + pad)
	if map_id == "city":
		for zs in CITY_ROWS: if absf(z - zs) < 3.6 + pad: return true
		for xs in CITY_COLS: if absf(x - xs) < 3.6 + pad: return true
		return false
	if map_id != "fareej": return false
	return absf(absf(z) - 47.0) < 4.0 + pad or absf(z) < 4.5 + pad or (absf(x + 13.0) < 4.0 + pad and absf(z) < 47.0)

## «City Life»'s streets: four running east-west between the rows of blocks, five north-south.
const CITY_ROWS := [-46.5, -15.5, 15.5, 46.5]
const CITY_COLS := [-70.0, -42.0, -14.0, 14.0, 42.0]
var city_towers: Array[float] = [] # how tall the tower over each building is

func _random_site(rng: RandomNumberGenerator, pad: float, lo: float, hi: float) -> Vector2:
	for k in 200:
		var p := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(lo, hi)
		if absf(p.x) > WALL - 8.0 or absf(p.y) > WALL - 8.0: continue
		if map_id == "beach" and p.y > BEACH_SHORE - 10.0: continue # keep it out of the water
		if map_id == "kuwait" and p.x > KW_SHORE - 10.0: continue
		if map_id == "beach" and absf(p.x) < PIER_W / 2.0 + 3.0 + pad and p.y > PIER_FROM - 18.0: continue # and off the way to the pier
		if not in_site(p.x, p.y, pad) and not on_street(p.x, p.y, 1.0): return p
	return Vector2(lo, lo)

## `seed` shuffles where the generators, hooks, pallets, hatches are, so every round plays differently.
## Everyone in a room gets the same seed from the server, so they all build the same layout.
var layout_seed := 1
func configure(id: String, seed := 1, th := "normal") -> void:
	map_id = id
	theme = th
	layout_seed = seed
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
	elif id == "kuwait": # «مدينة الكويت»: the Gulf Road by the National Assembly, the sea and the towers
		noise.seed = 965
		relief = 0.0
		tree_count = 0
		grass_per_chunk = 0
		fog_density = 0.007
		moon_dir = Vector3(0.62, 0.34, -0.71).normalized() # over the sea
		for k in KW_KIOSKS: buildings.append([k[0], k[1], k[2], 7.0, 5.5, 3.2])
		sites.append([KW_ASSEMBLY.x, KW_ASSEMBLY.z - 20.0, 0.0, 30.0]) # the Assembly: two circles cover it
		sites.append([KW_ASSEMBLY.x, KW_ASSEMBLY.z + 20.0, 0.0, 30.0])
		sites.append([KW_BOX.x, KW_BOX.z, 0.0, 2.5])
	elif id == "city": # «City Life»: a block of shop fronts under towers, on a grid of streets
		noise.seed = 505
		relief = 0.0
		tree_count = 0
		grass_per_chunk = 0
		fog_density = 0.012
		moon_dir = Vector3(-0.35, 0.42, -0.84).normalized()
		var lay := RandomNumberGenerator.new()
		lay.seed = 31
		for i in [-84.0, -56.0, -28.0, 0.0, 28.0]:
			for j in [-62.0, -31.0, 0.0, 31.0, 62.0]:
				if i == 0.0 and j == 0.0: continue # the square where everyone starts
				buildings.append([i + lay.randf_range(-2.0, 2.0), j + lay.randf_range(-1.5, 1.5), 0.0 if lay.randf() < 0.5 else PI,
					lay.randf_range(8.0, 10.0), lay.randf_range(6.0, 7.5), 3.4])
				city_towers.append(lay.randf_range(10.0, 46.0))
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
	if Gfx.weak: grass_per_chunk = int(grass_per_chunk * 0.75) # thinner on the older phones (it is drawn in the shadow pass too)
	if id == "garage": # the car park lays out its own floor, so none of the outdoor plan applies
		_plan_garage(rng)
		_plan_road()
		return
	sites.append([0.0, 0.0, _raw_h(0.0, 0.0), 6.0])
	for b in buildings:
		sites.append([b[0], b[1], _raw_h(b[0], b[1]), maxf(b[3], b[4]) * (1.05 if id == "fareej" else 0.75) + 1.0])
	# the market: a big flat plot on the east side, shop fronts facing the middle of the map
	var mz: float = -34.0 if id == "beach" else 2.0 # on the beach it sits back from the water
	var msx := 56.0
	var mpx := 62.0
	var myaw := -PI / 2.0
	if id == "kuwait": # the sea is on the east: the market sits behind the Assembly, facing the road
		mz = 82.0; msx = -70.0; mpx = -76.0; myaw = PI / 2.0
	var mh := _raw_h(msx, mz)
	sites.append([msx, mz, mh, 21.0])
	market = {"pos": Vector3(mpx, mh, mz), "yaw": myaw, "w": MARKET_W, "d": MARKET_D}
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
	if id != "kuwait": door_points.append([mbase + mrot * Vector3(0, 0, -MARKET_D / 2.0), market.yaw]) # (Kuwait City: the mosque stands there)
	order = _shuffled(door_points.size(), rng)
	for k in mini(9, door_points.size()): pallet_points.append(door_points[order[k]])
	# lockers and vault windows: the first 8 buildings, plus the market
	for bi in mini(buildings.size(), 8):
		var b: Array = buildings[bi]
		locker_points.append([_local(b, Vector3(b[3] / 2.0 - 0.75, 0, -b[4] / 2.0 + 0.6)), b[2]])
		window_points.append([_local(b, Vector3(-b[3] / 2.0, 0, 0)), Basis(Vector3.UP, b[2]) * Vector3(-1, 0, 0)])
	if id == "kuwait": # either side of the mosque, outside it
		locker_points.append([mbase + mrot * Vector3(21.0, 0, 2.0), market.yaw])
		locker_points.append([mbase + mrot * Vector3(-21.0, 0, 2.0), market.yaw])
	else:
		locker_points.append([mbase + mrot * Vector3(12.6, 0, -4.3), market.yaw])
		locker_points.append([mbase + mrot * Vector3(-12.6, 0, -4.3), market.yaw])
		window_points.append([mbase + mrot * Vector3(-MARKET_W / 2.0, 0, 1.0), mrot * Vector3(-1, 0, 0)])
	# 2 exit gates on opposite edges
	for g in [[0.0, -WALL, 0.0], [0.0, WALL, PI]]:
		sites.append([g[0], g[1], _raw_h(g[0], g[1]), 8.0])
		var gy := _raw_h(g[0], g[1])
		if id == "beach" and g[1] > 0.0: gy = PIER_Y # out across the lagoon: the gate stands on the pier
		gate_points.append([Vector3(g[0], gy, g[1]), g[2]])
	# 9 hooks and 5 possible hatches: anywhere free
	for hi in 9:
		var hp := _random_site(rng, 3.5, 22.0, 100.0)
		sites.append([hp.x, hp.y, _raw_h(hp.x, hp.y), 2.5])
		hook_points.append(Vector3(hp.x, _raw_h(hp.x, hp.y), hp.y))
	for hi in 5:
		var hp := _random_site(rng, 3.0, 30.0, 100.0)
		sites.append([hp.x, hp.y, _raw_h(hp.x, hp.y), 2.2])
		hatch_points.append(Vector3(hp.x, _raw_h(hp.x, hp.y), hp.y))
	_plan_road()
	_plan_trees()
	if has_power_box(): _plan_power_box() # decided with the layout: the server hears where it is

## The hooks along each escape road: one every 60 m on alternating sides of the lane, so a car
## the killer stops can be emptied onto the nearest one.
func _plan_road() -> void:
	road_hook0 = hook_points.size()
	for g in gate_points:
		var gp: Vector3 = g[0]
		var b := Basis(Vector3.UP, float(g[1]))
		for k in range(1, ROAD_HOOKS + 1):
			var p: Vector3 = gp + b * Vector3((LANE_W / 2.0 - 1.6) * (1.0 if k % 2 == 1 else -1.0), 0.0, -60.0 * k)
			hook_points.append(Vector3(p.x, gp.y, p.z))

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
	if map_id in ["garage", "city"]: return "indoor" # bare concrete / pavement everywhere
	if map_id == "kuwait": return "sand" if pos.x > KW_SAND else "indoor"
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
	if map_id == "kuwait": return smoothstep(KW_SAND - 3.0, KW_SAND, x)
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
		# the beach's north side is the lagoon: (-52, 52) was in the water past the wading wall
		# (BEACH_SHORE + 9), and the killer started there with no way out. On the sand instead.
		if map_id == "beach": p = Vector2(-52.0, BEACH_SHORE - 24.0)
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
	elif map_id == "kuwait": # the sand slopes into the Gulf on the east side
		h -= smoothstep(KW_SHORE - 2.0, KW_SHORE + 26.0, x) * 3.4
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
	if theme == "rain": _wet()
	_build_terrain()
	build_step = 1
	await get_tree().process_frame
	if map_id == "fareej": _build_fareej()
	elif map_id == "rubkhali": _build_rubkhali()
	elif map_id == "garage": _build_garage()
	elif map_id == "beach": _build_beach()
	elif map_id == "kuwait": _build_kuwait()
	else: _build_buildings()
	if map_id == "city": _build_city()
	_build_objectives()
	_build_extras()
	_build_doors()
	if map_id == "kuwait": _build_mosque() # his mosque where the market would be
	elif map_id != "garage": _build_market()
	if map_id != "kuwait" and has_power_box(): _build_power_box()
	grid_all = theme in ["halloween", "sunset"] # the whole map hangs on the box (Kuwait City otherwise: its street lights)
	build_step = 2
	await get_tree().process_frame
	if not map_id in ["garage", "kuwait"]: _build_scatter() # the garage and Kuwait City park their own cars
	_build_theme_props()
	if map_id == "rubkhali": _build_animals()
	_build_scenery()
	_build_owner_props()
	_build_trees()
	build_step = 3
	await get_tree().process_frame
	if not map_id in ["garage", "city", "kuwait"]:
		_build_rocks()
		await _build_grass()
	build_step = 4
	_build_blobs()
	_build_decals()
	_build_particles()
	_build_probe()
	await get_tree().physics_frame # the colliders have to be in the physics space before the
	await get_tree().physics_frame # killer's car looks for a clear spot among them
	_place_drive_car()
	_place_escape_cars()
	_sharpen() # last, so the killer's car and its cabin are included
	for l in find_children("*", "OmniLight3D", true, false): # far lights cost nothing
		l.distance_fade_enabled = true
		l.distance_fade_begin = 32.0 if Gfx.weak else 45.0 # an older phone lights fewer pixels
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
## Anisotropic filtering on every textured material of the map (the procedural surfaces, the
## owner's models, the car-park pieces, the MultiMeshes): plain trilinear smears the ground, walls
## and floors into mush at a glancing angle. The 4x / 16x level comes from Gfx (the viewport).
var aniso_mats := 0
func _sharpen() -> void:
	var seen := {}
	for n in find_children("*", "GeometryInstance3D", true, false):
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.material_override: _aniso(mi.material_override, seen)
			if mi.mesh:
				for k in mi.mesh.get_surface_count():
					_aniso(mi.get_active_material(k), seen)
		elif n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if (n as MultiMeshInstance3D).material_override: _aniso((n as MultiMeshInstance3D).material_override, seen)
			if mm and mm.mesh:
				for k in mm.mesh.get_surface_count(): _aniso(mm.mesh.surface_get_material(k), seen)

func _aniso(m: Material, seen: Dictionary) -> void:
	if m == null or seen.has(m): return
	seen[m] = true
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		if b.albedo_texture or b.normal_texture:
			b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			aniso_mats += 1
	if m.next_pass: _aniso(m.next_pass, seen)

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
	elif theme == "halloween": # just dark: no orange or red cast any more (the owner)
		gr.set_shader_parameter("base_col", Color(0.04, 0.05, 0.035))
		gr.set_shader_parameter("tip_col", Color(0.12, 0.14, 0.09))
		fol.set_shader_parameter("tint", Color(0.7, 0.75, 0.7))
	_mat.grass = gr
	# desert surfaces
	_mat.mud = _pbr(Color(0.26, 0.2, 0.14), Color(0.58, 0.47, 0.34), 0.03, Vector3(0.35, 0.35, 0.35), 0.95)
	_mat.cloth = _pbr(Color(0.035, 0.03, 0.028), Color(0.13, 0.115, 0.1), 0.05, Vector3(0.6, 0.6, 0.6), 1.0)
	_mat.sand_rock = _pbr(Color(0.16, 0.13, 0.09), Color(0.42, 0.35, 0.25), 0.02, Vector3(0.5, 0.5, 0.5), 0.95)

# ---------------- environment ----------------
## Register a light that the blackout, the flicker and the killer can all touch.
## `house` lights go out when he walks up to them.
func _amb_light(l: Light3D, house := false, flick := true, on_grid := false) -> void:
	amb_lights.append([l, l.light_energy, house, flick, 1.0, on_grid])
	NFLook.halo(l)
	if flick and l is OmniLight3D: flicker.append(l)

func _build_environment() -> void:
	env = Environment.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	if ResourceLoader.exists("res://assets/sky/moon.jpg"): # the owner's moon
		sm.set_shader_parameter("moon_tex", load("res://assets/sky/moon.jpg"))
		sm.set_shader_parameter("has_moon_tex", 1.0)
	if ResourceLoader.exists("res://assets/sky/milkyway.jpg"): # the owner's night sky photograph
		sm.set_shader_parameter("night_tex", load("res://assets/sky/milkyway.jpg"))
		sm.set_shader_parameter("has_night_tex", 1.0)
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
		"halloween": # a grey night with every light on; the power box takes it to the dark (DARK_*)
			env.ambient_light_color = Color(0.13, 0.13, 0.16)
			env.ambient_light_energy = 1.0
			env.fog_light_color = Color(0.05, 0.05, 0.06)
			env.fog_density = fog_density * 1.3
			env.adjustment_saturation = 0.85
		"rain": # «مطر»: a wet, blue-grey night; the ground shines and the lightning lights it all
			env.ambient_light_color = Color(0.17, 0.2, 0.26)
			env.ambient_light_energy = 1.1
			env.fog_light_color = Color(0.14, 0.16, 0.2)
			env.fog_density = fog_density * 1.25
			env.adjustment_saturation = 0.82
	# the map's own film look: a little more or less colour and contrast per map. (A colour-correction
	# curve was tried first: on screen it crushed the darks and burnt the colours — the environment
	# reads the curve's 8-bit texture as sRGB — so it is not used.)
	var look: Array = {"fareej": [1.06, 1.04], "garage": [0.86, 1.1], "beach": [0.92, 1.06], "village": [0.88, 1.08]}.get(map_id, [1.0, 1.0])
	env.adjustment_saturation *= float(look[0])
	env.adjustment_contrast *= float(look[1])
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
			moon.light_color = Color(0.62, 0.68, 0.82)
			moon.light_energy = 0.9
		"rain":
			moon.light_color = Color(0.62, 0.7, 0.9)
			moon.light_energy = 0.9 # behind the clouds
	if map_id == "rubkhali": # hard noon light through the dust
		moon.light_color = Color(1.0, 0.91, 0.74)
		moon.light_energy = 2.4
	else: moon.light_energy *= 0.6 # the owner: the moonlight was far too bright (it was x1.4)
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
					elif theme == "halloween": gcol = gcol.darkened(0.45)
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
		occluders += 1

func _build_buildings() -> void:
	var idx := 0
	var wall_mat: Material = _mat.concrete if map_id == "city" else _mat.wood # shop fronts in the city
	for b in buildings:
		var w: float = b[3]; var d: float = b[4]; var hgt: float = b[5]
		var t := 0.2
		var body := StaticBody3D.new()
		body.name = "Building%d" % idx
		body.position = Vector3(b[0], _raw_h(b[0], b[1]), b[1])
		body.rotation.y = b[2]
		_box(body, Vector3(w + 0.6, 1.2, d + 0.6), Vector3(0, -0.5, 0), _mat.concrete)
		var y0 := 0.1
		_box(body, Vector3(w, hgt, t), Vector3(0, y0 + hgt / 2.0, -d / 2.0), wall_mat, true) # back
		_box(body, Vector3(t, hgt, d), Vector3(w / 2.0, y0 + hgt / 2.0, 0), wall_mat, true) # right
		# left wall with a window gap
		var seg := (d - 1.4) / 2.0
		_box(body, Vector3(t, hgt, seg), Vector3(-w / 2.0, y0 + hgt / 2.0, -d / 2.0 + seg / 2.0), wall_mat)
		_box(body, Vector3(t, hgt, seg), Vector3(-w / 2.0, y0 + hgt / 2.0, d / 2.0 - seg / 2.0), wall_mat)
		_box(body, Vector3(t, 1.0, 1.4), Vector3(-w / 2.0, y0 + 0.5, 0), wall_mat)
		_box(body, Vector3(t, hgt - 2.1, 1.4), Vector3(-w / 2.0, y0 + 2.1 + (hgt - 2.1) / 2.0, 0), wall_mat)
		# front wall with a door gap
		var fw := (w - 1.3) / 2.0
		_box(body, Vector3(fw, hgt, t), Vector3(-w / 2.0 + fw / 2.0, y0 + hgt / 2.0, d / 2.0), wall_mat)
		_box(body, Vector3(fw, hgt, t), Vector3(w / 2.0 - fw / 2.0, y0 + hgt / 2.0, d / 2.0), wall_mat)
		_box(body, Vector3(1.3, hgt - 2.2, t), Vector3(0, y0 + 2.2 + (hgt - 2.2) / 2.0, d / 2.0), wall_mat)
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

# ---------------- «مدينة الكويت» (Kuwait City) ----------------
## The owner's reference picture, without the far towers of the skyline: the Gulf Road running
## north-south through the middle (two carriageways, a median of grass and palms), the National
## Assembly and its gardens on the west, a car park and the corniche promenade on the east, the
## sand and a rock breakwater, the sea, the Kuwait Towers on their point and a warship out at
## anchor. The street lights hang on one power box: the killer pulls it, survivors fix it.
const KW_ROAD_HALF := 16.0                 # the twin carriageway, kerb to kerb
const KW_WALK := 5.8                       # each sidewalk
const KW_PARK := Vector2(24.0, 44.0)       # the car park, x from .. to
const KW_PROM := Vector2(44.0, 56.0)       # the corniche promenade
const KW_SAND := 56.0                      # sand from here to the water
const KW_SHORE := 62.0                     # the water line
const KW_WATER := -0.6
const KW_ASSEMBLY := Vector3(-75.0, 0.0, 0.0)
const KW_TOWERS := Vector3(104.0, 0.0, -62.0) # south-east: looking down the road to the south, as in his picture
const KW_BOX := Vector3(-23.6, 0.0, 9.0)   # the power box, on the west sidewalk
const KW_KIOSKS := [[-38.0, -52.0, PI / 2.0], [-38.0, 52.0, PI / 2.0], [-38.0, -90.0, PI / 2.0], [-38.0, 90.0, PI / 2.0],
	[-78.0, -78.0, 0.0], [50.0, -64.0, -PI / 2.0], [50.0, 64.0, -PI / 2.0], [50.0, -8.0, -PI / 2.0]]
const KW_MEDIAN := 92.0                    # the median runs to here each way, clear of the gates
const KW_HEADS := [-1.75, 1.75]             # his twin-head light: where the two lamps hang (x), at
const KW_HEAD_Y := 8.55                    # this height, measured off the model
var power_box := Vector3.INF               # where the box stands (INF: this map has none)
var grid_off := false
var grid_mats: Array[StandardMaterial3D] = [] # the lamps' glow: dark while the power is cut
var _grid_glow: Array[float] = []
var box_lamp: StandardMaterial3D
var grid_glare: StandardMaterial3D # the halo round the street lamps (dims with the power)
var kw_parts := 0

## Many copies of one of the owner's models as one MultiMesh per sub-mesh (one draw call each),
## optional box collision per copy (`hull`: size, centre height), drawn up to `far` metres.
func _kw_many(name: String, xf: Array, hull := Vector3.ZERO, hull_y := 0.0, far := 0.0, shadow := true) -> Array:
	var ps := _scene_model("res://assets/props/%s.glb" % name)
	var out: Array = []
	if ps == null or xf.is_empty(): return out
	var src := ps.instantiate() as Node3D
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var rel := src.global_transform.affine_inverse() * m.global_transform if m.is_inside_tree() else m.transform
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m.mesh
		mm.instance_count = xf.size()
		for i in xf.size(): mm.set_instance_transform(i, (xf[i] as Transform3D) * rel)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if far > 0.0: mmi.visibility_range_end = far
		add_child(mmi)
		out.append(mmi)
	src.free()
	if hull != Vector3.ZERO:
		var body := StaticBody3D.new()
		body.name = "KW_%s" % name
		for t in xf:
			var tt: Transform3D = t
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = hull * tt.basis.get_scale()
			cs.shape = bs
			cs.transform = Transform3D(tt.basis.orthonormalized(), tt.origin + Vector3(0, hull_y * tt.basis.get_scale().y, 0))
			body.add_child(cs)
		add_child(body)
	kw_parts += xf.size()
	return out

func _kw_one(name: String, at: Vector3, yaw: float, k := 1.0, hull := Vector3.ZERO, hull_y := 0.0) -> Node3D:
	var ps := _scene_model("res://assets/props/%s.glb" % name)
	if ps == null: return null
	var parent: Node3D = self
	if hull != Vector3.ZERO: parent = _solid(at, yaw, hull * k, hull_y * k)
	var n := ps.instantiate() as Node3D
	if parent == self:
		n.position = at
		n.rotation.y = yaw
	n.scale = Vector3(k, k, k)
	parent.add_child(n)
	kw_parts += 1
	return n

## Pavers drawn in code: rows of rectangular stones, each a little different, with sunken grout and
## a normal map from it, laid in world space (one tile of the texture covers 2 m). `warm`: the
## corniche's sandy stone; otherwise the grey of the walks.
var _pavers := {}
func _paver_mat(raised: bool, warm := false) -> StandardMaterial3D:
	var key := "%s%s" % [raised, warm]
	if _pavers.has(key): return _pavers[key]
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var hgt := Image.create(n, n, false, Image.FORMAT_L8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41 if warm else 17
	var base := Color(0.55, 0.48, 0.38) if warm else Color(0.36, 0.36, 0.37)
	var rows := 8
	var cols := 4
	var cell: Array = []
	for r in rows:
		var row: Array = []
		for c in cols + 1: row.append(rng.randf_range(-0.07, 0.07))
		cell.append(row)
	for y in n:
		var r := y * rows / n
		var off := (n / cols / 2) if r % 2 == 1 else 0
		for x in n:
			var xx := (x + off) % n
			var c := xx * cols / n
			var gx := xx % (n / cols)
			var gy := y % (n / rows)
			var grout := gx < 2 or gy < 2
			var v: float = cell[r][c] + rng.randf_range(-0.025, 0.025)
			var col := base.darkened(0.55) if grout else Color(base.r + v, base.g + v, base.b + v)
			img.set_pixel(x, y, col)
			hgt.set_pixel(x, y, Color(0.1, 0.1, 0.1) if grout else Color(0.8 + v, 0.8 + v, 0.8 + v))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	var nrm := hgt.duplicate() as Image
	nrm.bump_map_to_normal_map(3.0)
	nrm.generate_mipmaps()
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(nrm)
	m.normal_scale = 0.8
	m.roughness = 0.78
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_pavers[key] = m
	return m

## A raised strip you can walk and drive onto: a flat top `h` high, and on both long sides a ramp
## of collision 0.5 m wide (about 17°), so a foot or a tyre rides up the kerb instead of stopping.
func _kerb_body(c: Vector3, w: float, length: float, h: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Kerb"
	body.position = c
	var top := CollisionShape3D.new()
	var tb := BoxShape3D.new()
	tb.size = Vector3(w, h, length)
	top.shape = tb
	top.position.y = h / 2.0
	body.add_child(top)
	for sx in [-1.0, 1.0]:
		var ramp := CollisionShape3D.new()
		var cp := ConvexPolygonShape3D.new()
		var x0: float = sx * w / 2.0
		var x1: float = sx * (w / 2.0 + 0.5)
		var L := length / 2.0
		cp.points = PackedVector3Array([Vector3(x0, 0, -L), Vector3(x0, h, -L), Vector3(x1, 0, -L),
			Vector3(x0, 0, L), Vector3(x0, h, L), Vector3(x1, 0, L)])
		ramp.shape = cp
		body.add_child(ramp)
	add_child(body)
	kerbs.append([c, w, length, h])

var kerbs: Array = [] # [centre, width, length, height]: main shows «قفز» at their edges

## A street light on the grid: its light goes out with the power, and its glow map too.
func _grid_light(at: Vector3, col: Color, energy: float, reach: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = reach
	l.position = at
	add_child(l)
	_amb_light(l, false, false, true)

## Kuwait City's street lights, as in the owner's picture: a cone of sodium-gold light straight down
## from the head, so each lamp throws a warm pool on the asphalt and lights the trees under it, and
## the road between the lamps stays darker.
const KW_SODIUM := Color(1.0, 0.66, 0.3)
func _street_cone(at: Vector3, energy := 7.0, reach := 15.0, angle := 66.0) -> void:
	var l := SpotLight3D.new()
	l.light_color = KW_SODIUM
	l.light_energy = energy
	l.spot_range = reach
	l.spot_angle = angle
	l.spot_angle_attenuation = 0.85
	l.spot_attenuation = 0.9
	l.light_specular = 0.7
	l.position = at
	l.rotation.x = -PI / 2.0 # the cone points straight down
	l.distance_fade_enabled = true
	l.distance_fade_begin = 60.0 if Gfx.weak else 95.0
	l.distance_fade_length = 15.0
	add_child(l)
	_amb_light(l, false, false, true)

## A warm light from the ground up into a palm's crown, like the photographs of the Gulf Road.
func _uplight(at: Vector3, energy := 4.0) -> void:
	var l := SpotLight3D.new()
	l.light_color = Color(1.0, 0.74, 0.42)
	l.light_energy = energy
	l.spot_range = 13.0
	l.spot_angle = 24.0
	l.spot_angle_attenuation = 0.7
	l.position = at
	l.rotation.x = PI / 2.0 # pointing up
	l.distance_fade_enabled = true
	l.distance_fade_begin = 50.0 if Gfx.weak else 80.0
	l.distance_fade_length = 12.0
	add_child(l)
	_amb_light(l, false, false, true)

## A long strip of ground cut into pieces along the road: the Mobile renderer lights each mesh with
## its 8 nearest lights only, so one 224 m slab would be lit by 8 lamps and dark everywhere else.
func _strip(size: Vector3, centre: Vector3, mat: Material, seg := 16.0) -> void:
	var n := maxi(1, ceili(size.z / seg))
	var seg_len := size.z / float(n)
	for i in n:
		var z := centre.z - size.z / 2.0 + seg_len * (float(i) + 0.5)
		_mesh_box(self, Vector3(size.x, size.y, seg_len), Vector3(centre.x, centre.y, z), mat)

func _grid_glow_of(n: Node) -> void:
	var mesh: Mesh = null
	if n is MultiMeshInstance3D: mesh = (n as MultiMeshInstance3D).multimesh.mesh
	elif n is MeshInstance3D: mesh = (n as MeshInstance3D).mesh
	if mesh == null: return
	for si in mesh.get_surface_count():
		var m := mesh.surface_get_material(si) as StandardMaterial3D
		if m == null or m.get_texture(BaseMaterial3D.TEXTURE_EMISSION) == null or grid_mats.has(m): continue
		m.emission_enabled = true
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		m.emission = Color(1.0, 0.85, 0.6)
		m.emission_energy_multiplier = 2.4
		grid_mats.append(m)
		_grid_glow.append(2.4)

# ---------------- «بين العصر والمغرب» ----------------
## The round starts in the afternoon and the sun goes down over SUNSET_TIME (five minutes of the
## round's own clock, `round_t`, the same on every phone): golden light, then the sky reddens, then
## dusk, then nothing. From then on the night is pitch dark (DARK_*) until a survivor turns the street
## lights on at the power box (`grid_off` false); the killer can cut them again. Written every frame.
const SUNSET_TIME := 300.0
const MOON_RISE := 150.0     # the moon comes up over this long once the sun is gone
var moon_now := -10.0        # the moon's height in degrees (tests)
var _vol_base := -1.0
var round_t := 0.0           # the round's clock (main copies the rules' one in)
var _dk := 1.0               # how far into the pitch dark (follows the power box)
var _sun_az := Vector2(0.3, -0.9).normalized() # where it goes down (where the moon hangs on the other nights)
func sun_left() -> float: return maxf(SUNSET_TIME - round_t, 0.0)
func night_fell() -> bool: return round_t >= SUNSET_TIME

func _step_sunset(dt: float) -> void:
	var t := clampf(round_t / SUNSET_TIME, 0.0, 1.0)
	# degrees over the horizon: it touches the horizon just before the five minutes are up, and at
	# five minutes it is gone and the night is complete
	var el := lerpf(38.0, -4.0, pow(t, 1.25)) if round_t <= SUNSET_TIME else -4.0 - (round_t - SUNSET_TIME) * 0.1
	var day := clampf((el - 3.0) / 17.0, 0.0, 1.0)
	var warm := smoothstep(30.0, 6.0, el) * smoothstep(-5.0, 0.0, el)
	var night := 1.0 - smoothstep(-4.0, 4.0, el)
	_dk = move_toward(_dk, 1.0 if grid_off else 0.0, dt * 1.5)
	# the sun moves across the sky as it goes down (it drifts round as well as down), and once it is
	# gone the moon comes up on the other side over MOON_RISE seconds
	var r := deg_to_rad(el)
	var az := _sun_az.rotated(deg_to_rad(lerpf(-12.0, 6.0, t)))
	var dir := Vector3(az.x * cos(r), sin(r), az.y * cos(r)).normalized()
	var since := round_t - SUNSET_TIME
	var mel := lerpf(-8.0, 34.0, smoothstep(0.0, 1.0, clampf(since / MOON_RISE, 0.0, 1.0))) if since > -20.0 else -10.0
	var mr := deg_to_rad(mel)
	var maz := (-_sun_az).rotated(deg_to_rad(lerpf(-20.0, 10.0, clampf(since / MOON_RISE, 0.0, 1.0))))
	var mdir := Vector3(maz.x * cos(mr), sin(mr), maz.y * cos(mr)).normalized()
	var sun_up := el > -3.0
	_sky_mat.set_shader_parameter("moon_dir", dir if sun_up else mdir)
	_sky_mat.set_shader_parameter("day", day)
	_sky_mat.set_shader_parameter("warm", warm)
	_sky_mat.set_shader_parameter("sun_disc", 1.0 if sun_up else 0.0)
	moon_now = mel
	if map_id == "rubkhali": _sky_mat.set_shader_parameter("sun", day) # the sandstorm goes with the sun
	env.tonemap_exposure = lerpf(0.8, _exp_base, night) * Gfx.brightness
	if _vol_base < 0.0: _vol_base = env.volumetric_fog_density
	if env.volumetric_fog_enabled: # the sun in thick air is a white haze: the air is clear by day
		env.volumetric_fog_density = _vol_base * lerpf(0.12, 1.0, night)
	if _blood: return # the gates have power: the blood moon owns the light now
	var desert := map_id == "rubkhali"
	var amb_day := Color(0.72, 0.6, 0.44) if desert else Color(0.6, 0.67, 0.8)
	var amb_warm := Color(0.78, 0.55, 0.38)
	var amb_dusk := Color(0.24, 0.23, 0.36)
	var night_amb := Color(0.16, 0.2, 0.32).lerp(DARK_AMB, _dk)
	var col := amb_day.lerp(amb_warm, warm).lerp(amb_dusk, smoothstep(4.0, -3.0, el)).lerp(night_amb, night)
	var e := lerpf(lerpf(1.15, 0.9, warm), lerpf(1.3, DARK_AMB_E, _dk), night)
	env.ambient_light_color = col
	env.ambient_light_energy = e
	var fog_day := Color(0.76, 0.6, 0.38) if desert else Color(0.62, 0.68, 0.78)
	env.fog_light_color = fog_day.lerp(Color(0.8, 0.5, 0.32), warm).lerp(Color(0.07, 0.09, 0.14).lerp(DARK_FOG, _dk), night)
	env.fog_density = fog_base * lerpf(0.18, 1.0, night)
	if el > -1.0: # the sun's light
		moon.basis = Basis.looking_at(-dir)
		moon.light_color = Color(1.0, 0.94, 0.84).lerp(Color(1.0, 0.52, 0.26), warm)
		moon.light_energy = 2.2 * pow(clampf((el + 1.0) / 22.0, 0.0, 1.0), 0.7)
		moon.shadow_enabled = el > 0.5
	else: # the moon's: cold, faint while the power is out, up as it climbs
		moon.basis = Basis.looking_at(-mdir)
		moon.light_color = Color(0.6, 0.68, 0.95).lerp(DARK_MOON, _dk)
		moon.light_energy = lerpf(_moon_base, DARK_MOON_E, _dk) * smoothstep(-2.0, 12.0, mel)
		moon.shadow_enabled = mel > 4.0

## The power out is the old Halloween night, exactly (the owner): the colour of nothing, a moon you
## can hardly see, black fog. Only the torches (and the pumpkins) light anything until it is fixed.
const DARK_AMB := Color(0.09, 0.09, 0.11)
const DARK_AMB_E := 0.44     # (0.22 x the lighter nights' 2.0, as it was)
const DARK_MOON := Color(0.62, 0.68, 0.82)
const DARK_MOON_E := 0.14    # (0.1 x 1.4, as it was)
const DARK_FOG := Color(0.025, 0.025, 0.03)
var grid_all := false        # every lamp of the map hangs on the box (all but Kuwait City: there, the street lights)
var _lit := {}               # the lit night's colours, kept while the power is out

func set_grid(on: bool) -> void:
	if env and grid_off == on and theme != "sunset": # (the sunset mode draws its own sky: _step_sunset)
		if not on:
			_lit = {"amb": env.ambient_light_color, "fog": env.fog_light_color, "moon": moon.light_color if moon else Color.WHITE}
		var tw2 := create_tween().set_parallel(true)
		var d := 0.6 if on else 0.35
		tw2.tween_property(env, "ambient_light_energy", _amb_base if on else DARK_AMB_E, d)
		tw2.tween_property(env, "ambient_light_color", _lit.get("amb", env.ambient_light_color) if on else DARK_AMB, d)
		tw2.tween_property(env, "fog_light_color", _lit.get("fog", env.fog_light_color) if on else DARK_FOG, d)
		if moon:
			tw2.tween_property(moon, "light_energy", _moon_base if on else DARK_MOON_E, d)
			tw2.tween_property(moon, "light_color", _lit.get("moon", moon.light_color) if on else DARK_MOON, d)
	if grid_off == on and not garage_panels.is_empty(): # the car park's strip lights hang on it too
		var tw4 := create_tween().set_parallel(true)
		for m in garage_panels: tw4.tween_property(m, "emission_energy_multiplier", 3.2 if (on and not blackout) else 0.05, 0.5)
	grid_off = not on
	for i in grid_mats.size():
		var tw := create_tween()
		tw.tween_property(grid_mats[i], "emission_energy_multiplier", _grid_glow[i] if (on and not blackout) else 0.0, 0.8 if on else 0.25)
	if box_lamp: box_lamp.emission = Color(0.2, 1.0, 0.35) if on else Color(1.0, 0.15, 0.1)
	if grid_glare:
		var tw3 := create_tween()
		tw3.tween_property(grid_glare, "albedo_color:a", 0.55 if (on and not blackout) else 0.0, 0.8 if on else 0.25)

func _build_kuwait() -> void:
	_build_buildings() # the kiosks: lockers, doors, windows, generators by their doors
	var rng := RandomNumberGenerator.new()
	rng.seed = 965
	var y := 0.0
	# ---- the ground: paving on the land, lawns in front of the Assembly ----
	var pave := _paver_mat(false)
	var land := KW_SAND + WALL
	for xi in 6: # the paving in 28 m tiles (see _strip)
		var w6 := land / 6.0
		_strip(Vector3(w6, 0.02, WALL * 2.0), Vector3(-WALL + w6 * (float(xi) + 0.5), 0.0, 0), pave, 28.0)
	var lawn := _pbr(Color(0.06, 0.14, 0.04), Color(0.18, 0.34, 0.1), 0.05, Vector3(0.6, 0.6, 0.6), 0.95)
	for lz in [-38.0, -12.0, 14.0, 40.0]:
		_mesh_box(self, Vector3(20.0, 0.06, 20.0), Vector3(-40.0, 0.06, lz), lawn)
	# ---- the Gulf Road, built for real: fine asphalt, three lanes each way with dashed lines, solid
	# edge lines, zebra crossings, raised kerbs you can walk (and drive) up, the median between ----
	var asphalt := _pbr(Color(0.035, 0.035, 0.04), Color(0.1, 0.1, 0.11), 0.35, Vector3(0.9, 0.9, 0.9), 0.82)
	asphalt.uv1_triplanar = true
	asphalt.uv1_world_triplanar = true
	asphalt.uv1_scale = Vector3(0.25, 0.25, 0.25)
	# flush with the ground the cars roll on (2.5 cm), so a car sits on it instead of in it
	_strip(Vector3(KW_ROAD_HALF, 0.02, WALL * 2.0 + 2.0), Vector3(-KW_ROAD_HALF / 2.0, 0.015, 0), asphalt)
	_strip(Vector3(KW_ROAD_HALF, 0.02, WALL * 2.0 + 2.0), Vector3(KW_ROAD_HALF / 2.0, 0.015, 0), asphalt)
	var white := _flat(Color(0.9, 0.9, 0.86), 0.55, 0.0, 0.35)
	var yellow := _flat(Color(0.95, 0.75, 0.15), 0.55, 0.0, 0.35)
	var marks := {"w": [], "y": []}
	for sx in [-1.0, 1.0]:
		for lane_x in [6.3, 10.6]: # the dashed lines between the three lanes
			for z in range(-110, 111, 9):
				if absf(float(z)) < 5.0 or absf(absf(float(z)) - 64.0) < 5.0: continue # not across the crossings
				marks.w.append(Transform3D(Basis().scaled(Vector3(0.16, 1.0, 4.5)), Vector3(sx * lane_x, 0.032, float(z))))
		marks.y.append(Transform3D(Basis().scaled(Vector3(0.18, 1.0, WALL * 2.0)), Vector3(sx * 2.45, 0.032, 0))) # inner edge
		marks.w.append(Transform3D(Basis().scaled(Vector3(0.18, 1.0, WALL * 2.0)), Vector3(sx * (KW_ROAD_HALF - 0.45), 0.032, 0)))
		for cz in [-64.0, 0.0, 64.0]: # zebra crossings
			for k in 9:
				marks.w.append(Transform3D(Basis().scaled(Vector3(0.6, 1.0, 4.0)), Vector3(sx * (3.0 + k * 1.4), 0.033, cz)))
	for key in marks: # in 32 m chunks, each lit by its own nearest lamps (the long lines are cut too)
		var chunks := {}
		for t in marks[key]:
			var tt: Transform3D = t
			var sz := tt.basis.get_scale()
			if sz.z > 40.0: # a line the length of the road: cut it
				for zc in range(-112, 112, 32):
					var piece := Transform3D(Basis().scaled(Vector3(sz.x, 1.0, 32.0)), Vector3(tt.origin.x, tt.origin.y, float(zc) + 16.0))
					if not chunks.has(zc): chunks[zc] = []
					chunks[zc].append(piece)
				continue
			var ck := int(floor((tt.origin.z + 112.0) / 32.0)) * 32 - 112
			if not chunks.has(ck): chunks[ck] = []
			chunks[ck].append(tt)
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, 0.012, 1.0)
		bm.material = white if key == "w" else yellow
		for ck in chunks:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = bm
			mm.instance_count = chunks[ck].size()
			for t in chunks[ck].size(): mm.set_instance_transform(t, chunks[ck][t])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
	# kerbs: granite edges, and a walkable ramp of collision so feet and tyres ride up onto them
	var kerb := _pbr(Color(0.42, 0.41, 0.39), Color(0.62, 0.61, 0.58), 0.6, Vector3(1.2, 1.2, 1.2), 0.7)
	var walk := _paver_mat(true)
	var med_len := KW_MEDIAN * 2.0
	for sx in [-1.0, 1.0]:
		# the sidewalk: pavers raised 15 cm, a granite kerb on the road side
		var cx: float = sx * (KW_ROAD_HALF + KW_WALK / 2.0)
		_strip(Vector3(KW_WALK, 0.15, WALL * 2.0), Vector3(cx, 0.075, 0), walk)
		_strip(Vector3(0.3, 0.17, WALL * 2.0), Vector3(sx * (KW_ROAD_HALF + 0.15), 0.085, 0), kerb, 32.0)
		_kerb_body(Vector3(cx, 0, 0), KW_WALK, WALL * 2.0, 0.15)
	# the median: raised, kerbed, ending well before the gates
	_strip(Vector3(4.2, 0.2, med_len), Vector3(0, 0.1, 0), kerb, 23.0)
	_strip(Vector3(3.6, 0.04, med_len - 0.6), Vector3(0, 0.22, 0), lawn, 23.0)
	_kerb_body(Vector3.ZERO, 4.2, med_len, 0.2)
	# the median planted: grass all along it round the palms, nothing near the gates
	var planters: Array = []
	var palms: Array = []
	var lights: Array = []
	for z in range(-int(KW_MEDIAN) + 5, int(KW_MEDIAN) - 4, 10):
		planters.append(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0, 0.22, float(z))))
	for z in range(-80, 81, 10):
		if z % 20 == 0: palms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.1)), Vector3(0, 0.22, float(z))))
		else: lights.append(Transform3D(Basis(), Vector3(0, 0.22, float(z))))
	_kw_many("kw_planter", planters, Vector3.ZERO, 0.0, 120.0, false)
	# twin-head lights along both kerbs as well (the sidewalk tiles used to carry the lamps)
	for sx in [-1.0, 1.0]:
		for z in range(-100, 101, 20):
			lights.append(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(sx * (KW_ROAD_HALF + 0.9), 0.15, float(z) + 10.0 * sx)))
	# ---- trees all down the street: one every few metres on both sides ----
	var trees: Array = []
	var step := 6 if Gfx.weak else 4
	for sx in [-1.0, 1.0]:
		for z in range(-104, 105, step):
			if sx < 0.0 and absf(float(z) - KW_BOX.z) < 2.5: continue # the power box stands there
			trees.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.85, 1.1)), Vector3(sx * (KW_ROAD_HALF + KW_WALK - 1.2), 0.15, float(z))))
	for tz in [-46.0, -30.0, -6.0, 6.0, 30.0, 46.0]:
		for tx in [-46.0, -33.0]: trees.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(tx, 0.06, tz)))
	_kw_many("kw_tree", trees, Vector3(0.8, 4.0, 0.8), 2.0, 110.0, true)
	var prom_palms: Array = []
	for z in range(-104, 105, 10): prom_palms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(KW_PROM.y - 2.0, 0.2, float(z))))
	var all_palms: Array = palms + prom_palms
	if _kw_many("kw_palm", all_palms, Vector3(0.8, 6.0, 0.8), 3.0, 170.0, true).is_empty():
		for t in all_palms:
			var tt: Transform3D = t
			tree_plan.append([tt.origin.x, 0.0, tt.origin.z, 1, 1.0, 0.0])
	# the promenade: warm pavers, raised and kerbed like the walks
	_strip(Vector3(KW_PROM.y - KW_PROM.x, 0.2, WALL * 2.0), Vector3((KW_PROM.x + KW_PROM.y) / 2.0, 0.1, 0), _paver_mat(true, true))
	_kerb_body(Vector3((KW_PROM.x + KW_PROM.y) / 2.0, 0, 0), KW_PROM.y - KW_PROM.x, WALL * 2.0, 0.2)
	for z in range(-98, 99, 14): lights.append(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(KW_PROM.x + 2.0, 0.2, float(z))))
	# the street lights: his twin heads, burning yellow, each head a glowing lamp and a light
	_kw_many("kw_light", lights, Vector3(0.4, 9.0, 0.4), 4.5, 170.0, true)
	var lamp_glow := _flat(Color(1.0, 0.72, 0.36), 0.3, 0.0, 12.0) # hot enough to bloom
	lamp_glow.emission = Color(1.0, 0.68, 0.32)
	grid_mats.append(lamp_glow)
	_grid_glow.append(12.0)
	var heads: Array = []
	for t in lights:
		var tt: Transform3D = t
		for hx in KW_HEADS: heads.append(Transform3D(Basis(), tt * Vector3(hx, KW_HEAD_Y, 0.42)))
		_street_cone(tt.origin + Vector3(0, KW_HEAD_Y - 0.3, 0))
	# the glare round every lamp head, as a camera sees a sodium lamp at night
	var glare := MultiMesh.new()
	glare.transform_format = MultiMesh.TRANSFORM_3D
	var gq := QuadMesh.new()
	gq.size = Vector2(2.2, 2.2)
	grid_glare = StandardMaterial3D.new()
	grid_glare.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_glare.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	grid_glare.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_glare.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	grid_glare.albedo_texture = NFDecor.tex("soft")
	grid_glare.albedo_color = Color(1.0, 0.62, 0.26, 0.55)
	grid_glare.no_depth_test = false
	gq.material = grid_glare
	glare.mesh = gq
	glare.instance_count = heads.size()
	for i in heads.size(): glare.set_instance_transform(i, heads[i])
	var gmi := MultiMeshInstance3D.new()
	gmi.multimesh = glare
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gmi)
	for t in palms: # the median's palms lit from their feet
		var tt: Transform3D = t
		_uplight(tt.origin + Vector3(0.9, 0.3, 0.0))
	for i in prom_palms.size():
		if i % 2 == 0:
			var tt: Transform3D = prom_palms[i]
			_uplight(tt.origin + Vector3(-0.9, 0.3, 0.0), 3.2)
	var hm := MultiMesh.new()
	hm.transform_format = MultiMesh.TRANSFORM_3D
	var sph := SphereMesh.new()
	sph.radius = 0.22; sph.height = 0.3; sph.radial_segments = 10; sph.rings = 5
	sph.material = lamp_glow
	hm.mesh = sph
	hm.instance_count = heads.size()
	for t in heads.size(): hm.set_instance_transform(t, heads[t])
	var hmi := MultiMeshInstance3D.new()
	hmi.multimesh = hm
	hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hmi)
	# ---- crossings: traffic lights at the middle crossing, his signs along the walks ----
	for c in [[-KW_ROAD_HALF - 0.8, -4.0, 0.0], [KW_ROAD_HALF + 0.8, 4.0, PI], [-1.6, 4.0, PI / 2.0], [1.6, -4.0, -PI / 2.0]]:
		var tl := _kw_one("kw_traffic", Vector3(c[0], 0.05, c[1]), c[2], 1.0, Vector3(0.4, 5.0, 0.4), 2.5)
		if tl: prop_glow(tl, Color(1, 1, 1), 2.5)
	var signs := _kw_one("kw_signs", Vector3(-KW_ROAD_HALF - KW_WALK + 0.6, 0.05, -60.0), PI / 2.0)
	if signs:
		var top := signs.find_child("row_top", true, false) as Node3D
		if top: # the sheet's upper row stands on the ground too, further along the walk
			top.position.y = 0.0
			top.position.x += 22.0
	# ---- the car park by the sea: his cars in rows ----
	var park := _flat(Color(0.06, 0.06, 0.065), 0.6)
	_strip(Vector3(KW_PARK.y - KW_PARK.x, 0.05, WALL * 2.0 - 8.0), Vector3((KW_PARK.x + KW_PARK.y) / 2.0, 0.07, 0), park)
	var bay := MultiMesh.new()
	bay.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(5.0, 0.02, 0.12)
	bm.material = _flat(Color(0.85, 0.85, 0.82), 0.6, 0.0, 0.2)
	bay.mesh = bm
	var bays: Array = []
	var cars := {"kw_nova": [], "kw_chevelle": [], "kw_supercar": [], "kw_pickup": [], "car": []}
	var kinds := cars.keys()
	for row in [KW_PARK.x + 3.0, KW_PARK.y - 3.0]:
		for z in range(-100, 101, 3):
			bays.append(Transform3D(Basis(), Vector3(row, 0.11, float(z) - 1.5)))
			if (z + 100) % 33 < 3 or rng.randf() < 0.3: continue # aisles to walk through, and empty bays
			var kind: String = kinds[rng.randi() % kinds.size()]
			# nose into the bay: his cars are long along x, the Land Cruiser along z
			var yaw := (PI / 2.0 if row < 34.0 else -PI / 2.0) if kind == "car" else (PI if row < 34.0 else 0.0)
			var k := 0.9 if kind == "car" else 1.0
			cars[kind].append(Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.04, 0.04)).scaled(Vector3.ONE * k), Vector3(row, 0.08, float(z))))
	bay.instance_count = bays.size()
	for i in bays.size(): bay.set_instance_transform(i, bays[i])
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = bay
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bmi.visibility_range_end = 90.0
	add_child(bmi)
	for kind in cars:
		_kw_many(kind, cars[kind], Vector3(1.9, 1.4, 4.4) if kind == "car" else Vector3(5.2 if kind == "kw_pickup" else 4.5, 1.5, 1.9), 0.7, 140.0, true)
	# ---- the corniche: benches facing the water, his white car on its deck, a frost of lights in snow ----
	var benches: Array = []
	for z in range(-95, 96, 15): benches.append(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(KW_PROM.y - 4.5, 0.05, float(z) + 5.0)))
	_kw_many("kw_bench", benches, Vector3(1.8, 0.9, 0.6), 0.45, 90.0, true)
	_kw_one("kw_white", Vector3(KW_PROM.x + 6.0, 0.05, 40.0), -PI / 2.0, 1.0, Vector3(5.2, 1.4, 2.4), 0.7)
	if theme == "snow":
		var flakes: Array = []
		for t in lights:
			var tt: Transform3D = t
			flakes.append(Transform3D(Basis(), tt.origin + Vector3(0, 5.6, 0.25)))
		for m in _kw_many("kw_flake", flakes, Vector3.ZERO, 0.0, 120.0, false): prop_glow(m, Color(0.7, 0.9, 1.0), 2.5)
	# his bins along the walks and the corniche
	var bins: Array = []
	for z in range(-95, 96, 19):
		bins.append(Transform3D(Basis(), Vector3(-KW_ROAD_HALF - 0.9, 0.15, float(z) + 5.0)))
		bins.append(Transform3D(Basis(), Vector3(KW_PROM.y - 4.5, 0.05, float(z) - 2.0)))
	_kw_many("kw_trash", bins, Vector3(0.6, 1.0, 0.6), 0.5, 80.0, true)
	# grass all down the middle of the road: his patches between the planters, tufts round every palm
	var grass: Array = []
	var tufts: Array = []
	for z in range(-int(KW_MEDIAN) + 3, int(KW_MEDIAN) - 2, 3): # never past the median's ends: the gates stay clear
		grass.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.3)), Vector3(rng.randf_range(-0.9, 0.9), 0.2, float(z))))
	for t in palms + trees:
		var tt: Transform3D = t
		for i in 4:
			var a := TAU * i / 4.0 + rng.randf()
			tufts.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.2)), tt.origin + Vector3(cos(a), 0.0, sin(a)) * 1.3))
	for lz in [-38.0, -12.0, 14.0, 40.0]: # the Assembly's lawns
		for i in 10: grass.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 1.2), Vector3(-40.0 + rng.randf_range(-9, 9), 0.08, lz + rng.randf_range(-9, 9))))
	_kw_many("kw_grass", grass + tufts, Vector3.ZERO, 0.0, 70.0, false)
	var clumps: Array = [] # his jungle clump is 10k triangles: one at the foot of each median palm only
	for t in palms:
		var tt: Transform3D = t
		clumps.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), tt.origin + Vector3(0.0, 0.1, 1.2)))
	_kw_many("kw_clump", clumps, Vector3.ZERO, 0.0, 50.0, false)
	# barriers where the road meets the gates and round the car park's ends
	var bars: Array = []
	for zs in [-1.0, 1.0]:
		for x in [-12.0, -8.0, 8.0, 12.0]: bars.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), Vector3(x, 0.05, zs * 96.0)))
		for x in [26.0, 30.0, 38.0, 42.0]: bars.append(Transform3D(Basis(), Vector3(x, 0.05, zs * 104.0)))
	_kw_many("kw_barrier", bars, Vector3(2.0, 1.4, 0.8), 0.7, 110.0, true)
	# ---- the sea: sand, rocks along the water, the towers on their point, a warship ----
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.03, 0.08, 0.14, 0.86)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.metallic = 0.5
	water.roughness = 0.05
	water.normal_enabled = true
	water.normal_texture = _noise_tex(0.08, 256, true)
	water.normal_scale = 0.5
	water.uv1_scale = Vector3(0.05, 0.05, 0.05)
	water.uv1_triplanar = true
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(700.0, 900.0)
	pm.material = water
	sea.mesh = pm
	sea.position = Vector3(KW_SHORE + 350.0 - 6.0, KW_WATER, 0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.add_to_group("far")
	add_child(sea)
	var deep := StaticBody3D.new() # you can wade in, you cannot swim out
	deep.name = "Gulf"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(4.0, 14.0, WALL * 2.0)
	cs.shape = bs
	cs.position = Vector3(KW_SHORE + 8.0, 5.0, 0)
	deep.add_child(cs)
	add_child(deep)
	var sand: Array = [] # his sand mounds along the beach
	for z in range(-104, 105, 13):
		sand.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, rng.randf_range(0.6, 1.0), 1.0)), Vector3(KW_SAND + 3.0 + rng.randf_range(-1.0, 1.0), height(KW_SAND + 3.0, float(z)) - 0.25, float(z))))
	_kw_many("kw_sand", sand, Vector3.ZERO, 0.0, 140.0, false)
	var piles: Array = []
	var rocks: Array = []
	for z in range(-110, 111, 5):
		if (z / 5) % 3 == 0:
			piles.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(KW_SHORE + 1.2, height(KW_SHORE + 1.2, float(z)) - 0.4, float(z))))
			continue
		var k := rng.randf_range(0.7, 1.3)
		rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k, k * 0.8, k)), Vector3(KW_SHORE + 1.5 + rng.randf_range(-0.8, 0.8), height(KW_SHORE + 1.5, float(z)) - 0.5, float(z))))
	for i in 26: # the point the towers stand on
		var a := TAU * i / 26.0
		var k := rng.randf_range(1.0, 1.8)
		rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k, k, k)), KW_TOWERS + Vector3(cos(a) * 26.0, -2.4, sin(a) * 26.0)))
	_kw_many("kw_rock", rocks, Vector3.ZERO, 0.0, 0.0, false)
	_kw_many("kw_rocks2", piles, Vector3.ZERO, 0.0, 0.0, false)
	var isle := _pbr(Color(0.5, 0.46, 0.4), Color(0.7, 0.66, 0.6), 0.03, Vector3(0.3, 0.3, 0.3), 0.8)
	var cyl := MeshInstance3D.new()
	var cm2 := CylinderMesh.new()
	cm2.top_radius = 25.0; cm2.bottom_radius = 27.0; cm2.height = 3.0; cm2.radial_segments = 32
	cm2.material = isle
	cyl.mesh = cm2
	cyl.position = KW_TOWERS + Vector3(0, -0.6, 0)
	cyl.add_to_group("far")
	add_child(cyl)
	var towers := _kw_one("kw_towers", KW_TOWERS + Vector3(0, 0.9, 0), -PI / 2.0)
	if towers:
		for gi in towers.find_children("*", "GeometryInstance3D", true, false): gi.add_to_group("far")
	for h in [[0.0, 46.0, 9.0], [0.0, 74.0, 6.0], [-10.0, 36.0, 7.0]]: # the blue spheres, lit
		var bl := OmniLight3D.new()
		bl.light_color = Color(0.35, 0.6, 1.0)
		bl.light_energy = 3.0
		bl.omni_range = float(h[2]) * 2.2
		bl.position = KW_TOWERS + Vector3(0, float(h[1]), float(h[0]))
		add_child(bl)
	for i in 6: # warm floodlights round the base, as in the picture
		var fl := OmniLight3D.new()
		fl.light_color = Color(1.0, 0.75, 0.45)
		fl.light_energy = 2.2
		fl.omni_range = 16.0
		var a := TAU * i / 6.0
		fl.position = KW_TOWERS + Vector3(cos(a) * 18.0, 2.0, sin(a) * 18.0)
		add_child(fl)
	var ship := _kw_one("kw_ship", Vector3(150.0, KW_WATER - 0.4, 55.0), 0.35)
	if ship:
		for gi in ship.find_children("*", "GeometryInstance3D", true, false): gi.add_to_group("far")
	# ---- the National Assembly, lit from its feet ----
	var asm_node := _kw_one("kw_assembly", KW_ASSEMBLY, PI / 2.0, 1.0, Vector3(80.0, 30.0, 46.0), 15.0)
	if asm_node:
		for gi in asm_node.find_children("*", "GeometryInstance3D", true, false): gi.add_to_group("far")
	else:
		var body := StaticBody3D.new()
		body.position = KW_ASSEMBLY
		_box(body, Vector3(46.0, 26.0, 80.0), Vector3(0, 13.0, 0), _mat.concrete, true)
		add_child(body)
	for z in range(-36, 37, 9):
		var up := OmniLight3D.new()
		up.light_color = Color(1.0, 0.82, 0.58)
		up.light_energy = 2.4
		up.omni_range = 14.0
		up.position = Vector3(KW_ASSEMBLY.x + 25.0, 1.2, float(z))
		add_child(up)
	for z in range(-34, 35, 8): # yellow light inside: it shows through the glass between the ribs
		for hy in [5.0, 13.0]:
			var il := OmniLight3D.new()
			il.light_color = Color(1.0, 0.8, 0.38)
			il.light_energy = 2.6
			il.omni_range = 11.0
			il.position = Vector3(KW_ASSEMBLY.x + 20.5, hy, float(z))
			add_child(il)
	var oc := OccluderInstance3D.new() # nothing behind the Assembly is drawn while it hides it
	var bo := BoxOccluder3D.new()
	bo.size = Vector3(42.0, 24.0, 76.0)
	oc.occluder = bo
	oc.position = KW_ASSEMBLY + Vector3(0, 12.0, 0)
	add_child(oc)
	occluders += 1
	# ---- the power box ----
	_build_power_box()

## Kuwait City: the owner's golden-crescent mosque in place of the market (no shops, no restaurant),
## set back so the generators on its forecourt stay clear, lit warm, with its own collision.
func _build_mosque() -> void:
	var mrot := Basis(Vector3.UP, market.yaw)
	var at: Vector3 = market.pos + mrot * Vector3(0, 0, -5.0)
	var m := _kw_one("kw_mosque", at, market.yaw, 1.0, Vector3(30.0, 18.0, 17.0), 9.0)
	if m:
		prop_glow(m, Color(1.0, 0.85, 0.5), 2.2)
		for gi in m.find_children("*", "GeometryInstance3D", true, false): gi.add_to_group("far")
	else:
		var body := StaticBody3D.new()
		body.position = at
		body.rotation.y = market.yaw
		_box(body, Vector3(30.0, 9.0, 17.0), Vector3(0, 4.5, 0), _mat.concrete, true)
		add_child(body)
	for k in 5: # warm floodlights along its front
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.45)
		l.light_energy = 2.2
		l.omni_range = 12.0
		l.position = at + mrot * Vector3(-12.0 + k * 6.0, 1.5, 10.5)
		add_child(l)
		_amb_light(l, false, false, true)

## Kuwait City's night, matched to the owner's photograph: a deep navy sky and shadow, the sea
## black-blue, and everything warm comes from the sodium lamps and the floodlights, which bloom.
var _kw_set := false
func _kw_look() -> void:
	if env == null: return
	if not _kw_set and moon: # once: the settings panel runs this again on every change
		_kw_set = true
		# the shadows go navy and a little lower, so the warm pools stand out (not darker than the
		# owner's own picture: the road there is easy to read)
		env.ambient_light_color = env.ambient_light_color.lerp(Color(0.15, 0.18, 0.3), 0.7)
		_amb_base = env.ambient_light_energy * 0.55
		env.ambient_light_energy = _amb_base * (0.3 if grid_off else 1.0)
		env.fog_light_color = env.fog_light_color.lerp(Color(0.05, 0.07, 0.14), 0.75)
		# the screenshots came out under a blue moonlit haze: the photograph has clear dark air and
		# all its warmth from the lamps. Thin flat fog (the fog event still scales this).
		fog_base *= 0.35
		env.fog_density = fog_base
		env.fog_sky_affect = 0.25
		if moon:
			moon.light_color = Color(0.62, 0.7, 0.95)
			moon.light_volumetric_fog_energy = 0.0 # the moon does not light the air: no blue haze
			_moon_base = moon.light_energy * 0.75
			moon.light_energy = _moon_base * (0.35 if grid_off else 1.0)
	if env.volumetric_fog_enabled: # thin warm-grey air that only the lamps light
		env.volumetric_fog_density = 0.011
		env.volumetric_fog_albedo = Color(0.9, 0.82, 0.72)
		env.volumetric_fog_ambient_inject = 0.0
		env.volumetric_fog_gi_inject = 0.0
	env.glow_intensity = 1.1
	env.glow_strength = 1.1
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.85
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06

## The street lights' power box: a grey cabinet on the west sidewalk with a warning plate and a lamp
## on top (green while the power is on, red when it has been cut). Drawn on everyone's map.
## Every map has a power box in Halloween and «بين العصر والمغرب»: in front of the market where there
## is one (where everybody passes), otherwise on a free spot picked from the room's seed, so every
## phone puts it in the same place. Kuwait City keeps its own on the west sidewalk.
func has_power_box() -> bool:
	return map_id == "kuwait" or theme in ["halloween", "sunset"]

var power_box_yaw := PI / 2.0
func _plan_power_box() -> void:
	if map_id == "kuwait":
		power_box = KW_BOX
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed * 31 + 4049
	var at := Vector3.INF
	if not market.is_empty():
		var mrot := Basis(Vector3.UP, float(market.yaw))
		for k in 16:
			var off := mrot * Vector3(rng.randf_range(-10.0, 10.0), 0.0, float(market.d) / 2.0 + rng.randf_range(6.0, 11.0))
			var c: Vector3 = market.pos + off
			if absf(c.x) > WALL - 8.0 or absf(c.z) > WALL - 8.0: continue
			if in_site(c.x, c.z, 1.5) or near_tree(c.x, c.z, 2.0): continue
			if map_id == "beach" and c.z > BEACH_SHORE - 4.0: continue
			at = Vector3(c.x, _raw_h(c.x, c.z), c.z)
			break
	if at == Vector3.INF:
		var p2 := _random_site(rng, 2.0, 10.0, 60.0)
		at = Vector3(p2.x, _raw_h(p2.x, p2.y), p2.y)
	power_box = at
	power_box_yaw = rng.randf() * TAU
	sites.append([at.x, at.z, at.y, 1.6])

func _build_power_box() -> void:
	var at := power_box
	var yaw := power_box_yaw
	var body := StaticBody3D.new()
	body.name = "PowerBox"
	body.position = at
	body.rotation.y = yaw # (Kuwait City: its doors toward the road)
	var grey := _pbr(Color(0.32, 0.34, 0.33), Color(0.5, 0.52, 0.5), 0.02, Vector3(0.6, 0.6, 0.6), 0.5, 0.6)
	_box(body, Vector3(1.4, 1.7, 0.7), Vector3(0, 0.85, 0), grey)
	_mesh_box(body, Vector3(1.5, 0.08, 0.8), Vector3(0, 1.74, 0), grey)
	_mesh_box(body, Vector3(0.02, 1.5, 0.02), Vector3(0, 0.85, 0.36), _flat(Color(0.1, 0.1, 0.1), 0.5)) # the doors' seam
	_mesh_box(body, Vector3(0.36, 0.3, 0.01), Vector3(0.0, 1.3, 0.36), _flat(Color(1.0, 0.82, 0.1), 0.5, 0.0, 0.6)) # ⚡ plate
	if _swap_model(body, "kw_panel", 0.0, 1.25): # his rusty control panel in place of the cabinet (same collision)
		prop_glow(_last_model, Color(1.0, 0.9, 0.6), 2.0)
	var sl := OmniLight3D.new() # a yellow work lamp over it: you can see the box from down the street
	sl.light_color = Color(1.0, 0.8, 0.3)
	sl.light_energy = 2.4
	sl.omni_range = 9.0
	sl.position = Vector3(0, 3.0, 0.6)
	body.add_child(sl)
	box_lamp = _flat(Color(0.2, 1.0, 0.35), 0.4, 0.0, 4.0)
	_mesh_box(body, Vector3(0.18, 0.12, 0.18), Vector3(0, 1.84, 0), box_lamp)
	var l := OmniLight3D.new()
	l.light_color = Color(0.9, 0.95, 1.0)
	l.light_energy = 1.2
	l.omni_range = 5.0
	l.position = Vector3(0, 2.4, 0.8)
	body.add_child(l)
	add_child(body)
	_blob(at, 1.2)

# ---------------- «City Life» ----------------
## The towers over the shop fronts, the streets and their lamps, neon, and the owner's cyberpunk
## city (`assets/props/city_skyline.glb`) all round outside the wall as the skyline. The towers are
## drawn as two MultiMeshes (warm and cold windows, world-space triplanar so every size of box
## gets whole windows), no collision: nobody can get up there.
var city_parts := 0
var occluders := 0

func _window_tex(warm: bool) -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 if warm else 8
	img.fill(Color(0, 0, 0, 1))
	for cx in 4:
		for cy in 4:
			if rng.randf() < 0.42: continue # dark window
			var c := Color(1.0, 0.78, 0.48) if warm else Color(0.62, 0.82, 1.0)
			c = c * rng.randf_range(0.55, 1.0)
			img.fill_rect(Rect2i(cx * 16 + 3, cy * 16 + 4, 10, 8), Color(c.r, c.g, c.b, 1))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _build_city() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mms: Array[MultiMesh] = []
	for warm in [true, false]:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.1, 0.1, 0.12)
		m.roughness = 0.55
		m.metallic = 0.3
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(1.0 / 4.0, 1.0 / 3.2, 1.0 / 4.0) # one window bay: 4 m wide, 3.2 m a floor
		m.emission_enabled = true
		m.emission_texture = _window_tex(warm)
		m.emission_energy_multiplier = 1.8
		var bm := box.duplicate() as BoxMesh
		bm.material = m
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = bm
		mms.append(mm)
	var xs: Array = [[], []]
	var neon_cols := [Color(1.0, 0.15, 0.6), Color(0.15, 0.9, 1.0), Color(0.75, 0.3, 1.0), Color(1.0, 0.85, 0.2)]
	var neon_m := StandardMaterial3D.new()
	neon_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	neon_m.vertex_color_use_as_albedo = true
	neon_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var signs := MultiMesh.new()
	signs.transform_format = MultiMesh.TRANSFORM_3D
	signs.use_colors = true
	var qm := QuadMesh.new()
	qm.material = neon_m
	signs.mesh = qm
	var sx: Array = []
	var lit := 0
	for k in buildings.size():
		var b: Array = buildings[k]
		var th: float = city_towers[k] if k < city_towers.size() else 18.0
		var base := Vector3(b[0], _raw_h(b[0], b[1]) + float(b[5]) + 0.4, b[1])
		var bs := Basis(Vector3.UP, float(b[2]))
		var size := Vector3(float(b[3]) - 0.3, th, float(b[4]) - 0.3)
		xs[k % 2].append(Transform3D(bs.scaled(size), base + Vector3(0, th / 2.0, 0)))
		# a neon sign on the street face, and a second one higher on the tall ones
		for h in ([2.2, th * 0.6] if th > 24.0 else [2.2]):
			var col: Color = neon_cols[(k + int(h)) % neon_cols.size()]
			var face := base + bs * Vector3(0, h - (float(b[5]) + 0.4 if h < 3.0 else 0.0), float(b[4]) / 2.0 + 0.08)
			sx.append([Transform3D(bs.scaled(Vector3(float(b[3]) * 0.55, 0.75 if h < 3.0 else 2.2, 1.0)), face), col])
			if h < 3.0 and lit < (8 if Gfx.weak else 14): # its colour on the pavement in front
				var l := OmniLight3D.new()
				l.light_color = col
				l.light_energy = 1.3
				l.omni_range = 7.5
				l.position = face + bs * Vector3(0, -0.4, 1.4)
				add_child(l)
				_amb_light(l)
				lit += 1
	for i in 2:
		mms[i].instance_count = xs[i].size()
		for t in xs[i].size(): mms[i].set_instance_transform(t, xs[i][t])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mms[i]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
	# the towers hide what is behind them (the occlusion pass: Godot skips drawing it)
	for i in 2:
		for t in xs[i]:
			var tt: Transform3D = t
			var oc := OccluderInstance3D.new()
			var bo := BoxOccluder3D.new()
			bo.size = tt.basis.get_scale() * 0.96
			oc.occluder = bo
			oc.transform = Transform3D(tt.basis.orthonormalized(), tt.origin)
			add_child(oc)
			occluders += 1
	signs.instance_count = sx.size()
	for t in sx.size():
		signs.set_instance_transform(t, sx[t][0])
		signs.set_instance_color(t, (sx[t][1] as Color) * 1.0)
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = signs
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smi)
	# the streets: asphalt strips with dashed centre lines, pavement everywhere else
	var asphalt := _flat(Color(0.05, 0.05, 0.055), 0.55, 0.1)
	var pave := _pbr(Color(0.16, 0.16, 0.17), Color(0.3, 0.3, 0.31), 0.03, Vector3(0.25, 0.25, 0.25), 0.85)
	_mesh_box(self, Vector3(WALL * 2.0, 0.04, WALL * 2.0), Vector3(0, 0.03, 0), pave)
	for zs in CITY_ROWS: _mesh_box(self, Vector3(WALL * 2.0, 0.04, 7.2), Vector3(0, 0.06, zs), asphalt)
	for xc in CITY_COLS: _mesh_box(self, Vector3(7.2, 0.045, WALL * 2.0), Vector3(xc, 0.065, 0), asphalt)
	var dash := MultiMesh.new()
	dash.transform_format = MultiMesh.TRANSFORM_3D
	var dm := BoxMesh.new()
	dm.size = Vector3(0.18, 0.02, 2.2)
	dm.material = _flat(Color(0.85, 0.8, 0.55), 0.6, 0.0, 0.25)
	dash.mesh = dm
	var dt: Array = []
	for zs in CITY_ROWS:
		for x in range(-int(WALL) + 3, int(WALL) - 3, 6): dt.append(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(x, 0.09, zs)))
	for xc in CITY_COLS:
		for z in range(-int(WALL) + 3, int(WALL) - 3, 6): dt.append(Transform3D(Basis(), Vector3(xc, 0.09, z)))
	dash.instance_count = dt.size()
	for t in dt.size(): dash.set_instance_transform(t, dt[t])
	var dmi := MultiMeshInstance3D.new()
	dmi.multimesh = dash
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dmi.visibility_range_end = 90.0
	add_child(dmi)
	# street lamps along the east-west streets, alternating sides
	var n := 0
	for zs in CITY_ROWS:
		for x in range(-96, 97, 32):
			var side := 1.0 if (n % 2 == 0) else -1.0
			var p := Vector3(float(x) + 8.0, 0.0, float(zs) + 4.4 * side)
			if in_site(p.x, p.z, 0.5): continue
			_lamp_post(p, 0.0 if side < 0.0 else PI)
			n += 1
	city_parts = xs[0].size() + xs[1].size() + sx.size() + n
	# the skyline: his cyberpunk city, round the outside (fewer on the older phones)
	var sky := _scene_model("res://assets/props/city_skyline.glb")
	if sky:
		var k := 3 if Gfx.weak else 6
		for i in k:
			var a := TAU * float(i) / float(k) + 0.4
			var c := sky.instantiate() as Node3D
			c.position = Vector3(cos(a), 0.0, sin(a)) * (HALF + 230.0) + Vector3(0, -2.0, 0)
			c.rotation.y = -a + PI / 2.0
			for gi in c.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(c)
			for gi in c.find_children("*", "GeometryInstance3D", true, false): gi.add_to_group("far")
			prop_glow(c, Color(0.9, 0.75, 1.0), 2.4)
			scenery += 1
	# the night over a city: purple-blue, a little brighter (the towers' glow)
	if env:
		env.fog_light_color = Color(0.2, 0.16, 0.3)
		env.ambient_light_color = Color(0.32, 0.3, 0.45)

# ---------------- the owner's props, where they belong ----------------
## His models from the November batch: the ancient world-tree and the outpost (watchtowers, forge,
## campfire, weapons) as landmarks in the woods, wrecked and vintage cars, the galleon run aground on
## the beach, saguaro cactus in the Empty Quarter, the crystal lantern tree, and his grass clumps
## scattered in chunks that each stop drawing past 55 m. Big ones get box collision; grass and the
## skyline none.
var owner_props := 0

func _solid(at: Vector3, yaw: float, size: Vector3, centre_y: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.rotation.y = yaw
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position.y = centre_y
	body.add_child(cs)
	add_child(body)
	return body

func _owner_prop(name: String, at: Vector3, yaw: float, k := 1.0, col := Vector3.ZERO, col_y := 0.0) -> Node3D:
	var ps := _scene_model("res://assets/props/%s.glb" % name)
	if ps == null: return null
	var parent: Node3D = self
	if col != Vector3.ZERO: parent = _solid(at, yaw, col * k, col_y * k)
	var n := ps.instantiate() as Node3D
	if parent == self:
		n.position = at
		n.rotation.y = yaw
	n.scale = Vector3(k, k, k)
	parent.add_child(n)
	sites.append([at.x, at.z, at.y, maxf(col.x, col.z) * k * 0.6 + 1.0])
	owner_props += 1
	return n

func _grass_chunks(name: String, count: int, rng: RandomNumberGenerator, kmin: float, kmax: float) -> void:
	var ps := _scene_model("res://assets/props/%s.glb" % name)
	if ps == null or count <= 0: return
	var src := ps.instantiate() as Node3D
	var meshes: Array = []
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		meshes.append([(mi as MeshInstance3D).mesh, (mi as MeshInstance3D).transform])
	src.free()
	var CH := 4 # 4 x 4 chunks over the map: each one is culled on its own (HLOD-style ranges)
	var cells := {}
	var tries := 0
	var placed := 0
	while placed < count and tries < count * 6:
		tries += 1
		var p := _free_spot(rng, 0.6)
		if p == Vector3.INF: continue
		if map_id == "beach" and p.z > BEACH_SHORE - 3.0: continue
		var key := Vector2i(clampi(int((p.x + HALF) / SIZE * CH), 0, CH - 1), clampi(int((p.z + HALF) / SIZE * CH), 0, CH - 1))
		if not cells.has(key): cells[key] = []
		var k := rng.randf_range(kmin, kmax)
		cells[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k, k, k)), p))
		placed += 1
	for key in cells:
		for m in meshes:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = m[0]
			mm.instance_count = cells[key].size()
			for t in cells[key].size(): mm.set_instance_transform(t, cells[key][t] * (m[1] as Transform3D))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 55.0 if not Gfx.weak else 40.0
			mmi.visibility_range_end_margin = 6.0
			add_child(mmi)
	owner_props += placed

func _build_owner_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_id) + 2026
	var spot := func(pad: float) -> Vector3:
		var p := _free_spot(rng, pad)
		return p
	match map_id:
		"forest", "village":
			var t: Vector3 = spot.call(9.0)
			if t != Vector3.INF and map_id == "forest": _owner_prop("world_tree", t, rng.randf() * TAU, 1.0, Vector3(5.0, 14.0, 5.0), 7.0)
			var o: Vector3 = spot.call(9.0)
			if o != Vector3.INF: _owner_prop("outpost", o, rng.randf() * TAU, 1.0, Vector3(14.0, 4.0, 6.0), 2.0)
			for i in 3:
				var c: Vector3 = spot.call(3.5)
				if c != Vector3.INF: _owner_prop("car_ruin", c, rng.randf() * TAU, 1.0, Vector3(4.4, 1.5, 2.0), 0.75)
			for i in 2:
				var lt: Vector3 = spot.call(3.0)
				if lt != Vector3.INF:
					var n := _owner_prop("lantern_tree", lt, rng.randf() * TAU, 1.0, Vector3(1.0, 3.0, 1.0), 1.5)
					if n: _lantern_light(n)
			if map_id == "village":
				for i in 2:
					var v: Vector3 = spot.call(3.5)
					if v != Vector3.INF: _owner_prop("car_vintage", v, rng.randf() * TAU, 1.0, Vector3(4.3, 1.5, 1.9), 0.75)
			_grass_chunks("grass_green", 70 if Gfx.weak else 140, rng, 0.8, 1.5)
		"fareej":
			for i in 3:
				var v: Vector3 = spot.call(3.5)
				if v != Vector3.INF: _owner_prop("car_vintage", v, rng.randf() * TAU, 1.0, Vector3(4.3, 1.5, 1.9), 0.75)
			_grass_chunks("grass_dry", 40 if Gfx.weak else 80, rng, 0.8, 1.3)
		"rubkhali":
			for i in (14 if Gfx.weak else 24):
				var c: Vector3 = spot.call(2.0)
				if c != Vector3.INF: _owner_prop("cactus", c, rng.randf() * TAU, rng.randf_range(0.7, 1.3), Vector3(0.7, 4.0, 0.7), 2.0)
			_grass_chunks("grass_dry", 80 if Gfx.weak else 160, rng, 0.8, 1.4)
		"beach":
			for gx in [-66.0, 66.0, -40.0, 40.0]: # run aground on the sand by the water, wherever it fits
				var g := Vector3(gx, height(gx, BEACH_SHORE - 6.0) - 0.6, BEACH_SHORE - 6.0)
				if in_site(g.x, g.z, 14.0): continue
				_owner_prop("galleon", g, 0.35 * signf(gx), 1.0, Vector3(26.0, 7.0, 8.0), 3.0)
				break
			_grass_chunks("grass_dry", 40 if Gfx.weak else 90, rng, 0.8, 1.3)
		"city":
			for i in 4:
				var v: Vector3 = spot.call(3.5)
				if v != Vector3.INF: _owner_prop("car_vintage", v, PI / 2.0 * float(rng.randi() % 4), 1.0, Vector3(4.3, 1.5, 1.9), 0.75)
			for i in 4:
				var c: Vector3 = spot.call(3.5)
				if c != Vector3.INF: _owner_prop("car_ruin", c, rng.randf() * TAU, 1.0, Vector3(4.4, 1.5, 2.0), 0.75)
			for i in 2:
				var lt: Vector3 = spot.call(3.0)
				if lt != Vector3.INF:
					var n := _owner_prop("lantern_tree", lt, rng.randf() * TAU, 1.0, Vector3(1.0, 3.0, 1.0), 1.5)
					if n: _lantern_light(n)

func _lantern_light(n: Node3D) -> void:
	prop_glow(n, Color(0.85, 0.97, 1.0), 2.4) # crystal lanterns: a cold blue-white
	var l := OmniLight3D.new()
	l.light_color = Color(0.55, 0.88, 1.0)
	l.light_energy = 1.5
	l.omni_range = 7.0
	l.position = Vector3(0, 1.7, 0)
	n.add_child(l)
	_amb_light(l)

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

## Where the ravens sit (`NFRavens`): the top of every gallows post on the map (not the roads'),
## and the roofs.
func raven_perches() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if map_id == "garage": return out
	var gallows := ResourceLoader.exists("res://assets/props/hook.glb")
	for i in mini(road_hook0, hook_points.size()):
		out.append(hook_points[i] + (Vector3(0, 5.18, HOOK_POST_Z) if gallows else Vector3(0, 3.32, 0)))
	for b in buildings:
		if map_id == "city": continue # the towers are too tall to see a bird on
		out.append(_local(b, Vector3(0, float(b[5]) + 0.5, 0)))
	return out

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
		l.distance_fade_enabled = true # a 5 m glow: nobody sees it from further than this
		l.distance_fade_begin = 40.0
		l.distance_fade_length = 8.0
		if hook_points.find(hp) >= road_hook0 and road_hook0 > 0: # the 18 along the roads: only drawn near
			for gi in body.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).visibility_range_end = 150.0
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
		# the escape road: a 600 m walled lane behind the gate (local -z is "out"), the escape car
		# waiting at its start, hooks and crash barriers along it, and the last gate at its end
		var road_mat := _flat(Color(0.07, 0.065, 0.06), 0.8)
		var lane_w := LANE_W
		var road_far := ROAD_LEN + 8.5
		var z0 := 0.5
		while z0 < road_far: # in 50 m pieces: each light only has to reach the pieces near it, and culling works
			var z1 := minf(z0 + 50.0, road_far)
			_box(body, Vector3(lane_w, 1.0, z1 - z0), Vector3(0, gy - 0.48, -(z0 + z1) / 2.0), road_mat)
			for sx in [-1.0, 1.0]:
				_box(body, Vector3(0.6, 9.0, z1 - z0), Vector3(sx * (lane_w / 2.0 + 0.3), gy + 3.5, -(z0 + z1) / 2.0), _mat.concrete)
			for ch in body.get_children(): # 600 m of floor and walls drawn again in every shadow cascade: not worth it
				if ch is MeshInstance3D and (ch as MeshInstance3D).position.z < -1.0:
					(ch as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			z0 = z1
		_box(body, Vector3(lane_w + 1.2, 9.0, 0.6), Vector3(0, gy + 3.5, -ROAD_LEN - 6.0), _mat.concrete) # dead end behind the last gate
		for i in int(ROAD_LEN / 40.0): # lamps down the lane, alternating sides
			var lz := -8.0 - i * 40.0
			var sx := -1.0 if i % 2 == 0 else 1.0
			_mesh_box(body, Vector3(0.12, 4.0, 0.12), Vector3(sx * (lane_w / 2.0 - 0.3), gy + 2.0, lz), _mat.metal)
			_mesh_box(body, Vector3(0.3, 0.12, 0.3), Vector3(sx * (lane_w / 2.0 - 0.5), gy + 4.0, lz), _flat(Color(1.0, 0.85, 0.55), 0.5, 0.0, 3.0))
			var ll := OmniLight3D.new()
			ll.position = Vector3(sx * (lane_w / 2.0 - 0.9), gy + 3.6, lz)
			ll.light_color = Color(1.0, 0.82, 0.55)
			ll.light_energy = 2.0
			ll.omni_range = 16.0
			ll.distance_fade_enabled = true
			ll.distance_fade_begin = 36.0
			ll.distance_fade_length = 8.0
			body.add_child(ll) # steady, no halo in the fog: thirty of them along each road
		# dashed centre line: one MultiMesh for the whole road
		var dash := BoxMesh.new()
		dash.size = Vector3(0.16, 0.02, 2.4)
		dash.material = _flat(Color(0.7, 0.65, 0.3))
		var dmm := MultiMesh.new()
		dmm.transform_format = MultiMesh.TRANSFORM_3D
		dmm.mesh = dash
		var n_dash := int((ROAD_LEN - 6.0) / 6.5)
		dmm.instance_count = n_dash
		for k in n_dash: dmm.set_instance_transform(k, Transform3D(Basis(), Vector3(0, gy + 0.03, -5.0 - k * 6.5)))
		var dmi := MultiMeshInstance3D.new()
		dmi.multimesh = dmm
		dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(dmi)
		# crash barriers half across the lane, between the hooks, first one side then the other:
		# the car has to weave, so a driver who looks back at the killer hits one
		var reflector := _flat(Color(1.0, 0.2, 0.12), 0.4, 0.0, 2.5)
		for k in range(1, ROAD_HOOKS):
			var bz := -30.0 - 60.0 * k
			var bx := (lane_w / 2.0 - 2.7) * (1.0 if k % 2 == 1 else -1.0)
			_box(body, Vector3(5.4, 1.1, 0.7), Vector3(bx, gy + 0.55, bz), _mat.concrete)
			_mesh_box(body, Vector3(5.0, 0.14, 0.05), Vector3(bx, gy + 0.85, bz + 0.37), reflector)
		# how far is left, every 100 m on the wall
		for left in [500, 400, 300, 200, 100]:
			var mz := -(ROAD_LEN - float(left))
			_mesh_box(body, Vector3(2.6, 1.0, 0.08), Vector3(-(lane_w / 2.0 - 0.1), gy + 4.4, mz), _flat(Color(0.05, 0.12, 0.07), 0.7))
			_sign_text(body, "%d م" % left, Vector3(-(lane_w / 2.0 - 0.1), gy + 4.4, mz + 0.06), 70, Color(0.65, 1.0, 0.72))
		# the last gate: two towers and a lit header; through it, you are out
		var finish := _flat(Color(0.8, 1.0, 0.85), 0.5, 0.0, 4.0)
		var fz := -ROAD_LEN
		for sx in [-1.0, 1.0]:
			_box(body, Vector3(1.6, 8.0, 1.6), Vector3(sx * (lane_w / 2.0 - 0.8), gy + 4.0, fz), _mat.concrete)
			_mesh_box(body, Vector3(0.25, 6.6, 0.25), Vector3(sx * (lane_w / 2.0 - 1.75), gy + 3.3, fz + 0.85), finish)
		_mesh_box(body, Vector3(lane_w, 1.2, 1.6), Vector3(0, gy + 7.4, fz), _mat.concrete)
		_mesh_box(body, Vector3(lane_w - 3.4, 0.3, 0.2), Vector3(0, gy + 6.55, fz + 0.85), finish)
		_sign_text(body, "البوابة الأخيرة", Vector3(0, gy + 7.4, fz + 0.85), 120, Color(0.6, 1.0, 0.7))
		var fl := OmniLight3D.new()
		fl.position = Vector3(0, gy + 4.0, fz + 3.0)
		fl.light_color = Color(0.7, 1.0, 0.8)
		fl.light_energy = 6.0
		fl.omni_range = 26.0
		fl.distance_fade_enabled = true
		fl.distance_fade_begin = 90.0
		fl.distance_fade_length = 20.0
		body.add_child(fl)
		# from inside the map every gate looks straight down its road: 600 m of pieces, lamps,
		# barriers and signs were all drawn (and their lights counted) whenever a gate was in view.
		# Past 170 m they are not drawn at all; the fog already hides them there.
		for gi in body.find_children("*", "GeometryInstance3D", true, false):
			var g3 := gi as GeometryInstance3D
			if g3 is MultiMeshInstance3D or g3.position.z > -14.0: continue
			g3.visibility_range_end = 170.0
			g3.visibility_range_end_margin = 6.0

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
	if map_id != "kuwait": # Kuwait City's east side is the open sea
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
			runs.append([Vector3(gx + GATE_HALF, 0, z), Vector3(1, 0, 0), (KW_SAND + 4.0 if map_id == "kuwait" else WALL) - gx - GATE_HALF, yaw])
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
	return out_d > ROAD_LEN - 1.5 and lateral < LANE_W / 2.0 + 0.5

## How far along gate i's road a point is (0 at the gate, ROAD_LEN at the last gate).
func road_d(i: int, pos: Vector3) -> float:
	var gp: Vector3 = gate_points[i][0]
	return (pos - gp).dot(Basis(Vector3.UP, float(gate_points[i][1])) * Vector3(0, 0, -1))

## The metres left to the last gate.
func road_left(i: int, pos: Vector3) -> float:
	return maxf(ROAD_LEN - road_d(i, pos), 0.0)

## The road (past the gate, between its walls) this point is on, -1 none.
func road_at(pos: Vector3) -> int:
	for i in gate_points.size():
		var gp: Vector3 = gate_points[i][0]
		var out := Basis(Vector3.UP, float(gate_points[i][1])) * Vector3(0, 0, -1)
		var rel := pos - gp
		if rel.dot(out) > 1.0 and absf(rel.dot(out.cross(Vector3.UP))) < LANE_W / 2.0 + 1.0 and absf(rel.y) < 5.0: return i
	return -1

## Where gate i's escape car waits, and where its road ends (the last gate).
func esc_start(i: int) -> Vector3:
	var g: Array = gate_points[i]
	var at: Vector3 = (g[0] as Vector3) + Basis(Vector3.UP, float(g[1])) * Vector3(0, 0, -ESC_AT)
	return Vector3(at.x, (g[0] as Vector3).y, at.z)

func road_end(i: int) -> Vector3:
	var g: Array = gate_points[i]
	return (g[0] as Vector3) + Basis(Vector3.UP, float(g[1])) * Vector3(0, 0, -ROAD_LEN)

## One escape car waiting just past each gate, its nose down the road: the survivors' way out.
func _place_escape_cars() -> void:
	var ps := _model("car_drive") if _model("car_drive") else _model("car")
	for gi in gate_points.size():
		var c := NFCar.new()
		c.name = "EscapeCar%d" % gi
		c.position = esc_start(gi) + Vector3(0, 0.05, 0)
		c.rotation.y = float(gate_points[gi][1]) + PI
		add_child(c)
		c.setup(ps, CAR_SCALE, null, Color(0.5, 0.48, 0.45), false) # no cabin: they drive it from behind
		c.limit = ESC_TOP
		esc_cars.append(c)

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
		if map_id == "kuwait" and x > KW_SHORE - 6.0: continue
		# the beach: nothing in front of the pier's ramp (a barrel or a car there blocked the way up)
		if map_id == "beach" and absf(x) < PIER_W / 2.0 + 3.0 + pad and z > PIER_FROM - 18.0: continue
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
				NFDecor.fire(body, 0.25, not Gfx.weak)
				fire_fx += 1
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
	tw.tween_property(env, "ambient_light_energy", (0.45 if on else 1.0) * (DARK_AMB_E if grid_off else _amb_base), 1.2)
	for m in garage_panels: # the strip lights go dead with everything else
		tw.parallel().tween_property(m, "emission_energy_multiplier", 0.05 if on else 3.2, 1.0)
	var lit := not on and not grid_off # Kuwait City's lamp heads and their glare go dark too
	for i in grid_mats.size():
		tw.parallel().tween_property(grid_mats[i], "emission_energy_multiplier", _grid_glow[i] if lit else 0.0, 0.6)
	if grid_glare: tw.parallel().tween_property(grid_glare, "albedo_color:a", 0.55 if lit else 0.0, 0.6)
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
	l.distance_fade_begin = 38.0 if Gfx.weak else 55.0
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
		lm.albedo_color = Color(0.16, 0.15, 0.12)
	leaves.lifetime = 9.0 if theme == "snow" else 7.0
	leaves.preprocess = leaves.lifetime
	leaves.visibility_aabb = AABB(Vector3(-22, -14, -22), Vector3(44, 26, 44))
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	leaves.emitting = map_id != "garage" # nothing falls from the sky under a concrete slab
	add_child(leaves)
	if theme == "rain":
		leaves.emitting = false
		if map_id != "garage": # it rains outside the car park, not under the slab
			rain = NFDecor.rain([350, 650, 1000][Gfx.eff_effects()] if not Gfx.weak else 300)
			add_child(rain)
		_bolt_t = 8.0 + randf() * 10.0

## Decals: blood pooled under every hook and dragged away from it, oil under the generators, grime
## and stains about the map, and on the rain night puddles that mirror the lamps. Forward+ draws all
## of them; the Mobile renderer of the older phones only the ones by the hooks and generators.
func _build_decals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_id + theme) + gen_points.size() * 31
	var few := Gfx.weak or not Gfx.engine_hd()
	var holder := Node3D.new()
	holder.name = "Decals"
	add_child(holder)
	for i in hook_points.size():
		if i >= road_hook0 and road_hook0 > 0 and i % 2 == 1: continue # every other one along the roads
		var hp: Vector3 = hook_points[i] + Vector3(0, 0, 0.9)
		NFDecor.decal(holder, hp, rng.randf_range(1.4, 2.0), "blood", rng.randf() * TAU)
		decals += 1
		if not few and i < road_hook0: # someone was dragged here
			var a := rng.randf() * TAU
			NFDecor.decal(holder, hp + Vector3(cos(a), 0, sin(a)) * 2.2, 0.8, "drag", -a, 3.2, 30.0)
			decals += 1
	for g in gen_points:
		NFDecor.decal(holder, g + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)), rng.randf_range(2.0, 2.8), "oil", rng.randf() * TAU)
		decals += 1
	if few: return
	var tries := 0
	var want := 26 if map_id != "garage" else 40
	var laid := 0
	while laid < want and tries < want * 4:
		tries += 1
		var p := Vector3(rng.randf_range(-HALF + 6, HALF - 6), 0, rng.randf_range(-HALF + 6, HALF - 6))
		if map_id == "beach" and p.z > BEACH_SHORE - 2.0: continue # not in the water
		p.y = height(p.x, p.z) if map_id != "garage" else 0.0
		var kind := "dirt" if rng.randf() < 0.65 else ("oil" if map_id == "garage" else "blood")
		NFDecor.decal(holder, p, rng.randf_range(1.5, 3.5) if kind == "dirt" else rng.randf_range(0.8, 1.5), kind, rng.randf() * TAU, rng.randf_range(1.0, 1.6))
		laid += 1
	decals += laid
	if theme == "rain" or map_id == "garage": # standing water (the car park leaks)
		var n := 0
		tries = 0
		while n < 18 and tries < 80:
			tries += 1
			var p := Vector3(rng.randf_range(-HALF + 8, HALF - 8), 0, rng.randf_range(-HALF + 8, HALF - 8))
			if map_id == "beach" and p.z > BEACH_SHORE - 2.0: continue
			p.y = height(p.x, p.z) if map_id != "garage" else 0.0
			NFDecor.decal(holder, p, rng.randf_range(1.8, 4.0), "puddle", rng.randf() * TAU, rng.randf_range(1.0, 1.8), 45.0)
			n += 1
		decals += n

## The owner's scenery models: big dunes outside the Empty Quarter's wall (and behind the beach) so
## the horizon is sand hills, not a flat line; sand patches on the beach; and on the forest patches of
## forest floor — leaf litter, ferns, half-buried stones and a fallen log — laid where the ground is
## flat enough to take them. No collision: it is all low or outside the wall.
var scenery := 0

func _scene_model(path: String) -> PackedScene:
	if not _models.has(path): _models[path] = load(path) if ResourceLoader.exists(path) else null
	return _models[path]

func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_id) + 77
	if map_id in ["rubkhali", "beach"]:
		var dune := _scene_model("res://assets/scatter/dune.glb")
		if dune:
			var n := 12 if map_id == "rubkhali" else 5
			for i in n:
				var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(n)
				if map_id == "beach": a = PI * 0.15 + PI * 0.7 * float(i) / float(n - 1) # the south side only: the sea is north
				var r := HALF + rng.randf_range(55.0, 95.0)
				var d := dune.instantiate() as Node3D
				var k := rng.randf_range(0.9, 1.5)
				d.scale = Vector3(k, k * rng.randf_range(0.8, 1.2), k)
				d.position = Vector3(cos(a) * r, -1.5, sin(a) * r)
				d.rotation.y = rng.randf() * TAU
				for gi in d.find_children("*", "GeometryInstance3D", true, false):
					(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(d)
				scenery += 1
	if map_id == "beach":
		var blob := _scene_model("res://assets/scatter/sand_blob.glb")
		if blob:
			var tries := 0
			var n := 0
			while n < 14 and tries < 80:
				tries += 1
				var p := _free_spot(rng, 5.0)
				if p == Vector3.INF or p.z > BEACH_SHORE - 4.0: continue
				if absf(height(p.x - 4.0, p.z) - height(p.x + 4.0, p.z)) > 0.35: continue
				var b := blob.instantiate() as Node3D
				b.position = p + Vector3(0, -0.06, 0)
				b.rotation.y = rng.randf() * TAU
				var k := rng.randf_range(0.6, 1.1)
				b.scale = Vector3(k, k, k)
				add_child(b)
				n += 1
			scenery += n
	if map_id == "forest":
		var patch := _scene_model("res://assets/scatter/forest_floor.glb")
		if patch:
			var want := 6 if Gfx.weak else 12
			var tries := 0
			var n := 0
			while n < want and tries < 120:
				tries += 1
				var p := _free_spot(rng, 4.5)
				if p == Vector3.INF: continue
				var k := rng.randf_range(0.6, 0.8)
				var e := 6.0 * k
				var hs := [height(p.x - e, p.z - e), height(p.x + e, p.z - e), height(p.x - e, p.z + e), height(p.x + e, p.z + e)]
				if (hs.max() as float) - (hs.min() as float) > 0.55: continue # too steep: it would float
				var f := patch.instantiate() as Node3D
				f.position = Vector3(p.x, (hs.min() as float) + 0.04, p.z)
				f.rotation.y = rng.randf() * TAU
				f.scale = Vector3(k, k, k)
				for gi in f.find_children("*", "GeometryInstance3D", true, false):
					(gi as GeometryInstance3D).visibility_range_end = 70.0
					(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(f)
				n += 1
			scenery += n

## The rain night's lightning: every 9-25 s the sky and the whole map flash white twice, quickly.
## (No thunder until the owner sends a sound: nothing is synthesized.)
func _step_lightning(dt: float) -> void:
	_bolt_t -= dt
	if _bolt_t <= 0.0:
		_bolt_t = randf_range(9.0, 25.0)
		_bolt = 1.0
	if _bolt <= 0.0: return
	_bolt = maxf(_bolt - dt * 2.6, 0.0)
	# two strokes: bright, a dip, bright again, fading
	var k := _bolt * (0.6 + 0.4 * absf(sin(_bolt * 18.0)))
	var mb := DARK_MOON_E if grid_off else _moon_base # the power out: the flash lights the dark, then it is dark again
	var ab := DARK_AMB_E if grid_off else _amb_base
	if moon: moon.light_energy = mb * (1.0 + k * 3.5)
	if env: env.ambient_light_energy = ab * (1.0 + k * 1.6)
	if _bolt <= 0.0:
		if moon: moon.light_energy = mb
		if env: env.ambient_light_energy = ab

## Rain makes every surface wet: rougher things get glossier and a little darker (the reflections
## of the lamps then run over the ground). Applied to the map's own materials once they exist.
func _wet() -> void:
	for k in _mat:
		var m = _mat[k]
		if m is StandardMaterial3D:
			var sm := m as StandardMaterial3D
			sm.roughness = clampf(sm.roughness * 0.55, 0.08, 1.0)
			sm.albedo_color = sm.albedo_color.darkened(0.18)

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
	if theme == "rain": return "rain"
	return "fog" if theme == "fog" else "night"

## Visibility ranges by size (the optimisation pass): whatever is small stops drawing at about half
## the preset's view distance, everything else at the view distance (Low 80 m … Ultra 200 m; fog has
## swallowed it well before). Only things under 30 m across: Godot measures the range to the middle
## of an instance, so a map-wide MultiMesh or the ground must never get one. A small margin of
## hysteresis keeps them from flickering at the edge. Nodes in the "far" group (dunes, the skyline,
## the wall) and anything that already set its own range are left alone.
var ranged := 0
func _apply_view_ranges() -> void:
	var view := Gfx.view_dist()
	ranged = 0
	for gi in find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		if g.is_in_group("far"): continue
		if g.visibility_range_end > 0.0 and not g.has_meta("vr"): continue # set on purpose elsewhere
		var ab := g.get_aabb()
		var sc := g.global_transform.basis.get_scale()
		var big := maxf(ab.size.x * absf(sc.x), maxf(ab.size.y * absf(sc.y), ab.size.z * absf(sc.z)))
		if big > 30.0 or big <= 0.0: continue
		g.visibility_range_end = minf(view * 0.5, 70.0) if big < 1.6 else view
		g.visibility_range_end_margin = 4.0
		g.set_meta("vr", true)
		ranged += 1

func _apply_quality() -> void:
	_apply_view_ranges()
	var fx := Gfx.eff_effects()
	var sh := Gfx.eff_shadows()
	env.glow_enabled = fx >= 1
	NFLook.apply(env, look_kind())
	if map_id == "kuwait" and theme != "halloween": _kw_look()
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
	if theme == "sunset" and env and moon: _step_sunset(_dt)
	if not animals.is_empty(): _step_animals(_dt)
	for i in amb_lights.size():
		var e: Array = amb_lights[i]
		var l: Light3D = e[0]
		var gridded := e.size() > 5 and bool(e[5]) or (grid_all and not pumpkin_lights.has(l))
		var want := 0.0 if (blackout or (grid_off and gridded)) else 1.0
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
		elif market_dark or (grid_off and grid_all): ml[0].light_energy = 0.0
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
		if rain: rain.global_position = follow.global_position + Vector3(0, 11.0, 0)
	if theme == "rain": _step_lightning(_dt)

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
		NFDecor.fire(body, 0.25, not Gfx.weak)
		fire_fx += 1
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

## The owner's animals (assets/animals): three horse breeds with their own walk, graze and idle
## clips (vinish.dev, CC BY 4.0), and his dromedary (no clips: it plods with a bob). The old merged
## meshes are the fallback when a file is missing.
const HORSES := ["arabian-horse", "bay-horse", "paint-horse"]
var animal_models := 0

func _animal_node(kind: String, k: int) -> Node3D:
	var path := ("res://assets/animals/%s.glb" % HORSES[k % HORSES.size()]) if kind == "horse" else "res://assets/animals/camel.glb"
	if ResourceLoader.exists(path):
		var n := (load(path) as PackedScene).instantiate() as Node3D
		var inner := Node3D.new() # the camel's model faces +X: turned so every animal faces +Z
		if kind == "camel": n.rotation.y = -PI / 2.0
		inner.add_child(n)
		for gi in n.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).visibility_range_end = 95.0 # the storm hides them long before this
			var aabb := (gi as VisualInstance3D).get_aabb()
			if aabb.size.length() < 0.12: (gi as GeometryInstance3D).visibility_range_end = 18.0 # eyes, lashes
		animal_models += 1
		return inner
	var mi := MeshInstance3D.new()
	mi.mesh = _animal_mesh(kind)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.visibility_range_end = 95.0
	return mi

func _build_animals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 616
	var count := 5 if Gfx.weak else 9 # every one is a skinned model of ~100k triangles up close
	for i in count:
		var kind := "camel" if i % 3 == 0 else "horse"
		var start := _free_spot(rng, 4.0)
		if start == Vector3.INF: continue
		var mi := _animal_node(kind, i)
		mi.position = start
		add_child(mi)
		var path: Array[Vector3] = [start]
		var p := Vector2(start.x, start.z)
		for k in 3: # a small loop of waypoints around where it started
			p += Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(9.0, 20.0)
			p.x = clampf(p.x, -WALL + 10.0, WALL - 10.0)
			p.y = clampf(p.y, -WALL + 10.0, WALL - 10.0)
			path.append(Vector3(p.x, height(p.x, p.y), p.y))
		var stand: bool = rng.randf() < (0.5 if kind == "camel" else 0.3)
		var ap: AnimationPlayer = null
		var found := mi.find_children("*", "AnimationPlayer", true, false)
		if not found.is_empty(): ap = found[0]
		animals.append({"node": mi, "path": path, "i": 1, "speed": rng.randf_range(0.9, 1.4),
			"bob": rng.randf() * TAU, "stand": stand, "yaw": rng.randf() * TAU, "ap": ap, "kind": kind})
		mi.rotation.y = animals[-1].yaw
		if ap:
			for c in ["Walk", "Idle", "Graze"]:
				if ap.has_animation(c): ap.get_animation(c).loop_mode = Animation.LOOP_LINEAR
			_animal_clip(animals[-1], "Graze" if stand else "Walk")

## Play a horse's clip (its own walk keeps pace with how fast it goes).
func _animal_clip(a: Dictionary, clip: String) -> void:
	var ap: AnimationPlayer = a.get("ap")
	if ap == null or not ap.has_animation(clip): return
	if ap.current_animation != clip: ap.play(clip, 0.4)
	ap.speed_scale = float(a.speed) / 1.25 if clip == "Walk" else 1.0

## Horses and camels plod between their waypoints. No sound, no collision: they are scenery.
func _step_animals(dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for a in animals:
		var mi: Node3D = a.node
		var base: float = height(mi.position.x, mi.position.z)
		if a.stand:
			mi.position.y = base + (0.0 if a.ap else 0.02 * sin(t * 0.7 + a.bob))
			mi.rotation.y = a.yaw + 0.05 * sin(t * 0.3 + a.bob)
			if a.ap and fmod(t + float(a.bob) * 3.0, 14.0) < dt * 1.5: # now and then a horse looks up from grazing
				_animal_clip(a, "Idle" if (a.ap as AnimationPlayer).current_animation == "Graze" else "Graze")
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
		if a.ap: # its own legs carry it: no bobbing
			mi.position.y = base
			continue
		mi.position.y = base + 0.06 * absf(sin(t * 3.4 + a.bob)) # plodding bob
		mi.rotation.x = 0.03 * sin(t * 3.4 + a.bob)

# ---------------- snow and halloween dressing ----------------
## A carved pumpkin with a candle inside.
var pumpkin_lights: Array[OmniLight3D] = []
var _pumpkin_xf: Array = [] # his pumpkin model, gathered and drawn as one MultiMesh at the end

func _pumpkin(at: Vector3, yaw: float, lit := true) -> void:
	pumpkins += 1
	if _scene_model("res://assets/props/pumpkin.glb"): # his Wicked Harvest pumpkin
		_pumpkin_xf.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * randf_range(0.85, 1.3)), at))
		if lit:
			var pl := OmniLight3D.new()
			pl.position = at + Vector3(0, 0.45, 0)
			pl.light_color = Color(1.0, 0.55, 0.15)
			pl.light_energy = 1.3
			pl.omni_range = 5.0
			add_child(pl)
			pumpkin_lights.append(pl)
			_amb_light(pl)
		return
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
	pumpkin_lights.append(l)
	_amb_light(l)
	add_child(root)

func _pumpkin_glow(mmi: MultiMeshInstance3D) -> void:
	var mesh := mmi.multimesh.mesh
	for si in mesh.get_surface_count():
		var m := mesh.surface_get_material(si) as StandardMaterial3D
		if m == null or m.get_texture(BaseMaterial3D.TEXTURE_EMISSION) == null: continue
		m.emission_enabled = true
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		m.emission = Color(1.0, 0.55, 0.15)
		m.emission_energy_multiplier = 3.0

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
	for i in (40 if Gfx.weak else 70): # pumpkins everywhere; one in three lit (lights cost)
		var p := _free_spot(rng, 1.0)
		if p == Vector3.INF: continue
		_pumpkin(p, rng.randf() * TAU, i % 3 == 0)
	for g in gen_points: _pumpkin(g + Vector3(1.6, 0, 1.2), rng.randf() * TAU, false)
	for hp in hook_points.slice(0, road_hook0): _pumpkin(hp + Vector3(-1.2, 0, 1.6), rng.randf() * TAU, false)
	for g in gate_points: # down both escape roads too, along the wall
		var gp: Vector3 = g[0]
		var gb := Basis(Vector3.UP, float(g[1]))
		for d in range(30, 600, 45):
			_pumpkin(gp + gb * Vector3((LANE_W / 2.0 - 0.8) * (1.0 if (d / 45) % 2 == 0 else -1.0), 0.0, -float(d)), rng.randf() * TAU, d % 135 == 30)
	if not _pumpkin_xf.is_empty():
		for m in _kw_many("pumpkin", _pumpkin_xf, Vector3.ZERO, 0.0, 120.0, true):
			_pumpkin_glow(m)
	# (the lights stay on now: the power box turns them out, see set_grid)
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
const PIER_Y := 0.45        # the deck of the pier that carries you out over the water to the north gate
const PIER_W := 8.0
const PIER_FROM := 34.0     # where the deck starts on the sand (a ramp comes up to it)

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
	var half_gap := PIER_W / 2.0 + 0.4 # the pier goes through it; under the deck it stays shut
	for sx in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var wide := SIZE / 2.0 - half_gap
		bs.size = Vector3(wide, 14.0, 4.0)
		cs.shape = bs
		cs.position = Vector3(sx * (half_gap + wide / 2.0), 5.0, BEACH_SHORE + 9.0) # wade in knee-deep, no further
		deep.add_child(cs)
	var under := CollisionShape3D.new()
	var ub := BoxShape3D.new()
	ub.size = Vector3(half_gap * 2.0, 12.0, 4.0)
	under.shape = ub
	under.position = Vector3(0, PIER_Y - 0.45 - 6.0, BEACH_SHORE + 9.0)
	deep.add_child(under)
	add_child(deep)
	_build_pier()
	# ---- palms: clusters on the dry sand, a few leaning over the water ----
	var palms := []
	for i in 90:
		var p := _free_spot(rng, 2.6)
		if p == Vector3.INF: continue
		if p.z > BEACH_SHORE + 2.0: continue
		if absf(p.x) < PIER_W / 2.0 + 2.0 and p.z > PIER_FROM - 12.0: continue # keep the way onto the pier clear
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

## The pier: a plank deck on posts from the sand out over the lagoon to the north gate (that gate
## stands on it at PIER_Y), with rails on both sides and a few lanterns, so both escape roads of the
## beach can be reached. Wide enough for her car.
func _build_pier() -> void:
	var body := StaticBody3D.new()
	body.name = "Pier"
	var deck_from := PIER_FROM
	var deck_to := WALL + 0.8
	var plank: Material = _mat.wood
	var mid_z := (deck_from + deck_to) / 2.0
	_box(body, Vector3(PIER_W, 0.4, deck_to - deck_from), Vector3(0, PIER_Y - 0.2, mid_z), plank)
	# a ramp up from the sand where the deck starts above it
	var sand := _raw_h(0.0, deck_from - 8.0)
	var rise := PIER_Y - sand
	if rise > 0.15:
		var run := 8.0
		var ang := atan2(rise, run)
		var ramp_len := sqrt(run * run + rise * rise)
		_box(body, Vector3(PIER_W, 0.4, ramp_len), Vector3(0, (sand + PIER_Y) / 2.0 - 0.2, deck_from - run / 2.0), plank, false, Vector3(-ang, 0, 0)) # tipped up toward the deck
	# posts into the water and rails along both sides (the rails are what keep you on the deck)
	var z := deck_from + 2.0
	while z < deck_to - 1.0:
		for sx in [-1.0, 1.0]:
			var ground := _raw_h(sx * (PIER_W / 2.0 - 0.3), z)
			_mesh_box(body, Vector3(0.35, PIER_Y - ground + 0.2, 0.35), Vector3(sx * (PIER_W / 2.0 - 0.3), (PIER_Y + ground) / 2.0 - 0.1, z), plank)
			_mesh_box(body, Vector3(0.14, 1.1, 0.14), Vector3(sx * (PIER_W / 2.0 - 0.1), PIER_Y + 0.55, z), plank)
		z += 6.0
	for sx in [-1.0, 1.0]:
		_box(body, Vector3(0.16, 1.2, deck_to - deck_from), Vector3(sx * (PIER_W / 2.0 - 0.1), PIER_Y + 0.6, mid_z), plank)
	add_child(body)
	for lz in [deck_from + 12.0, mid_z + 6.0, deck_to - 10.0]: # lanterns on the rail
		var ll := OmniLight3D.new()
		ll.position = Vector3(PIER_W / 2.0 - 0.5, PIER_Y + 1.6, lz)
		ll.light_color = Color(1.0, 0.75, 0.45)
		ll.light_energy = 1.6
		ll.omni_range = 11.0
		add_child(ll)
		_amb_light(ll)
		_mesh_box(self, Vector3(0.25, 0.32, 0.25), ll.position, _flat(Color(1.0, 0.8, 0.5), 0.5, 0.0, 3.0))

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
