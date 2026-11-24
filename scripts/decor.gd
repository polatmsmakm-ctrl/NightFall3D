class_name NFDecor
extends RefCounted
## The graphics pass's cheap dressing, all made in code (no image files):
##  * decals — blood under the hooks, drag marks, oil under the generators, dirt and stains, and on
##    the rain night puddles that are glossy enough to mirror the lamps (their own roughness map);
##  * fire — real flames, embers and smoke over every campfire on the maps;
##  * rain — the «مطر» weather's streaks that follow the camera, and its lightning;
##  * grade — one small colour-correction curve per map, so every map has its own film look.
## Every texture is drawn once per launch and kept (they are small: 128 px).

static var _tex := {}

## A texture by name, drawn the first time it is asked for.
static func tex(kind: String) -> Texture2D:
	if _tex.has(kind): return _tex[kind]
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = absi(hash(kind)) % 9973
	noise.frequency = 0.045
	noise.fractal_octaves = 4
	var c := Vector2(n, n) / 2.0
	for y in n:
		for x in n:
			var p := Vector2(x, y)
			var d := p.distance_to(c) / (n * 0.5) # 0 centre .. 1 edge
			var v := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var col := Color(0, 0, 0, 0)
			match kind:
				"blood": # a dark pool with ragged edges and a few drops around it
					var r := 0.55 + (v - 0.5) * 0.55
					var a := clampf((r - d) * 7.0, 0.0, 1.0)
					var drop := noise.get_noise_2d(x * 3.1 + 40.0, y * 3.1) > 0.48 and d < 0.95
					if drop: a = maxf(a, 0.9)
					col = Color(0.22 + v * 0.12, 0.012, 0.01, a * 0.92)
				"drag": # a smeared trail: long across x, thin across y
					var ty := absf(y - c.y) / (n * 0.5)
					var a := clampf((0.32 + (v - 0.5) * 0.4 - ty) * 6.0, 0.0, 1.0) * clampf((1.0 - absf(x - c.x) / (n * 0.5)) * 3.0, 0.0, 1.0)
					col = Color(0.2 + v * 0.1, 0.01, 0.01, a * 0.75)
				"oil": # a black, slightly blue-brown stain
					var a := clampf((0.62 + (v - 0.5) * 0.6 - d) * 4.0, 0.0, 1.0)
					col = Color(0.03 + v * 0.03, 0.025, 0.02, a * 0.8)
				"dirt": # soft grime, faint
					var a := clampf((0.75 - d) * 2.0, 0.0, 1.0) * clampf(v * 1.6 - 0.35, 0.0, 1.0)
					col = Color(0.09, 0.07, 0.05, a * 0.55)
				"puddle": # dark water: the albedo only darkens, the roughness map makes it shine
					var a := clampf((0.6 + (v - 0.5) * 0.5 - d) * 5.0, 0.0, 1.0)
					col = Color(0.02, 0.025, 0.03, a * 0.55)
				"puddle_orm": # occlusion 1, roughness almost 0 inside, metallic 0
					var a := clampf((0.6 + (v - 0.5) * 0.5 - d) * 5.0, 0.0, 1.0)
					col = Color(1.0, 0.04, 0.0, a)
				"soft": # a round soft spot (smoke and embers)
					var a := clampf(1.0 - d, 0.0, 1.0)
					col = Color(1, 1, 1, a * a)
				"streak": # a rain streak: a thin vertical line, fading at both ends
					var a := clampf(1.0 - absf(x - c.x) / 3.0, 0.0, 1.0) * clampf(1.0 - absf(y - c.y) / (n * 0.5), 0.0, 1.0)
					col = Color(0.8, 0.85, 0.95, a * 0.6)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[kind] = t
	return t

## One decal lying on the ground at `at` (it projects straight down), `w` metres across.
static func decal(parent: Node3D, at: Vector3, w: float, kind: String, yaw := 0.0, stretch := 1.0, fade := 40.0) -> Decal:
	var d := Decal.new()
	d.size = Vector3(w * stretch, 1.6, w)
	d.position = at + Vector3(0, 0.4, 0)
	d.rotation.y = yaw
	d.texture_albedo = tex(kind)
	if kind == "puddle":
		d.texture_orm = tex("puddle_orm")
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.normal_fade = 0.5 # only on what faces up: never smeared down a wall
	d.distance_fade_enabled = true
	d.distance_fade_begin = fade
	d.distance_fade_length = 8.0
	parent.add_child(d)
	return d

## Flames, embers and smoke over a campfire. `y` is the height of the fire bed above the node.
static func fire(parent: Node3D, y: float, rich: bool) -> void:
	var flames := GPUParticles3D.new()
	flames.amount = 26 if rich else 14
	flames.lifetime = 0.7
	flames.position = Vector3(0, y, 0)
	var fp := ParticleProcessMaterial.new()
	fp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fp.emission_sphere_radius = 0.22
	fp.direction = Vector3.UP
	fp.spread = 12.0
	fp.gravity = Vector3(0, 1.6, 0)
	fp.initial_velocity_min = 0.4; fp.initial_velocity_max = 0.9
	fp.scale_min = 0.55; fp.scale_max = 1.0
	var curve := CurveTexture.new()
	var cv := Curve.new()
	cv.add_point(Vector2(0, 0.6)); cv.add_point(Vector2(0.3, 1.0)); cv.add_point(Vector2(1, 0.0))
	curve.curve = cv
	fp.scale_curve = curve
	var grad := GradientTexture1D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.45, 1.0))
	g.set_color(1, Color(0.9, 0.18, 0.02, 0.0))
	g.add_point(0.45, Color(1.0, 0.45, 0.08, 0.85))
	grad.gradient = g
	fp.color_ramp = grad
	flames.process_material = fp
	flames.draw_pass_1 = _quad(0.5, "soft", true)
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flames.visibility_aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 3, 2))
	parent.add_child(flames)
	var embers := GPUParticles3D.new()
	embers.amount = 18 if rich else 8
	embers.lifetime = 2.2
	embers.position = Vector3(0, y + 0.2, 0)
	var ep := ParticleProcessMaterial.new()
	ep.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ep.emission_sphere_radius = 0.3
	ep.direction = Vector3.UP
	ep.spread = 30.0
	ep.gravity = Vector3(0.15, 0.7, 0.05)
	ep.initial_velocity_min = 0.6; ep.initial_velocity_max = 1.6
	ep.turbulence_enabled = true
	ep.turbulence_noise_strength = 0.6
	ep.scale_min = 0.5; ep.scale_max = 1.0
	var eg := GradientTexture1D.new()
	var g2 := Gradient.new()
	g2.set_color(0, Color(1.0, 0.7, 0.25, 1.0))
	g2.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	eg.gradient = g2
	ep.color_ramp = eg
	embers.process_material = ep
	embers.draw_pass_1 = _quad(0.05, "soft", true)
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	embers.visibility_aabb = AABB(Vector3(-2, -0.5, -2), Vector3(4, 6, 4))
	parent.add_child(embers)
	if not rich: return
	var smoke := GPUParticles3D.new()
	smoke.amount = 12
	smoke.lifetime = 4.5
	smoke.position = Vector3(0, y + 0.8, 0)
	var sp := ParticleProcessMaterial.new()
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sp.emission_sphere_radius = 0.25
	sp.direction = Vector3.UP
	sp.spread = 15.0
	sp.gravity = Vector3(0.25, 0.35, 0.1)
	sp.initial_velocity_min = 0.3; sp.initial_velocity_max = 0.6
	sp.scale_min = 0.8; sp.scale_max = 1.4
	var sc := CurveTexture.new()
	var scv := Curve.new()
	scv.add_point(Vector2(0, 0.4)); scv.add_point(Vector2(1, 1.0))
	sc.curve = scv
	sp.scale_curve = sc
	var sg := GradientTexture1D.new()
	var g3 := Gradient.new()
	g3.set_color(0, Color(0.12, 0.11, 0.1, 0.0))
	g3.set_color(1, Color(0.1, 0.1, 0.1, 0.0))
	g3.add_point(0.25, Color(0.13, 0.12, 0.11, 0.32))
	sg.gradient = g3
	sp.color_ramp = sg
	smoke.process_material = sp
	smoke.draw_pass_1 = _quad(1.4, "soft", false)
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 9, 6))
	parent.add_child(smoke)

## The rain: streaks falling round whatever the world follows (moved there every frame).
static func rain(amount: int) -> GPUParticles3D:
	var r := GPUParticles3D.new()
	r.amount = amount
	r.lifetime = 0.9
	var rp := ParticleProcessMaterial.new()
	rp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rp.emission_box_extents = Vector3(16, 0.5, 16)
	rp.direction = Vector3(0.08, -1, 0.04)
	rp.spread = 2.0
	rp.gravity = Vector3(0, -9.8, 0)
	rp.initial_velocity_min = 14.0; rp.initial_velocity_max = 17.0
	rp.particle_flag_align_y = true # each streak points the way it falls
	r.process_material = rp
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex("streak")
	m.albedo_color = Color(0.75, 0.8, 0.9, 0.42)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	r.draw_pass_1 = q
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.visibility_aabb = AABB(Vector3(-20, -18, -20), Vector3(40, 22, 40))
	r.preprocess = 1.0
	return r

## A one-shot burst of particles at `at` that frees itself: the pistol's smoke and sparks.
## `col0` -> `col1` over its life; `add` for light (sparks, flash), alpha for smoke.
static func burst(parent: Node, at: Vector3, dir: Vector3, n: int, life: float, size: float, speed: Vector2,
		spread: float, gravity: Vector3, col0: Color, col1: Color, add: bool, grow := 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var m := ParticleProcessMaterial.new()
	m.direction = dir.normalized() if dir.length() > 0.001 else Vector3.UP
	m.spread = spread
	m.initial_velocity_min = speed.x
	m.initial_velocity_max = speed.y
	m.gravity = gravity
	m.damping_min = 1.5; m.damping_max = 3.0
	m.scale_min = 0.6; m.scale_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5)); sc.add_point(Vector2(1, grow))
	var st := CurveTexture.new(); st.curve = sc
	m.scale_curve = st
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	g.colors = PackedColorArray([col0, col0, Color(col1.r, col1.g, col1.b, 0.0)])
	var gt := GradientTexture1D.new(); gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	p.draw_pass_1 = _quad(size, "soft", add)
	p.amount = n
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)
	return p

static func _quad(sz: float, kind: String, add: bool) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(sz, sz)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if add: m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = tex(kind)
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	return q

## The map's film look: a gentle S-curve and a tint in the shadows and in the highlights, as a
## one-dimensional lookup the environment applies after the tone mapping (free to draw).
static func grade(map_id: String, theme: String) -> GradientTexture1D:
	# [shadow tint, highlight tint] as small offsets per channel
	var sh := Vector3(0.0, 0.012, 0.03)   # forest: teal night
	var hi := Vector3(0.012, 0.006, -0.01)
	match map_id:
		"village": sh = Vector3(0.004, 0.012, 0.006); hi = Vector3(0.01, 0.008, -0.012)
		"fareej": sh = Vector3(0.02, 0.008, -0.004); hi = Vector3(0.035, 0.012, -0.03)   # warm, old streets
		"garage": sh = Vector3(-0.004, 0.022, 0.006); hi = Vector3(-0.01, 0.02, -0.015)  # sick strip-light green
		"beach": sh = Vector3(-0.004, 0.01, 0.038); hi = Vector3(0.008, 0.012, 0.004)    # moonlit blue
		"rubkhali": sh = Vector3(0.03, 0.01, -0.02); hi = Vector3(0.025, 0.004, -0.04)   # baked orange
	match theme:
		"halloween": sh += Vector3(0.015, 0.0, -0.01); hi += Vector3(0.02, -0.004, -0.02)
		"snow": sh += Vector3(-0.005, 0.0, 0.02); hi += Vector3(-0.004, 0.004, 0.012)
		"fog": sh *= 0.5; hi *= 0.5
		"rain": sh += Vector3(-0.006, 0.004, 0.022); hi += Vector3(-0.008, 0.0, 0.01)
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	var pts := [[0.0, 0.0], [0.18, 0.165], [0.5, 0.5], [0.8, 0.825], [1.0, 1.0]] # input -> S-curve
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color.BLACK, Color.WHITE])
	for i in pts.size():
		var t: float = pts[i][0]
		var v: float = pts[i][1]
		var shw := clampf(1.0 - t / 0.5, 0.0, 1.0) # how much of the shadow tint
		var hiw := clampf((t - 0.5) / 0.5, 0.0, 1.0)
		var off := sh * shw + hi * hiw
		var col := Color(clampf(v + off.x, 0, 1), clampf(v + off.y, 0, 1), clampf(v + off.z, 0, 1))
		if i == 0: g.set_color(0, col)
		elif i == pts.size() - 1: g.set_color(1, col)
		else: g.add_point(t, col)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.width = 256
	gt.use_hdr = false
	return gt
