class_name NFLook
## The high-end look: everything the Forward+ renderer can draw that the Mobile one could not.
## Every environment in the game (the maps, the camp, the results stage) goes through `apply()`,
## and so do the lights and the characters that gain something from it. With the light engine
## («محرك الرسم: خفيف», Gfx.ENGINE_PATH) none of this runs and the game looks as it did before.
##
## What each «جودة المؤثرات» level turns on (the adaptive governor drops a level when the frame
## rate cannot keep up, so the heavy ones go first):
##   0  glow only
##   1  + ambient occlusion, volumetric fog, shadows from the torch and the headlights
##   2  + bounced light (SSIL), global illumination over the map (SDFGI), reflections in the car park

static func hd() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

## kind: "night" (every night map), "day" (the Empty Quarter), "garage", "fog" (the fog weather),
## "camp" (the start screen), "stage" (the results stage and the victory shot).
static func apply(env: Environment, kind: String) -> void:
	if env == null or not hd(): return
	var fx := Gfx.eff_effects()
	# ambient occlusion: the dark where things meet the ground and each other
	env.ssao_enabled = fx >= 1
	env.ssao_radius = 1.3
	env.ssao_intensity = 2.4
	env.ssao_power = 1.7
	env.ssao_detail = 0.7
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.2 # at night most light is ambient; let the occlusion bite a little into the rest
	# light bouncing off nearby surfaces: a lamp warms the wall beside it, a torch the floor
	env.ssil_enabled = fx >= 2
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.85
	env.ssil_sharpness = 0.98
	env.ssil_normal_rejection = 1.0
	# global illumination over the whole map, worked out live (the maps change every round, so it
	# cannot be baked)
	# (daylight and the strip-lit car park only: on the moonlit maps it washed the white walls out,
	# and the lamps' bounce there comes from SSIL instead)
	env.sdfgi_enabled = fx >= 2 and kind in ["day", "garage"]
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = kind == "day"
	env.sdfgi_bounce_feedback = 0.45
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.25
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	env.sdfgi_energy = 1.0 if kind == "day" else 0.55 # the night maps already carry a lot of flat ambient
	env.sdfgi_normal_bias = 1.1
	env.sdfgi_probe_bias = 1.1
	# volumetric fog: shafts of light from the lamps, the headlights and the torches
	env.volumetric_fog_enabled = fx >= 1 and kind != "stage"
	env.volumetric_fog_density = {"night": 0.024, "fog": 0.045, "garage": 0.018, "day": 0.01, "camp": 0.018}.get(kind, 0.024)
	env.volumetric_fog_albedo = Color(0.95, 0.82, 0.62) if kind == "day" else Color(0.78, 0.82, 0.9)
	env.volumetric_fog_emission = Color.BLACK
	env.volumetric_fog_anisotropy = 0.7 if kind == "day" else 0.55 # forward glow round every light
	env.volumetric_fog_length = 56.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.3
	env.volumetric_fog_ambient_inject = 0.06
	env.volumetric_fog_sky_affect = 0.0 # the sky stays sharp
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.9
	# bloom round bright things
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0 if kind != "day" else 1.4
	for i in 7: env.set_glow_level(i, i in [1, 2, 3, 4])
	# lamps and headlights mirrored in the car park's polished concrete
	env.ssr_enabled = fx >= 2 and kind == "garage"
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3

## A key light gets soft, sharper-edged shadows (the moon, the sun, the camp's key light).
static func soft_sun(l: DirectionalLight3D, angle_deg := 0.6) -> void:
	if l == null or not hd(): return
	l.light_angular_distance = angle_deg
	l.shadow_blur = 1.2

## A torch, the headlights, the camp fire: real shadows from a moving light.
static func shadows_on(l: Light3D, need_fx := 1) -> void:
	if l == null or not hd(): return
	l.light_volumetric_fog_energy = 3.5 # a visible beam in the fog
	l.shadow_enabled = Gfx.eff_effects() >= need_fx
	l.shadow_bias = 0.05
	l.shadow_normal_bias = 1.2
	if l is SpotLight3D: (l as Light3D).light_size = 0.08
	else: l.light_size = 0.15

## A lamp, a fire, a lit window: a soft halo in the volumetric fog.
static func halo(l: Light3D, k := 1.8) -> void:
	if l == null or not hd(): return
	l.light_volumetric_fog_energy = k

static var _masks := {}

## Skin that lets a little light through (subsurface scattering), only where the character's
## colour map is skin: `assets/chars/<file>_skin.png`, a grey mask baked from the colour map by
## tools/skin_mask.py. A character without a mask is left alone (clothes would turn waxy).
static func skin(root: Node, file: String) -> void:
	if root == null or not hd(): return
	var path := "res://assets/chars/%s_skin.png" % file
	if not _masks.has(path): _masks[path] = load(path) if ResourceLoader.exists(path) else null
	var mask: Texture2D = _masks[path]
	if mask == null: return
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in (m.mesh.get_surface_count() if m.mesh else 0):
			var mat := m.get_active_material(s) as StandardMaterial3D
			if mat == null or mat.subsurf_scatter_enabled: continue
			mat.subsurf_scatter_enabled = true
			mat.subsurf_scatter_strength = 0.32
			mat.subsurf_scatter_skin_mode = true
			mat.subsurf_scatter_texture = mask
