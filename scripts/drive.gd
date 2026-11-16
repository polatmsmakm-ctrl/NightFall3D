class_name NFCar
extends CharacterBody3D
## The killer's Land Cruiser: one per map, and only the killer can drive it.
## On the killer's phone it is driven here (`drive()` every physics step, move_and_slide).
## On everyone else's phone it follows the position the killer reports while his animation
## reads "drive" (`follow()`), so the server and the protocol do not change: the `st` relay
## already carries a position, a yaw and an animation name.
## A survivor it runs into is hit the normal way (`hit` input, same cooldown, same rules).

const MAX_FWD := 11.0     # m/s; the killer runs at 4.6, survivors sprint at 4.3
const MAX_BACK := 4.5
const ACCEL := 6.5
const BRAKE := 16.0
const COAST := 3.5
const TURN := 1.6         # rad/s once it is moving
const RAM_SPEED := 3.0    # slower than this, touching a survivor is not a hit
const LIGHT_ENERGY := 15.0
# the cabin (assets/props/cabin.glb, the owner's Mud-Caked Toyota Cabin) in the car's own space:
# its floor on the body's floor, its dashboard against the bottom of the windscreen
const CABIN_AT := Vector3(0.0, 0.5, 0.15)
const EYE := Vector3(0.42, 1.5, -0.3) # the driver's eyes: left-hand seat, under the 1.68 m roof

var speed := 0.0          # along the car's own +z (its front); negative in reverse
var steer := 0.0
var driven := false       # someone is at the wheel (lights on, engine running)
var bump := 0.0           # how hard the last crash was (0..1); main reads it and clears it
var model: Node3D         # the visible car, tilted to the ground under it
var lights: SpotLight3D
var tail: OmniLight3D
var engine: AudioStreamPlayer3D
var radio: AudioStreamPlayer3D # the owner's song (assets/sfx/radio.mp3), from the dashboard
var radio_on := false     # the switch; it only plays while someone is at the wheel
var _radio_started := false
var inside: Node3D        # the cabin + headliner + pillars, only shown to the killer while he drives
var _last := Vector3.ZERO # remote phones work the speed out from how far it moved

func setup(ps: PackedScene, scale_k: float, cabin_ps: PackedScene = null) -> void:
	floor_snap_length = 0.7
	floor_max_angle = deg_to_rad(42.0)
	floor_constant_speed = true
	wall_min_slide_angle = deg_to_rad(20.0)
	safe_margin = 0.04
	# two long rounded "skids" for the wheels, so bumps and kerbs roll under it instead of
	# catching a flat box edge, plus the cabin
	for sx in [-0.55, 0.55]:
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.42
		cap.height = 4.1
		cs.shape = cap
		cs.rotation.x = PI / 2.0
		cs.position = Vector3(sx, 0.44, 0.0)
		add_child(cs)
	var cab := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.75, 1.15, 4.05)
	cab.shape = bs
	cab.position = Vector3(0, 1.32, 0)
	add_child(cab)
	model = Node3D.new()
	add_child(model)
	if ps:
		var n := ps.instantiate() as Node3D
		n.scale = Vector3.ONE * scale_k
		model.add_child(n)
	else: # no model file: a plain dark box, so the round still works
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.8, 1.5, 4.2)
		mi.mesh = bm
		mi.position.y = 0.95
		model.add_child(mi)
	inside = Node3D.new()
	inside.visible = false
	model.add_child(inside)
	if cabin_ps:
		var cab_m := cabin_ps.instantiate() as Node3D
		cab_m.position = CABIN_AT
		inside.add_child(cab_m)
	_trim()
	lights = SpotLight3D.new() # one beam for both headlamps: the mobile renderer counts lights
	lights.position = Vector3(0, 1.0, 2.25)
	lights.rotation = Vector3(-0.08, PI, 0) # a spot light shines down its -z; the car's front is +z
	lights.light_color = Color(1.0, 0.93, 0.78)
	lights.spot_range = 42.0
	lights.spot_angle = 33.0
	lights.spot_attenuation = 0.6
	lights.light_energy = 0.0
	lights.shadow_enabled = false
	NFLook.shadows_on(lights)
	model.add_child(lights)
	tail = OmniLight3D.new()
	tail.position = Vector3(0, 0.75, -3.0) # behind the bumper: a red patch on the ground, not a red car
	tail.light_color = Color(1.0, 0.1, 0.06)
	tail.omni_range = 1.7
	tail.light_energy = 0.0
	tail.shadow_enabled = false
	model.add_child(tail)
	# the engine is the owner's sound or nothing: drop assets/sfx/engine.mp3 in and it plays
	if ResourceLoader.exists("res://assets/sfx/engine.mp3"):
		var st = load("res://assets/sfx/engine.mp3")
		if st is AudioStreamMP3: (st as AudioStreamMP3).loop = true
		engine = AudioStreamPlayer3D.new()
		engine.stream = st
		engine.bus = Aud.SFX
		engine.unit_size = 6.0
		engine.max_distance = 60.0
		add_child(engine)
	# the radio: a real 3D sound in the car, so survivors hear it coming (muffled and fading with
	# distance) and the driver hears it up close
	if ResourceLoader.exists("res://assets/sfx/radio.mp3"):
		var rs = load("res://assets/sfx/radio.mp3")
		if rs is AudioStreamMP3: (rs as AudioStreamMP3).loop = true
		radio = AudioStreamPlayer3D.new()
		radio.stream = rs
		radio.bus = Aud.MUSIC
		radio.position = Vector3(0, 1.2, 0.55)
		radio.unit_size = 5.0
		radio.max_db = 0.0
		radio.max_distance = 48.0
		radio.attenuation_filter_cutoff_hz = 2200.0 # further away it loses its treble, like through a car body
		radio.attenuation_filter_db = -20.0
		radio.panning_strength = 0.7
		model.add_child(radio)
	_last = position

## Turn the radio on or off. Off pauses it, so it carries on from the same place next time.
func set_radio(on: bool) -> void:
	radio_on = on

## Seen from the driver's seat the body's own shell is invisible (its faces point outward and are
## culled), which leaves the windows clear and keeps the bonnet in view; these give the inside a
## roof and the windscreen its frame.
func _trim() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.075, 0.068, 0.062)
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var parts := [ # size, position, tilt about x
		[Vector3(1.62, 0.03, 1.2), Vector3(0, 1.66, -0.13), 0.0],      # headliner
		[Vector3(0.07, 0.6, 0.09), Vector3(0.78, 1.43, 0.63), -0.65],  # A-pillars
		[Vector3(0.07, 0.6, 0.09), Vector3(-0.78, 1.43, 0.63), -0.65],
		[Vector3(0.07, 0.7, 0.13), Vector3(0.8, 1.32, -0.78), 0.0],    # B-pillars
		[Vector3(0.07, 0.7, 0.13), Vector3(-0.8, 1.32, -0.78), 0.0],
		[Vector3(1.6, 0.06, 0.08), Vector3(0, 1.64, 0.46), 0.0],       # top of the windscreen
	]
	for e in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = e[0]
		bm.material = m
		mi.mesh = bm
		mi.position = e[1]
		mi.rotation.x = e[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inside.add_child(mi)

func show_inside(on: bool) -> void:
	inside.visible = on

## Where the driver's eyes are, in the world (follows the car's tilt).
func eye() -> Vector3:
	return model.global_transform * EYE

## Where it is facing (flat).
func forward() -> Vector3:
	return Vector3(sin(rotation.y), 0.0, cos(rotation.y))

## The driver's phone: throttle -1..1 (stick up = forward), turn -1..1 (right = +1).
func drive(throttle: float, turn: float, dt: float) -> void:
	if throttle > 0.05:
		if speed < -0.3: speed = move_toward(speed, 0.0, BRAKE * dt)
		else: speed = move_toward(speed, MAX_FWD * throttle, ACCEL * dt)
	elif throttle < -0.05:
		if speed > 0.3: speed = move_toward(speed, 0.0, BRAKE * dt)
		else: speed = move_toward(speed, -MAX_BACK * -throttle, ACCEL * 0.7 * dt)
	else:
		speed = move_toward(speed, 0.0, COAST * dt)
	steer = move_toward(steer, clampf(turn, -1.0, 1.0), 4.0 * dt)
	# a car turns only while it rolls, and the other way round in reverse
	var k := clampf(absf(speed) / 4.0, 0.0, 1.0) * signf(speed)
	rotation.y = wrapf(rotation.y - steer * TURN * k * dt, -PI, PI)
	var fall := velocity.y
	var f := forward()
	velocity = f * speed
	velocity.y = -2.0 if is_on_floor() else fall - 22.0 * dt
	move_and_slide()
	# ran into something: a head-on crash stops it dead (and the camera feels it)
	var crash := 0.0
	var scrape := false
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if absf(n.y) > 0.6: continue
		scrape = true
		var into := -f.dot(n) * signf(speed)
		if into > 0.55: crash = maxf(crash, absf(speed))
	if crash > 2.5:
		bump = clampf(crash / MAX_FWD, 0.0, 1.0)
		speed *= -0.12
	elif scrape: # sliding along a wall bleeds the speed off
		speed = move_toward(speed, 0.0, 9.0 * dt)
	_tilt(get_floor_normal() if is_on_floor() else Vector3.UP, dt)
	_effects(dt)

## Everyone else's phone: ease toward what the killer reported.
func follow(at: Vector3, yaw: float, dt: float) -> void:
	var w := 1.0 - exp(-12.0 * dt)
	position = position.lerp(at, w)
	rotation.y = lerp_angle(rotation.y, yaw, w)
	var moved := Vector2(position.x - _last.x, position.z - _last.z).length()
	speed = lerpf(speed, moved / maxf(dt, 0.001), 1.0 - exp(-6.0 * dt))
	_last = position
	_tilt(_ground_normal(), dt)
	_effects(dt)

## Nobody in it: lights off, engine off, and it sits where it was left.
func park(dt: float) -> void:
	speed = 0.0
	_last = position
	_effects(dt)

func _tilt(n: Vector3, dt: float) -> void:
	var local := (global_basis.inverse() * n).normalized()
	if local.y < 0.5: local = Vector3.UP
	var q := Quaternion(Vector3.UP, local)
	model.quaternion = model.quaternion.slerp(q, 1.0 - exp(-8.0 * dt))

func _ground_normal() -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.5, 0), global_position + Vector3(0, -1.5, 0))
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	return hit.normal if not hit.is_empty() else Vector3.UP

func _effects(dt: float) -> void:
	var on := 1.0 if driven else 0.0
	lights.light_energy = lerpf(lights.light_energy, LIGHT_ENERGY * on, 1.0 - exp(-6.0 * dt))
	lights.visible = lights.light_energy > 0.05
	tail.light_energy = lerpf(tail.light_energy, (0.45 + (0.55 if speed < -0.3 or (driven and absf(speed) < 0.4) else 0.0)) * on, 1.0 - exp(-8.0 * dt))
	tail.visible = tail.light_energy > 0.05
	if radio:
		var want := radio_on and driven
		if want and not _radio_started:
			radio.play()
			_radio_started = true
		elif _radio_started:
			radio.stream_paused = not want
	if engine:
		if driven and not engine.playing: engine.play()
		elif not driven and engine.playing: engine.stop()
		engine.pitch_scale = 0.8 + clampf(absf(speed) / MAX_FWD, 0.0, 1.0) * 0.7
