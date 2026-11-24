class_name NFRavens extends Node3D
## The owner's raven (`assets/props/raven.glb`): a few perch on the gallows, the walls and the roofs,
## take off cawing when anyone comes close, circle over the map and land somewhere else; three more
## circle high all round. Its sounds are his: the crow's caw when it is close to me (under
## `NEAR` m), the raven's call when it is far. No collision, no effect on the round: every phone
## runs its own flock from the map's seed.

const NEAR := 20.0       # metres: crow caw closer than this, raven call further
const SCARE := 8.0       # anyone this close makes a perched raven take off
const SPEED := 9.0
var birds: Array = []    # {node, wings:[l, r], state 0 perched / 1 flying / 2 circling, at, to, perch, t, centre, r, h, caw}
var perches: Array[Vector3] = []
var listeners: Callable  # -> Array[Vector3]: everyone on the map (mine and the others)
var _crow: AudioStream
var _raven: AudioStream
var _model: PackedScene
var rng := RandomNumberGenerator.new()

func setup(spots: Array[Vector3], perched: int, high: int, seed: int) -> void:
	rng.seed = seed
	perches = spots
	_crow = load("res://assets/sfx/crow.mp3") if ResourceLoader.exists("res://assets/sfx/crow.mp3") else null
	_raven = load("res://assets/sfx/raven.mp3") if ResourceLoader.exists("res://assets/sfx/raven.mp3") else null
	_model = load("res://assets/props/raven.glb") if ResourceLoader.exists("res://assets/props/raven.glb") else null
	for i in perched + high:
		var b := _bird()
		if i < perched and not perches.is_empty():
			b.perch = rng.randi() % perches.size()
			b.node.position = perches[b.perch]
			b.node.rotation.y = rng.randf() * TAU
			_land(b)
		else:
			b.high = true # these never come down
			_circle(b, Vector3(rng.randf_range(-60, 60), 0, rng.randf_range(-60, 60)), rng.randf_range(38.0, 55.0))
			b.node.position = b.centre + Vector3(b.r, b.h, 0)
		birds.append(b)

func _bird() -> Dictionary:
	var n := Node3D.new()
	add_child(n)
	var body: Node3D
	if _model: body = _model.instantiate()
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.16, 0.42, 0.2)
		mi.mesh = bm
		mi.position.y = 0.21
		body = mi
	n.add_child(body)
	for c in body.find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(c as GeometryInstance3D).visibility_range_end = 140.0 # a speck past that
	# wings: the model is perched with them folded, so flying needs a pair that flaps
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.04, 0.04, 0.05)
	wm.roughness = 0.6
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wings: Array = []
	for s in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.05 * s, 0.3, 0.0)
		var w := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.24, 0.5, 0.015) # a long tapering feathered blade
		w.mesh = pm
		w.material_override = wm
		w.rotation = Vector3(0, 0, -PI / 2.0 * s) # tip outward, flat across the body
		w.position = Vector3(0.25 * s, 0, 0)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(w)
		n.add_child(pivot)
		pivot.visible = false
		wings.append(pivot)
	var snd := AudioStreamPlayer3D.new()
	snd.bus = Aud.SFX
	snd.unit_size = 8.0
	snd.max_distance = 160.0
	n.add_child(snd)
	return {"node": n, "body": body, "wings": wings, "snd": snd, "state": 0, "perch": -1, "t": 0.0,
		"centre": Vector3.ZERO, "r": 30.0, "h": 40.0, "ang": rng.randf() * TAU, "caw": rng.randf_range(4.0, 16.0),
		"to": Vector3.ZERO, "flap": rng.randf() * TAU}

func _land(b: Dictionary) -> void:
	b.state = 0
	b.t = rng.randf_range(25.0, 60.0) # sits a while, then flies anyway
	(b.node as Node3D).rotation.x = 0.0
	(b.node as Node3D).rotation.z = 0.0
	for w in b.wings: (w as Node3D).visible = false

func _circle(b: Dictionary, centre: Vector3, h: float) -> void:
	b.state = 2
	b.centre = centre
	b.h = h
	b.r = rng.randf_range(22.0, 48.0)
	b.t = rng.randf_range(18.0, 40.0)
	for w in b.wings: (w as Node3D).visible = true

func _caw(b: Dictionary, force_near := false) -> void:
	var cam := get_viewport().get_camera_3d()
	var d := 999.0
	if cam: d = cam.global_position.distance_to((b.node as Node3D).global_position)
	var close := force_near or d < NEAR
	var s: AudioStream = _crow if close else _raven
	if s == null: return
	var p: AudioStreamPlayer3D = b.snd
	p.stream = s
	p.volume_db = -2.0 if close else 4.0
	p.pitch_scale = rng.randf_range(0.92, 1.08)
	p.play()

func _process(dt: float) -> void:
	var near: Array = listeners.call() if listeners.is_valid() else []
	for b in birds:
		var n: Node3D = b.node
		b.t -= dt
		match int(b.state):
			0: # perched: anyone close, or bored -> off it goes
				var scared := false
				for p in near:
					if (p as Vector3).distance_to(n.position) < SCARE: scared = true
				if scared or b.t <= 0.0:
					b.state = 1
					var away := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
					b.to = n.position + away * rng.randf_range(25.0, 45.0) + Vector3(0, rng.randf_range(18.0, 30.0), 0)
					b.t = 6.0
					for w in b.wings: (w as Node3D).visible = true
					_caw(b, scared)
			1: # climbing away, then circling
				var dir: Vector3 = (b.to - n.position)
				if dir.length() < 2.0 or b.t <= 0.0:
					_circle(b, Vector3(n.position.x, 0, n.position.z) + Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20)), n.position.y + rng.randf_range(4.0, 14.0))
				else:
					_fly(b, n.position + dir.normalized() * SPEED * 1.2 * dt, dt, 1.6)
			2: # circling; now and then it calls; after a while it comes down on a free perch
				b.ang = float(b.ang) + dt * SPEED / float(b.r)
				var want: Vector3 = b.centre + Vector3(cos(b.ang) * b.r, b.h, sin(b.ang) * b.r)
				_fly(b, n.position.lerp(want, minf(1.0, dt * 2.0)), dt, 0.8)
				b.caw = float(b.caw) - dt
				if b.caw <= 0.0:
					b.caw = rng.randf_range(10.0, 24.0)
					_caw(b)
				if b.t <= 0.0 and not perches.is_empty() and not b.get("high", false):
					b.perch = rng.randi() % perches.size()
					b.state = 3
				elif b.t <= 0.0:
					b.t = rng.randf_range(18.0, 40.0)
			3: # gliding down to the perch
				var tgt: Vector3 = perches[b.perch]
				var dv: Vector3 = tgt - n.position
				if dv.length() < 0.4:
					n.position = tgt
					_land(b)
				else:
					_fly(b, n.position + dv.normalized() * minf(SPEED * dt, dv.length()), dt, 0.35)

func _fly(b: Dictionary, to: Vector3, dt: float, beat: float) -> void:
	var n: Node3D = b.node
	var v := to - n.position
	if v.length() > 0.001:
		var yaw := atan2(v.x, v.z)
		n.rotation.y = lerp_angle(n.rotation.y, yaw, minf(1.0, dt * 4.0))
		n.rotation.x = lerpf(n.rotation.x, 1.15, minf(1.0, dt * 3.0)) # the body level, head forward
		n.rotation.z = lerpf(n.rotation.z, clampf(angle_difference(n.rotation.y, yaw) * -2.0, -0.5, 0.5), minf(1.0, dt * 3.0))
	n.position = to
	b.flap = float(b.flap) + dt * (9.0 + 7.0 * beat)
	var f := sin(float(b.flap)) * (0.25 + 0.55 * beat)
	# the body is pitched level, so its head runs along local +Y: the wings beat about that axis
	(b.wings[0] as Node3D).rotation.y = -f
	(b.wings[1] as Node3D).rotation.y = f
