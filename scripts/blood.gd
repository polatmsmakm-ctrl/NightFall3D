class_name NFBlood
extends Node3D
## Blood, built from the owner's three Meshy models (assets/props/blood_pool.glb, blood_smear.glb,
## blood_drop.glb):
##  * drops (`drip`): his droplet, falling under gravity, one physics ray per drop per step; where a
##    drop lands it leaves a spatter on that surface (the ground, a roof, a wall);
##  * marks: his puddle (spatter, pools, wall splashes) and his smear (the drag of a running or crawling
##    survivor), laid on the surface a ray found, turned and sized at random, spreading out after they
##    land, then drying dark and flat and fading away (`MARK_LIFE`);
##  * `bleed(name, feet, kind)`: called every frame for every survivor on every phone; a hurt survivor
##    drips from the wound (more often the faster they move) and a crawling one drags a smear;
##  * `splash(at, dir)`: a blow lands — a spray of drops out the far side, a splash on a wall behind
##    the victim if there is one within reach, and a pool spreading under them.
## Everything is pooled: drops in one MultiMesh of `MAX_DROPS`, marks in three ring-buffered
## MultiMeshes (ground, smears, walls). Old marks are overwritten when a pool is full. No node is
## created after `setup()`.

const MARK_LIFE := 80.0      # seconds a mark stays (it dries from DRY_FROM of its life and fades at the end)
const DRY_FROM := 0.3
const FADE := 0.15           # the last share of its life it spends fading out
const GRAVITY := 9.8
const DROP_LIFE := 3.0

var max_drops := 48
var caps := {"pool": 110, "smear": 40, "wall": 30}

var world: NightWorld
var exclude: Array = []      # RIDs the drops pass through (the local player's own capsule)
var drops_mm: MultiMesh
var _d_pos: PackedVector3Array = []
var _d_vel: PackedVector3Array = []
var _d_size: PackedFloat32Array = []
var _d_age: PackedFloat32Array = []
var _d_live := 0
var sets := {}               # kind -> {mm, xf: Array[Transform3D], size, born, grow, seed, n, next}
var _clock := 0.0
var _tick := 0.0
var _st := {}                # survivor name -> {t, last, d, ms}
var landed := 0              # drops that reached a surface (tests)
var rays := 0                # rays cast (tests)

func setup(w: NightWorld, skip: Array) -> void:
	world = w
	exclude = skip
	if Gfx.weak:
		max_drops = 24
		caps = {"pool": 56, "smear": 20, "wall": 14}
	var drop_mesh := _mesh("res://assets/props/blood_drop.glb")
	drops_mm = MultiMesh.new()
	drops_mm.transform_format = MultiMesh.TRANSFORM_3D
	drops_mm.mesh = drop_mesh
	var dm := StandardMaterial3D.new() # a drop of blood in the air: dark, wet, a hot highlight
	dm.albedo_color = Color(0.3, 0.008, 0.012)
	dm.roughness = 0.05
	dm.metallic = 0.0
	dm.metallic_specular = 0.8
	dm.rim_enabled = true
	dm.rim = 0.25
	dm.rim_tint = 0.9
	if drop_mesh: drop_mesh.surface_set_material(0, dm)
	drops_mm.instance_count = max_drops
	drops_mm.visible_instance_count = 0
	_d_pos.resize(max_drops); _d_vel.resize(max_drops); _d_size.resize(max_drops); _d_age.resize(max_drops)
	var dmi := MultiMeshInstance3D.new()
	dmi.multimesh = drops_mm
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dmi.custom_aabb = AABB(Vector3(-2000, -200, -2000), Vector3(4000, 900, 4000))
	add_child(dmi)
	var pool_mesh := _mesh("res://assets/props/blood_pool.glb")
	var smear_mesh := _mesh("res://assets/props/blood_smear.glb")
	sets["pool"] = _make_set(pool_mesh, caps.pool)
	sets["smear"] = _make_set(smear_mesh, caps.smear)
	sets["wall"] = _make_set(pool_mesh, caps.wall)

## The first mesh in a model, and its textures fed to the blood shader.
var _tex := {}
func _mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path): return null
	var ps := load(path) as PackedScene
	if ps == null: return null
	var root := ps.instantiate()
	var found: Mesh = null
	var stack: Array = [root]
	while not stack.is_empty() and found == null:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D: found = (n as MeshInstance3D).mesh
		stack.append_array(n.get_children())
	if found:
		found = found.duplicate()
		var m := found.surface_get_material(0) as StandardMaterial3D
		if m:
			_tex[found] = [m.albedo_texture, m.normal_texture if m.normal_enabled else null]
	root.free()
	return found

func _make_set(mesh: Mesh, cap: int) -> Dictionary:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	if mesh:
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/blood.gdshader")
		var tx: Array = _tex.get(mesh, [null, null])
		if tx[0]: sm.set_shader_parameter("albedo_tex", tx[0])
		if tx[1]:
			sm.set_shader_parameter("normal_tex", tx[1])
			sm.set_shader_parameter("has_normal", true)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-2000, -200, -2000), Vector3(4000, 900, 4000))
		add_child(mi)
	var xf: Array = []
	xf.resize(cap)
	var z: Array = [] # plain Arrays (reference types: edited in place through the dictionary)
	z.resize(cap)
	z.fill(0.0)
	# per mark: size (metres when spread), born (for drying and life), grow (seconds to spread),
	# gs (when the current spreading began), from (the share of `size` it spreads from), seed, st (stretch)
	return {"mm": mm, "xf": xf, "size": z.duplicate(), "born": z.duplicate(), "grow": z.duplicate(),
		"gs": z.duplicate(), "from": z.duplicate(), "seed": z.duplicate(), "st": z.duplicate(),
		"n": 0, "next": 0, "cap": cap}

func count(kind: String) -> int: return int(sets[kind].n) if sets.has(kind) else 0
func drops_live() -> int: return _d_live

# --- drops ---------------------------------------------------------------------------------------

## One drop of blood, `size` metres tall, from `at` with velocity `vel`. A full pool of drops, or a
## drop nobody is near to see falling, lands straight away where it would have.
func drip(at: Vector3, vel: Vector3, size: float, seen := true) -> void:
	if not seen or _d_live >= max_drops:
		_land_now(at, size)
		return
	var i := _d_live
	_d_live += 1
	_d_pos[i] = at; _d_vel[i] = vel; _d_size[i] = size; _d_age[i] = 0.0

func _land_now(at: Vector3, size: float) -> void:
	var hit := _ray(at + Vector3(0, 0.3, 0), at + Vector3(0, -6.0, 0))
	if hit.is_empty(): return
	_landed(hit.position, hit.normal, size, Vector3.ZERO)

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	rays += 1
	var q := PhysicsRayQueryParameters3D.create(a, b, 1, exclude)
	q.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(q)

var _pclock := 0.0 # game time as the bodies move (bleed() measures speed and drips by it)
func _physics_process(dt: float) -> void:
	_pclock += dt
	if drops_mm == null: return
	var i := 0
	while i < _d_live:
		var p := _d_pos[i]
		var v := _d_vel[i]
		v.y -= GRAVITY * dt
		v *= 1.0 - 0.15 * dt # a little drag
		var np := p + v * dt
		var hit := _ray(p, np)
		_d_age[i] += dt
		if not hit.is_empty():
			_landed(hit.position, hit.normal, _d_size[i], v)
			_kill(i)
			continue
		if _d_age[i] > DROP_LIFE:
			_kill(i)
			continue
		_d_pos[i] = np
		_d_vel[i] = v
		i += 1
	drops_mm.visible_instance_count = _d_live
	for k in _d_live:
		var v := _d_vel[k]
		# tail up the way it came: the drop's point trails behind it
		var up := (-v).normalized() if v.length() > 0.3 else Vector3.UP
		var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		var s := _d_size[k] * (1.0 + clampf(v.length() * 0.05, 0.0, 0.5)) # stretched as it speeds up
		var b := Basis(side, up, side.cross(up)).scaled(Vector3(_d_size[k], s, _d_size[k]))
		drops_mm.set_instance_transform(k, Transform3D(b, _d_pos[k] - up * s * 0.5))

func _kill(i: int) -> void:
	_d_live -= 1
	_d_pos[i] = _d_pos[_d_live]; _d_vel[i] = _d_vel[_d_live]; _d_size[i] = _d_size[_d_live]; _d_age[i] = _d_age[_d_live]

## A drop reached a surface: blood gathers where blood already is (a survivor standing still makes a
## pool, not a hundred spots), otherwise a new spatter, stretched the way the drop was moving.
func _landed(at: Vector3, normal: Vector3, size: float, vel: Vector3) -> void:
	landed += 1
	var wall := absf(normal.y) < 0.6
	var kind := "wall" if wall else "pool"
	var s: Dictionary = sets[kind]
	if not wall:
		var near := _near_mark(s, at, 0.22)
		if near >= 0:
			_grow_mark(s, near, minf(float(s.size[near]) * 1.07 + size * 0.6, 0.85))
			return
	var flat := Vector3(vel.x, 0.0, vel.z)
	var yaw := atan2(flat.x, flat.z) if flat.length() > 0.5 else randf() * TAU
	var stretch := clampf(1.0 + flat.length() * 0.18, 1.0, 1.9)
	mark(kind, at, normal, size * randf_range(7.0, 11.0), yaw, randf_range(0.25, 0.6), stretch)

# --- marks ---------------------------------------------------------------------------------------

## A mark of `kind` ("pool", "smear" or "wall") on the surface at `at` facing `normal`, `size`
## metres across when it has spread (over `grow` seconds), turned `yaw` about the normal and
## stretched along it by `stretch`.
func mark(kind: String, at: Vector3, normal: Vector3, size: float, yaw: float, grow := 0.5, stretch := 1.0) -> int:
	var s: Dictionary = sets.get(kind, {})
	if s.is_empty() or s.mm.mesh == null: return -1
	var i: int = s.next
	s.next = (i + 1) % int(s.cap)
	s.n = mini(int(s.n) + 1, int(s.cap))
	var up := normal.normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	if absf(up.y) < 0.6: ref = Vector3.DOWN # on a wall: the long way runs down it
	var fwd := (ref - up * ref.dot(up)).normalized().rotated(up, yaw)
	var right := up.cross(fwd).normalized()
	var lift := randf_range(0.004, 0.014) # marks lying over one another never fight
	var b := Basis(right, up, fwd)
	s.xf[i] = Transform3D(b, at + up * lift)
	s.size[i] = size
	s.seed[i] = randf()
	s.born[i] = _clock
	s.gs[i] = _clock
	s.grow[i] = maxf(grow, 0.05)
	s.from[i] = 0.18
	s.st[i] = stretch
	_place(s, i)
	(s.mm as MultiMesh).visible_instance_count = int(s.n)
	_custom(s, i)
	return i

func _place(s: Dictionary, i: int) -> void:
	var t: Transform3D = s.xf[i]
	var sz := float(s.size[i])
	var st := float(s.st[i])
	var b := t.basis
	b = Basis(b.x * sz / st, b.y * maxf(sz, 0.2), b.z * sz * st) # thin: the mesh is 5 cm tall at 1 m
	(s.mm as MultiMesh).set_instance_transform(i, Transform3D(b, t.origin))

func _near_mark(s: Dictionary, at: Vector3, r: float) -> int:
	var n := int(s.n)
	var cap := int(s.cap)
	for k in mini(n, 14): # the last few laid down
		var i := (int(s.next) - 1 - k + cap) % cap
		var t: Transform3D = s.xf[i]
		if t.origin.distance_squared_to(at) < r * r and _clock - float(s.born[i]) < MARK_LIFE * DRY_FROM:
			return i
	return -1

## More blood on a pool: it spreads on from the size it is now (never a jump).
func _grow_mark(s: Dictionary, i: int, to: float) -> void:
	var now_m := _spread(s, i) * float(s.size[i])
	s.size[i] = to
	s.from[i] = clampf(now_m / to, 0.05, 1.0)
	s.gs[i] = _clock
	s.grow[i] = 1.4
	_place(s, i)
	_custom(s, i)

func _spread(s: Dictionary, i: int) -> float:
	var t := clampf((_clock - float(s.gs[i])) / float(s.grow[i]), 0.0, 1.0)
	return lerpf(float(s.from[i]), 1.0, 1.0 - pow(1.0 - t, 3.0))

## What a mark shows now: (spread, dryness, what is left, seed) — the shader's INSTANCE_CUSTOM.
func state(s: Dictionary, i: int) -> Color:
	var age := _clock - float(s.born[i])
	var life := MARK_LIFE
	var dry := clampf((age - life * DRY_FROM) / (life * (1.0 - DRY_FROM - FADE)), 0.0, 1.0)
	var left := clampf((life - age) / (life * FADE), 0.0, 1.0)
	return Color(_spread(s, i), dry, left, float(s.seed[i]))

func _custom(s: Dictionary, i: int) -> void:
	(s.mm as MultiMesh).set_instance_custom_data(i, state(s, i))

func _process(dt: float) -> void:
	_clock += dt
	_tick -= dt
	if _tick > 0.0: return
	_tick = 0.1 # marks change slowly: a tenth of a second is plenty
	for kind in sets:
		var s: Dictionary = sets[kind]
		var n := int(s.n)
		if n == 0: continue
		var cap := int(s.cap)
		var gone := 0
		for k in n:
			var i := (int(s.next) - 1 - k + cap) % cap
			if _clock - float(s.born[i]) >= MARK_LIFE:
				gone = n - k # this one and every older one are spent
				break
			_custom(s, i)
		if gone > 0:
			s.n = n - gone
			# the ring keeps the newest at next-1 back to next-n, so dropping the oldest is only the count;
			# the visible range must stay contiguous from 0, so rebuild it when the oldest are spent
			_compact(s)

## Keep the live marks in instances 0..n-1 (visible_instance_count draws the first n).
func _compact(s: Dictionary) -> void:
	var n := int(s.n)
	var cap := int(s.cap)
	var keep: Array = []
	for k in range(n - 1, -1, -1):
		var i := (int(s.next) - 1 - k + cap) % cap
		keep.append([s.xf[i], s.size[i], s.born[i], s.grow[i], s.seed[i], s.st[i], s.gs[i], s.from[i]])
	for j in keep.size():
		var e: Array = keep[j]
		s.xf[j] = e[0]; s.size[j] = e[1]; s.born[j] = e[2]; s.grow[j] = e[3]; s.seed[j] = e[4]; s.st[j] = e[5]
		s.gs[j] = e[6]; s.from[j] = e[7]
		_place(s, j)
		_custom(s, j)
	s.next = n % cap
	(s.mm as MultiMesh).visible_instance_count = n

# --- survivors -----------------------------------------------------------------------------------

## Every survivor, every frame, on every phone. `kind`: 0 not bleeding (fine, healed, dead, gone,
## hooked: the hook has its own), 1 hurt on their feet, 2 down and crawling.
func bleed(n: String, feet: Vector3, kind: int, cam: Vector3 = Vector3.INF) -> void:
	if kind == 0:
		_st.erase(n)
		return
	var now := _pclock
	if not _st.has(n):
		_st[n] = {"t": randf_range(0.2, 0.8), "last": feet, "at": now, "d": 0.0, "v": Vector3.ZERO}
	var s: Dictionary = _st[n]
	var dt := clampf(now - float(s.at), 0.0, 0.25)
	s.at = now
	var moved: Vector3 = feet - (s.last as Vector3)
	s.last = feet
	if moved.length() > 3.0: moved = Vector3.ZERO # a teleport, a seat, a respawn
	var v := Vector3(moved.x, 0.0, moved.z) / maxf(dt, 0.001)
	s.v = (s.v as Vector3).lerp(v, 0.25)
	var spd := (s.v as Vector3).length()
	var run := clampf((spd - 1.2) / 4.0, 0.0, 1.0)
	var seen := cam == Vector3.INF or cam.distance_to(feet) < 45.0
	s.t = float(s.t) - dt
	if kind == 1:
		if float(s.t) <= 0.0:
			# still: a slow drip; walking: now and then; running: often, two at a time
			s.t = lerpf(randf_range(0.9, 1.7), randf_range(0.14, 0.3), run) * (1.4 if spd < 0.3 else 1.0)
			var k := 1 + (1 if run > 0.6 and randf() < 0.6 else 0)
			for j in k:
				var dir := (s.v as Vector3).normalized() if spd > 0.3 else Vector3.ZERO
				var side := Vector3(-dir.z, 0.0, dir.x)
				var wound := feet + Vector3(0, randf_range(0.78, 1.02), 0) + side * randf_range(-0.2, 0.2) - dir * 0.12
				var vel := (s.v as Vector3) * randf_range(0.75, 0.95) + Vector3(randf_range(-0.25, 0.25), randf_range(-0.4, 0.1), randf_range(-0.25, 0.25))
				drip(wound, vel, randf_range(0.011, 0.024) * (1.2 if run > 0.6 else 1.0), seen)
		# running hard: the blood runs down and smears off now and then
		s.d = float(s.d) + Vector2(moved.x, moved.z).length()
		if run > 0.7 and float(s.d) > randf_range(3.2, 5.5):
			s.d = 0.0
			_trail_mark(feet, s.v, randf_range(0.28, 0.45))
	else: # down: dragging themselves along, a smear behind them
		s.d = float(s.d) + Vector2(moved.x, moved.z).length()
		if float(s.d) > 0.65:
			s.d = 0.0
			_trail_mark(feet, s.v, randf_range(0.5, 0.75))
		if float(s.t) <= 0.0:
			s.t = randf_range(1.2, 2.2)
			drip(feet + Vector3(randf_range(-0.2, 0.2), 0.35, randf_range(-0.2, 0.2)), Vector3.ZERO, 0.016, seen)

func _trail_mark(feet: Vector3, v: Vector3, size: float) -> void:
	var hit := _ray(feet + Vector3(0, 0.6, 0), feet + Vector3(0, -2.0, 0))
	if hit.is_empty(): return
	var flat := Vector3(v.x, 0.0, v.z)
	var yaw := atan2(flat.x, flat.z) if flat.length() > 0.2 else randf() * TAU
	mark("smear", hit.position, hit.normal, size, yaw + randf_range(-0.25, 0.25), 0.35, randf_range(0.9, 1.3))

## A blow lands on someone standing at `at` (chest height), struck from the direction `dir` points
## along: blood sprays out of the far side, splashes a wall behind them if one is within 2.6 m, and a
## pool spreads under them.
func splash(at: Vector3, dir: Vector3, cam: Vector3 = Vector3.INF) -> void:
	var away := Vector3(dir.x, 0.0, dir.z).normalized()
	if away.length() < 0.1: away = Vector3.FORWARD
	var seen := cam == Vector3.INF or cam.distance_to(at) < 50.0
	var n := (10 if Gfx.weak else 18)
	for i in n:
		var spread := Vector3(randf_range(-0.7, 0.7), 0.0, randf_range(-0.7, 0.7))
		var vel := (away + spread).normalized() * randf_range(1.6, 4.6) + Vector3.UP * randf_range(0.3, 2.4)
		drip(at + Vector3(randf_range(-0.1, 0.1), randf_range(-0.15, 0.15), randf_range(-0.1, 0.1)), vel, randf_range(0.012, 0.03), seen)
	for k in 2: # behind them: the wall takes it
		var to := at + (away + Vector3(randf_range(-0.35, 0.35), randf_range(-0.15, 0.25), randf_range(-0.35, 0.35))).normalized() * 2.6
		var hit := _ray(at, to)
		if not hit.is_empty() and absf((hit.normal as Vector3).y) < 0.6:
			var d: float = at.distance_to(hit.position)
			mark("wall", hit.position, hit.normal, randf_range(0.45, 0.85) * (1.2 - d / 2.6 * 0.4), randf_range(-0.5, 0.5), 0.12, randf_range(1.0, 1.5))
			break
	var g := _ray(at, at + Vector3(0, -3.0, 0))
	if not g.is_empty():
		mark("pool", g.position, g.normal, randf_range(0.55, 0.8), randf() * TAU, randf_range(2.5, 4.0), 1.0)
