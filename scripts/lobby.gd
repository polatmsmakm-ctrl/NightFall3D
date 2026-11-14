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

var stock: Array[Node3D] = []     # the shipped cast, shown when we are not in a room
var cast := {}                  # other players in the room: name -> {rig, tag}
var me_rig: CharacterRig
var me_char := ""
var me_name := ""
var _emoting := {} # rig -> seconds left before going back to idle
var me_label: Label3D
var fire: OmniLight3D
var pivot: Node3D
var cam: Camera3D
var key_light: OmniLight3D
var focused := false
var _focus := 0.0
var _slide := 0.0
var _slide_from := Vector3.ZERO
var _dot_tex: ImageTexture

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

func _ready() -> void:
	var kit := NightWorld.new() # borrow the world's materials and meshes (never added to the tree)
	kit._make_materials()
	var env := Environment.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
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
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.basis = Basis.looking_at(-Vector3(0.35, 0.33, -0.88).normalized())
	moon.light_color = Color(0.5, 0.6, 0.95)
	moon.light_energy = 1.0
	moon.shadow_enabled = true
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
	# camp props: stone ring, sitting logs, tent, crate with a lantern, stump with an axe, backpacks
	var rock: Material = kit._mat.rock
	var wood: Material = kit._mat.wood
	for k in 11:
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
	for k in 6:
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
	var fire_root := Node3D.new()
	fire_root.position = Vector3(0, 0.22, 0)
	add_child(fire_root)
	_fire_layer(fire_root, 46, 0.75, 0.17, 1.5, 0.34, [Color(1.0, 0.5, 0.1, 0.0), Color(1.0, 0.36, 0.06, 0.42), Color(0.6, 0.06, 0.0, 0.0)], true, Vector2(0.15, 0.5)) # outer flames
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
	stock.append(killer)
	var rim := OmniLight3D.new() # faint red rim so his outline reads in the dark
	rim.position = Vector3(2.4, 2.2, -8.6)
	rim.light_color = Color(1.0, 0.15, 0.1)
	rim.light_energy = 1.4
	rim.omni_range = 5.0
	add_child(rim)
	# a soft key light in front of the stand, so the chosen character is not a silhouette
	key_light = OmniLight3D.new()
	key_light.position = STAND + Vector3(0.5, 1.9, 1.7)
	key_light.light_color = Color(1.0, 0.86, 0.72)
	key_light.light_energy = 1.9
	key_light.omni_range = 6.0
	add_child(key_light)
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
		var stream: AudioStreamMP3 = load("res://assets/sfx/%s.mp3" % snd[0])
		stream.loop = true
		a.stream = stream
		a.volume_db = snd[1]
		add_child(a)
		a.play()
	kit.free()

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
	me_rig.setup(char_id, ["idle", "campfire"] + EMOTES)
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
		r.add_child(_tag(n, Color(1, 0.45, 0.45) if killer else Color(0.78, 0.92, 1.0), 2.2))
		cast[n] = {"rig": r, "char": str(d.char), "seat": int(d.seat)}
	var in_room := not players.is_empty()
	for s in stock: s.visible = not in_room

## Play a campfire emote. `who` is the player's name; mine is the one standing at the fire.
func emote(who: String, k: int) -> void:
	k = clampi(k, 0, EMOTES.size() - 1)
	var r: CharacterRig = null
	if who == me_name or who == "": r = me_rig
	elif cast.has(who): r = cast[who].rig
	if r == null or not is_instance_valid(r): return
	if not r.player.has_animation(EMOTES[k]): return
	r.play(EMOTES[k])
	_emoting[r] = 3.4 # then back to sitting / standing

func _tick_emotes(dt: float) -> void:
	for r in _emoting.keys():
		if not is_instance_valid(r):
			_emoting.erase(r)
			continue
		_emoting[r] -= dt
		if _emoting[r] <= 0.0:
			_emoting.erase(r)
			r.play("idle" if r == me_rig else ("campfire" if r.player.has_animation("campfire") else "idle"))

func _process(dt: float) -> void:
	_tick_emotes(dt)
	var tt := Time.get_ticks_msec() / 1000.0
	var flick := 0.78 + 0.14 * sin(tt * 13.0) * sin(tt * 4.3) + 0.08 * sin(tt * 27.0)
	fire.light_energy = 3.4 * flick
	fire.position = Vector3(0.05 * sin(tt * 9.0), 0.75 + 0.05 * sin(tt * 7.0), 0.05 * cos(tt * 11.0)) # shadows dance
	pivot.rotation.y = 0.1 * sin(tt * 0.13) * (1.0 - _focus)
	var want := 1.0 if focused else 0.0
	if absf(_focus - want) > 0.001:
		_focus = move_toward(_focus, want, dt * 1.6)
		var e: float = _focus * _focus * (3.0 - 2.0 * _focus) # smoothstep
		cam.position = (CAM_IDLE[0] as Vector3).lerp(CAM_CHAR[0], e)
		cam.rotation = (CAM_IDLE[1] as Vector3).lerp(CAM_CHAR[1], e)
	key_light.light_energy = lerpf(0.9, 2.1, _focus)
	if _slide > 0.0 and me_rig:
		_slide = maxf(_slide - dt * 3.4, 0.0)
		var k: float = 1.0 - _slide
		me_rig.position = _slide_from.lerp(STAND, k * k * (3.0 - 2.0 * k))
