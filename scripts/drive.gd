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
const EYE := Vector3(0.42, 1.45, -0.02) # the driver's eyes: left-hand seat, under the 1.68 m roof
const CARGO := Vector3(0.0, 0.62, -1.3) # (old) the load floor behind the seats
## A carried survivor rides in the passenger seat (right-hand side; the car is left-hand drive),
## slumped (CharacterRig "slump") at 0.82 of their size: our characters are 1.9 m tall and the car
## is 0.9 of a real one, and at that scale head and feet stay between the floor and the roof.
const SEAT_HIPS := Vector3(-0.42, 0.95, -0.30)
const DRIVER_HIPS := Vector3(0.42, 0.95, -0.08)  # the killer in the driver's seat, forward on the cushion
## Characters are 1.9 m tall and the cabin's headliner is at 1.645 m: seated, a character is at most
## 0.81 m from the hips to the top of the head, so at 0.72 with the hips at 0.95 m the head is at
## 1.53 m (and the feet on the floor at 0.5). The same scale for the victim and the driver.
const VICTIM_SCALE := 0.72
## Two gears: first tops out at 40 km/h, second at 70 km/h (the button by the speedometer).
const GEAR_TOP := [11.0, 19.5]
const HIPS_Y := 1.06                    # the Mixamo hips height every character shares, standing
# the steering wheel cut out of the cabin (cabin.glb node `steer`): its axis in cabin space
const STEER_AXIS := Vector3(0.004, -0.39, 0.921)
const STEER_TURNS := 2.3                # radians of wheel for full lock
const STEER_RIM := 0.205
const WHEEL_R := 0.41                   # tyre radius in the model's metres (x CAR_SCALE in the game)
const STEER_MAX := 0.55                 # how far the front wheels turn, radians

var speed := 0.0          # along the car's own +z (its front); negative in reverse
var steer := 0.0
var driven := false       # someone is at the wheel (lights on, engine running)
var bump := 0.0           # how hard the last crash was (0..1); main reads it and clears it
var model: Node3D         # the visible car, tilted to the ground under it
var lights: SpotLight3D
var tail: OmniLight3D
var engine: AudioStreamPlayer3D
var radio: AudioStreamPlayer3D # the owner's song (assets/sfx/radio.mp3), from the dashboard
var radio_on := false     # the switch; it keeps playing after he gets out if he left it on
var gear := 1             # 1 or 2
var _radio_started := false
var inside: Node3D        # the cabin + headliner + pillars, only shown to the killer while he drives
var _last := Vector3.ZERO # remote phones work the speed out from how far it moved
var _last_yaw := 0.0
var _scale := 1.0
var wheels := []          # [node, front?] — the four wheels of car_drive.glb, turned every frame
var spin := 0.0           # how far the wheels have rolled (radians)
var frame_node: Node3D    # the body, leaned in turns and dipped under braking
var lean := Vector2.ZERO  # x: roll, y: pitch (radians), eased
var _prev_speed := 0.0
var steer_node: Node3D    # the steering wheel, turned with the steering; the hands ride on it
var hands := []           # [glove, side] on the wheel rim
var gloves := []          # the glove pieces on the rim (children of the steering wheel)
var hand_root: Node3D     # the sleeves (the gloves ride on the steering wheel; hidden with it)
var arms := []            # [upper arm, forearm, shoulder, side]
var bob := 0.0            # suspension: how far the body sits from rest (m), a damped spring
var bob_v := 0.0
var _prev_vy := 0.0
var _t := 0.0
var door_node: Node3D     # car_drive.glb's driver door (`door_l`), on its hinge
var door_hinge := Vector3.ZERO
var door_open := 0.0      # 0 shut .. 1 wide open, eased toward the getting-in / out sequence
## Getting in and out are two clips on an AnimationPlayer (`door_anim`), built in `_door_clips()`:
## "get_in" — the door swings open, he climbs in, it shuts, and a method key turns the ignition;
## "get_out" — the door opens, he steps out, it shuts (the key comes out when it starts). Played on
## every phone (the others start it when the killer's `st` animation turns to or from "drive"),
## so it costs nothing on the network.
const SEQ_IN := {"open": 0.45, "shut": 1.2, "closed": 1.5, "done": 1.8}
const SEQ_OUT := {"open": 0.45, "out": 0.5, "shut": 0.9, "done": 1.25}
const DOOR_SILL := 0.3    # the bottom of the door's window, in the door's own space (hinge at 1.1 m)
const DOOR_SWING := -1.15 # rad: the back edge of the door swings out (+x), on its front hinge
var door_anim: AnimationPlayer
var door_root: Node3D     # sits on the hinge and leans with the body; `door_node` turns inside it
var seq := ""             # "in", "out" or "" (nothing playing)
var seq_t := 0.0
var starter: AudioStreamPlayer3D  # the owner's "starting the car" clip
var passer: AudioStreamPlayer3D   # the owner's "car passing by" clip
var engine_gain := 0.0    # the loop fades in under the starter and out when he switches off
var running := false      # the engine is on (after the key, until he gets out)
var dust: GPUParticles3D
var smoke: GPUParticles3D
var dust_on := true       # off in the car park: concrete does not throw dust
var driver_local := false # this phone is driving it (is_on_floor() only means something here)

func setup(ps: PackedScene, scale_k: float, cabin_ps: PackedScene = null, dust_col := Color(0.62, 0.55, 0.45), dusty := true) -> void:
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
	_scale = scale_k
	if ps:
		var n := ps.instantiate() as Node3D
		n.scale = Vector3.ONE * scale_k
		model.add_child(n)
		for nm in ["wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr"]: # car_drive.glb: wheels on their own axles
			var w := n.find_child(nm, true, false) as Node3D
			if w: wheels.append([w, nm.begins_with("wheel_f")])
		frame_node = n.find_child("frame", true, false) as Node3D
		door_node = n.find_child("door_l", true, false) as Node3D
		if door_node: # put the door inside a hinge node so the clip only has to turn it
			door_hinge = door_node.position
			door_root = Node3D.new()
			door_root.name = "door_hinge"
			door_node.get_parent().add_child(door_root)
			door_node.reparent(door_root, false)
			door_node.transform = Transform3D()
			door_root.position = door_hinge
			# the sculpt is a shell seen from outside: the door's inside is its back faces, drawn
			# again as a dark trim panel so the open door is not see-through from the front
			var mi: MeshInstance3D = door_node as MeshInstance3D if door_node is MeshInstance3D else door_node.find_child("*", true, false) as MeshInstance3D
			if mi:
				var card := MeshInstance3D.new()
				card.name = "door_card"
				# only the panel under the window: the glass, its frame and the mirror drawn dark from
				# inside blocked the side window
				var arr := mi.mesh.surface_get_arrays(0)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				var keep := PackedInt32Array()
				for t in range(0, ix.size(), 3):
					if vs[ix[t]].y < DOOR_SILL and vs[ix[t + 1]].y < DOOR_SILL and vs[ix[t + 2]].y < DOOR_SILL:
						keep.append(ix[t]); keep.append(ix[t + 1]); keep.append(ix[t + 2])
				arr[Mesh.ARRAY_INDEX] = keep
				var panel := ArrayMesh.new()
				if keep.size() > 0: panel.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				card.mesh = panel
				var trim := StandardMaterial3D.new()
				trim.albedo_color = Color(0.12, 0.1, 0.09)
				trim.roughness = 0.8
				trim.cull_mode = BaseMaterial3D.CULL_FRONT
				card.material_override = trim
				mi.add_child(card)
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
		steer_node = cab_m.find_child("steer", true, false) as Node3D
	_trim()
	_seats()
	_hands()
	_door_clips()
	dust_on = dusty
	dust = _puffs(dust_col, 48, 1.3, 0.55, Vector3(0, 0.25, -2.2))
	smoke = _puffs(Color(0.32, 0.32, 0.33, 0.5), 14, 0.9, 0.18, Vector3(-0.55, 0.42, -2.25))
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
	# the owner's sounds: the engine running (a seamless loop), the starter, and a car going past
	for f in ["engine.ogg", "engine.mp3"]:
		if engine == null and ResourceLoader.exists("res://assets/sfx/" + f):
			var st = load("res://assets/sfx/" + f)
			if st is AudioStreamMP3: (st as AudioStreamMP3).loop = true
			if st is AudioStreamOggVorbis: (st as AudioStreamOggVorbis).loop = true
			engine = _snd(st, 6.0, 60.0)
	if ResourceLoader.exists("res://assets/sfx/car_start.mp3"): starter = _snd(load("res://assets/sfx/car_start.mp3"), 7.0, 70.0)
	if ResourceLoader.exists("res://assets/sfx/car_pass.mp3"): passer = _snd(load("res://assets/sfx/car_pass.mp3"), 9.0, 45.0)
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

func _snd(st: AudioStream, unit: float, reach: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = Aud.SFX
	p.unit_size = unit
	p.max_distance = reach
	p.position = Vector3(0, 0.8, 1.4) # under the bonnet
	add_child(p)
	return p

## The two clips. The door's track is its yaw on the hinge (opens in 0.45 s, eased out like a door
## thrown open; swings shut faster); "get_in" ends with a method key on `_turn_key`.
func _door_clips() -> void:
	door_anim = AnimationPlayer.new()
	door_anim.name = "door_anim"
	door_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	add_child(door_anim) # root node "..": the car
	var lib := AnimationLibrary.new()
	for kind in ["get_in", "get_out"]:
		var q: Dictionary = SEQ_IN if kind == "get_in" else SEQ_OUT
		var a := Animation.new()
		a.length = q.done
		if door_node:
			var tr := a.add_track(Animation.TYPE_VALUE)
			a.track_set_path(tr, NodePath(str(get_path_to(door_node)) + ":rotation:y"))
			a.track_set_interpolation_type(tr, Animation.INTERPOLATION_LINEAR) # eased by each key's transition
			a.value_track_set_update_mode(tr, Animation.UPDATE_CONTINUOUS)
			a.track_insert_key(tr, 0.0, 0.0, 0.5)               # ease out: thrown open
			a.track_insert_key(tr, q.open, DOOR_SWING)
			a.track_insert_key(tr, q.shut, DOOR_SWING, 2.0)     # ease in: pulled shut, stops hard
			a.track_insert_key(tr, q.get("closed", q.done), 0.0)
		if kind == "get_in":
			var mt := a.add_track(Animation.TYPE_METHOD)
			a.track_set_path(mt, NodePath("."))
			a.track_insert_key(mt, q.done - 0.02, {"method": "_turn_key", "args": []})
		lib.add_animation(kind, a)
	door_anim.add_animation_library("", lib)

## The method key at the end of "get_in": door shut, he is in, the key turns.
func _turn_key() -> void:
	if running: return
	running = true
	if starter: starter.play()

## Start the getting-in ("in") or getting-out ("out") clip on this phone.
func begin(kind: String) -> void:
	seq = kind
	seq_t = 0.0
	if kind == "out": # key off: the engine winds down at once
		running = false
		if starter and starter.playing: starter.stop()
	door_anim.stop()
	door_anim.play("get_in" if kind == "in" else "get_out")

## How far through getting in he is: 0 at the door .. 1 in the seat with the door shut.
func seated() -> float:
	if seq == "in": return clampf(seq_t / SEQ_IN.done, 0.0, 1.0)
	return 1.0

## A car going past someone at speed: the owner's pass-by clip, from the car (with its own Doppler).
func whoosh() -> void:
	if passer and not passer.playing: passer.play()

func _sequence(dt: float) -> void:
	if seq != "":
		seq_t += dt
		if seq == "in" and seq_t >= SEQ_IN.done + 0.05:
			_turn_key() # in case the clip's method key was skipped (a very long frame)
			seq = ""
		elif seq == "out" and seq_t >= SEQ_OUT.done:
			seq = ""
	door_open = clampf(door_node.rotation.y / DOOR_SWING, 0.0, 1.0) if door_node else 0.0
	# the cabin shows through the open door for everyone; the driver always sees it from the seat
	if not show_cabin: inside.visible = door_open > 0.02

## The two front seats (the cabin model has none): cushion, reclined back, headrest. Everyone sees
## them; the passenger seat is where a carried survivor slumps.
func _seats() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.12, 0.1)
	m.roughness = 0.72
	for sx in [0.42, -0.42]:
		var seat := Node3D.new()
		seat.position = Vector3(sx, 0.0, 0.0)
		model.add_child(seat)
		for e in [[Vector3(0.5, 0.14, 0.52), Vector3(0, 0.86, -0.2), 0.08],      # cushion, nose up a touch
				[Vector3(0.5, 0.72, 0.13), Vector3(0, 1.22, -0.56), -0.38],    # back, reclined
				[Vector3(0.3, 0.17, 0.1), Vector3(0, 1.66, -0.72), -0.38]]:    # headrest
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = e[0]
			bm.material = m
			mi.mesh = bm
			mi.position = e[1]
			mi.rotation.x = e[2]
			seat.add_child(mi)

## The killer's hands on the wheel: gloves on the rim at ten to two, riding with the wheel, and the
## sleeves back to the shoulders (re-aimed every frame in _arms). Only the driver sees them.
func _hands() -> void:
	if steer_node == null: return
	hand_root = Node3D.new()
	hand_root.visible = false
	inside.add_child(hand_root)
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.07, 0.055, 0.055)
	glove.roughness = 0.55
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color(0.11, 0.018, 0.022) # her robe: a dark, dried crimson
	sleeve.roughness = 0.92
	var n := STEER_AXIS.normalized()
	var up := (Vector3.UP - n * n.y).normalized()
	var lx := (Vector3.RIGHT - n * n.x).normalized()   # +x: the driver's left
	for side in [1.0, -1.0]:
		var dir: Vector3 = (up * cos(1.05) + lx * side * sin(1.05)).normalized()
		var at: Vector3 = dir * STEER_RIM
		var g := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.034
		cm.height = 0.12
		cm.material = glove
		g.mesh = cm
		var tang := n.cross(dir).normalized()       # the fist closes round the rim
		g.basis = Basis(tang.cross(n).normalized(), tang, n) # capsule's own y along the rim
		g.position = at - n * 0.02
		steer_node.add_child(g)
		var knuckle := MeshInstance3D.new()
		var km := BoxMesh.new()
		km.size = Vector3(0.075, 0.045, 0.085)
		km.material = glove
		knuckle.mesh = km
		knuckle.position = at - n * 0.055
		knuckle.basis = g.basis
		steer_node.add_child(knuckle)
		gloves.append(g); gloves.append(knuckle)
		hands.append([g, side])
		var arm := []
		for r in [0.043, 0.036]:
			var mi := MeshInstance3D.new()
			var c2 := CapsuleMesh.new()
			c2.radius = r
			c2.height = 0.3
			c2.material = sleeve
			mi.mesh = c2
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hand_root.add_child(mi)
			arm.append(mi)
		arm.append(Vector3(0.42 + 0.2 * side, 1.3, -0.44)) # the shoulder, in car space
		arm.append(side)
		arms.append(arm)

## Upper arm and forearm from the shoulder to the glove on the wheel, the elbow dropped and out.
func _arms() -> void:
	if hand_root == null: return
	for g in gloves: g.visible = hand_root.visible and seated() > 0.75
	if not hand_root.visible: return
	for i in arms.size():
		var a: Array = arms[i]
		var g: Node3D = hands[i][0]
		var wrist: Vector3 = inside.to_local(g.global_position) + Vector3(0, -0.01, -0.07)
		var sh: Vector3 = a[2]
		var elbow: Vector3 = (sh + wrist) * 0.5 + Vector3(0.09 * float(a[3]), -0.13, 0.0)
		_bone(a[0], sh, elbow)
		_bone(a[1], elbow, wrist)

func _bone(mi: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var d := to - from
	var l := d.length()
	if l < 0.01: return
	(mi.mesh as CapsuleMesh).height = maxf(l + 0.06, 2.0 * (mi.mesh as CapsuleMesh).radius + 0.01)
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), (from + to) * 0.5)

## Dust off the back wheels, smoke out of the exhaust: soft camera-facing puffs.
func _puffs(col: Color, amount: int, life: float, size: float, at: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.position = at
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.5, -1)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.25, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.6))
	var gc := CurveTexture.new()
	gc.curve = grow
	pm.scale_curve = gc
	var fade := Gradient.new()
	fade.set_color(0, Color(col.r, col.g, col.b, col.a * 0.55))
	fade.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.7, 0.05, 0.1) if amount > 20 else Vector3(0.03, 0.03, 0.03)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	var g := Gradient.new() # a soft round puff
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 64
	m.albedo_texture = gt
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

var show_cabin := false   # this phone is driving and looking from the seat
func show_inside(on: bool) -> void:
	show_cabin = on
	inside.visible = on or door_open > 0.02
	if hand_root: hand_root.visible = false # her own arms are on the wheel now (NFReach)

## Where a carried survivor's rig stands so their hips land on the passenger seat.
func seat_spot() -> Vector3:
	return (model.global_transform * inside.transform) * SEAT_HIPS - Vector3(0, HIPS_Y * VICTIM_SCALE, 0)

## Where the killer's own rig stands so her hips land on the driver's seat.
func driver_spot() -> Vector3:
	return (model.global_transform * inside.transform) * DRIVER_HIPS - Vector3(0, HIPS_Y * VICTIM_SCALE, 0)

## The driver's hands: [left wrist, right wrist, left elbow pole, right elbow pole], in the world.
## The grips are the two points on the rim at ten to two (they turn with the wheel); the wrist sits
## a few centimetres back from the rim toward her. Facing the car's front, her left is +x.
func grips() -> Array:
	var xf := model.global_transform * inside.transform
	var out := [xf * Vector3(0.62, 1.25, 0.2), xf * Vector3(0.22, 1.25, 0.2)]
	for h in hands:
		var g: Node3D = h[0]
		var at: Vector3 = g.global_position + (xf.basis * Vector3(0, -0.02, -0.06))
		out[0 if float(h[1]) > 0.0 else 1] = at
	out.append(xf * Vector3(0.42 + 0.45, 0.8, -0.35))
	out.append(xf * Vector3(0.42 - 0.45, 0.8, -0.35))
	return out

func top() -> float:
	return GEAR_TOP[clampi(gear, 1, 2) - 1]

## Where the driver's eyes are, in the world (follows the car's tilt).
func eye() -> Vector3:
	return (model.global_transform * inside.transform) * EYE # moves with the body: lean, bob, vibration

## Where it is facing (flat).
func forward() -> Vector3:
	return Vector3(sin(rotation.y), 0.0, cos(rotation.y))

## The driver's phone: throttle -1..1 (stick up = forward), turn -1..1 (right = +1).
func drive(throttle: float, turn: float, dt: float) -> void:
	driver_local = true
	if throttle > 0.05:
		if speed < -0.3: speed = move_toward(speed, 0.0, BRAKE * dt)
		else: # strong off the line, easing off as it nears top speed
			var pull := ACCEL * lerpf(1.35, 0.55, clampf(speed / top(), 0.0, 1.0)) * (1.0 if gear == 1 else 0.85)
			speed = move_toward(speed, top() * throttle, pull * dt)
	elif throttle < -0.05:
		if speed > 0.3: speed = move_toward(speed, 0.0, BRAKE * dt)
		else: speed = move_toward(speed, -MAX_BACK * -throttle, ACCEL * 0.7 * dt)
	else:
		speed = move_toward(speed, 0.0, COAST * dt)
	steer = move_toward(steer, clampf(turn, -1.0, 1.0), 4.0 * dt)
	# a car turns only while it rolls, the other way round in reverse, and less sharply flat out
	var k := clampf(absf(speed) / 4.0, 0.0, 1.0) * signf(speed) * lerpf(1.0, 0.62, clampf(absf(speed) / MAX_FWD, 0.0, 1.0))
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
	driver_local = false
	var w := 1.0 - exp(-12.0 * dt)
	position = position.lerp(at, w)
	rotation.y = lerp_angle(rotation.y, yaw, w)
	var step := Vector2(position.x - _last.x, position.z - _last.z)
	var fwd := forward()
	var sgn := 1.0 if step.dot(Vector2(fwd.x, fwd.z)) >= 0.0 else -1.0
	speed = lerpf(speed, sgn * step.length() / maxf(dt, 0.001), 1.0 - exp(-6.0 * dt))
	# the steering the driver must have used, from how fast it turned
	var yaw_rate := wrapf(rotation.y - _last_yaw, -PI, PI) / maxf(dt, 0.001)
	var kk := clampf(absf(speed) / 4.0, 0.15, 1.0) * (1.0 if speed >= 0.0 else -1.0)
	steer = lerpf(steer, clampf(-yaw_rate / (TURN * kk), -1.0, 1.0), 1.0 - exp(-8.0 * dt))
	_last = position
	_last_yaw = rotation.y
	_tilt(_ground_normal(), dt)
	_effects(dt)

## Nobody in it: lights off, engine off, and it sits where it was left.
func park(dt: float) -> void:
	speed = 0.0
	steer = move_toward(steer, 0.0, 2.0 * dt)
	_last = position
	_last_yaw = rotation.y
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

## Wheels roll with the speed and the front pair steers; the body leans out of a turn, dips its
## nose when braking and squats when pulling away (only the body: the wheels stay on the ground).
func _animate(dt: float) -> void:
	spin = wrapf(spin + speed / (WHEEL_R * _scale) * dt, -TAU, TAU)
	for e in wheels:
		var w: Node3D = e[0]
		var a := steer * -STEER_MAX if e[1] else 0.0 # stick right = turn right = wheels toward -x
		w.basis = Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, spin)
	var accel := (speed - _prev_speed) / maxf(dt, 0.001)
	_prev_speed = speed
	var want := Vector2(steer * clampf(absf(speed) / MAX_FWD, 0.0, 1.0) * 0.055,
		clampf(-accel * 0.006, -0.05, 0.05))
	lean = lean.lerp(want, 1.0 - exp(-5.0 * dt))
	# suspension: a bump (the car's vertical speed changing) kicks a damped spring under the body
	var vy := velocity.y if driven else 0.0
	bob_v += clampf(-(vy - _prev_vy) * 0.35, -0.6, 0.6)
	_prev_vy = vy
	bob_v += (-140.0 * bob - 14.0 * bob_v) * dt
	bob = clampf(bob + bob_v * dt, -0.06, 0.06)
	# the engine: a fine shiver at idle, a rougher one at speed
	_t += dt
	var shake := 0.0
	if driven: shake = (0.0012 + 0.0022 * clampf(absf(speed) / MAX_FWD, 0.0, 1.0)) * sin(_t * 61.0) * sin(_t * 17.0)
	var tilt := Transform3D(Basis(Vector3.FORWARD, lean.x) * Basis(Vector3.RIGHT, lean.y + shake * 2.0), Vector3(0, bob + shake, 0))
	var pivot := Transform3D(Basis(), Vector3(0, 0.8, 0))
	var t := pivot * tilt * pivot.affine_inverse()
	if frame_node:
		frame_node.transform = t
		inside.transform = t
	if door_root: # the hinge leans with the body; the clip turns the door inside it
		door_root.transform = t * Transform3D(Basis(), door_hinge)
	if steer_node: # the steering wheel follows the front wheels, the gloves with it
		steer_node.basis = Basis(STEER_AXIS.normalized(), steer * STEER_TURNS)
	_arms()
	if dust:
		dust.emitting = dust_on and driven and absf(speed) > 2.5 and (is_on_floor() or not driver_local)
		dust.amount_ratio = clampf(absf(speed) / MAX_FWD, 0.25, 1.0)
		smoke.emitting = driven

func _effects(dt: float) -> void:
	_sequence(dt)
	_animate(dt)
	var on := 1.0 if driven else 0.0
	lights.light_energy = lerpf(lights.light_energy, LIGHT_ENERGY * on, 1.0 - exp(-6.0 * dt))
	lights.visible = lights.light_energy > 0.05
	tail.light_energy = lerpf(tail.light_energy, (0.45 + (0.55 if speed < -0.3 or (driven and absf(speed) < 0.4) else 0.0)) * on, 1.0 - exp(-8.0 * dt))
	tail.visible = tail.light_energy > 0.05
	if radio:
		var want := radio_on # left on, it keeps playing in the parked car
		if want and not _radio_started:
			radio.play()
			_radio_started = true
		elif _radio_started:
			radio.stream_paused = not want
	if engine:
		# the loop comes up under the starter clip and dies away when he switches off
		var want := 1.0 if (running and driven and (starter == null or not starter.playing or starter.get_playback_position() > 2.2)) else 0.0
		engine_gain = move_toward(engine_gain, want, (0.8 if want > engine_gain else 2.0) * dt)
		if engine_gain > 0.001 and not engine.playing: engine.play()
		elif engine_gain <= 0.001 and engine.playing: engine.stop()
		engine.volume_db = linear_to_db(maxf(engine_gain, 0.0001))
		engine.pitch_scale = 0.85 + clampf(absf(speed) / top(), 0.0, 1.0) * 0.6 # drops when he shifts up
