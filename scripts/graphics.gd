extends Node
## Graphics settings (saved), FPS modes, and an adaptive performance governor.
## Autoload name: Gfx

signal changed

const PATH := "user://graphics.cfg"
## «محرك الرسم»: the game ships on Forward+ (the high-end look, NFLook). If a phone cannot keep up,
## this file switches it back to the Mobile renderer from the next launch: project.godot reads it
## through application/config/project_settings_override.
const ENGINE_PATH := "user://override.cfg"
const FPS_OPTS := [0, 30, 60, 120] # 0 = Auto
const SCALE_OPTS := [0.85, 0.9, 1.0]
const PRESETS := { # shadows, aa, scale index, effects
	0: [0, 0, 0, 0], # Medium
	1: [1, 1, 2, 1], # High
	2: [2, 2, 2, 2], # Ultra
	3: [0, 0, 0, 0], # Low: the same as Medium, plus a shorter view, simpler models sooner, softer textures
}
## How far the map is drawn, per preset (metres): small things stop at about half of it.
## Low, Medium, High, Ultra -> 3, 0, 1, 2.
const VIEW := {3: 80.0, 0: 110.0, 1: 150.0, 2: 200.0}
var perf_hud := false # «مراقب الأداء»: FPS, frame time, draw calls, objects, triangles, memory on screen

var fps_idx := 0
var preset := 1
var shadows := 1
var aa := 1
var scale_idx := 2
var effects := 1
## A phone or tablet with a recent Apple chip (iPhone 15 Pro and later, any M-chip iPad): it starts on
## «فائق» and «فائق» draws more there (see apply(), world._apply_quality, main's rigs).
var strong := false
## An older iPhone or iPad (iPhone 15 / 14 Pro and before: A16 and older chips, the iPhone 13 and 14
## among them). It gets its own start: the lighter Mobile renderer from the second launch, settings
## that hold 60 there, and a governor that may go further down (resolution to 70%, a steady 30).
var weak := false
const TIER := 4 # raise it to re-apply the strong-device defaults once on every phone
const WEAK_TIER := 1 # the same for the older-phone defaults
## This launch is the last one on Forward+ before the lighter renderer takes over (the renderer only
## changes at start-up): its heavy effects stay off meanwhile.
var _transit := false
var brightness := 1.0 # «السطوع»: multiplies the exposure of the maps and the camp (0.6 .. 1.6)
# the controls rows in the settings panel (saved with the rest in graphics.cfg)
var look_sens := 1.0   # «حساسية الكاميرا»: how far a drag turns the camera (0.4 .. 2.0)
var fov_add := 0.0     # «مجال الرؤية»: degrees added to every round camera (-10 .. +15)
var btn_scale := 1.0   # «حجم الأزرار»: the round's touch buttons (0.8 .. 1.3)
var btn_alpha := 1.0   # «وضوح الأزرار»: how solid they are drawn (0.35 .. 1.0)
signal look_changed

# runtime-only reductions made by the governor (not saved)
var dyn_scale := 1.0
var rt_shadows := 2
var rt_effects := 2
var rt_fps_cap := 0
var menu_open := false

var _t := 0.0
var _frames := 0
var _warm := 6.0
var _quiet := 0.0 # the round is loading or just began: frame times say nothing about the settings
var _bad := 0
var _good := 0
var _hud: Label
var _panel: PanelContainer
var _opts := {}
var _vol := {}        # slider + percentage label per bus
var _vol_rows := []   # the two rows that "Details" folds away
var _vol_split := false
var _editor: NFControlsEdit
var _engine_note: Label
var last_avg_ms := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	strong = detect_strong()
	weak = detect_weak()
	_load()
	_transit = weak and engine_hd() and not engine_next_hd()
	# an override written before the Mobile renderer carried its MSAA level: add it, for the next launch
	if FileAccess.file_exists(ENGINE_PATH):
		var oc := ConfigFile.new()
		if oc.load(ENGINE_PATH) == OK and not oc.has_section_key("rendering", "anti_aliasing/quality/msaa_3d"):
			oc.set_value("rendering", "anti_aliasing/quality/msaa_3d", 1)
			oc.save(ENGINE_PATH)
	_build_ui()
	apply()

## iPhone 15 Pro (iPhone16,x) and later, and the M1 iPad Pro (iPad13,x) and later. NF_STRONG=1
## pretends, for the tests and the screenshots.
static func detect_strong() -> bool:
	if OS.get_environment("NF_STRONG") == "1": return true
	var m := OS.get_model_name()
	if m.begins_with("iPhone"): return m.trim_prefix("iPhone").get_slice(",", 0).to_int() >= 16
	if m.begins_with("iPad"): return m.trim_prefix("iPad").get_slice(",", 0).to_int() >= 13
	return false

## The older phones and tablets (see weak). NF_WEAK=1 pretends, for the tests.
static func detect_weak() -> bool:
	if OS.get_environment("NF_WEAK") == "1": return true
	if detect_strong(): return false
	var m := OS.get_model_name()
	return m.begins_with("iPhone") or m.begins_with("iPad")

## «فائق» on a strong device: everything below turns up a notch.
func low() -> bool: return preset == 3
func view_dist() -> float: return float(VIEW.get(preset, 150.0)) * (0.85 if weak else 1.0)

func maxed() -> bool:
	return strong and eff_effects() >= 2 and eff_shadows() >= 2

func eff_shadows() -> int: return mini(shadows, rt_shadows)
func eff_effects() -> int: return 0 if _transit else mini(effects, rt_effects)

## How far the governor may take the resolution down (FSR rebuilds it): further on an older phone.
## Metal (the iPhone, the iPad, a Mac): MetalFX is there. Off everywhere else, and in the tests.
func on_metal() -> bool:
	return OS.get_name() in ["iOS", "macOS"] and RenderingServer.get_current_rendering_driver_name() == "metal"

## «MetalFX» picked in the edge smoothing, on Forward+ on Metal (elsewhere it falls back to «عالي»).
func metalfx_temporal() -> bool:
	return aa == 3 and on_metal() and engine_hd()

func scale_floor() -> float:
	return 0.7 if weak else 0.85

func target_fps() -> int:
	var f: int = FPS_OPTS[fps_idx]
	if f == 0:
		var r := DisplayServer.screen_get_refresh_rate()
		f = int(clampf(roundf(r), 30.0, 120.0)) if (r > 1.0 and r < 1000.0) else 60
	if rt_fps_cap > 0: f = mini(f, rt_fps_cap)
	return f

func render_scale() -> float:
	return clampf(SCALE_OPTS[scale_idx] * dyn_scale, scale_floor(), 1.0)

## true: this launch runs the high-end renderer.
func engine_hd() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

## What the next launch will use (the override file is only read at start-up).
func engine_next_hd() -> bool:
	return not FileAccess.file_exists(ENGINE_PATH)

func set_engine(hd: bool) -> void:
	if hd:
		if FileAccess.file_exists(ENGINE_PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(ENGINE_PATH))
	else:
		var c := ConfigFile.new()
		c.set_value("rendering", "renderer/rendering_method", "mobile")
		c.set_value("rendering", "renderer/rendering_method.mobile", "mobile")
		# the Mobile renderer keeps its MSAA 2x: the project's level has to say so, or every
		# pipeline is compiled again the first time it is drawn (a hitch on everything new on screen)
		c.set_value("rendering", "anti_aliasing/quality/msaa_3d", 1)
		c.save(ENGINE_PATH)
	_transit = weak and engine_hd() and not engine_next_hd()

func apply() -> void:
	var vp := get_viewport()
	Engine.max_fps = target_fps()
	# Godot compiles its pipelines ahead for the MSAA level in the project settings only: a different
	# level on the viewport compiles every one of them again the first time it is drawn — the hitches
	# at the start of every round. So the viewport always uses the project's level:
	#  * Forward+ (project: none): MSAA multiplied the cost of the depth pass, the occlusion and the
	#    fog at the iPhone's full resolution, and its resolve under the screen-space effects is a
	#    suspect for the black dots. Its edges are smoothed after the frame instead (SMAA / FXAA).
	#  * Mobile (the override file sets 2x): MSAA 2x, resolved in the GPU's tile memory, nearly free.
	var proj_msaa := int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0))
	if engine_hd():
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = (Viewport.SCREEN_SPACE_AA_SMAA if (maxed() or aa >= 2) else Viewport.SCREEN_SPACE_AA_FXAA) if aa > 0 else Viewport.SCREEN_SPACE_AA_DISABLED
		if metalfx_temporal(): vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED # MetalFX smooths the edges itself
	else:
		vp.msaa_3d = Viewport.MSAA_2X if (aa > 0 and proj_msaa >= 1) else Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	# no MSAA on the 2D layer: it made the whole screen a multisampled target that the 3D picture was
	# copied into and resolved every frame (at the iPhone's full resolution). The HUD draws its own
	# smooth edges (anti-aliased lines and rings), the font is anti-aliased already.
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.scaling_3d_scale = render_scale()
	# below 100% the picture is rebuilt with AMD FSR (sharper than plain stretching), so the governor
	# can take the resolution down a little without it looking soft
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale() < 0.999 else Viewport.SCALING_3D_MODE_BILINEAR
	# on the iPhone, Apple's own MetalFX: «MetalFX» in the edge smoothing is the temporal one (it
	# rebuilds every frame from the last ones: smoother edges and finer detail than FSR at the same
	# render size, and no SMAA pass); otherwise the spatial one replaces FSR below 100%
	if metalfx_temporal(): vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
	elif on_metal() and engine_hd() and render_scale() < 0.999: vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_SPATIAL
	vp.fsr_sharpness = 0.35
	var s := eff_shadows()
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096][s], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][s])
	if engine_hd(): # how fine the high-end effects are drawn (NFLook decides which ones are on)
		var fx := eff_effects()
		vp.positional_shadow_atlas_size = [1024, 2048, 4096][s]
		RenderingServer.positional_soft_shadow_filter_set_quality(
			[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][s])
		if maxed(): # high-quality occlusion at half resolution: full resolution cost a lot and showed little
			RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH, true, 0.5, 2, 50.0, 300.0)
		else:
			RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM if fx >= 2 else RenderingServer.ENV_SSAO_QUALITY_LOW,
				true, 0.5, 2, 50.0, 300.0)
		RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_LOW, true, 0.5, 2, 50.0, 300.0)
		RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_16)
		RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_15_FRAMES)
		RenderingServer.environment_set_volumetric_fog_volume_size(64 if fx >= 2 else 48, 64 if fx >= 2 else 40) # 96³ was 3.4x the work
		RenderingServer.environment_set_volumetric_fog_filter_active(true)
		RenderingServer.sub_surface_scattering_set_quality(RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_MEDIUM if maxed() else RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_LOW)
	# sharper ground at a glancing angle, and models keep their full detail further away
	vp.anisotropic_filtering_level = Viewport.ANISOTROPY_8X if maxed() else (Viewport.ANISOTROPY_2X if weak else Viewport.ANISOTROPY_4X)
	# older phones swap to the simpler level of detail of every model sooner (the GPU's vertex work)
	vp.mesh_lod_threshold = 0.7 if maxed() else (3.0 if low() else (2.0 if weak else 1.0))
	# «منخفض»: one mip level softer textures (half the memory traffic), on top of what FSR asks
	vp.texture_mipmap_bias = 0.6 if low() else 0.0
	changed.emit()

func _reset_runtime() -> void:
	dyn_scale = 1.0; rt_shadows = 2; rt_effects = 2; rt_fps_cap = 0
	_bad = 0; _good = 0; _warm = 4.0

func _load() -> void:
	var c := ConfigFile.new()
	var ok := c.load(PATH) == OK
	if strong and (not ok or c.get_value("g", "tier", 0) is bool or int(c.get_value("g", "tier", 0)) < TIER):
		# once per phone (and again whenever TIER goes up): a strong device starts on «فائق» at a
		# locked, smooth 60 — the owner asked for 60 every time on ultra, not 120 with dips.
		# MSAA 2x rather than 4x: Forward+ resolves it in a separate pass on Metal, and on a
		# 460 ppi screen 2x already hides the edges. After that the player's own choice stands.
		# (TIER 3, after "the game lags" on the 18 Pro Max: 90% of the screen's 2868 x 1320 rebuilt
		# with FSR — the same picture at 460 ppi for a fifth fewer pixels — and SMAA in place of MSAA.)
		# (TIER 4, the graphics pass: MetalFX temporal on the iPhone in place of SMAA + FSR.)
		preset = 2
		shadows = PRESETS[2][0]; aa = 3; scale_idx = 1; effects = PRESETS[2][3]
		fps_idx = 2
		if ok:
			brightness = clampf(float(c.get_value("g", "bright", brightness)), 0.6, 1.6)
			_load_controls(c)
		_save()
		return
	if weak and (not ok or int(c.get_value("g", "weak", 0)) < WEAK_TIER):
		# once per older phone: the Mobile renderer from the next launch (Forward+ draws its extra
		# effects with passes these GPUs pay dearly for), moon shadows, MSAA 2x (nearly free on the
		# Mobile renderer, resolved in the GPU's tile memory), 85% resolution rebuilt with FSR, a
		# locked 60 (the 13 Pro and 14 Pro would otherwise try for 120 and heat up). The governor
		# takes it from there; the player's own choices stand afterwards.
		preset = 1
		shadows = 1; aa = 1; scale_idx = 0; effects = 1
		fps_idx = 2
		if ok:
			brightness = clampf(float(c.get_value("g", "bright", brightness)), 0.6, 1.6)
			_load_controls(c)
		_save()
		set_engine(false)
		return
	if not ok: return
	fps_idx = clampi(c.get_value("g", "fps", fps_idx), 0, 3)
	preset = clampi(c.get_value("g", "preset", preset), 0, 3)
	perf_hud = bool(c.get_value("g", "perf", perf_hud))
	shadows = clampi(c.get_value("g", "shadows", shadows), 0, 2)
	aa = clampi(c.get_value("g", "aa", aa), 0, 3)
	scale_idx = clampi(c.get_value("g", "scale", scale_idx), 0, 2)
	effects = clampi(c.get_value("g", "effects", effects), 0, 2)
	brightness = clampf(float(c.get_value("g", "bright", brightness)), 0.6, 1.6)
	_load_controls(c)

func _load_controls(c: ConfigFile) -> void:
	look_sens = clampf(float(c.get_value("g", "sens", look_sens)), 0.4, 2.0)
	fov_add = clampf(float(c.get_value("g", "fov", fov_add)), -10.0, 15.0)
	btn_scale = clampf(float(c.get_value("g", "btn", btn_scale)), 0.8, 1.3)
	btn_alpha = clampf(float(c.get_value("g", "btn_a", btn_alpha)), 0.35, 1.0)

func _save() -> void:
	var c := ConfigFile.new()
	c.set_value("g", "fps", fps_idx); c.set_value("g", "preset", preset); c.set_value("g", "perf", perf_hud)
	c.set_value("g", "shadows", shadows); c.set_value("g", "aa", aa)
	c.set_value("g", "scale", scale_idx); c.set_value("g", "effects", effects)
	c.set_value("g", "bright", brightness)
	c.set_value("g", "sens", look_sens); c.set_value("g", "fov", fov_add)
	c.set_value("g", "btn", btn_scale); c.set_value("g", "btn_a", btn_alpha)
	c.set_value("g", "tier", TIER if strong else 0)
	c.set_value("g", "weak", WEAK_TIER if weak else 0)
	c.save(PATH)

# ---------- adaptive governor ----------
## The governor looks away for a while: the map is building itself, or a round has just started
## (main calls it). Loading hitches used to count as "too slow" and take settings away for good.
func quiet(seconds: float) -> void:
	_quiet = maxf(_quiet, seconds)
	_t = 0.0; _frames = 0; _bad = 0

func _process(dt: float) -> void:
	_t += dt; _frames += 1
	if _warm > 0.0 or _quiet > 0.0:
		_warm = maxf(_warm - dt, 0.0); _quiet = maxf(_quiet - dt, 0.0); _t = 0.0; _frames = 0
		return
	if _t < 2.0: return
	var avg := _t / float(_frames)
	_t = 0.0; _frames = 0
	last_avg_ms = avg * 1000.0
	_hud.text = _perf_text(avg)
	if menu_open: return
	var target := 1.0 / float(target_fps())
	if avg > target * 1.18: _bad += 1; _good = 0
	elif avg < target * 1.06: _good += 1; _bad = 0
	else: _bad = 0; _good = 0
	if _bad >= 2:
		_bad = 0; _step_down()
	# no stepping back up by itself: going up, finding it too slow, coming down again every twenty
	# seconds was a hitch each way (shadow atlases, fog buffers and the render size are rebuilt).
	# What it gave away comes back when the player changes a setting.

## «مراقب الأداء»: what the frame costs, from Godot's own counters (the same as the editor's monitors).
func _perf_text(avg: float) -> String:
	if not perf_hud: # the one line it always showed
		return "%d FPS  %.1f ms  target %d  scale %d%%" % [roundi(1.0 / avg), avg * 1000.0, target_fps(), roundi(render_scale() * 100.0)]
	return "%d FPS  %.1f ms (target %d)  res %d%%\ndraw %d  objects %d  tris %dk\nmemory %d MB  video %d MB  CPU %.1f ms" % [
		roundi(1.0 / avg), avg * 1000.0, target_fps(), roundi(render_scale() * 100.0),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
		roundi(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
		roundi(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0]

func _step_down() -> void:
	# a smooth 60 with everything on beats a stuttering 120: the frame rate gives way first, then the
	# heaviest effects (occlusion, volumetric fog), then the render size in ONE step (every change of
	# it rebuilds the render buffers: a hitch each), then the shadows
	if target_fps() > 60: rt_fps_cap = 60
	elif eff_effects() > 0: rt_effects = eff_effects() - 1
	elif render_scale() > scale_floor() + 0.001:
		dyn_scale = scale_floor() / SCALE_OPTS[scale_idx]
	elif eff_shadows() > 0: rt_shadows = eff_shadows() - 1
	# an older phone that still cannot hold 60 with all of that given away: a steady 30 is smoother
	# than 40-something that jumps around. It stays for the session (60 again would only drop back).
	elif weak and target_fps() > 30: rt_fps_cap = 30
	else: return
	apply()

## Back up, in the reverse order: the effects and shadows it gave away come back too (they used
## to stay off for the rest of the session), then the resolution.
var _ups := 0
func _step_up() -> void:
	_ups += 1
	if rt_effects < effects and _ups >= 2: rt_effects += 1; _ups = 0
	elif rt_shadows < shadows and _ups >= 2: rt_shadows += 1; _ups = 0
	elif dyn_scale < 1.0 and rt_effects >= effects and rt_shadows >= shadows: dyn_scale = minf(dyn_scale + 0.05, 1.0)
	else: return
	apply()

# ---------- UI ----------
func in_ui(pos: Vector2) -> bool:
	if menu_open: return true
	var w := get_viewport().get_visible_rect().size.x
	return pos.x > w - 150.0 and pos.y < 80.0

func _build_ui() -> void:
	var layer := CanvasLayer.new(); layer.layer = 20; add_child(layer)
	var theme := NFUI.theme()
	_hud = Label.new(); _hud.position = Vector2(16, 10); _hud.theme = theme
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.modulate = Color(1, 1, 1, 0.7); _hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	var gear := Button.new(); gear.text = "Settings"
	gear.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	gear.offset_left = -140; gear.offset_right = -12; gear.offset_top = 12; gear.offset_bottom = 64
	gear.pressed.connect(_toggle)
	NFUI.dress(gear, "gear")
	layer.add_child(gear)
	_panel = PanelContainer.new(); _panel.theme = theme; _panel.visible = false
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(520, 0)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH; _panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	layer.add_child(_panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(m)
	var sc := ScrollContainer.new() # the panel now holds sound + graphics: let it scroll on a short screen
	sc.custom_minimum_size = Vector2(480, 430)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	m.add_child(sc)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var title := Label.new(); title.text = "Settings"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(title)
	_vol_row(v, "master", "Sound")
	var det := Button.new(); det.text = "Details"; det.custom_minimum_size.y = 44
	det.pressed.connect(func() -> void:
		_vol_split = not _vol_split
		det.text = "Hide details" if _vol_split else "Details"
		for r in _vol_rows: r.visible = _vol_split)
	NFUI.dress(det, "gear"); v.add_child(det)
	var hap := Button.new()
	hap.custom_minimum_size.y = 46
	hap.text = "Vibration: %s" % ("On" if Aud.haptics else "Off")
	hap.pressed.connect(func() -> void:
		Aud.set_haptics(not Aud.haptics)
		hap.text = "Vibration: %s" % ("On" if Aud.haptics else "Off")
		if Aud.haptics: NFHaptics.pulse("tick"))
	NFUI.dress(hap, "heart")
	v.add_child(hap)
	_vol_rows.append(_vol_row(v, "music", "Music volume"))
	_vol_rows.append(_vol_row(v, "sfx", "Game volume"))
	_vol_rows.append(_vol_row(v, "dance", "Dance music"))
	for r in _vol_rows: r.visible = false
	_bright_row(v)
	var ct := Label.new(); ct.text = "Controls"; ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ct.modulate = Color(1, 0.75, 0.7); v.add_child(ct)
	_num_row(v, "_sens", "Camera sensitivity", 40.0, 200.0, 5.0, "%d%%", func() -> float: return look_sens * 100.0,
		func(x: float) -> void: look_sens = x / 100.0)
	_num_row(v, "_fov", "Field of view", -10.0, 15.0, 1.0, "%+d°", func() -> float: return fov_add,
		func(x: float) -> void: fov_add = x)
	_num_row(v, "_btn", "Button size", 80.0, 130.0, 5.0, "%d%%", func() -> float: return btn_scale * 100.0,
		func(x: float) -> void: btn_scale = x / 100.0)
	_num_row(v, "_btn_a", "Button opacity", 35.0, 100.0, 5.0, "%d%%", func() -> float: return btn_alpha * 100.0,
		func(x: float) -> void: btn_alpha = x / 100.0)
	_row(v, "fps", "Frame rate", ["Auto", "30", "60", "120"])
	_row(v, "preset", "Graphics", ["Low", "Medium", "High", "Ultra"], [3, 0, 1, 2])
	_row(v, "shadows", "Shadows", ["Low", "Medium", "High"])
	_row(v, "aa", "Anti-aliasing", ["Off", "Normal", "High", "MetalFX (iPhone)"])
	_row(v, "scale", "Render resolution", ["85%", "90%", "100%"])
	_row(v, "effects", "Effects quality", ["Low", "Medium", "High"])
	_row(v, "engine", "Renderer", ["High (best look)", "Light (faster)"])
	_row(v, "perf", "Performance monitor", ["Off", "On"])
	_engine_note = Label.new()
	_engine_note.add_theme_font_size_override("font_size", 15)
	_engine_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_engine_note.modulate = Color(1, 0.8, 0.5)
	v.add_child(_engine_note)
	var ctl := Button.new(); ctl.text = "Button layout (position and size)"; ctl.custom_minimum_size.y = 52
	ctl.pressed.connect(_edit_controls); NFUI.dress(ctl, "gear"); v.add_child(ctl)
	var close := Button.new(); close.text = "Close"; close.custom_minimum_size.y = 52
	close.pressed.connect(_toggle); NFUI.dress(close, "exit"); v.add_child(close)
	_refresh()

## The touch-layout editor, reachable without leaving the round (the game ignores input while it is up).
func _edit_controls() -> void:
	if _editor and is_instance_valid(_editor): return
	_editor = NFControlsEdit.new()
	_panel.visible = false
	_editor.closed.connect(func() -> void:
		_editor = null
		_panel.visible = menu_open)
	add_child(_editor)

## A 0-100% volume row. The bus follows the slider while it is being dragged.
func _vol_row(parent: Control, key: String, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	parent.add_child(h)
	var l := Label.new(); l.text = label; l.custom_minimum_size.x = 150; h.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0; s.max_value = 100.0; s.step = 1.0
	s.custom_minimum_size = Vector2(220, 44)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.set_value_no_signal(roundf(Aud.get_vol(key) * 100.0))
	h.add_child(s)
	var pct := Label.new()
	pct.text = "%d%%" % roundi(Aud.get_vol(key) * 100.0)
	pct.custom_minimum_size.x = 64
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(pct)
	s.value_changed.connect(func(val: float) -> void:
		Aud.set_vol(key, val / 100.0)
		pct.text = "%d%%" % roundi(val))
	_vol[key] = [s, pct]
	return h

## «السطوع»: 60-160%, live on the map (or the camp) behind the panel while it is dragged.
func _bright_row(parent: Control) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	parent.add_child(h)
	var l := Label.new(); l.text = "Brightness"; l.custom_minimum_size.x = 150; h.add_child(l)
	var s := HSlider.new()
	s.min_value = 60.0; s.max_value = 160.0; s.step = 5.0
	s.custom_minimum_size = Vector2(220, 44)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.set_value_no_signal(roundf(brightness * 100.0))
	h.add_child(s)
	var pct := Label.new()
	pct.text = "%d%%" % roundi(brightness * 100.0)
	pct.custom_minimum_size.x = 64
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(pct)
	s.value_changed.connect(func(val: float) -> void:
		brightness = val / 100.0
		pct.text = "%d%%" % roundi(val)
		look_changed.emit())
	s.drag_ended.connect(func(_c: bool) -> void: _save())
	_vol["_bright"] = [s, pct]

## A slider row for the controls: live while dragging (look_changed tells the round), saved on release.
var _nums := {}
func _num_row(parent: Control, key: String, label: String, lo: float, hi: float, step: float, fmt: String, get_v: Callable, set_v: Callable) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	parent.add_child(h)
	var l := Label.new(); l.text = label; l.custom_minimum_size.x = 150; h.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo; sl.max_value = hi; sl.step = step
	sl.custom_minimum_size = Vector2(220, 44)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sl)
	var pct := Label.new()
	pct.custom_minimum_size.x = 64
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(pct)
	sl.value_changed.connect(func(val: float) -> void:
		set_v.call(val)
		pct.text = fmt % roundi(val)
		look_changed.emit())
	sl.drag_ended.connect(func(_c: bool) -> void: _save())
	_nums[key] = [sl, pct, get_v, fmt]

func _row(parent: Control, key: String, label: String, items: Array, ids: Array = []) -> void:
	var h := HBoxContainer.new(); parent.add_child(h)
	var l := Label.new(); l.text = label; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(l)
	var o := OptionButton.new(); o.custom_minimum_size = Vector2(200, 48)
	for k in items.size(): o.add_item(items[k], int(ids[k]) if k < ids.size() else k)
	o.item_selected.connect(func(i: int): _on_select(o.get_item_id(i), key))
	h.add_child(o)
	_opts[key] = o

func _refresh() -> void:
	for key in _nums:
		var val: float = (_nums[key][2] as Callable).call()
		_nums[key][0].set_value_no_signal(val)
		_nums[key][1].text = str(_nums[key][3]) % roundi(val)
	for key in _vol:
		var val: float = brightness if key == "_bright" else Aud.get_vol(key)
		_vol[key][0].set_value_no_signal(roundf(val * 100.0))
		_vol[key][1].text = "%d%%" % roundi(val * 100.0)
	_opts["fps"].select(fps_idx); _opts["preset"].select(_opts["preset"].get_item_index(preset)); _opts["shadows"].select(shadows)
	_opts["perf"].select(1 if perf_hud else 0)
	_opts["aa"].select(aa); _opts["scale"].select(scale_idx); _opts["effects"].select(effects)
	_opts["engine"].select(0 if engine_next_hd() else 1)
	_engine_note.visible = engine_next_hd() != engine_hd()
	_engine_note.text = "Close and reopen the game to change the renderer"

func _on_select(i: int, key: String) -> void:
	match key:
		"fps": fps_idx = i
		"preset":
			preset = i
			var p: Array = PRESETS[i]
			shadows = p[0]; aa = p[1]; scale_idx = p[2]; effects = p[3]
		"shadows": shadows = i
		"aa": aa = i
		"scale": scale_idx = i
		"effects": effects = i
		"engine": set_engine(i == 0)
		"perf": perf_hud = i == 1
	_reset_runtime()
	_refresh(); _save(); apply()

## Open the settings panel from a menu button (the gear is always on screen too).
func open_settings() -> void:
	if not menu_open: _toggle()

func _toggle() -> void:
	menu_open = not menu_open
	_panel.visible = menu_open
	if menu_open: _refresh()
	if not menu_open: _warm = 2.0
