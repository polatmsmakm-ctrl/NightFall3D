class_name NFHeli
extends Node3D
## The rescue helicopter (the owner's model, assets/props/heli.glb: `frame`, the main rotor `rotor`
## on its hub and the tail rotor `tail`; nose toward +z). It follows the rules' `heli` row on every
## phone: 1 coming (flies in over the round's HELI_COME seconds, slowing, nose up to flare as it
## arrives), 2 hovering over its spot with the rope ladder down, 3 someone climbing, 4 away with them,
## 5 leaving without anyone. Rotors spin, the body drifts and rocks a little in the hover, a
## searchlight points at the ladder's foot, its sound comes from where it is.

const HOVER_Y := 15.0          # the ladder's top above the ground
const RUNG := 0.32             # between the rungs
const LADDER_GAP := 0.46       # between the two ropes
const ATTACH := Vector3(-2.3, 1.1, 2.4) # the side door (the fuselage runs along x -1, its left side at -2.2), in its own frame
const LEAVE_TIME := 14.0

var spot := Vector3.ZERO       # the ladder's foot
var from_dir := Vector3(1, 0, 0) # it comes in from (and leaves toward) this side
var body: Node3D
var rotor: Node3D
var tail: Node3D
var ladder: Node3D
var light: SpotLight3D
var sound: AudioStreamPlayer3D
var st := 0
var leave_t := -1.0
var t := 0.0
var final_yaw := 0.0
var hover := Vector3.ZERO      # where the body sits in the hover
var ladder_len := 14.0
var pos := Vector3.ZERO        # where the body is now (smoothed)

func setup(at: Vector3, dir: Vector3) -> void:
	spot = at
	from_dir = Vector3(dir.x, 0, dir.z).normalized() if dir.length() > 0.01 else Vector3(1, 0, 0)
	final_yaw = atan2(-from_dir.x, -from_dir.z) # nose pointing back toward where it came from... turned to face in
	var b := Basis(Vector3.UP, final_yaw)
	hover = spot + Vector3(0, HOVER_Y, 0) - b * ATTACH
	body = Node3D.new()
	add_child(body)
	var ps: PackedScene = load("res://assets/props/heli.glb") if ResourceLoader.exists("res://assets/props/heli.glb") else null
	if ps:
		var m := ps.instantiate() as Node3D
		body.add_child(m)
		rotor = m.find_child("rotor", true, false) as Node3D
		tail = m.find_child("tail", true, false) as Node3D
	else: # a stand-in until the model is there
		var mi := MeshInstance3D.new()
		var bx := BoxMesh.new()
		bx.size = Vector3(2.6, 2.6, 9.0)
		mi.mesh = bx
		mi.position = Vector3(0, 1.6, 0)
		body.add_child(mi)
	# the rope ladder: two ropes and the rungs between them, hanging from the side door
	ladder = Node3D.new()
	ladder.position = ATTACH
	body.add_child(ladder)
	ladder_len = HOVER_Y - 0.45
	var rope_m := StandardMaterial3D.new()
	rope_m.albedo_color = Color(0.42, 0.33, 0.22)
	rope_m.roughness = 0.9
	for sx in [-1.0, 1.0]:
		var r := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.018; cy.bottom_radius = 0.018; cy.height = ladder_len; cy.radial_segments = 6
		cy.material = rope_m
		r.mesh = cy
		r.position = Vector3(sx * LADDER_GAP / 2.0, -ladder_len / 2.0, 0)
		ladder.add_child(r)
	var rungs := MultiMesh.new()
	rungs.transform_format = MultiMesh.TRANSFORM_3D
	var rm := CylinderMesh.new()
	rm.top_radius = 0.022; rm.bottom_radius = 0.022; rm.height = LADDER_GAP; rm.radial_segments = 6
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.24, 0.14)
	wood.roughness = 0.8
	rm.material = wood
	rungs.mesh = rm
	var n := int(ladder_len / RUNG)
	rungs.instance_count = n
	for i in n:
		rungs.set_instance_transform(i, Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), Vector3(0, -ladder_len + 0.25 + i * RUNG, 0)))
	var rmi := MultiMeshInstance3D.new()
	rmi.multimesh = rungs
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ladder.add_child(rmi)
	ladder.visible = false
	light = SpotLight3D.new()
	light.light_color = Color(0.85, 0.92, 1.0)
	light.light_energy = 9.0
	light.spot_range = 45.0
	light.spot_angle = 18.0
	light.position = Vector3(0, 0.6, 4.0)
	body.add_child(light)
	if ResourceLoader.exists("res://assets/sfx/heli.ogg"):
		var s := load("res://assets/sfx/heli.ogg") as AudioStream
		if s is AudioStreamOggVorbis: (s as AudioStreamOggVorbis).loop = true
		sound = AudioStreamPlayer3D.new()
		sound.stream = s
		sound.bus = "SFX"
		sound.unit_size = 34.0
		sound.max_distance = 520.0
		sound.volume_db = 4.0
		body.add_child(sound)
	visible = false

## Where the ladder's rungs are in the world: its foot and its top (the climber goes between them).
func ladder_foot() -> Vector3: return ladder.global_transform * Vector3(0, -ladder_len, 0)
func ladder_top() -> Vector3: return ladder.global_transform * Vector3(0, 0, 0)
## The way a climber faces the ladder (toward the helicopter's side).
func ladder_face() -> Vector3: return (body.global_transform.basis * Vector3(1, 0, 0)).normalized()
## The rung nearest a height on the ladder, in the world (for the climber's hands).
func rung_at(y_world: float) -> Vector3:
	var local := ladder.global_transform.affine_inverse() * Vector3(0, y_world, 0)
	var i := clampi(int(round((local.y + ladder_len - 0.25) / RUNG)), 0, int(ladder_len / RUNG) - 1)
	return ladder.global_transform * Vector3(0, -ladder_len + 0.25 + i * RUNG, 0)

func step(dt: float, h: Dictionary, come_time: float) -> void:
	t += dt
	var s := int(h.get("st", 0))
	if s != st:
		if s >= 1 and s <= 3 and st == 0: pos = hover + from_dir * 280.0 + Vector3(0, 75.0, 0)
		if s >= 4 and st != s: leave_t = 0.0
		st = s
	if st == 0:
		visible = false
		if sound and sound.playing: sound.stop()
		return
	visible = true
	if sound and not sound.playing: sound.play()
	var want := hover
	var yaw := final_yaw
	var pitch := 0.0
	var roll := 0.0
	if st == 1: # flying in: fast and high, slowing and coming down, nose up to flare at the end
		var u := clampf(1.0 - float(h.get("t", 0.0)) / come_time, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - u, 2.4)
		var start := hover + from_dir * 280.0 + Vector3(0, 75.0, 0)
		want = start.lerp(hover, e)
		pitch = lerpf(0.22, -0.18, smoothstep(0.55, 0.95, u)) * (1.0 - smoothstep(0.95, 1.0, u)) # nose down, then the flare
		ladder.visible = u > 0.9
	elif st == 2 or st == 3: # the hover: never quite still
		want = hover + Vector3(sin(t * 0.6) * 0.45, sin(t * 0.9) * 0.25, cos(t * 0.5) * 0.4)
		roll = sin(t * 0.7) * 0.03
		pitch = sin(t * 0.55) * 0.02
		ladder.visible = true
	else: # away: lift, then nose down and off the way it came
		leave_t += dt
		var u := clampf(leave_t / LEAVE_TIME, 0.0, 1.0)
		var lift := smoothstep(0.0, 0.35, u) * 18.0
		var go := pow(maxf(u - 0.2, 0.0) / 0.8, 2.0) * 320.0
		want = hover + Vector3(0, lift + go * 0.18, 0) + from_dir * go
		pitch = 0.25 * smoothstep(0.15, 0.4, u)
		yaw = final_yaw + PI * smoothstep(0.05, 0.3, u) # it turns round to leave the way it came
		ladder.visible = st == 4 or u < 0.4 # (it reels the ladder in when it leaves without anyone)
		if u >= 1.0:
			visible = false
			if sound: sound.stop()
			return
	pos = pos.lerp(want, 1.0 - exp(-3.0 * dt)) if pos != Vector3.ZERO else want
	body.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, roll)), pos)
	if rotor: rotor.rotate_object_local(Vector3.UP, dt * 26.0)
	if tail: tail.rotate_object_local(Vector3.RIGHT, dt * 40.0)
	# the ladder swings under the hover, a little more while someone climbs it
	ladder.rotation = Vector3(sin(t * 1.3) * (0.05 if st == 3 else 0.03), 0, sin(t * 1.1 + 0.6) * (0.06 if st == 3 else 0.035))
	if light.is_inside_tree() and light.global_position.distance_to(spot) > 1.0 and absf((spot - light.global_position).normalized().y) < 0.999:
		light.look_at(spot, Vector3.UP)
