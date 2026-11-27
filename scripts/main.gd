extends Node3D
## NightFall game scene: menu -> world -> local player + other players, objectives, HUD, audio.
## Rules run on the server online (server/rules.js) and locally in trial mode (scripts/rules.gd).

const WALK := {"killer": 4.6, "survivor": 1.73}   # survivors +8%
const RUN := {"killer": 4.6, "survivor": 4.32}    # still under the killer's 4.6
const CROUCH_SPEED := 1.1
const CARRY_SPEED := 3.6
# ground speed each animation was authored for; playback is scaled to it so feet don't slide
const NATURAL := {"walk": 1.3, "run": 3.7, "sprint": 5.2, "crouchwalk": 1.0, "injured": 1.6, "climb": 1.0, "crawl": 0.7}
const ACCEL := 20.0
const DECEL := 28.0
var rain_audio: AudioStreamPlayer
var _text_hint := "" # a line under the middle of the screen for the killer (the power box cooling)
var ravens: NFRavens
var catdog: NFCatDog # the cat at the first generator, and the dog (scripts/catdog.gd)
const FeastScript := preload("res://scripts/feast.gd")
const Crumbs := preload("res://scripts/crumbs.gd")
const GorillaScript := preload("res://scripts/gorilla.gd")
var feast: Node3D   # «الوحش» eating whoever is on his hook a second time (scripts/feast.gd)
const KissScript := preload("res://scripts/kiss.gd")
var kiss: Node3D    # «Kiss»: shake the phone three times, then face a teammate (scripts/kiss.gd)
var kiss_mode := 0.0 # seconds the Kiss button stays on offer after the three shakes
const KISS_OFFER := 20.0
const SHAKE_G := 1.35 # a shake: the phone's own acceleration (gravity taken out) above this many g
var shake_n := 0
var shake_last := -9.0
var shake_hi := false
var kiss_cd := {}   # survivor -> when (msec) their last kiss happened, from the events
var gorilla: Node3D # the owner's gorilla and the horse, after the cat and the dog (scripts/gorilla.gd)
const SFX := ["knife1", "knife2", "knife3", "knife4", "gunshot", "scream_beast", "crow", "raven", "gate", "heart", "breath", "steps_out", "steps_in", "gen_run", "chase", "ambient", "doom", "rope", "male_pain", "scream1", "scream2", "oof1", "oof2", "oof3",
	# the owner's sound pack (November): see «The owner's sound pack» in CLAUDE.md
	"heart_fast", "breath_hurt", "breath_hide", "whimper", "steps_killer", "steps_beast", "steps_hurt", "power_hum", "terror",
	"moon_rumble", "amb_night", "amb_sea", "amb_garage", "amb_storm", "amb_cold", "swing1", "swing2", "gen_done", "gen_boom",
	"trap_snap", "vault", "fall1", "fall2", "fall3", "groan1", "groan2", "groan3", "scare",
	"struggle_m1", "struggle_m2", "struggle_m3", "struggle_f1", "struggle_f2", "struggle_f3", "breath_m", "breath_f", "breath_hurt_m",
	"heal_other", "heal_self", "torch_on", "torch_off", "steps_approach",
	"impact", "final", "warn", "hook_sting", "chime", "healed", "locker", "thunder"]
const SFX_LOOPS := ["heart", "heart_fast", "breath", "breath_hurt", "breath_hide", "whimper", "steps_out", "steps_in", "steps_killer",
	"steps_beast", "steps_hurt", "gen_run", "chase", "ambient", "power_hum", "terror", "moon_rumble", "amb_night", "amb_sea",
	"amb_garage", "amb_storm", "amb_cold", "breath_m", "breath_f", "breath_hurt_m", "heal_other", "heal_self", "steps_approach"]
const NIMBLE_VAULT := 0.65 # «Light Feet»: her vaults take 65% of the time
const MALE := ["survivor2", "survivor3", "killer2"] # the other characters (the killer «البركة القرمزية» too) use the female voice clips
const TERROR_RADIUS := 24.0 # survivors start to feel the killer inside this distance
const CHASE_NEAR := 16.0     # the chase music plays when she is this close on foot, even unseen (never while she drives)
## quick signals: what the three buttons say, their icon, and how they look on a team-mate's screen
const SIG_TEXT := ["Come here", "Killer here", "I'm repairing", "Door", "Trap"]  # the last two are local only: a door somebody heard, a trap that shut
const SIG_ICON := ["pin", "skull", "wrench", "door", "trap"]
## the one random event of the round
const EVENT_NAME := ["", "Thick fog!", "Alarm!"]
const SIG_LIFE := 7.0
const STATE_COL := {"ok": Color(0.55, 1.0, 0.6), "hurt": Color(1.0, 0.68, 0.25), "down": Color(1.0, 0.42, 0.28),
	"carried": Color(1.0, 0.42, 0.28), "hooked": Color(1.0, 0.25, 0.25), "dead": Color(0.5, 0.5, 0.52), "escaped": Color(0.45, 0.8, 1.0)}
const STATE_ICON := {"hurt": "drop", "down": "down", "carried": "carry", "hooked": "hook", "dead": "skull", "escaped": "out"}
const STATE_WORD := {"ok": "Healthy", "hurt": "Hurt", "down": "Down", "carried": "Carried", "hooked": "Hooked", "dead": "Dead", "escaped": "Escaped"}

var menu: GameMenu
var world: NightWorld
var rules: Rules
var loading: NFLoading        # the map-building screen, freed once the world is up
var sigs: Array = []          # live quick signals: {n, k, pos, t}
var theme := "normal"         # normal / snow / halloween
var scare_t := 0.0            # seconds left of the killer close-up
var scare_cam: Camera3D
var breaths := {}             # name -> breath-vapour particles (snow theme)
var dev_dot: Button           # hidden developer tools (only built when this phone has them)
var dev_panel: PanelContainer
var esp_nodes := {}           # name -> {meshes, mat, mark, label}
var cam_kick := Vector2.ZERO  # pitch / roll impulse left to play out
var cam_kick_v := Vector2.ZERO
var cam_extra := 0.0          # how far the camera has pulled back (hooked)
var hook_cam := 0.0           # seconds left of the camera swinging round to the hook
var slowmo := 0.0             # seconds of the escape slow-motion left
var heart_beat := 0.0         # drives the heartbeat buzz
var hit_anim := {}            # name -> seconds left of the one-shot flinch
var ev_shown := -1            # which event warning has been shown
var ev_on := false            # the event is running right now
var adhan_player: AudioStreamPlayer3D
var adhan_state := 0
var sig_open := false         # the three-message panel is showing
var sig_close := 0.0          # closes itself if untouched
var body: CharacterBody3D
var cshape: CollisionShape3D
var rig: CharacterRig
var cam_pivot: Node3D
var arm: SpringArm3D
var ui: Control
var minimap: Control
var hud_layer: CanvasLayer
var grade: ColorRect          # the full-screen grade (vignette + grain)
var results: NFResults # the end-of-round stage, built when the round is over
var started := false
var cfg := {}
var offline := false
var my_name := ""
var my_role := "killer"
var remotes := {} # name -> {node, rig, pos, yaw, anim, role, step}
var sounds := {}
var gen_audio: Array = [] # one engine-sound player per generator
var chars := {} # player name -> character id (picks the voice)
var oof_t := {} # name -> seconds until the next pained "oof" while limping
var amb: AudioStreamPlayer
var chase_music: AudioStreamPlayer
var heart: AudioStreamPlayer
var breath: AudioStreamPlayer
var my_steps: AudioStreamPlayer
var my_bleed: Node3D
var chase_hold := 0.0
var los_t := 0.0
var marks: Array = []
var mark_i := 0

var yaw := 0.0
var pitch := -0.25
var stick_id := -1
var stick_origin := Vector2.ZERO
var stick_vec := Vector2.ZERO
var look_id := -1
var sprint := false
var crouch := false
var attack_t := 0.0
var attack_cd := 0.0
var hit_sent := false
var boost_t := 0.0
var send_t := 0.0
var step_t := 0.0
var mark_t := 0.0

var ctx := {} # button id -> what it would do right now
var hold := {} # running hold action: {btn, kind, touch, t, need, i, n}
var vault := {}
var skill := {}
var next_skill := 5.0
var boom_t := {}
var flash := ""
var flash_t := 0.0
var my_state := "ok"
var last_state := "ok"
var last_locker := -1
var was_powered := false
var doom_music: AudioStreamPlayer
var main_cam: Camera3D
var impact_t := -1.0 # seconds since the moon hit (-1: it has not)
var danger := 0.0 # survivors: how close the killer is (0..1)
var noise := 0.0 # killer: loudest nearby survivor (0..1)
var noise_dir := 0.0
var flash_light: SpotLight3D
var light_on := false
var battery := 100.0 # percent; a full charge lasts about two and a half minutes
var last_hatch := -1
var xp_saved := false
var lobby_scene: Node3D
var spectating := "" # who I am watching after escaping or dying
var big_map := false
var match_time := 0.0
var car: NFCar                # the killer's Land Cruiser (world.drive_car), the same on every phone
var driving := false          # I am the killer and I am at the wheel
var car_look := 0.0           # seconds since I last dragged the camera while driving
var ram_cd := {}              # survivor -> seconds before the car can hit them again
var car_told := false         # the "your car is here" line has been shown
var pop := {}             # button id -> seconds left of its press dip
# the event feed (top right): who went down, got hooked, was saved, got out; generators; the gates
const FEED_LIFE := 6.0
var feed := []            # newest first: {"t": text, "i": icon, "c": colour, "life": seconds}
var feed_hp := {}         # name -> last state seen (the feed reports the changes)
var feed_gens := -1
var feed_pw := false
# where the last hit came from (a red arc on the ring toward it), and the gate arrow once they open
var hit_t := 0.0
var hit_from := Vector3.ZERO
var car_leaving := 0.0     # seconds until he is out (the door opens first)
var car_remote := false   # the killer on another phone is at the wheel (to open the door when that changes)
var pass_cd := 0.0        # the pass-by sound waits this long before it can play again
var car_inside := true        # driving from the seat (true) or from the chase camera behind
var escape_banner := 0.0
# the road chase: past a gate, one shared escape car to the last gate 600 m on
var bot: NFBot             # trial mode: the computer killer (scripts/bot.gd), null otherwise
# the last one standing goes down: a slow-motion shot circling them (FIN_TIME of game time at FIN_SCALE)
const FIN_TIME := 1.0
const FIN_SCALE := 0.3
var fin_t := 0.0
var fin_who := ""
var fin_cam: Camera3D
var fin_ang := 0.0
var fin_done := false
var bot_baked := false
var esc_i := -1            # the escape car I am in (Rules.car_of), -1 none
var esc_seen := []         # per road: the last state seen, so every phone starts / stops its car once
var esc_vis := true        # my own body shows in the car (all six seats are drawn)
var esc_arrived := false   # the "arrive" input has gone out for the car I drive
var esc_ram_cd := 0.0      # the killer's car: seconds before it can catch another escape car
var esc_warn := 0.0        # in an escape car: the "she is right behind you" buzz waits this long
var esc_nitro := {}        # road -> true once its driver has fired the nitro (one per run)
var esc_popped := {}       # road -> the spikes have been reported
# the killer's tools: traps on the map, a strip of spikes across an escape road
var trap_cd := 0.0
var gun_cd := 0.0          # a beat between two shots of the stun gun
# «وضع القنّاص»: lying on the tower's roof with the rifle
var sniping := false
var scope := 0              # NFSniper.ZOOMS: 0 none, 1 x4, 2 x8
var snipe_cd := 0.0
var snipe_kick := 0.0
var my_rifle: Node3D        # the rifle in my hands, first person
var stair_ph := 0.0         # the step bob up the stairs
var my_gun: NFGun          # the pistol in my hand («وضع السلاح»)
var gun_aim := 0.0         # seconds the gun stays raised after the button
var gun_pending := -1.0    # the shot leaves once the arms are up
const GUN_POSES := ["idle", "walk", "run", "sprint", "injured", "crouchwalk"] # the arms are free in these
var heli: NFHeli             # the rescue helicopter (comes for the last survivor)
var heli_p := 0.0            # how far up the ladder the climber is, smoothed between snapshots
var heli_st_seen := 0
var gate_count_last := -1.0 # the gate countdown as last seen (-1: not counting)
var beast_try := 0.0       # the developer tools' «the Beast eats me» try-out (trial mode): >0 while on
var beast_hold := 0.0      # seconds the head has hung at the end of it
var beast_back := {}       # what to put back afterwards: where I stood, my hooks, the killer's own setting
var vanished := false      # the developer tools' «Vanish»: hidden on every other phone (st flag v)
var trap_nodes := []       # one node per trap slot (Rules.TRAPS)
var spike_nodes := []      # one strip per road
var snap_sent := 0.0       # my own phone: a trap I stepped in has been reported
var sense_t := 0.0         # «عين الليل»: the pulse of the arrow toward her

func _ready() -> void:
	lobby_scene = NFLobby.new() # the campfire start screen (scripts/lobby.gd)
	add_child(lobby_scene)
	menu = GameMenu.new()
	menu.lobby = lobby_scene
	add_child(menu)
	menu.start_game.connect(_start)
	Net.message.connect(_on_net)
	if not Net.replay.is_empty(): # "play again" in trial mode: same settings, fresh layout
		var again: Dictionary = Net.replay
		Net.replay = {}
		_start.call_deferred(again)

func results_shown() -> bool:
	return results != null and is_instance_valid(results) and results.visible

func _start(c: Dictionary) -> void:
	Crumbs.listen()
	Crumbs.mark("round start: %s %s" % [str(c.get("map", "")), str(c.get("theme", ""))])
	if started: return
	cfg = c
	offline = c.get("offline", false)
	my_name = str(c.me)
	menu.visible = false
	menu.lobby = null
	if lobby_scene:
		lobby_scene.queue_free()
		lobby_scene = null
	theme = str(c.get("theme", "normal"))
	loading = NFLoading.new() # covers the screen while the map builds itself over the next frames
	loading.setup(str(c.map), theme)
	add_child(loading)
	world = NightWorld.new()
	world.sniper = bool(c.get("sniper", false)) and str(c.map) == "kuwait" # «وضع القنّاص»
	world.configure(str(c.map), int(c.get("seed", randi() % 1000000) if not offline else randi() % 1000000), theme)
	add_child(world)
	world.build() # staged: terrain + buildings + objectives first, the rest over the next frames
	Gfx.quiet(30.0) # the governor waits until the map is built and the round has settled
	rules = Rules.new()
	rules.gun = bool(c.get("gun", false)) # «وضع السلاح»: the host's choice, sent with start
	rules.sniper = world.sniper
	rules.setup(world.gen_points.size(), world.gate_points.size(), world.pallet_points.size(), world.hatch_points.size(),
		c.players, int(c.get("seed", 1)) if not offline else randi() % 1000000, world.door_points.size())
	rules.has_grid = world.has_power_box() # Kuwait City; every map in Halloween and «بين العصر والمغرب»
	rules.heli_ok = world.heli_spot != Vector3.INF # the rescue helicopter for the last survivor
	rules.set_grid_mode(1 if theme == "halloween" else (2 if theme == "sunset" else 0))
	for p in c.players: chars[str(p.name)] = str(p.char)
	Net.last_char = str(chars.get(my_name, Net.last_char)) # the one who stands at the fire next time
	Net.save()
	for p in c.players:
		if str(p.name) == my_name:
			my_role = str(p.role)
			_build_player(str(p.char), world.spawn_point(my_role, int(p.slot)))
	_build_audio()
	for p in c.players:
		if str(p.name) != my_name: _add_remote(p)
	for p in c.players:
		if offline and p.get("bot", false) and remotes.has(str(p.name)): # the computer killer
			bot = NFBot.new()
			add_child(bot)
			bot.setup(self, str(p.name), remotes[str(p.name)].node.position)
	_build_marks()
	_build_ui()
	if world.sniper:
		if my_role == "survivor": body.collision_mask |= NightWorld.SN_LAYER # the barrier at the stairs stops survivors only
		body.collision_mask |= NightWorld.SN_EDGE # nobody walks off the roof's edge
		_flash.call_deferred("Sniper mode — climb the stairs and take the rifle from the roof" if my_role == "killer" else "Sniper mode — one gate, by the towers. Watch the roof!")
	if theme == "snow": # cold enough to see everyone's breath
		if my_role == "survivor": breaths[my_name] = _make_breath(rig)
		for n in remotes: breaths[n] = _make_breath(remotes[n].rig)
	if not offline:
		var xz := func(v: Vector3) -> Array: return [snappedf(v.x, 0.1), snappedf(v.z, 0.1)]
		var lay := {"g": [], "h": [], "p": [], "x": [], "d": []}
		for v in world.hatch_points: lay.x.append(xz.call(v))
		for v in world.gen_points: lay.g.append(xz.call(v))
		for v in world.hook_points: lay.h.append(xz.call(v))
		for v in world.pallet_points: lay.p.append(xz.call(v[0]))
		for v in world.door_points: lay.d.append(xz.call(v[0]))
		lay.c = [] # where each gate's escape car waits, and the last gate at the end of its road
		lay.e = []
		for i in world.gate_points.size():
			lay.c.append(xz.call(world.esc_start(i)))
			lay.e.append(xz.call(world.road_end(i)))
		if world.power_box != Vector3.INF: lay.b = xz.call(world.power_box) # the power box (decided with the layout)
		if world.heli_spot != Vector3.INF: lay.k = xz.call(world.heli_spot) # the rescue helicopter's ladder
		Net.send({"t": "layout", "d": lay})
	started = true

func _build_player(char_name: String, at: Vector3) -> void:
	body = CharacterBody3D.new()
	cshape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35; cap.height = 1.8
	cshape.shape = cap; cshape.position.y = 0.9
	body.add_child(cshape)
	rig = CharacterRig.new()
	body.add_child(rig)
	rig.setup(char_name, CharacterRig.ANIMS, hd_chars(), false) # the 100k close-up model on strong devices, no skin pass
	body.position = at
	body.floor_snap_length = 0.5
	body.floor_max_angle = deg_to_rad(50.0)
	add_child(body)
	world.follow = body
	my_bleed = _make_bleed()
	body.add_child(my_bleed)
	cam_pivot = Node3D.new()
	cam_pivot.position.y = 1.6
	body.add_child(cam_pivot)
	arm = SpringArm3D.new() # keeps the camera from going through trees and walls
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	arm.shape = probe
	arm.margin = 0.15
	arm.add_excluded_object(body.get_rid())
	cam_pivot.add_child(arm)
	var cam := Camera3D.new()
	cam.far = 400.0
	arm.add_child(cam)
	main_cam = cam
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.93, 0.82)
	cam_pivot.add_child(lamp)
	if my_role == "killer": # first person
		arm.spring_length = 0.0
		arm.position.y = 0.2
		cam.fov = 80.0 + Gfx.fov_add
		cam.near = 0.1
		rig.visible = false
		lamp.position = Vector3(0, 0.3, -0.5)
		lamp.light_energy = 0.8; lamp.omni_range = 11.0
	else: # third person
		arm.spring_length = 3.4
		arm.position.y = 0.3
		cam.fov = 70.0 + Gfx.fov_add
		lamp.position = Vector3(0.6, 0.9, 1.6)
		lamp.light_energy = 0.45; lamp.omni_range = 7.0 # just enough to read your own character; the flashlight does the rest
		flash_light = _make_flashlight()
		flash_light.position = Vector3(0, 1.45, 0)
		NFLook.shadows_on(flash_light) # my own torch throws real shadows (the others' do not: too costly)
		body.add_child(flash_light)

func _make_flashlight() -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = Color(1.0, 0.95, 0.85)
	l.light_energy = 7.0
	l.spot_range = 24.0
	l.spot_angle = 26.0
	l.spot_attenuation = 0.7
	l.visible = false
	return l

## Strong devices on «فائق» play the round with MY character's close-up model (100k triangles,
## the 4096 colour map): it is the one the camera sits behind. Everyone else wears the 30k one:
## seven close-up models were 700k skinned triangles drawn again in every shadow cascade, and the
## round lagged on the 18 Pro Max too.
func hd_chars() -> bool:
	return Gfx.strong and Gfx.effects >= 2 and Gfx.shadows >= 2

func _add_remote(p: Dictionary) -> void:
	var node := Node3D.new()
	var r := CharacterRig.new()
	node.add_child(r)
	r.setup(str(p.char), CharacterRig.ANIMS, false, false) # the round model: only my own character gets the close-up one
	node.position = world.spawn_point(str(p.role), int(p.slot))
	if p.get("dummy", false): # trial-mode practice target
		var gp: Vector3 = world.gen_points[0]
		node.position = gp + Vector3(1.8, 0.0, 1.2) if my_role == "killer" else body.position + Vector3(2.5, 0, 0)
		rules.s[str(p.name)].hp = "ok" if my_role == "killer" else "hurt"
	var bleed := _make_bleed()
	node.add_child(bleed)
	var tag := Label3D.new()
	tag.text = str(p.name)
	tag.font = Net.font
	tag.font_size = 48
	tag.pixel_size = 0.004
	tag.position.y = 2.25
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(1, 0.4, 0.4) if str(p.role) == "killer" else Color(0.75, 0.9, 1)
	tag.visible = str(p.role) == my_role # no name tags across teams
	node.add_child(tag)
	var glow := OmniLight3D.new() # faint light so other players are not pitch black
	glow.position = Vector3(0, 2.0, 0)
	glow.light_energy = 0.5; glow.omni_range = 3.5
	if str(p.role) == "killer": glow.light_color = Color(1, 0.25, 0.2)
	node.add_child(glow)
	var torch: SpotLight3D = null
	if str(p.role) == "survivor": # other survivors' flashlights are real lights: the killer can spot them
		torch = _make_flashlight()
		torch.position = Vector3(0, 1.45, 0.2)
		torch.rotation.y = PI
		r.add_child(torch)
	var steps := AudioStreamPlayer3D.new()
	steps.bus = Aud.SFX
	steps.stream = sounds.steps_out
	steps.unit_size = 4.0
	steps.max_distance = 32.0
	node.add_child(steps)
	add_child(node)
	remotes[str(p.name)] = {"node": node, "rig": r, "pos": node.position, "yaw": 0.0, "anim": "idle", "role": str(p.role), "step": 0.0, "steps": steps, "torch": torch, "lit": false, "bleed": bleed, "v": false, "spd": 0.0, "g": 0, "gp": 0.0, "gun": null}

# ---------------- audio ----------------
func _loop_player(stream_name: String, db: float, autoplay := false, bus := Aud.SFX) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.bus = bus
	a.stream = sounds[stream_name]
	a.volume_db = db
	add_child(a)
	if autoplay: a.play()
	return a

func _build_audio() -> void:
	for n in SFX: # OGG where there is one (it loops without a gap), else the MP3
		var path := "res://assets/sfx/%s.ogg" % n
		if not ResourceLoader.exists(path): path = "res://assets/sfx/%s.mp3" % n
		if ResourceLoader.exists(path): sounds[n] = load(path)
	for n in SFX_LOOPS:
		if sounds.get(n) != null: sounds[n].set("loop", true)
	_build_beds()
	amb = _loop_player("ambient", -13.0, true, Aud.MUSIC)
	if world.theme == "rain" and ResourceLoader.exists("res://assets/sfx/rain.ogg"): # «مطر»: the owner's rain, looped
		var rs: AudioStream = load("res://assets/sfx/rain.ogg")
		if rs is AudioStreamOggVorbis: (rs as AudioStreamOggVorbis).loop = true
		rain_audio = AudioStreamPlayer.new()
		rain_audio.bus = Aud.MUSIC
		rain_audio.stream = rs
		rain_audio.volume_db = -17.0 if world.map_id == "garage" else -7.0 # muffled under the car park's slab
		add_child(rain_audio)
		rain_audio.play()
	chase_music = _loop_player("chase", -60.0, false, Aud.MUSIC)
	doom_music = AudioStreamPlayer.new()
	doom_music.bus = Aud.MUSIC
	doom_music.stream = sounds.doom
	doom_music.volume_db = -2.0
	add_child(doom_music)
	heart = _loop_player("heart", -60.0)
	breath = _loop_player("breath", -60.0)
	my_steps = _loop_player("steps_out", -60.0)
	for gp in world.gen_points:
		var a := AudioStreamPlayer3D.new()
		a.bus = Aud.SFX
		a.stream = sounds.gen_run
		a.position = gp + Vector3(0, 1, 0)
		a.unit_size = 5.0
		# the killer only hears a generator from close by (8 m); survivors hear it from far
		a.max_distance = 8.0 if my_role == "killer" else 45.0
		add_child(a)
		gen_audio.append(a)

## The developer tools' try-out (trial mode only, the rules are on this phone): I am put on the nearest
## hook as if for the second time with «الوحش» as the killer, the 30 s meal plays on me (scripts/feast.gd),
## the head hangs there for 5 s, and then I am back where I stood, whole, as I was. Nothing counts.
func _beast_try_start() -> void:
	if not offline or my_role != "survivor" or feast == null or beast_try > 0.0: return
	if not rules.free_now(my_name):
		_flash("Only while you are on your feet")
		return
	var best := -1
	var bd := INF
	var n_hooks: int = world.road_hook0 if world.road_hook0 > 0 else world.hook_points.size()
	for i in n_hooks:
		var d := body.global_position.distance_to(world.hook_points[i])
		var taken := false
		for o in rules.s:
			if rules.s[o].hp == "hooked" and int(rules.s[o].hook_i) == i: taken = true
		if d < bd and not taken:
			bd = d
			best = i
	if best < 0: return
	var p: Dictionary = rules.s[my_name]
	beast_back = {"pos": body.global_position, "hooks": int(p.hooks), "hp": str(p.hp), "beast": rules.beast}
	rules.beast = true
	p.hp = "hooked"
	p.hooks = 2
	p.hook_i = best
	p.t = float(Rules.HOOK_TIME[1])
	beast_try = 1.0
	beast_hold = 0.0
	_flash("Trying it out: «الوحش» eats you — you come back after")

func _beast_try_step(dt: float) -> void:
	if beast_try <= 0.0: return
	var p: Dictionary = rules.s[my_name]
	if rules.over or (p.hp != "hooked" and not feast.held.has(my_name)):
		_beast_try_end()
		return
	if float(p.t) < 0.3: # the meal is over: keep the head on the hook a moment instead of dying
		p.t = 0.3
		feast.held[my_name] = true
		beast_hold += dt
		if beast_hold > 5.0: _beast_try_end()

func _beast_try_end() -> void:
	beast_try = 0.0
	feast.held.erase(my_name)
	var p: Dictionary = rules.s[my_name]
	p.hp = str(beast_back.get("hp", "ok")) if not rules.over else p.hp
	p.hooks = int(beast_back.get("hooks", 0))
	p.hook_i = -1
	p.t = 0.0
	rules.beast = bool(beast_back.get("beast", false))
	if beast_back.has("pos"): body.global_position = beast_back.pos
	_flash("You're back")

## Being eaten (or what is left) on «الوحش»'s hook: main keeps them hanging there.
func _kept(n: String) -> bool:
	return feast != null and feast.keeps(n)

func _hook_at(n: String) -> int:
	var i: int = feast.hook_of(n) if _kept(n) else -1
	if i < 0 and rules.s.has(n): i = int(rules.s[n].hook_i)
	return clampi(i, 0, world.hook_points.size() - 1)

func _node_of(n: String) -> Variant:
	if n == my_name: return body
	var r = remotes.get(n)
	return r.node if r != null else null

func _kissing(n: String) -> bool:
	return kiss != null and kiss.busy(n)

## Three quick shakes of the phone: the Kiss button is on offer for a while (survivors, in a round).
func _shake_watch(dt: float) -> void:
	kiss_mode = maxf(kiss_mode - dt, 0.0)
	if my_role != "survivor" or not rules.free_now(my_name): return
	var g := Input.get_gravity()
	var unit := g.length() if g.length() > 0.5 else 9.81
	var a := Input.get_accelerometer() - g
	var hi := a.length() / unit > SHAKE_G
	var now := Time.get_ticks_msec() / 1000.0
	if hi and not shake_hi and now - shake_last > 0.16: # one peak of the shake
		if now - shake_last > 1.3: shake_n = 0
		shake_n += 1
		shake_last = now
		if shake_n >= 3:
			shake_n = 0
			_kiss_ready()
	shake_hi = hi

func _kiss_ready() -> void:
	kiss_mode = KISS_OFFER
	NFHaptics.pulse("tick")
	_flash("Kiss is ready — go up to a teammate")

## A teammate close enough to kiss: on their feet, not in a kiss, neither of us kissed lately.
func _kiss_target(pos: Vector3) -> String:
	if kiss_mode <= 0.0 or _kissing(my_name) or Time.get_ticks_msec() - int(kiss_cd.get(my_name, -999999)) < int(Rules.KISS_CD * 1000.0): return ""
	var best := ""
	var bd := 2.2
	for n in rules.s:
		if n == my_name or not rules.free_now(n) or _kissing(n): continue
		if Time.get_ticks_msec() - int(kiss_cd.get(n, -999999)) < int(Rules.KISS_CD * 1000.0): continue
		var d := pos.distance_to(_pos_of(n))
		if d < bd and absf(pos.y - _pos_of(n).y) < 1.0:
			bd = d
			best = n
	return best

func _rig_of(n: String) -> Variant:
	if n == my_name: return rig
	var r = remotes.get(n)
	return r.rig if r != null else null

## One bite of «الوحش»'s meal (scripts/feast.gd): the crunch, their cry (not on the last), the camera
## and the phone for whoever is being eaten, a shake for anyone close.
func _feast_bite(n: String, at: Vector3, stage: int, last: bool) -> void:
	_sfx("knife%d" % (1 + randi() % 4), at, 0.0, randf_range(0.62, 0.74)) # under his eating sound (scripts/feast.gd)
	if stage < 4 and not last: _voice_hit(n)
	if n == my_name:
		_shake(0.55)
		NFHaptics.pulse("hit")
	elif body.position.distance_to(at) < 12.0:
		_shake(0.18)
	if last: _feed("%s was eaten" % n, "skull", Color(0.9, 0.25, 0.2))

## A hit: the victim cries out in their own voice (3D for everyone else, plain for the victim).
func _voice_hit(n: String) -> void:
	var clip := "male_pain" if chars.get(n, "survivor1") in MALE else ("scream1" if randf() < 0.5 else "scream2")
	_sfx(clip, null if n == my_name else _pos_of(n) + Vector3(0, 1.5, 0), 0.0 if n == my_name else 5.0)

## Snow theme: a small puff of vapour in front of a character's mouth.
func _make_breath(parent: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.05
	m.direction = Vector3(0, 0.25, 1)
	m.spread = 22.0
	m.gravity = Vector3(0, 0.25, 0)
	m.initial_velocity_min = 0.25; m.initial_velocity_max = 0.6
	m.scale_min = 0.5; m.scale_max = 1.2
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(0.85, 0.92, 1.0, 0.0), Color(0.88, 0.94, 1.0, 0.33), Color(0.9, 0.95, 1.0, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.26, 0.26)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = NFUI.soft_dot()
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = mat
	p.draw_pass_1 = q
	p.amount = 6
	p.lifetime = 1.7
	p.explosiveness = 0.55
	p.position = Vector3(0, 1.62, 0.12)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p

## The killer lifts you: her face fills the screen for a moment (scripts/main.gd `scare_t`).
func _start_scare() -> void:
	if rules.killer == "" or not remotes.has(rules.killer): return
	scare_t = 0.62
	_sfx("scare", null, 0.0)
	if scare_cam == null:
		scare_cam = Camera3D.new()
		scare_cam.fov = 48.0
		scare_cam.near = 0.05
		add_child(scare_cam)
	_aim_scare()
	scare_cam.current = true

func _aim_scare() -> void:
	if scare_cam == null: return
	var head := _pos_of(rules.killer) + Vector3(0, 1.74, 0) # her face while she lifts (the old killer's sat at 1.62)
	var fwd := Basis(Vector3.UP, _yaw_of(rules.killer)) * Vector3(0, 0, 1)
	var shake := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * 0.012
	scare_cam.global_position = head + fwd * 0.52 + Vector3(0, 0.05, 0) + shake
	scare_cam.look_at(head + Vector3(0, 0.02, 0), Vector3.UP)
	scare_cam.rotation.z = sin(scare_t * 28.0) * 0.05

func _end_scare() -> void:
	scare_t = 0.0
	if main_cam and results == null: main_cam.current = true # the results stage owns the camera once it is up

## Blood for a hooked survivor: drops falling from the body and a pool that spreads under it.
func _make_bleed() -> Node3D:
	var root := Node3D.new()
	var p := GPUParticles3D.new()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.12
	m.gravity = Vector3(0, -7.0, 0)
	m.initial_velocity_min = 0.0; m.initial_velocity_max = 0.25
	m.spread = 180.0
	p.process_material = m
	var drop := _blood_model("res://assets/props/blood_drop.glb")
	if drop: # the owner's droplet, falling point up
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.3, 0.008, 0.012)
		dm.roughness = 0.05
		dm.metallic_specular = 0.8
		drop.surface_set_material(0, dm)
		m.scale_min = 0.018; m.scale_max = 0.03
		p.draw_pass_1 = drop
	else:
		var q := QuadMesh.new()
		q.size = Vector2(0.045, 0.07)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.42, 0.0, 0.0)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		q.material = mat
		p.draw_pass_1 = q
	p.amount = 16
	p.lifetime = 0.75
	p.position = Vector3(0, 2.0, 0.05)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	var pool := MeshInstance3D.new()
	var pmesh := _blood_model("res://assets/props/blood_pool.glb")
	if pmesh: # the owner's puddle, darkened to blood and wet
		var src := pmesh.surface_get_material(0) as StandardMaterial3D
		var pm2 := StandardMaterial3D.new()
		if src:
			pm2.albedo_texture = src.albedo_texture
			pm2.normal_enabled = src.normal_enabled
			pm2.normal_texture = src.normal_texture
		pm2.albedo_color = Color(0.42, 0.05, 0.06)
		pm2.roughness = 0.05
		pm2.metallic_specular = 0.75
		pmesh.surface_set_material(0, pm2)
		pool.mesh = pmesh
		pool.rotation.y = randf() * TAU
	else:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.5; cyl.bottom_radius = 0.5; cyl.height = 0.01; cyl.radial_segments = 20
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.22, 0.0, 0.0)
		pm.roughness = 0.15
		cyl.material = pm
		pool.mesh = cyl
	pool.position.y = 0.03
	pool.name = "Pool"
	root.add_child(pool)
	root.visible = false
	return root

var _blood_models := {}
func _blood_model(path: String) -> Mesh:
	if not _blood_models.has(path):
		var found: Mesh = null
		if ResourceLoader.exists(path):
			var bps := load(path) as PackedScene
			var root: Node = bps.instantiate() if bps else Node.new()
			var stack: Array = [root]
			while not stack.is_empty() and found == null:
				var nd: Node = stack.pop_back()
				if nd is MeshInstance3D: found = (nd as MeshInstance3D).mesh
				stack.append_array(nd.get_children())
			root.free()
		_blood_models[path] = found
	var m: Mesh = _blood_models[path]
	return m.duplicate() if m else null

func _update_bleed(b: Node3D, hooked: bool, dt: float) -> void:
	if not hooked:
		b.visible = false
		return
	var pool := b.get_node("Pool") as MeshInstance3D
	if not b.visible:
		b.visible = true
		pool.scale = Vector3(0.15, 0.3, 0.15)
	var k := minf(pool.scale.x + dt * 0.035, 1.6) # the pool keeps spreading while they hang
	pool.scale = Vector3(k, 0.3, k)

## Loop the right footstep recording for the ground under `at`; faster/louder when running, silent when still.
func _steps(a: Node, at: Vector3, moving: bool, running: bool, base_db: float, kind := "") -> void:
	if not moving:
		if a.playing: a.stop()
		return
	var surf := world.surface_at(at)
	var want: AudioStream = sounds.steps_in if surf == "indoor" else sounds.steps_out
	if kind != "" and sounds.get("steps_" + kind) != null: want = sounds["steps_" + kind] # her heavy tread, his, a limp
	if a.stream != want:
		a.stream = want
		a.play()
	elif not a.playing: a.play()
	a.pitch_scale = (1.25 if running else 0.9) * (0.82 if surf == "sand" else 1.0) # sand: duller, softer
	if kind == "hurt": a.pitch_scale = 1.15 if running else 1.0 # the recording is a slow, dragging walk
	elif kind != "": a.pitch_scale = 1.35 if running else 1.0
	a.volume_db = base_db + (0.0 if running else -9.0) + (-4.0 if surf == "sand" else 0.0)

func _line_of_sight(to: Vector3) -> bool:
	var from := body.position + Vector3(0, 1.6, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to + Vector3(0, 1.2, 0))
	q.exclude = [body.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## The owner's sound pack: the night around the map (its own bed per map and weather), the sea along
## the shore, the killer's low drone as she closes in, the moon's rumble as it comes down, the power
## box humming while it is on, thunder after the lightning, and my own whimper while I hang.
var beds := {}           # name -> AudioStreamPlayer / AudioStreamPlayer3D
var _bolts_seen := 0
var _thunder_in := -1.0

func _bed(n: String, db: float, at = null) -> Node:
	if sounds.get(n) == null: return null
	var a: Node
	if at == null:
		a = AudioStreamPlayer.new()
	else:
		a = AudioStreamPlayer3D.new()
		a.position = at
		a.unit_size = 5.0
		a.max_distance = 40.0
	a.bus = Aud.SFX
	a.stream = sounds[n]
	a.volume_db = db
	add_child(a)
	beds[n] = a
	return a

func _build_beds() -> void:
	var m := world.map_id
	var amb := "amb_night"
	if m == "garage": amb = "amb_garage"
	elif m == "rubkhali": amb = "amb_storm"
	elif world.theme == "snow": amb = "amb_cold"
	var a := _bed(amb, -16.0)
	if a: a.play()
	if m in ["beach", "kuwait"]:
		var s := _bed("amb_sea", -60.0)
		if s: s.play()
	_bed("terror", -60.0)
	_bed("moon_rumble", -60.0)
	var w := _bed("whimper", -60.0)
	if w and chars.get(my_name, "") in MALE and sounds.get("breath_hurt_m"): w.stream = sounds.breath_hurt_m
	_bed("heal_other", -60.0)
	_bed("heal_self", -60.0)
	if world.has_power_box() and world.power_box != Vector3.INF:
		var h := _bed("power_hum", -6.0, world.power_box + Vector3(0, 1.0, 0))
		if h: h.play()

## Others healing (online the snapshot does not say whom: a survivor working with nothing to repair
## near them is healing). Offline the rules say it outright.
var heal_snd := {} # name -> AudioStreamPlayer3D

func _heal_remotes(dt: float) -> void:
	for n in remotes:
		var r: Dictionary = remotes[n]
		var on := false
		var self_h := false
		if r.role == "survivor" and r.anim == "repair" and (r.node as Node3D).visible:
			var p: Vector3 = (r.node as Node3D).global_position
			on = true
			for g in world.gen_points:
				if _near(p, g, 2.6): on = false
			if world.power_box != Vector3.INF and _near(p, world.power_box, 2.6): on = false
			self_h = on and rules.s.has(n) and rules.s[n].hp == "hurt" and rules.healers.get(n, "") in ["", n]
		if not on and not heal_snd.has(n): continue
		if not heal_snd.has(n):
			var a := AudioStreamPlayer3D.new()
			a.bus = Aud.SFX
			a.unit_size = 4.0
			a.max_distance = 30.0
			a.volume_db = -60.0
			(r.node as Node3D).add_child(a)
			a.position = Vector3(0, 1.0, 0)
			heal_snd[n] = a
		var hs: AudioStreamPlayer3D = heal_snd[n]
		var want: AudioStream = sounds.get("heal_self" if self_h else "heal_other")
		if on and hs.stream != want:
			hs.stream = want
			hs.play()
		if on and not hs.playing: hs.play()
		hs.volume_db = lerpf(hs.volume_db, 0.0 if on else -60.0, 1.0 - exp(-6.0 * dt))
		if not on and hs.playing and hs.volume_db < -54.0: hs.stop()

func _bed_vol(n: String, db: float, dt: float, rate := 3.0) -> void:
	var a = beds.get(n)
	if a == null: return
	var on := db > -55.0
	if on and not a.playing: a.play()
	a.volume_db = lerpf(a.volume_db, db, 1.0 - exp(-rate * dt))
	if not on and a.playing and a.volume_db < -54.0: a.stop()

func _step_beds(dt: float, danger: float) -> void:
	# the sea: loud on the sand, gone a long way inland (the shore runs north on the beach, east in Kuwait City)
	if beds.has("amb_sea"):
		var d := 0.0
		if world.map_id == "beach": d = NightWorld.BEACH_SHORE - body.position.z
		else: d = NightWorld.KW_SHORE - body.position.x
		_bed_vol("amb_sea", lerpf(-12.0, -60.0, clampf(d / 70.0, 0.0, 1.0)), dt, 1.5)
	# her drone under the heartbeat, only when the chase music is not already carrying it
	var chasing: bool = chase_music != null and chase_music.playing and chase_music.volume_db > -30.0
	_bed_vol("terror", lerpf(-30.0, -12.0, danger) if danger > 0.05 and not chasing else -60.0, dt)
	# the moon (or the sun) coming down: a rumble that grows over the last two minutes
	var doom_k := 0.0
	if rules.doom > 0.0 and rules.powered: doom_k = 1.0 - clampf(rules.doom / Rules.DOOM_TIME, 0.0, 1.0)
	_bed_vol("moon_rumble", lerpf(-26.0, -4.0, doom_k) if doom_k > 0.0 and impact_t < 0.0 else -60.0, dt, 1.0)
	# me on the hook
	_bed_vol("whimper", -14.0 if my_state == "hooked" else -60.0, dt)
	# healing: a friend, or myself with the kit
	var healing: bool = hold.get("kind", "") == "heal"
	var self_heal: bool = healing and str(hold.get("n", "")) == my_name
	_bed_vol("heal_self", -8.0 if self_heal else -60.0, dt, 6.0)
	_bed_vol("heal_other", -8.0 if healing and not self_heal else -60.0, dt, 6.0)
	_heal_remotes(dt)
	# the power box hums while it is on
	var hum = beds.get("power_hum")
	if hum: hum.volume_db = lerpf(hum.volume_db, -6.0 if rules.grid else -60.0, 1.0 - exp(-3.0 * dt))
	# thunder: a moment after each flash
	if world.bolts != _bolts_seen:
		_bolts_seen = world.bolts
		_thunder_in = randf_range(0.4, 1.8)
	if _thunder_in >= 0.0:
		_thunder_in -= dt
		if _thunder_in < 0.0: _sfx("thunder", null, randf_range(-6.0, 0.0), randf_range(0.9, 1.05))

func _sfx(n: String, at = null, db := 0.0, pitch_scale := 1.0) -> void:
	var a: Node
	if at == null:
		a = AudioStreamPlayer.new()
	else:
		a = AudioStreamPlayer3D.new()
		a.position = at
		a.unit_size = 6.0
		a.max_distance = 60.0
	a.bus = Aud.SFX
	if sounds.get(n) == null:
		a.free()
		return
	a.stream = sounds[n]
	a.volume_db = db
	a.pitch_scale = pitch_scale
	add_child(a)
	a.finished.connect(a.queue_free)
	a.play()

# scratch marks: glowing traces running survivors leave behind; only the killer sees them
func _build_marks() -> void:
	if my_role != "killer": return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.25, 0.08)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.12)
	q.material = mat
	for i in 60:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		marks.append({"node": mi, "t": 0.0})

func _drop_mark(at: Vector3) -> void:
	var m: Dictionary = marks[mark_i]
	mark_i = (mark_i + 1) % marks.size()
	m.t = 7.0
	m.node.visible = true
	m.node.position = at + Vector3(randf_range(-0.4, 0.4), 0.06, randf_range(-0.4, 0.4))
	m.node.rotation = Vector3(-PI / 2.0, randf() * TAU, 0)
	m.node.scale = Vector3.ONE

# ---------------- networking ----------------
## Sounds that come with another player's animation starting: her swing, a vault over a window.
func _anim_sound(r: Dictionary, na: String, who := "") -> void:
	var at: Vector3 = (r.node as Node3D).global_position + Vector3(0, 1.2, 0)
	if na == "attack" and r.role == "killer": _sfx("swing%d" % randi_range(1, 2), at, 4.0, randf_range(0.95, 1.05))
	elif na == "vault":
		if my_role == "killer" and rules and rules.perk.get(who, "") == "nimble": return # «Light Feet»: she vaults without a sound
		_sfx("vault", at, 2.0)

func _on_net(m: Dictionary) -> void:
	if not started: return
	match str(m.t):
		"st":
			var r = remotes.get(str(m.n))
			if r:
				r.pos = Vector3(m.p[0], m.p[1], m.p[2])
				r.yaw = float(m.p[3])
				var na := str(m.a)
				if na != r.anim and r.node.visible and not bool(r.get("v", false)): _anim_sound(r, na, str(m.n))
				r.anim = na
				var nl := int(m.get("f", 0)) == 1
				if nl != r.lit and r.role == "survivor" and r.node.visible: _sfx("torch_on" if nl else "torch_off", (r.node as Node3D).global_position + Vector3(0, 1.3, 0), -4.0)
				r.lit = nl
				r.v = int(m.get("v", 0)) == 1 # the developer tools' «Vanish» on that phone
				r.g = int(m.get("g", 0)) # the gun: 0 put away, 1 lowered, 2 raised
				r.gp = float(m.get("gp", 0.0)) # where it points, up or down
		"ev": # the server's referee: the round's state (gs) and what happened
			var d = m.get("d")
			if d is Dictionary and str(m.get("n", "?")) == "": # only the server referees
				if str(d.get("k", "")) == "gs": rules.apply(d)
				else: _on_event(d)
		"left":
			var r = remotes.get(str(m.name))
			if r:
				r.node.queue_free()
				remotes.erase(str(m.name))
		"ad": # the developer tools on someone's phone: the billboard plays (or stops) his video
			if world: world.play_ad(bool(m.get("on", true)))
		"sig": # a team-mate's quick message (the server only relays it to their own side)
			var sp = m.get("p")
			if sp is Array and sp.size() == 2:
				_add_sig(str(m.get("n", "?")), int(m.get("k", 0)), Vector3(float(sp[0]), body.position.y, float(sp[1])))
		"room":
			if not offline and (str(m.get("code", "")) == "" or str(m.get("state", "")) == "lobby"):
				_to_menu()

## Show a quick message on screen; `pos` is where the sender was when they sent it.
func _add_sig(from: String, k: int, pos: Vector3) -> void:
	k = clampi(k, 0, SIG_TEXT.size() - 1)
	for sg in sigs: # one live message per player
		if str(sg.n) == from:
			sg.k = k; sg.pos = pos; sg.t = SIG_LIFE
			return
	sigs.append({"n": from, "k": k, "pos": pos, "t": SIG_LIFE})

## Trial mode shows it on my own screen only; online the server passes it to my own side.
func _send_sig(k: int) -> void:
	sig_open = false
	_add_sig(my_name, k, body.position)
	if not offline:
		Net.send({"t": "sig", "k": k, "p": [snappedf(body.position.x, 0.1), snappedf(body.position.z, 0.1)]})

## Send one of my inputs to the referee (the server, or the local rules in trial mode).
func _ev(d: Dictionary) -> void:
	if offline:
		for e in rules.handle(d, my_name): _on_event(e)
	else:
		Net.send({"t": "ev", "d": d})

## «وضع السلاح»: fire the stun gun where the camera looks. It hits her if she is within range, near the
## middle of the screen and nothing solid stands between; this phone decides, the rules keep the count.
func _shoot() -> void:
	if not rules.gun or my_role != "survivor" or gun_cd > 0.0 or not rules.free_now(my_name) or _held() > 0.0: return
	if int(rules.s.get(my_name, {}).get("ammo", 0)) <= 0: return
	gun_cd = 0.6
	var cam := get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z if cam else Vector3(sin(yaw), 0, cos(yaw))
	var from := body.position + Vector3(0, 1.35, 0) + Vector3(fwd.x, 0, fwd.z).normalized() * 0.4
	var hit := false
	var to := from + fwd * Rules.GUN_RANGE
	if rules.killer != "" and (remotes.has(rules.killer) or bot):
		var kp := _pos_of(rules.killer) + Vector3(0, 1.0, 0) # her middle: the aim may sit anywhere from knee to head
		# the aim is the middle of the screen: how far her body is from the camera's own line
		var co: Vector3 = cam.global_position if cam else from
		var dv := kp - co
		var along := dv.dot(fwd)
		var off := (dv - fwd * along).length()
		var dist := from.distance_to(kp)
		if along > 0.5 and dist < Rules.GUN_RANGE and off < 1.1 + along * 0.05:
			var q := PhysicsRayQueryParameters3D.create(from, kp, 1)
			q.exclude = [body.get_rid()]
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				hit = true
				to = kp
	if my_gun and my_gun.visible:
		from = my_gun.muzzle()
		my_gun.shot()
	gun_aim = 1.4
	_beam(from, to, hit, true)
	_shake(0.3) # the kick of it
	NFHaptics.pulse("hit" if hit else "tick")
	_ev({"k": "shoot", "hit": hit})
	if hit: _flash("Got her! Stunned for 3 seconds — run")

## A short bright beam for a shot: blue when it hit, pale when it missed. Gone in a fifth of a second.
## A shot from the pistol, on every phone: the owner's gunshot, a flash at the muzzle that lights
## the shooter up for an instant, the bullet as a short streak of fire flying to where it went,
## a puff of smoke that hangs and rises from the barrel, a brass case thrown out to the right,
## sparks where it struck, and on a hit the stun's blue crackle on her.
func _beam(a: Vector3, b: Vector3, hit: bool, mine := false) -> void:
	_sfx("gunshot", null if mine else a, 0.0 if mine else 4.0, randf_range(0.96, 1.04))
	var dir := (b - a).normalized() if a.distance_to(b) > 0.01 else Vector3.FORWARD
	# the flash: a hot star at the muzzle and a light for 60 ms
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.72, 0.35)
	fl.light_energy = 5.0
	fl.omni_range = 6.0
	fl.shadow_enabled = false
	add_child(fl)
	fl.global_position = a + dir * 0.1
	var ftw := create_tween()
	ftw.tween_property(fl, "light_energy", 0.0, 0.07)
	ftw.tween_callback(fl.queue_free)
	NFDecor.burst(self, a + dir * 0.06, dir, 10, 0.09, 0.22, Vector2(0.5, 2.5), 25.0, Vector3.ZERO,
		Color(1.0, 0.85, 0.45, 1.0), Color(1.0, 0.35, 0.05), true, 0.2)
	# smoke from the barrel: grey, drifting up and spreading
	NFDecor.burst(self, a + dir * 0.08, dir * 0.6 + Vector3.UP * 0.4, 0 + (10 if Gfx.weak else 18), 1.8, 0.32,
		Vector2(0.2, 0.9), 35.0, Vector3(0, 0.35, 0), Color(0.7, 0.7, 0.72, 0.45), Color(0.5, 0.5, 0.52), false, 3.2)
	# the bullet: a short streak of fire that flies there (~200 m/s, so it is seen for a few frames)
	var tr := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, 0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.75, 0.35)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.material = m
	tr.mesh = bm
	tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tr)
	tr.global_position = a + dir * 0.4
	if a.distance_to(b) > 0.01: tr.look_at(b, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
	var t := clampf(a.distance_to(b) / 200.0, 0.03, 0.15)
	var ttw := create_tween()
	ttw.tween_property(tr, "global_position", b, t)
	ttw.tween_callback(func():
		tr.queue_free()
		# sparks where it struck, and the stun's blue on her
		NFDecor.burst(self, b, -dir + Vector3.UP * 0.5, 14, 0.35, 0.08, Vector2(2.0, 5.0), 60.0, Vector3(0, -9.0, 0),
			Color(1.0, 0.8, 0.4, 1.0), Color(1.0, 0.3, 0.05), true, 0.4)
		if hit: NFDecor.burst(self, b, Vector3.UP, 16, 0.5, 0.18, Vector2(0.5, 2.0), 180.0, Vector3.ZERO,
			Color(0.5, 0.85, 1.0, 1.0), Color(0.3, 0.5, 1.0), true, 1.5))
	# the spent case, out to the right and down
	var side := dir.cross(Vector3.UP).normalized()
	var cs := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.006; cm.bottom_radius = 0.006; cm.height = 0.02; cm.radial_segments = 6; cm.rings = 1
	cm.material = _brass()
	cs.mesh = cm
	cs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cs)
	var c0 := a - dir * 0.12 + Vector3.UP * 0.03
	cs.global_position = c0
	var v0 := side * randf_range(1.6, 2.4) + Vector3.UP * randf_range(1.5, 2.2) - dir * 0.3
	var ground := c0.y - 1.3
	var fly := func(k: float) -> void:
		var p := c0 + v0 * k + Vector3(0, -4.9 * k * k, 0)
		p.y = maxf(p.y, ground)
		cs.global_position = p
		cs.rotation = Vector3(k * 31.0, k * 17.0, 0.0)
	var ctw := create_tween()
	ctw.tween_method(fly, 0.0, 0.7, 0.7)
	ctw.tween_interval(2.0)
	ctw.tween_callback(cs.queue_free)

var _brass_m: StandardMaterial3D
func _brass() -> StandardMaterial3D:
	if _brass_m == null:
		_brass_m = StandardMaterial3D.new()
		_brass_m.albedo_color = Color(0.85, 0.65, 0.3)
		_brass_m.metallic = 1.0
		_brass_m.roughness = 0.3
	return _brass_m

## A killer's blow lands (either killer, on foot): the owner's knife slash from where it struck, blood
## spraying off the victim and a splash on the ground. Run down by the car it is only the thud.
func _slash(n: String) -> void:
	var by_car := car != null and (driving or car_remote)
	var at := _pos_of(n) + Vector3(0, 1.15, 0)
	if not by_car:
		_sfx("knife%d" % (1 + randi() % 4), null if n == my_name else at, 0.0 if n == my_name else 5.0, randf_range(0.95, 1.06))
	var from := _pos_of(rules.killer)
	var away := (at - from)
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	# a fine mist on the GPU, then the owner's drops, the wall behind them and the pool (NFBlood)
	NFDecor.burst(self, at, away + Vector3.UP * 0.3, 10 if Gfx.weak else 18, 0.45, 0.05, Vector2(1.0, 2.6), 40.0,
		Vector3(0, -9.0, 0), Color(0.42, 0.015, 0.02, 1.0), Color(0.25, 0.0, 0.01), false, 0.6)
	if blood: blood.splash(at, away, _cam_pos())

## Blood on the ground (scripts/blood.gd): drips from a hurt survivor on every phone, more often the
## faster they go; a smear behind one who is down and crawling. Nothing while fine, hooked (the hook
## has its own), dead, out, in a car or vanished.
var blood: NFBlood

func _blood_trail(n: String, feet: Vector3, kind: int) -> void:
	if blood: blood.bleed(n, feet, kind, _cam_pos())

## «بين العصر والمغرب»: a warning a minute before the sun is gone, and the call when it is.
var _sun_said := 0
func _sunset_calls() -> void:
	var left := world.sun_left()
	if _sun_said == 0 and left <= 60.0 and left > 0.0:
		_sun_said = 1
		_flash("The sun sets in a minute — get your torches ready" if my_role == "survivor" else "The sun sets in a minute")
	elif _sun_said <= 1 and left <= 0.0:
		_sun_said = 2
		if my_role == "survivor": _flash("The sun is down! Turn the lights on at the power box ⚡" if not rules.grid else "The sun is down — the lights are on")
		else: _flash("The sun is down — the dark is yours" if not rules.grid else "The sun is down")
		_feed("The sun is down", "moon", Color(1.0, 0.6, 0.4))

# ---------------- «وضع القنّاص» ----------------
## Her eye: lying down with the rifle it is just over the parapet; up the stairs it rises and dips
## with every step.
func _killer_eye(dt: float, v: float) -> void:
	var eye := 0.55 if sniping else 1.6
	if not sniping and v > 0.4 and world.on_stairs(body.position):
		stair_ph += dt * v / 0.32 * PI # a step every 0.32 m along the flight
		eye += absf(sin(stair_ph)) * 0.07 - 0.03
	cam_pivot.position.y = lerpf(cam_pivot.position.y, eye, 1.0 - exp(-10.0 * dt))
	snipe_cd = maxf(snipe_cd - dt, 0.0)
	snipe_kick = maxf(snipe_kick - dt * 3.0, 0.0)
	if my_rifle:
		my_rifle.visible = sniping and scope == 0
		my_rifle.position = Vector3(0.12, -0.17 - snipe_kick * 0.04, -0.4 + snipe_kick * 0.09)
		my_rifle.rotation = Vector3(snipe_kick * 0.25, PI, 0)

## Take the rifle from its crate: down on her belly, the rifle in her hands, the scope ready.
func _snipe_start() -> void:
	if sniping or my_role != "killer": return
	sniping = true
	scope = 0
	if world.rifle_stand: world.rifle_stand.visible = false
	if my_rifle == null:
		my_rifle = NFSniper.rifle()
		main_cam.add_child(my_rifle)
	_flash("You have the rifle — «Scope» x4 and x8, «Fire». One bullet drops whoever it hits")
	NFHaptics.pulse("hook")

func _snipe_stop() -> void:
	if not sniping: return
	sniping = false
	scope = 0
	main_cam.fov = _base_fov()
	if my_rifle: my_rifle.visible = false
	if world.rifle_stand: world.rifle_stand.visible = true

## The shot: straight down the middle of the screen. Whoever the line passes within 0.42 m of (on
## their feet, nothing in between) is hit; the round's rules drop them.
func _snipe_fire() -> void:
	if snipe_cd > 0.0 or not sniping: return
	snipe_cd = Rules.SNIPE_CD
	snipe_kick = 1.0
	var cam := main_cam
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 600.0, 1) # (the roof's invisible edge does not stop it)
	q.exclude = [body.get_rid()]
	var wh := get_world_3d().direct_space_state.intersect_ray(q)
	var wall_d: float = from.distance_to(wh.position) if not wh.is_empty() else 600.0
	var hit := ""
	var hit_d := wall_d
	for n in remotes:
		var r = remotes[n]
		if r.role != "survivor" or not rules.free_now(n) or not r.node.visible: continue
		var a: Vector3 = (r.node as Node3D).global_position + Vector3(0, 0.15, 0)
		var b: Vector3 = a + Vector3(0, 1.6, 0)
		var t := _ray_seg(from, dir, a, b)
		if t.x < 0.42 and t.y < hit_d:
			hit = n
			hit_d = t.y
	var at := from + dir * hit_d
	_ev({"k": "snipe", "n": hit, "p": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]})
	pitch = clampf(pitch + 0.035 / maxf(float(NFSniper.ZOOMS[scope]), 1.0) * 2.0, -0.9, 0.5) # the kick
	_shake(0.25)
	NFHaptics.pulse("hit")

## The closest a ray (from o along d) comes to the segment a-b: x the distance, y how far along the ray.
static func _ray_seg(o: Vector3, d: Vector3, a: Vector3, b: Vector3) -> Vector2:
	var best := Vector2(INF, INF)
	for k in 9:
		var p := a.lerp(b, float(k) / 8.0)
		var t := maxf((p - o).dot(d), 0.0)
		var dist := (o + d * t).distance_to(p)
		if dist < best.x: best = Vector2(dist, t)
	return best

## Everyone hears it and sees the tracer; the one it dropped gets the blood and the shake.
func _snipe_fx(by: String, p, n: String) -> void:
	var to := Vector3.INF
	if p is Array and (p as Array).size() >= 3: to = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var mine := by == my_name
	var from: Vector3
	if mine: from = main_cam.global_position - main_cam.global_basis.z * 0.95 - main_cam.global_basis.y * 0.12
	else:
		var kp := _pos_of(by)
		var fwd := Basis(Vector3.UP, _yaw_of(by)) * Vector3(0, 0, 1)
		from = kp + Vector3(0, 0.45, 0) + fwd * 1.5
	if n != "": to = _pos_of(n) + Vector3(0, 1.15, 0)
	if to == Vector3.INF: to = from + Vector3(0, 0, -1)
	_beam(from, to, false, mine)
	# the rifle's own crack: lower and much louder than the pistol, heard right across the map
	var a := AudioStreamPlayer.new()
	a.bus = Aud.SFX
	a.stream = sounds.get("gunshot")
	a.pitch_scale = 0.62
	a.volume_db = 4.0 if mine else clampf(2.0 - body.global_position.distance_to(from) * 0.05, -14.0, 2.0)
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)
	if n != "":
		if blood: blood.splash(to, (to - from).normalized(), _cam_pos())
		_feed("The sniper dropped %s" % n, "skull", Color(1.0, 0.35, 0.3))
		if n == my_name:
			_flash("Sniped! You're down — wait for someone to heal you")
			_shake(0.9)
			NFHaptics.pulse("grab")
	elif to.distance_to(body.global_position) < 6.0 and my_role == "survivor":
		_flash("A bullet right by you! The sniper can see you")
		_shake(0.2)

## Where the survivors stand (the cat looks up at the nearest one at its generator).
func _survivor_spots() -> Array:
	var out := []
	if my_role == "survivor": out.append(body.global_position)
	for n in remotes:
		if remotes[n].role == "survivor": out.append((remotes[n].node as Node3D).global_position)
	return out

func _cam_pos() -> Vector3:
	var c := get_viewport().get_camera_3d()
	return c.global_position if c else Vector3.INF

## Hurt and on their feet: one hand pressed to the wound (the left arm, by IK, over the clip), and a
## limp in the step (_lean_rig reads the "hurt" mark). Never while the pistol is out, in a car or a seat.
const WOUND_POSES := ["idle", "walk", "injured", "run", "sprint"]
func _wound_pose(rg: CharacterRig, hurt: bool, gun_out: bool) -> void:
	if rg == null or rg.skeleton == null: return
	rg.set_meta("hurt", hurt)
	var on := hurt and not gun_out and rg.current in WOUND_POSES
	if on:
		var b := Basis(Vector3.UP, rg.global_rotation.y)
		var fwd := b * Vector3(0, 0, 1)
		var left := b * Vector3(1, 0, 0)
		var k := rg.global_transform.basis.get_scale().x
		var s1 := rg.bone_at("mixamorig_Spine1")
		var sh := rg.bone_at("mixamorig_LeftArm")
		var t := s1 + (left * 0.1 + fwd * 0.13 - Vector3.UP * 0.04) * k
		var pole := sh + (left * 0.35 - Vector3.UP * 0.3 - fwd * 0.2) * k
		rg.reach(t, t, pole, pole)
		rg.reach_mod.use = [true, false]
		rg.set_meta("clutch", true)
	elif rg.get_meta("clutch", false):
		rg.reach_clear()
		rg.set_meta("clutch", false)

## The body's weight in the movement, on every character and every phone (from how they really
## move, so other players lean too): into a turn like a runner on a bend, forward when pulling away
## and into a sprint, back on the heels when pulling up. Pivots at the feet, so they stay planted.
## Only while walking, running, sprinting, limping, creeping or standing — never when carried, hung,
## in a seat or vaulting.
const LEAN_POSES := ["idle", "walk", "run", "sprint", "injured", "crouchwalk"]
var _leans := {}

func _lean_rig(rg: Node3D, dt: float, spd: float, anim: String) -> void:
	if rg == null or dt <= 0.0: return
	var id := rg.get_instance_id()
	var st: Dictionary = _leans.get(id, {"yaw": rg.rotation.y, "spd": spd, "roll": 0.0, "pitch": 0.0})
	if not anim in LEAN_POSES:
		_leans[id] = {"yaw": rg.rotation.y, "spd": spd, "roll": 0.0, "pitch": 0.0}
		rg.rotation.x = 0.0; rg.rotation.z = 0.0
		return
	var turn := angle_difference(float(st.yaw), rg.rotation.y) / dt # rad/s
	var acc := (spd - float(st.spd)) / dt # m/s²
	var fast := clampf(spd / 6.0, 0.0, 1.0)
	var want_roll := clampf(-turn * spd * 0.028, -0.2, 0.2) # ~11° at a hard sprinting turn
	var want_pitch := clampf(acc * 0.022, -0.1, 0.13) + (0.07 if anim == "sprint" else 0.03 * fast)
	var k := 1.0 - exp(-9.0 * dt)
	st.roll = lerpf(float(st.roll), want_roll, k)
	st.pitch = lerpf(float(st.pitch), want_pitch, k * 0.8)
	st.yaw = rg.rotation.y
	st.spd = spd
	_leans[id] = st
	rg.rotation.x = float(st.pitch)
	rg.rotation.z = float(st.roll)
	if rg.get_meta("hurt", false): # the limp: a dip and a sway on the bad leg, bent over the wound
		var ph := float(st.get("ph", 0.0)) + dt * clampf(spd, 0.0, 6.0) * 2.4
		st.ph = ph
		var go := clampf(spd / 1.5, 0.0, 1.0)
		rg.rotation.z += sin(ph) * 0.07 * go
		rg.rotation.x += 0.07 + absf(sin(ph)) * 0.05 * go

## «وضع السلاح»: up and down with the camera — a little above the camera's own tilt, since it
## looks down at me from behind.
func _gun_pitch() -> float:
	return clampf(pitch + 0.22, -0.9, 0.9)

## The pistols: mine (out while I can use my arms; raised for a moment by the button, the shot
## leaving once it is up) and every other survivor's, from what their phones say (`g`, `gp`).
func _step_guns(dt: float) -> void:
	if not rules.gun: return
	if my_role == "survivor" and rig:
		if my_gun == null:
			my_gun = NFGun.new()
			add_child(my_gun)
			my_gun.setup(rig)
		var out: bool = my_state in ["ok", "hurt"] and int(rules.s.get(my_name, {}).get("ammo", 0)) > 0 \
			and esc_i < 0 and int(rules.s.get(my_name, {}).get("locker", -1)) < 0 and vault.is_empty() and _held() <= 0.0 and str(rig.current) in GUN_POSES
		gun_aim = maxf(gun_aim - dt, 0.0)
		if gun_pending >= 0.0:
			gun_pending -= dt
			if gun_pending < 0.0: _shoot()
		my_gun.spd = Vector2(body.velocity.x, body.velocity.z).length()
		my_gun.step(out, 1.0 if gun_aim > 0.0 else 0.0, _gun_pitch(), rig.rotation.y, dt)
	for n in remotes:
		var r = remotes[n]
		if r.role != "survivor": continue
		var g = r.get("gun")
		var out2: bool = int(r.get("g", 0)) > 0 and r.node.visible and str(r.rig.current) in GUN_POSES
		if g == null:
			if not out2: continue
			g = NFGun.new()
			add_child(g)
			(g as NFGun).setup(r.rig)
			r.gun = g
		(g as NFGun).spd = float(r.get("spd", 0.0))
		(g as NFGun).step(out2, 1.0 if int(r.g) == 2 else 0.0, float(r.gp), r.rig.rotation.y, dt)

## The owner's map pictures (assets/ui/map: his generators, market, hook, gates and hatch, cut out of
## his sheet). Draws one `px` wide on the map; false if the picture is missing (the drawn icon then).
var _map_tex := {}
func _map_pic(at: Vector2, name: String, px: float, mod := Color.WHITE) -> bool:
	if not _map_tex.has(name):
		var path := "res://assets/ui/map/%s.png" % name
		_map_tex[name] = load(path) if ResourceLoader.exists(path) else null
	var t: Texture2D = _map_tex[name]
	if t == null: return false
	var asp := float(t.get_height()) / float(maxi(t.get_width(), 1))
	var sz := Vector2(px, px * asp) if asp <= 1.0 else Vector2(px / asp, px)
	minimap.draw_texture_rect(t, Rect2(at - sz / 2.0, sz), false, mod)
	return true

## The owner's button look (his picture): a black plate in a silver bevel and a glowing red ring,
## a white icon (his own pictures for the nine he drew, cut out into assets/ui/btn; the drawn icons
## for the rest), and the name on a dark pill with a red edge across the bottom, a red chevron under it.
const BTN_PIC := {"gun": "gun", "item": "bag", "jump": "vault", "crouch": "crouch", "light": "torch",
	"chat": "sig", "heal": "heal", "hand": "hand", "shoe": "sprint"}
var _btn_tex := {}
var _pill: StyleBoxFlat

func _btn_pic(icon: String) -> Texture2D:
	if not BTN_PIC.has(icon): return null
	if not _btn_tex.has(icon):
		var path := "res://assets/ui/btn/%s.png" % BTN_PIC[icon]
		_btn_tex[icon] = load(path) if ResourceLoader.exists(path) else null
	return _btn_tex[icon]

func _draw_btn(c: Vector2, r: float, icon: String, label: String, live: bool, on: bool, pk: float, ba: float) -> void:
	var dim := 1.0 if live else 0.45
	var red := Color(1.0, 0.12, 0.08) if on else Color(0.86, 0.06, 0.05)
	# the glow round the outside: stronger while held, and a ripple when pressed
	for k in 4:
		ui.draw_arc(c, r + 2.0 + k * 3.0, 0, TAU, 48, Color(red, (0.16 if on else 0.09) * (1.0 - k * 0.22) * ba * dim), 3.5, true)
	ui.draw_circle(c, r * (1.0 + 0.35 * sin(pk * PI)), Color(1, 0.3, 0.25, 0.22 * sin(pk * PI) * ba), false, 3.0, true)
	# the plate: black, with a darker well inside
	ui.draw_circle(c, r, Color(0.035, 0.03, 0.035, 0.88 * ba), true, -1.0, true)
	ui.draw_circle(c, r * 0.8, Color(0.015, 0.012, 0.016, 0.9 * ba), true, -1.0, true)
	if on: ui.draw_circle(c, r * 0.8, Color(0.5, 0.02, 0.02, 0.28 * ba), true, -1.0, true)
	for k in 3: # scratches in the well
		var a0 := 0.6 + k * 1.9
		ui.draw_line(c + Vector2.from_angle(a0) * r * 0.25, c + Vector2.from_angle(a0 + 0.5) * r * 0.62, Color(1, 1, 1, 0.035 * ba), 1.0, true)
	# the bevel: silver on top, darker under; then the red ring and a faint inner red line
	ui.draw_arc(c, r - 1.5, PI * 1.05, PI * 1.95, 32, Color(0.82, 0.82, 0.86, 0.85 * ba * dim), 2.2, true)
	ui.draw_arc(c, r - 1.5, PI * 0.05, PI * 0.95, 32, Color(0.3, 0.3, 0.33, 0.8 * ba * dim), 2.2, true)
	ui.draw_arc(c, r * 0.9, 0, TAU, 64, Color(red, 0.95 * ba * dim), 3.0 if on else 2.4, true)
	ui.draw_arc(c, r * 0.9, PI * 1.55, PI * 1.85, 12, Color(1, 0.55, 0.5, 0.7 * ba * dim), 3.0, true) # a highlight on the ring
	ui.draw_arc(c, r * 0.8, 0, TAU, 48, Color(0.9, 0.08, 0.06, 0.3 * ba * dim), 1.0, true)
	# the icon: his picture when there is one, else the drawn one in white
	var icol := Color(1, 1, 1, dim * maxf(ba, 0.6))
	var pic := _btn_pic(icon)
	var ic := c - Vector2(0, r * 0.12)
	if pic:
		var sz := r * 1.08
		ui.draw_texture_rect(pic, Rect2(ic - Vector2(sz, sz) / 2.0, Vector2(sz, sz)), false, icol)
	else:
		NFIcons.draw(ui, icon, ic, r * 0.74, Color(0.93, 0.93, 0.95, icol.a))
	# the name on a dark pill over the bottom of the ring, a red chevron under it
	if _pill == null:
		_pill = StyleBoxFlat.new()
		_pill.bg_color = Color(0.05, 0.04, 0.05, 0.94)
		_pill.set_border_width_all(2)
		_pill.border_color = Color(0.85, 0.08, 0.06)
		_pill.set_corner_radius_all(9)
		_pill.shadow_color = Color(0.9, 0.05, 0.03, 0.35)
		_pill.shadow_size = 5
		_pill.anti_aliasing = true
	var fs := int(clampf(r * 0.3, 13.0, 20.0))
	var tw := Net.font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pw := maxf(tw + 18.0, r * 1.05)
	var ph := fs + 9.0
	var prect := Rect2(c + Vector2(-pw / 2.0, r * 0.62), Vector2(pw, ph))
	_pill.border_color = Color(red, ba * dim)
	_pill.bg_color.a = 0.94 * ba
	ui.draw_style_box(_pill, prect)
	ui.draw_string(Net.font, Vector2(prect.position.x, prect.position.y + ph * 0.5 + fs * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, pw, fs, icol)
	var cv := Vector2(c.x, prect.end.y + 3.0)
	ui.draw_polyline(PackedVector2Array([cv + Vector2(-5, -1), cv + Vector2(0, 4), cv + Vector2(5, -1)]), Color(red, 0.9 * ba * dim), 2.0, true)

func _pos_of(n: String) -> Vector3:
	if n == my_name: return body.position
	var r = remotes.get(n)
	return r.node.position if r else Vector3.ZERO

## A one-shot flinch on whoever was struck. Does nothing at all until assets/anims/hit.glb
## exists, and it never touches movement or input: it is a pose, not a state.
func _hit_anim(who: String) -> void:
	var r: CharacterRig = rig if who == my_name else (remotes[who].rig if remotes.has(who) else null)
	if r == null or not r.has("hit"): return
	r.play("hit", 1.0)
	hit_anim[who] = 0.75

func _on_event(e: Dictionary) -> void:
	if bot: bot.on_event(e)
	match str(e.get("k", "")):
		"boom":
			boom_t[int(e.i)] = 4.0
			if int(e.i) >= 0 and int(e.i) < world.gen_points.size(): _sfx("gen_boom", world.gen_points[int(e.i)] + Vector3(0, 1, 0), 8.0)
			if my_role == "killer": _flash("Someone messed up a generator repair!")
		"hurt":
			if str(e.s) == "down": _final_check(str(e.n))
			_voice_hit(str(e.n))
			_slash(str(e.n))
			_hit_anim(str(e.n)) # a real flinch, if hit.glb has been dropped in
			if str(e.n) == my_name:
				# the rules let go of whatever I was working on (repair, heal, unhook, the power box) the
				# moment I am struck; so must this phone, or it went on «repairing» with nothing counted
				_end_hold()
				hit_t = 1.6 # the red arc points back at her
				hit_from = car.global_position if (car and (driving or car_remote)) else _pos_of(rules.killer)
				boost_t = 3.5 if _perk() == "burst" else 2.0 # «نفس ثاني»
				_shake(0.5 if str(e.s) == "hurt" else 0.85)
				NFHaptics.pulse("hit")
				_flash("You got hit! Run" if str(e.s) == "hurt" else "You're down")
			elif my_role == "killer": _flash("You hit %s" % str(e.n))
		"hooked":
			_sfx("rope", _pos_of(str(e.n)) + Vector3(0, 2, 0), 8.0)
			NFHaptics.pulse("hook")
			if str(e.n) == my_name: _sfx("rope", null, 0.0)
			elif my_role == "survivor" and str(e.s) == "hooked": _sfx("hook_sting", null, -8.0)
			_flash("%s %s" % [str(e.n), "is on the hook" if str(e.s) == "hooked" else "died"])
			if str(e.s) == "hooked": _feed("%s is on the hook" % str(e.n), "hook", Color(1.0, 0.35, 0.3))
		"kiss": # two survivors kiss and hug; the one kissed is healed (scripts/kiss.gd)
			var kis := str(e.n)
			var kd := str(e.get("to", ""))
			kiss_cd[kis] = Time.get_ticks_msec()
			kiss_cd[kd] = Time.get_ticks_msec()
			if kiss: kiss.start(kis, kd)
			if kis == my_name or kd == my_name:
				NFHaptics.pulse("tick")
				_flash("%s kissed you — you feel better" % kis if kd == my_name else "You kissed %s" % kd)
			_feed("%s kissed %s" % [kis, kd], "heart", Color(1.0, 0.45, 0.6))
		"rescued":
			NFHaptics.pulse("tick")
			if str(e.n) == my_name and _perk() == "burst": boost_t = 3.0
			if str(e.by) == str(e.n): _flash("%s got off the hook alone!" % str(e.n))
			elif int(e.get("hands", 1)) > 1: _flash("They saved %s together!" % str(e.n))
			else: _flash("%s saved %s" % [str(e.by), str(e.n)])
			_feed("%s freed themselves" % str(e.n) if str(e.by) == str(e.n) else "%s saved %s" % [str(e.by), str(e.n)], "rescue", Color(0.45, 1.0, 0.55))
		"grabbed":
			_flash("The killer pulled %s out of a locker" % str(e.n))
			_feed("The killer pulled %s out of a locker" % str(e.n), "search", Color(1.0, 0.55, 0.35))
		"empty":
			if my_role == "killer": _flash("The locker is empty")
		"stun":
			if my_role == "killer":
				_flash("They stunned you with the pistol!" if str(e.get("by", "")) == "gun" else "Stunned!")
				if str(e.get("by", "")) == "gun": _shake(0.7)
		"snipe": # «وضع القنّاص»: the rifle fired; n is whoever it dropped
			if str(e.get("n", "")) == my_name: _end_hold()
			_snipe_fx(str(e.get("by", "")), e.get("p", []), str(e.get("n", "")))
		"shot": # the stun gun: a beam from the shooter, to her if it hit
			var who := str(e.n)
			if who != my_name and remotes.has(who):
				var from: Vector3 = remotes[who].node.position + Vector3(0, 1.35, 0)
				var rg = remotes[who].get("gun")
				if rg != null and (rg as NFGun).visible:
					(rg as NFGun).shot()
					from = (rg as NFGun).muzzle()
				var to: Vector3 = (_pos_of(rules.killer) + Vector3(0, 1.3, 0)) if bool(e.hit) else from + Vector3(sin(remotes[who].yaw), 0, cos(remotes[who].yaw)) * 18.0
				_beam(from, to, bool(e.hit))
			if bool(e.hit): _feed("%s stunned the killer with the pistol!" % who, "gun", Color(0.5, 0.9, 1.0))
		"power":
			if my_role == "killer":
				boost_t = 3.5
				_flash("Rush!")
		"board":
			var who := str(e.n)
			if bool(e.get("drv", false)):
				_feed("%s got in the escape car and is driving" % who, "car", Color(0.5, 0.95, 1.0))
				if my_role == "killer": _flash("They're in the escape car! Chase them in yours")
			else: _feed("%s got in with them" % who, "car", Color(0.5, 0.95, 1.0))
		"arrive":
			NFHaptics.pulse("escape")
			_feed("They reached the last gate! (%s)" % ", ".join(PackedStringArray(e.get("who", []))), "out", Color(0.5, 1.0, 0.6))
			if my_role == "killer": _flash("They got away — they reached the last gate")
		"caught":
			var who_c: Array = e.get("who", [])
			if not who_c.is_empty(): _final_check(str(who_c[0]))
			var why := str(e.get("why", ""))
			var mine: bool = my_name in (e.get("who", []) as Array)
			_feed("The escape car's time ran out — they're down" if why == "time" else "The killer rammed the escape car!", "car", Color(1.0, 0.4, 0.3))
			if mine:
				_flash("Time's up! The car stopped and you're down" if why == "time" else "She rammed you! You fell out of the car")
				NFHaptics.pulse("impact")
			elif my_role == "killer": _flash("Caught them! Hang them on the hooks along the road" if why == "ram" else "Their time ran out — they're down on the road, hook them")
		"shield": # «جلد قاسي»
			_feed("%s blocked the hit (Tough Skin)" % str(e.n), "shield", Color(0.6, 0.85, 1.0))
			if str(e.n) == my_name:
				_flash("Tough Skin — the hit did nothing!")
				_shake(0.3)
				boost_t = 1.5
			elif my_role == "killer": _flash("The hit did nothing! Tough skin")
		"grid": # Kuwait City's power box
			var on := bool(e.get("on", true))
			world.set_grid(on)
			if on:
				_feed("The street lights are on" if rules.grid_mode == 2 else "Power's back — the street is lit", "bolt", Color(1.0, 0.9, 0.4))
				if my_role == "killer": _flash("Fix the power!")
			elif bool(e.get("sv", false)): # Halloween: one of the survivors switched it off
				_feed("%s turned the power off — it's dark" % str(e.get("by", "")), "bolt", Color(0.7, 0.75, 1.0))
				if my_role == "killer": _flash("They turned the lights off! Hunt them in the dark")
				elif str(e.get("by", "")) != my_name: _flash("%s turned the lights off — torches only" % str(e.get("by", "")))
			else:
				_feed("The killer cut the power!", "bolt", Color(1.0, 0.45, 0.3))
				if my_role == "survivor": _flash("The power is cut! Torches only — fix the box ⚡")
				_shake(0.15)
		"heli": # the rescue helicopter for the last survivor
			var hn := str(e.get("n", ""))
			match int(e.get("st", 0)):
				1:
					_feed("A rescue helicopter is coming for %s" % hn, "star", Color(0.6, 0.85, 1.0))
					if hn == my_name: _flash("You're the last one — a rescue helicopter is coming! %d seconds" % int(Rules.HELI_COME))
					elif my_role == "killer": _flash("A rescue helicopter is coming for the last one — catch them before they climb!")
				2:
					if hn == my_name:
						_flash("The rescue helicopter is here! Go to the ladder and climb")
						NFHaptics.pulse("hook")
					elif my_role == "killer": _flash("The helicopter dropped the ladder — grab it!")
				3: _feed("%s grabbed the ladder and is climbing!" % hn, "star", Color(0.6, 0.85, 1.0))
				4:
					_feed("%s got away in the helicopter!" % hn, "star", Color(0.45, 1.0, 0.55))
					if hn == my_name:
						_flash("You got away in the helicopter!")
						NFHaptics.pulse("escape")
				5:
					_feed("The rescue helicopter left without %s" % hn, "skull", Color(1.0, 0.5, 0.4))
					if hn == my_name: _flash("You got caught — the helicopter left without you")
		"mend": # «تفتّح» (Bloom)
			_feed("%s bloomed and is healthy again" % str(e.n), "heal", Color(0.75, 0.55, 1.0))
			if str(e.n) == my_name: _flash("Bloom — you're healthy again!")
		"rise": # «جناح الفالكيري»
			_feed("%s got up on her own!" % str(e.n), "star", Color(1.0, 0.55, 0.6))
			if str(e.n) == my_name:
				_flash("Valkyrie Wing — you got up on your own!")
				NFHaptics.pulse("escape")
		"trap":
			if my_role == "killer": _flash("You set a trap")
		"snap":
			var at := _pos_of(str(e.n))
			_sfx("trap_snap", null if str(e.n) == my_name else at + Vector3(0, 0.3, 0), 0.0 if str(e.n) == my_name else 8.0)
			_feed("%s stepped in a trap!" % str(e.n), "trap", Color(1.0, 0.45, 0.3))
			if str(e.n) == my_name:
				_flash("You stepped in a trap!")
				_shake(0.6)
				NFHaptics.pulse("hit")
			elif my_role == "killer":
				_flash("Your trap caught %s!" % str(e.n))
				_add_sig(str(e.n), 4, at) # an arrow to it on her screen
				NFHaptics.pulse("hook")
		"disarm":
			if my_role == "killer": _feed("%s disarmed a trap" % str(e.n), "trap", Color(0.8, 0.8, 0.8))
		"spike":
			if my_role == "killer": _flash("You laid spikes on the road")
		"pop":
			_feed("The spikes burst the escape car's tyres!", "spike", Color(1.0, 0.5, 0.3))
			if esc_i == int(e.i):
				_flash("The tyres burst! The car is slow now")
				_shake(0.8)
				NFHaptics.pulse("impact")
			elif my_role == "killer": _flash("You burst their tyres! Chase them")
		"door":
			world.set_door(int(e.i), bool(e.on))
			var at: Vector3 = world.door_points[int(e.i)][0]
			var far := body.position.distance_to(at)
			if str(e.get("by", "")) != my_name and far > 6.0 and far < 60.0:
				NFHaptics.pulse("tick")
				_add_sig("", 3, at) # you hear it swing from a long way off

## One line on the event feed.
func _feed(t: String, icon: String, col: Color) -> void:
	feed.push_front({"t": t, "i": icon, "c": col, "life": FEED_LIFE})
	if feed.size() > 5: feed.resize(5)

## The feed's other half: what changes in the round's state rather than arriving as an event
## (the same on every phone, offline and online, since both read the same snapshot).
var struggle_snd := 0 # when the next hook-struggle grunt may come
var feed_lk := {}     # name -> locker, for the locker door sound
var feed_gd: Array = [] # each generator done or not, for its sound

func _feed_watch(dt: float) -> void:
	for f in feed: f.life = float(f.life) - dt
	feed = feed.filter(func(f: Dictionary) -> bool: return float(f.life) > 0.0)
	if not started or rules == null: return
	for n in rules.s:
		var hp: String = rules.s[n].hp
		var was: String = feed_hp.get(n, hp)
		if hp != was:
			var who_at = null if n == my_name else _pos_of(n) + Vector3(0, 0.5, 0)
			if hp == "down" and was in ["ok", "hurt"]: _sfx("fall%d" % randi_range(1, 3), who_at, 0.0 if n == my_name else 6.0)
			if (was == "hurt" and hp == "ok") or (was == "down" and hp == "hurt"): _sfx("healed", who_at, -6.0 if n == my_name else 0.0)
			match hp:
				"down": _feed("%s is down" % n, "down", Color(1.0, 0.62, 0.3))
				"escaped": _feed("%s escaped!" % n, "out", Color(0.5, 0.85, 1.0))
				"dead": _feed("%s died" % n, "skull", Color(0.75, 0.75, 0.78))
		feed_hp[n] = hp
	for n in rules.s: # in or out of a locker: its door
		var lk: int = rules.s[n].get("locker", -1)
		if feed_lk.has(n) and int(feed_lk[n]) != lk: _sfx("locker", null if n == my_name else _pos_of(n) + Vector3(0, 1.0, 0), -4.0 if n == my_name else 4.0)
		feed_lk[n] = lk
	for i in rules.gens.size(): # a generator done: it roars into life where it stands, and a chime for everyone
		var gd: bool = rules.gens[i].done
		if i < feed_gd.size() and gd and not feed_gd[i]:
			_sfx("gen_done", world.gen_points[i] + Vector3(0, 1, 0), 8.0)
			_sfx("chime", null, -10.0)
	feed_gd = rules.gens.map(func(g: Dictionary) -> bool: return bool(g.done))
	var dc := rules.done_count()
	if feed_gens >= 0 and dc > feed_gens:
		_feed("Generator done — %d of %d" % [mini(dc, Rules.NEED), Rules.NEED], "wrench", Color(1.0, 0.88, 0.4))
		Crumbs.mark("generators done: %d" % dc)
	feed_gens = dc
	if rules.powered and not feed_pw: _feed("The gates have power — get out!", "door", Color(0.45, 1.0, 0.55))
	feed_pw = rules.powered

func _draw_feed(s: Vector2) -> void:
	var y := 84.0
	for f in feed:
		var life: float = f.life
		var a := clampf(life / 0.6, 0.0, 1.0) # fades out at the end
		var slide := clampf((life - (FEED_LIFE - 0.25)) / 0.25, 0.0, 1.0) * 60.0 # slides in from the edge
		var t: String = f.t
		var fs := 19
		var tw := Net.font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var right := s.x - 14.0 + slide
		var box := Rect2(Vector2(right - tw - 58.0, y), Vector2(tw + 58.0, 34.0))
		var col: Color = f.c
		ui.draw_rect(box, Color(0.03, 0.025, 0.035, 0.72 * a))
		ui.draw_rect(Rect2(Vector2(box.end.x - 4.0, y), Vector2(4.0, 34.0)), Color(col, 0.9 * a)) # a strip of its colour
		NFIcons.draw(ui, str(f.i), Vector2(box.end.x - 24.0, y + 17.0), 22.0, Color(col, a))
		ui.draw_string(Net.font, Vector2(box.position.x + 10.0, y + 24.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.96, 0.92, a))
		y += 40.0

## Where on the ring around the middle of the screen a point in the world lies (0 = straight ahead).
func _ring_dir(p: Vector3) -> Vector2:
	var to: Vector3 = p - body.position
	var a := -PI / 2.0 + wrapf(atan2(to.x, -to.z) + yaw, -PI, PI)
	return Vector2(cos(a), sin(a))

func _draw_hit(mid: Vector2) -> void:
	if hit_t <= 0.0: return
	var d := _ring_dir(hit_from)
	var a := atan2(d.y, d.x)
	var k := clampf(hit_t / 1.6, 0.0, 1.0)
	var rad := minf(mid.y * 0.7, 250.0)
	for w in [[26.0, 0.18], [14.0, 0.45], [6.0, 0.9]]: # a soft red blade with a bright edge
		ui.draw_arc(mid, rad, a - 0.42, a + 0.42, 24, Color(0.95, 0.08, 0.05, float(w[1]) * k), float(w[0]), true)
	var tip := mid + d * (rad + 20.0)
	var sd := Vector2(-d.y, d.x)
	ui.draw_colored_polygon(PackedVector2Array([tip + d * 16.0, tip - sd * 12.0, tip + sd * 12.0]), Color(1, 0.15, 0.1, 0.9 * k))

func _draw_gate(mid: Vector2) -> void:
	if my_role != "survivor" or not rules.powered or my_state not in ["ok", "hurt"] or spectating != "" or world == null or esc_i >= 0: return
	var best := Vector3.INF
	var bd := INF
	var on_road := world.road_at(body.position)
	var word := "Gate %d m"
	if on_road >= 0: # past the gate: the arrow shows the escape car, while it is still waiting
		if on_road >= world.esc_cars.size() or int(rules.roads[on_road].st) > 1: return
		best = (world.esc_cars[on_road] as NFCar).global_position
		bd = Vector2(best.x - body.position.x, best.z - body.position.z).length()
		word = "Car %d m"
		if bd < 4.0: return
	for gi in ([] if on_road >= 0 else range(world.gate_points.size())):
		if rules.sniper and gi != 0: continue # «وضع القنّاص»: the one gate, on the towers' side
		var p: Vector3 = world.gate_points[gi][0]
		var dd := Vector2(p.x - body.position.x, p.z - body.position.z).length()
		if dd < bd:
			bd = dd
			best = p
	if best == Vector3.INF or bd < 7.0: return
	var d := _ring_dir(best)
	if on_road >= 0 and d.y < -0.8: return # straight up the road: it is in plain sight (and the road panel is there)
	var at := mid + d * minf(mid.y * 0.8, 300.0)
	var beat := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	var col := Color(0.45, 1.0, 0.55, beat)
	ui.draw_circle(at, 23.0, Color(0.03, 0.06, 0.04, 0.8), true, -1.0, true)
	ui.draw_arc(at, 23.0, 0, TAU, 40, col, 2.5, true)
	NFIcons.draw(ui, "car" if on_road >= 0 else "out", at, 26.0, col)
	var tip := at + d * 33.0
	var sd := Vector2(-d.y, d.x)
	ui.draw_colored_polygon(PackedVector2Array([tip + d * 13.0, tip - sd * 9.0, tip + sd * 9.0]), col)
	_text(at + Vector2(0, 42.0), word % roundi(bd), 18, col, 200.0)

func _flash(t: String) -> void:
	flash = t
	flash_t = 2.5

func _to_menu() -> void:
	started = false
	get_tree().reload_current_scene.call_deferred()

func _leave() -> void:
	if offline: _to_menu()
	elif str(Net.room.get("host", "")) == my_name: Net.send({"t": "lobby"}) # host ends the round for everyone
	else: Net.send({"t": "leave"})

# ---------------- UI ----------------
## The grade pass: vignette, grain and a red squeeze at the edges when he is near. It sits
## under the HUD on its own layer, ignores touches, and turns itself off on the lowest
## graphics preset (shaders/grade.gdshader).
func _build_grade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1 # behind every piece of interface, over the 3D frame
	add_child(layer)
	grade = ColorRect.new()
	grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grade.gdshader")
	grade.material = mat
	layer.add_child(grade)
	grade.visible = Gfx.eff_effects() >= 1 # the governor can drop it mid-round
	Gfx.changed.connect(func() -> void:
		if grade: grade.visible = Gfx.eff_effects() >= 1)
	Gfx.look_changed.connect(func() -> void: # «مجال الرؤية» dragged in the settings: the camera follows live
		if main_cam and scare_t <= 0.0 and slowmo <= 0.0: main_cam.fov = _base_fov())

func _build_ui() -> void:
	_build_grade()
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_layer = layer
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	ui.draw.connect(_draw_ui)
	minimap = Control.new()
	minimap.position = Vector2(16 + _safe().x, 44)
	minimap.size = Vector2(170, 170)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(minimap)
	minimap.draw.connect(_draw_minimap)
	var leave := Button.new()
	leave.text = "End round" if (not offline and str(Net.room.get("host", "")) == my_name) else "Exit"
	leave.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	leave.offset_left = -312 - _safe().y; leave.offset_right = -152 - _safe().y
	leave.offset_top = 12; leave.offset_bottom = 64
	leave.pressed.connect(_leave)
	NFUI.dress(leave, "exit")
	layer.add_child(leave)
	_build_dev_ui(layer)

# ---------------- hidden developer tools ----------------
## A dim dot in the corner, and the little panel behind it. Built only when this phone unlocked them.
func _build_dev_ui(layer: CanvasLayer) -> void:
	if not Dev.unlocked: return
	var safe := _safe()
	# a real button now (it was a faint dot in the corner nobody could find): «أدوات» on the left edge
	dev_dot = Button.new()
	dev_dot.text = "Developer tools"
	dev_dot.focus_mode = Control.FOCUS_NONE
	dev_dot.theme = NFUI.theme()
	NFUI.dress(dev_dot, "gear")
	dev_dot.add_theme_font_size_override("font_size", 15)
	dev_dot.modulate = Color(1, 0.85, 0.5, 0.9)
	dev_dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	dev_dot.offset_left = 8.0 + safe.x; dev_dot.offset_right = 150.0 + safe.x
	dev_dot.offset_top = -20.0; dev_dot.offset_bottom = 20.0
	dev_dot.pressed.connect(func() -> void: dev_panel.visible = not dev_panel.visible)
	layer.add_child(dev_dot)
	dev_panel = PanelContainer.new()
	dev_panel.theme = NFUI.theme()
	dev_panel.visible = false
	dev_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	dev_panel.offset_left = 8.0 + safe.x; dev_panel.offset_right = 348.0 + safe.x
	dev_panel.offset_top = (-380.0 if (world and world.map_id == "kuwait") else -268.0) - (54.0 if offline else 0.0); dev_panel.offset_bottom = -46.0
	layer.add_child(dev_panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + side, 12)
	dev_panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	var esp_btn := Button.new()
	esp_btn.text = "See players: %s" % ("On" if Dev.esp else "Off")
	esp_btn.custom_minimum_size.y = 46
	esp_btn.pressed.connect(func() -> void:
		Dev.set_esp(not Dev.esp)
		esp_btn.text = "See players: %s" % ("On" if Dev.esp else "Off"))
	NFUI.dress(esp_btn, "next")
	v.add_child(esp_btn)
	var van_btn := Button.new() # the «Vanish» button on the screen, from here too
	van_btn.text = "Vanish button: %s" % ("On" if Dev.vanish_tool else "Off")
	van_btn.custom_minimum_size.y = 46
	van_btn.pressed.connect(func() -> void:
		Dev.set_vanish_tool(not Dev.vanish_tool)
		if not Dev.vanish_tool: vanished = false
		van_btn.text = "Vanish button: %s" % ("On" if Dev.vanish_tool else "Off"))
	NFUI.dress(van_btn, "ghost")
	v.add_child(van_btn)
	if offline: # trial mode only: what «الوحش» does on his hook, on me, and then I come back
		var try_btn := Button.new()
		try_btn.text = "Try: the Beast eats me"
		try_btn.custom_minimum_size.y = 46
		try_btn.pressed.connect(func() -> void:
			dev_panel.visible = false
			_beast_try_start())
		NFUI.dress(try_btn, "skull")
		v.add_child(try_btn)
	if world and world.map_id == "kuwait": # Kuwait City's billboard: his video, only when pressed here, on every phone
		var ad_btn := Button.new()
		ad_btn.text = "Play the ad video"
		ad_btn.custom_minimum_size.y = 46
		ad_btn.pressed.connect(func() -> void:
			if offline: world.play_ad(true)
			else: Net.send({"t": "ad", "on": true})
			_flash("The ad video is playing on the billboard"))
		NFUI.dress(ad_btn, "star")
		v.add_child(ad_btn)
		var ad_stop := Button.new()
		ad_stop.text = "Stop the video (picture comes back)"
		ad_stop.custom_minimum_size.y = 46
		ad_stop.pressed.connect(func() -> void:
			if offline: world.play_ad(false)
			else: Net.send({"t": "ad", "on": false}))
		NFUI.dress(ad_stop, "exit")
		v.add_child(ad_stop)
	var lbl := Label.new()
	lbl.text = "Speed x%.2f" % Dev.speed
	v.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = 1.0; sl.max_value = 2.0; sl.step = 0.05
	sl.custom_minimum_size.y = 40
	sl.set_value_no_signal(Dev.speed)
	sl.value_changed.connect(func(val: float) -> void:
		Dev.set_speed(val)
		lbl.text = "Speed x%.2f" % Dev.speed)
	v.add_child(sl)

## True while a touch belongs to the hidden panel, so the round ignores it.
func _dev_ui(pos: Vector2) -> bool:
	if dev_dot == null: return false
	if dev_dot.get_global_rect().grow(6.0).has_point(pos): return true
	return dev_panel.visible and dev_panel.get_global_rect().has_point(pos)

## See-through outline of another player's own model, plus a mast and a name tag above them.
func _build_esp() -> void:
	for n in remotes:
		if esp_nodes.has(n): continue
		var r = remotes[n]
		var col: Color = Color(1.0, 0.25, 0.2) if r.role == "killer" else Color(0.35, 0.95, 1.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(col, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true          # this is what makes it read through walls
		mat.render_priority = 120
		mat.grow = true
		mat.grow_amount = 0.012
		var meshes: Array = []
		for mi in r.rig.find_children("*", "MeshInstance3D", true, false): meshes.append(mi)
		var mark := Node3D.new()
		var line := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, 44.0, 0.07)
		var lmat := StandardMaterial3D.new()
		lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lmat.albedo_color = Color(col, 0.5)
		lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lmat.no_depth_test = true
		lmat.render_priority = 120
		bm.material = lmat
		line.mesh = bm
		line.position.y = 22.0
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mark.add_child(line)
		var tag := Label3D.new()
		tag.font = Net.font
		tag.font_size = 64
		tag.pixel_size = 0.0016 # fixed_size below keeps this constant on screen at any distance
		tag.position.y = 25.0
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.fixed_size = true
		tag.modulate = col
		tag.outline_size = 18
		tag.outline_modulate = Color(0, 0, 0, 0.9)
		mark.add_child(tag)
		mark.visible = false
		add_child(mark)
		# the team's own see-through look (survivors see each other through walls) and a name over the head
		var tmat := StandardMaterial3D.new()
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tmat.albedo_color = Color(0.4, 0.85, 1.0, 0.32)
		tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tmat.no_depth_test = true
		tmat.render_priority = 110
		tmat.grow = true
		tmat.grow_amount = 0.008
		var name_tag := Label3D.new()
		name_tag.font = Net.font
		name_tag.font_size = 48
		name_tag.pixel_size = 0.0014
		name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_tag.no_depth_test = true
		name_tag.fixed_size = true
		name_tag.modulate = Color(0.75, 0.92, 1.0)
		name_tag.outline_size = 14
		name_tag.outline_modulate = Color(0, 0, 0, 0.85)
		name_tag.text = n
		name_tag.visible = false
		name_tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(name_tag)
		esp_nodes[n] = {"meshes": meshes, "mat": mat, "mark": mark, "label": tag, "tmat": tmat, "name": name_tag}

func _update_esp() -> void:
	if (Dev.esp or my_role == "survivor") and esp_nodes.size() < remotes.size(): _build_esp()
	if esp_nodes.is_empty(): return
	for n in esp_nodes:
		var e: Dictionary = esp_nodes[n]
		var r = remotes.get(n)
		var on: bool = Dev.esp and r != null and r.node.visible and not _kept(n) and not _kissing(n)
		# survivors know each other: a name over every teammate still in the round, and their body seen
		# through walls (the killer's phone never gets either)
		var team: bool = my_role == "survivor" and r != null and r.role == "survivor" and r.node.visible \
			and rules.hp(n) in ["ok", "hurt", "down", "hooked", "carried"] and not _kept(n) and not _kissing(n)
		var ov: Material = e.mat if on else (e.tmat if team else null)
		for mi in e.meshes:
			if is_instance_valid(mi) and mi.material_overlay != ov: mi.material_overlay = ov
		var nt: Label3D = e.name
		nt.visible = team and not on
		if nt.visible:
			nt.position = r.node.position + Vector3(0, 2.2 * r.node.scale.y, 0)
			var dist := roundi(body.position.distance_to(r.node.position))
			nt.text = n if dist < 12 else "%s  %d m" % [n, dist]
		e.mark.visible = on
		if on:
			e.mark.position = r.node.position
			e.label.text = "%s   %d m" % [n, roundi(body.position.distance_to(r.node.position))]

## End of the round: the cast lines up on a dark stage (scripts/results.gd).
func _show_results() -> void:
	Crumbs.mark("results ok")
	var escaped := 0
	var dead := 0
	for n in rules.s:
		if rules.s[n].hp == "escaped": escaped += 1
		elif rules.s[n].hp == "dead": dead += 1
	var title := ""
	if my_role == "killer": title = "Round over — %d of %d escaped" % [escaped, rules.s.size()]
	else: title = "You escaped!" if rules.hp(my_name) == "escaped" else "You didn't make it"
	var stats := "Round %d:%02d  •  Generators %d/%d  •  Escaped %d of %d" % [int(match_time) / 60, int(match_time) % 60, rules.done_count(), Rules.NEED, escaped, rules.s.size()]
	var names: Array = rules.score.keys()
	names.sort_custom(func(x, y): return rules.score[x] > rules.score[y])
	var rows := []
	for n in names:
		rows.append({"name": n, "char": str(chars.get(n, "survivor1")),
			"role": str(rules.roles.get(n, "survivor")),
			"state": rules.hp(n) if rules.s.has(n) else "killer",
			"score": float(rules.score[n]), "mine": n == my_name})
	var out_rows := [] # the ones who got out: the victory shot before the numbers
	for r in rows:
		if str(r.get("state", "")) == "escaped": out_rows.append(r)
	var xp_from := Net.xp
	var gain := roundi(rules.score.get(my_name, 0.0))
	if not xp_saved: # points become experience; levels, escapes and kills are kept on the phone
		xp_saved = true
		Net.xp += gain
		Net.last_round = {"res": "killer" if my_role == "killer" else str(rules.hp(my_name)), "score": gain,
			"gens": rules.done_count(), "wipe": my_role != "killer" and escaped == 0}
		Net.record_match(1 if (my_role == "survivor" and rules.hp(my_name) == "escaped") else 0,
			dead if my_role == "killer" else 0, world.map_id, my_role, str(Net.last_round.res), gain)
	if hud_layer: hud_layer.visible = false # the stage replaces the HUD
	var host: bool = not offline and str(Net.room.get("host", "")) == my_name
	results = NFResults.new()
	add_child(results)
	results.setup({"rows": rows, "victory": out_rows, "title": title, "stats": stats, "xp_from": xp_from, "xp_to": xp_from + gain,
		"escapes": Net.escapes, "kills": Net.kills,
		# "play again" puts everyone back in the SAME room with the same settings
		"again_text": "Play again" if (offline or host) else "Back to the room",
		"on_again": func() -> void:
			if offline:
				Net.replay = cfg.duplicate(true) # same map, theme and players, new layout seed
			elif host:
				Net.send({"t": "lobby"})
			_to_menu(),
		"on_back": func() -> void:
			if host: Net.send({"t": "lobby"})
			_to_menu()})

## The one random event of the round: a blackout, thick fog, or one survivor given away.
func _round_event(dt: float) -> void:
	var live: bool = rules.ev_kind >= 0 and rules.ev_t > 0.0
	if live and ev_shown != rules.ev_kind:
		ev_shown = rules.ev_kind
		var msg: String = EVENT_NAME[rules.ev_kind]
		if world.map_id == "rubkhali" and rules.ev_kind < 2: # daylight out there: it is the storm, not the dark
			msg = "Heavy sandstorm!" if rules.ev_kind == 0 else "The storm got worse!"
		if rules.ev_kind == 2:
			if rules.ev_n == my_name: msg = "Alarm! Your position is revealed"
			elif my_role == "killer": msg = "Alarm! %s is revealed" % rules.ev_n
			else: msg = "Alarm! %s's position is revealed" % rules.ev_n
		if msg != "": # (the blackout comes with no line: the owner took «the lights went out» out)
			_flash(msg)
			_sfx("warn", null, -4.0)
		NFHaptics.pulse("tick")
	if live != ev_on:
		ev_on = live
		if rules.ev_kind == 0: world.set_blackout(live)
	if rules.ev_kind == 1: # the fog rolls in and back out again
		var f: float = clampf(rules.ev_t / 6.0, 0.0, 1.0) if live else 0.0
		if absf(world.fog_boost - f) > 0.01: world.set_fog(f)

## The call to prayer, from the minaret or from far out on the edge of the map.
func _adhan() -> void:
	if rules.adhan == adhan_state: return
	adhan_state = rules.adhan
	if adhan_state == 1:
		if not ResourceLoader.exists("res://assets/sfx/adhan.mp3"): return
		adhan_player = AudioStreamPlayer3D.new()
		adhan_player.bus = Aud.MUSIC
		adhan_player.stream = load("res://assets/sfx/adhan.mp3")
		adhan_player.position = world.adhan_point()
		adhan_player.unit_size = 26.0      # carries right across the map
		adhan_player.max_distance = 260.0
		adhan_player.volume_db = -14.0     # distant and quiet
		adhan_player.attenuation_filter_cutoff_hz = 3200.0 # muffled by the distance
		add_child(adhan_player)
		adhan_player.play()
	elif adhan_player and is_instance_valid(adhan_player): # gentle fade, then gone
		var tw := create_tween()
		tw.tween_property(adhan_player, "volume_db", -40.0, 2.5)
		tw.tween_callback(adhan_player.queue_free)
		adhan_player = null

## A short kick: the camera tips and rolls, then springs back. `power` is roughly 0..1.
## «الوحش» (killer2) screams when a chase starts — from where he is, on every phone in the chase —
## and the survivors' screens shake a little with it (not much: they still have to run).
var _cry_cd := 0.0
var _was_chasing := false
func _beast_cry(chasing: bool, dt: float) -> void:
	_cry_cd = maxf(_cry_cd - dt, 0.0)
	var start := chasing and not _was_chasing
	_was_chasing = chasing
	if not start or _cry_cd > 0.0 or rules.killer == "" or chars.get(rules.killer, "") != "killer2": return
	_cry_cd = 14.0
	if my_role == "killer":
		_sfx("scream_beast", null, -3.0)
	else:
		_sfx("scream_beast", _pos_of(rules.killer) + Vector3(0, 1.6, 0), 6.0)
		_shake(0.22)
		NFHaptics.pulse_scaled("hit", 0.35)

func _shake(power: float) -> void:
	cam_kick_v += Vector2(-power * 2.6, power * 2.2 * (1.0 if randf() < 0.5 else -1.0))

## The camera moves that are not simple kicks: carried sway, the hook pull-back, the escape zoom.
func _camera_feel(delta: float) -> void:
	# spring the kick back to rest
	cam_kick_v -= (cam_kick * 42.0 + cam_kick_v * 9.0) * delta
	cam_kick += cam_kick_v * delta
	var extra := 0.0
	var roll := cam_kick.y
	var tip := cam_kick.x
	match my_state:
		"carried": # hanging over his shoulder: a slow heavy sway
			var t := Time.get_ticks_msec() / 1000.0
			roll += sin(t * 1.9) * 0.1
			tip += sin(t * 1.3) * 0.05
			extra = 0.8
		"hooked": # swing round to the front of the hook, tip up, pull back
			extra = 3.4
			if hook_cam > 0.0:
				hook_cam = maxf(hook_cam - delta, 0.0)
				var k := 1.0 - exp(-1.8 * delta)
				yaw = lerp_angle(yaw, 0.0, k)   # a hooked character always faces +z
				pitch = lerpf(pitch, 0.1, k)
	if esc_i >= 0: extra = 4.2 # in an escape car: the camera rides behind it
	if my_role != "killer":
		cam_extra = lerpf(cam_extra, extra, 1.0 - exp(-2.2 * delta))
		arm.spring_length = 3.4 + cam_extra
	if slowmo > 0.0: # getting out: a brief slow pull back
		slowmo = maxf(slowmo - delta, 0.0)
		Engine.time_scale = lerpf(1.0, 0.45, clampf(slowmo / 0.25, 0.0, 1.0))
		if main_cam: main_cam.fov = lerpf(70.0, 84.0, clampf(slowmo / 1.1, 0.0, 1.0)) + Gfx.fov_add
		if slowmo <= 0.0:
			Engine.time_scale = 1.0
			if main_cam: main_cam.fov = _base_fov()
	cam_pivot.rotation = Vector3(pitch + tip, yaw, roll)

## Screen margins (left, right) in UI units to stay clear of the notch / Dynamic Island.
func _safe() -> Vector2:
	return NFUI.safe_insets(get_viewport())

func _others_alive() -> Array:
	var out := []
	for n in remotes:
		if remotes[n].role == "survivor" and rules.hp(n) in Rules.LIVE: out.append(n)
	return out

## On-screen buttons. Each: center, radius, label, id, enabled, icon.
## Positions and sizes come from the player's own layout (scripts/controls.gd).
func _buttons() -> Array:
	var rect := NFControls.area(get_viewport())
	var out := []
	if spectating != "":
		if _others_alive().size() > 1:
			out.append([rect.position + rect.size - Vector2(130, 120), 62.0, "Next", "next", true, "next"])
		return out
	var c = ctx.get("interact")
	var lay := NFControls.layout("killer" if my_role == "killer" else "survivor")
	for id in lay:
		if id == "gun" and not rules.gun: continue # only in «وضع السلاح»
		if esc_i >= 0 and (id != "sig" or rules.roads[esc_i].drv == my_name): continue # in an escape car: the driver's hands are on the wheel (the speedometer sits there); the others can still signal
		var e: Dictionary = lay[id]
		var label := NFControls.label_of(id)
		var icon := NFControls.icon_of(id)
		var on := true
		match id:
			"interact": # the interact button becomes whatever is in reach
				label = str(c.label) if c else ("Carry" if my_role == "killer" else "Use")
				icon = str(NFControls.CTX_ICON.get(str(c.kind), "hand")) if c else "hand"
				on = c != null
			"attack":
				on = attack_cd <= 0.0 and rules.carrying == ""
				if sniping:
					label = "Fire"
					icon = "gun"
					on = snipe_cd <= 0.0
				elif driving:
					label = "Camera"
					icon = "car"
					on = true
			"power":
				on = rules.power_cd <= 0.0 and rules.carrying == ""
				if sniping: # one scope, two magnifications
					label = ["Scope x4", "Scope x8", "No scope"][scope]
					icon = "eye"
					on = true
				elif driving:
					label = "Radio off" if car.radio_on else "Radio"
					icon = "note"
					on = car.radio != null
			"trap": # a trap at her feet, or on an escape road a strip of spikes
				var rd_i := world.road_at(body.position)
				var armed := 0
				for tr in rules.traps:
					if bool(tr[2]): armed += 1
				label = "Spikes" if rd_i >= 0 else "Trap %d/%d" % [armed, Rules.TRAPS]
				icon = "spike" if rd_i >= 0 else "trap"
				on = trap_cd <= 0.0 and rules.carrying == "" and not driving and not sniping and rules.stun <= 0.0 and (rd_i < 0 or int(rules.roads[rd_i].st) <= 1)
			"gun":
				var ammo := int(rules.s.get(my_name, {}).get("ammo", 0))
				label = "Pistol %d" % ammo
				on = ammo > 0 and gun_cd <= 0.0 and rules.free_now(my_name) and _held() <= 0.0
			"vault": on = ctx.has("vault")
			"heal": on = ctx.has("heal")
			"item": on = ctx.has("item")
			"light": on = battery > 0.0
			"sig": on = my_state in ["ok", "hurt", "down", "hooked"]
		out.append([NFControls.center_of(e, rect), float(e.r) * Gfx.btn_scale, label, id, on, icon])
	if Dev.unlocked and Dev.vanish_tool and spectating == "": # the developer tools' «Vanish» (this phone only has it)
		out.append([Vector2(rect.end.x - 58.0, rect.position.y + rect.size.y * 0.42), 40.0, "Vanish" if not vanished else "Visible", "vanish", true, "ghost"])
	if driving and car: # the gearbox, beside the speedometer: first (40 km/h), second (70) or third (90)
		var vs := get_viewport().get_visible_rect().size
		out.append([Vector2(vs.x / 2.0 + 190.0, vs.y - 104.0), 44.0, "Gear %d" % car.gear, "gear", true, "shift"])
	if esc_i >= 0 and rules.roads[esc_i].drv == my_name and int(rules.roads[esc_i].st) == 1: # the escape car's one nitro
		var vs := get_viewport().get_visible_rect().size
		var used: bool = esc_nitro.get(esc_i, false)
		out.append([Vector2(vs.x / 2.0 + 196.0, vs.y - 104.0), 52.0, "Used" if used else "Nitro", "nitro", not used, "nitro"])
	return out

## The three quick messages, stacked above the signal button. Each: rect, index.
func _sig_buttons() -> Array:
	if not sig_open: return []
	var out := []
	var at := Vector2(get_viewport().get_visible_rect().size.x / 2.0, 200.0)
	for b in _buttons():
		if b[3] == "sig": at = b[0]
	var up: bool = at.y - 78.0 - 2.0 * 54.0 > 8.0 # no room above? drop the list underneath
	for i in SIG_TEXT.size():
		var dy: float = (-78.0 - i * 54.0) if up else (78.0 + i * 54.0)
		out.append([Rect2(at + Vector2(-110.0, dy), Vector2(220.0, 48.0)), i])
	return out

func _text(pos: Vector2, t: String, size: int, col := Color.WHITE, width := 700.0) -> void:
	ui.draw_string_outline(Net.font, pos - Vector2(width / 2.0, 0), t, HORIZONTAL_ALIGNMENT_CENTER, width, size, 6, Color(0, 0, 0, 0.8))
	ui.draw_string(Net.font, pos - Vector2(width / 2.0, 0), t, HORIZONTAL_ALIGNMENT_CENTER, width, size, col)

func _draw_ui() -> void:
	var s := get_viewport().get_visible_rect().size
	var mid := s / 2.0
	if fin_t > 0.0: # the final shot: black bars, the name, nothing else
		var fbar := s.y * 0.11
		ui.draw_rect(Rect2(0, 0, s.x, fbar), Color(0, 0, 0, 0.92))
		ui.draw_rect(Rect2(0, s.y - fbar, s.x, fbar), Color(0, 0, 0, 0.92))
		ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0.5, 0.0, 0.0, 0.18))
		_text(Vector2(mid.x, s.y - fbar * 0.38), "The last one is down — %s" % fin_who, 34, Color(1, 0.35, 0.3))
		return
	if sniping and scope > 0: NFSniper.draw_scope(ui, s, NFSniper.ZOOMS[scope], snipe_kick)
	elif sniping: # lying with the rifle, no scope: a plain point where the shot goes
		ui.draw_circle(mid, 2.5, Color(1.0, 0.2, 0.15, 0.9))
		ui.draw_arc(mid, 11.0, 0, TAU, 24, Color(1, 1, 1, 0.45), 1.4, true)
	if rules.gun and my_role == "survivor" and esc_i < 0 and spectating == "" and int(rules.s.get(my_name, {}).get("ammo", 0)) > 0 \
			and my_state in ["ok", "hurt"]: # «وضع السلاح»: where the shot goes
		ui.draw_arc(mid, 9.0, 0, TAU, 24, Color(0.6, 0.9, 1.0, 0.7), 1.6, true)
		ui.draw_circle(mid, 1.8, Color(0.6, 0.9, 1.0, 0.8))
	# survivors: red edges pulse when the killer is close
	if rules.powered and rules.doom >= 0.0:
		var near := 1.0 - rules.doom / Rules.DOOM_TIME
		if near > 0.6: ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0.9, 0.1, 0.02, (near - 0.6) * 0.45)) # the sky closing in
		if impact_t >= 0.0:
			var wht := clampf(1.0 - impact_t / 1.2, 0.0, 1.0)
			ui.draw_rect(Rect2(Vector2.ZERO, s), Color(1.0, 0.25 + 0.75 * wht, 0.1 + 0.9 * wht, clampf(2.0 - impact_t * 0.45, 0.0, 1.0)))
	if scare_t > 0.0:
		var k := clampf(scare_t / 0.62, 0.0, 1.0)
		ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0.75, 0.0, 0.0, 0.3 * k))
		for e in 5: ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0.5, 0.0, 0.0, 0.22 * k), false, 26.0 + e * 30.0)
	if my_role == "survivor" and danger > 0.0:
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * lerpf(5.0, 12.0, danger))
		ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0.8, 0.0, 0.0, danger * 0.16 * pulse)) # whole screen goes a little red
		for k in 4: # darker red toward the edges
			ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0.9, 0.03, 0.03, danger * 0.13 * pulse), false, 30.0 + k * 34.0)
	if scare_t > 0.0: # his face fills the screen: no buttons, no map, nothing else
		_text(Vector2(mid.x, s.y * 0.86), "The killer is carrying you!", 34, Color(1, 0.35, 0.3))
		return
	if stick_id >= 0:
		ui.draw_circle(stick_origin, 70, Color(1, 1, 1, 0.12))
		ui.draw_circle(stick_origin + stick_vec * 70, 32, Color(1, 1, 1, 0.35))
	var ba := Gfx.btn_alpha # «وضوح الأزرار»
	for b in _buttons():
		var id: String = b[3]
		var live: bool = b[4]
		var pk: float = clampf(float(pop.get(id, 0.0)) / 0.16, 0.0, 1.0)
		var r: float = b[1] * (1.0 - 0.09 * sin(pk * PI)) # pressed: it dips and springs back
		var on: bool = (id == "crouch" and crouch) or (id == "sprint" and sprint) or (id == "light" and light_on) or (id == "sig" and sig_open) or (not hold.is_empty() and hold.btn == id)
		_draw_btn(b[0], r, str(b[5]), str(b[2]), live, on, pk, ba)
		if id == "light": # battery ring
			ui.draw_arc(b[0], b[1] + 5.0, -PI / 2.0, -PI / 2.0 + TAU * battery / 100.0, 32, Color(1, 0.9, 0.4) if battery > 25.0 else Color(1, 0.3, 0.2), 4.0)
		if id == "power" and driving: # the radio: a green ring while it plays
			if car.radio_on: ui.draw_arc(b[0], b[1] + 5.0, 0, TAU, 40, Color(0.4, 1, 0.5), 5.0)
		elif id == "power": # power indicator: ring refills during the cooldown
			var f := 1.0 - rules.power_cd / Rules.POWER_CD
			ui.draw_arc(b[0], b[1] + 5.0, -PI / 2.0, -PI / 2.0 + TAU * f, 40, Color(1, 0.5, 0.2) if f < 1.0 else Color(0.4, 1, 0.5), 5.0)
		if id == "attack" and attack_cd > 0.0:
			ui.draw_arc(b[0], b[1] + 5.0, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - attack_cd / 2.4), 40, Color(1, 1, 1, 0.7), 4.0)
	# team status bar along the top, then the objective (or the falling-moon ring) under it
	_draw_team(s)
	if driving and car: _draw_speedo(Vector2(mid.x, s.y - 112.0), car)
	elif esc_i >= 0 and rules.roads[esc_i].drv == my_name: _draw_speedo(Vector2(mid.x, s.y - 112.0), world.esc_cars[esc_i])
	var doom_up: bool = rules.powered and rules.doom >= 0.0
	var top := Vector2(mid.x, 96)
	var road := _road_view()
	if road >= 0:
		_draw_road(road, mid)
	elif rules.gate_t >= 0.0 and not rules.powered:
		_draw_gate_count(Vector2(mid.x, 120.0), rules.gate_t)
	elif doom_up:
		_draw_moon(Vector2(mid.x, 120.0))
		var falling := "the moon falls" # the moon on every map now, the Empty Quarter too
		if my_role == "killer": _text(Vector2(mid.x, 214), "Stop them escaping before %s" % falling, 22, Color(1, 0.5, 0.4))
		elif my_state in ["escaped", "dead"]: _text(Vector2(mid.x, 214), "%d of your team still inside" % _others_alive().size(), 22, Color(1, 0.9, 0.6))
		else: _text(Vector2(mid.x, 214), "Get out before %s!" % falling, 24, Color(1, 0.45, 0.35))
	elif my_role == "survivor" and my_state in ["escaped", "dead"]:
		_text(top, "%d of your team still inside" % _others_alive().size(), 24, Color(1, 0.9, 0.6))
	else:
		_text(top, "Generators %d/%d" % [rules.done_count(), Rules.NEED], 26, Color(1, 0.9, 0.6))
	if theme == "sunset" and road < 0: # «بين العصر والمغرب»: how long until the sun is gone
		var tr := Vector2(mid.x + 250.0, 96.0)
		if not world.night_fell():
			var left := int(world.sun_left())
			_text(tr, "☀ Sunset in %d:%02d" % [left / 60, left % 60], 22, Color(1.0, 0.75, 0.4) if left > 60 else Color(1.0, 0.45, 0.3))
		elif rules.has_grid and not rules.grid:
			_text(tr, "Dark — turn the lights on ⚡" if my_role == "survivor" else "The dark is yours", 22, Color(1.0, 0.55, 0.4))
	var sub := Vector2(mid.x, 242.0) if doom_up else top + Vector2(0, 32)
	if my_role == "survivor":
		var me: Dictionary = rules.s.get(my_name, {})
		match my_state:
			"hurt": _text(sub, "Hurt", 22, Color(1, 0.5, 0.35))
			"down": _text(sub, "Down — wait for someone to heal you (%d)" % int(me.t), 22, Color(1, 0.4, 0.35))
			"carried": _text(sub, "The killer is carrying you", 22, Color(1, 0.4, 0.35))
			"hooked":
				_text(sub, "On the hook — %d s" % int(me.t), 22, Color(1, 0.4, 0.35))
				if me.hooks == 1:
					var bar := Rect2(mid.x - 200, s.y - 96, 400, 22)
					ui.draw_rect(bar, Color(0, 0, 0, 0.65))
					ui.draw_rect(Rect2(bar.position, Vector2(400 * clampf(me.esc, 0.0, 1.0), 22)), Color(0.9, 0.15, 0.1))
					ui.draw_rect(bar, Color(1, 1, 1, 0.7), false, 2.0)
					_text(Vector2(mid.x, s.y - 108), "Tap «Free yourself» fast and don't stop!", 20, Color(1, 0.85, 0.5))
				else: _text(sub + Vector2(0, 28), "You can't free yourself this time — wait for a rescue", 20, Color(1, 0.7, 0.5))
			"dead": _text(sub, "You died — watching %s" % spectating if spectating != "" else "You died", 22, Color(1, 0.4, 0.35))
			"escaped": _text(sub, "You escaped — watching %s" % spectating if spectating != "" else "You escaped", 22, Color(0.5, 1, 0.6))
		if escape_banner > 0.0:
			_text(mid + Vector2(0, -40), "You escaped!", 54, Color(0.5, 1, 0.6))
			_text(mid + Vector2(0, 10), "+150 points — wait for your team to get out", 24, Color(0.85, 1, 0.9))
		if not me.is_empty() and me.locker >= 0: _text(sub + Vector2(0, 28), "Hiding in a locker", 20, Color(0.7, 0.85, 1))
	else:
		# detection indicator: how loud the nearest running survivor is, and where
		var c := sub + Vector2(0, 8)
		ui.draw_circle(c, 20, Color(0, 0, 0, 0.5))
		ui.draw_arc(c, 20, 0, TAU, 32, Color(1, 1, 1, 0.4), 2.0)
		if noise > 0.02:
			ui.draw_circle(c, 6.0 + 12.0 * noise, Color(1, 0.3, 0.2, 0.4 + 0.5 * noise))
			var ang := -PI / 2.0 + noise_dir
			ui.draw_line(c + Vector2(cos(ang), sin(ang)) * 24.0, c + Vector2(cos(ang), sin(ang)) * 40.0, Color(1, 0.4, 0.3), 5.0)
			_text(c + Vector2(0, 52), "Running nearby", 18, Color(1, 0.6, 0.5))
		if rules.stun > 0.0: _text(mid + Vector2(0, -60), "Stunned", 30, Color(1, 0.9, 0.3))
		if rules.carrying != "": _text(sub + Vector2(0, 84), "Carrying %s — take them to a hook" % rules.carrying, 20, Color(1, 0.7, 0.5))
		if _text_hint != "": _text(sub + Vector2(0, 116), _text_hint, 20, Color(1.0, 0.85, 0.4))
		if attack_t > 0.55: # first person: show the swing
			ui.draw_arc(mid + Vector2(0, 120), 260, -PI * 0.75, -PI * 0.25, 24, Color(1, 1, 1, 0.35), 14.0)
	# hold progress + skill check
	if not hold.is_empty():
		var p := 0.0
		var hands := 0
		match hold.kind:
			"rep": p = rules.gens[hold.i].p
			"pfix": p = rules.grid_p
			"heal": p = rules.s[hold.n].heal if rules.s.has(hold.n) else 0.0
			"rescue":
				if rules.s.has(hold.n):
					p = float(rules.s[hold.n].get("resc", 0.0))
					# online the snapshot says how many hands; offline, count them here
					hands = int(rules.s[hold.n].get("hands", 0))
					if hands <= 0: hands = rules.hands_on(hold.n)
			_: p = hold.t / hold.need
		var bar := Rect2(mid.x - 180, s.y - 90, 360, 18)
		ui.draw_rect(bar, Color(0, 0, 0, 0.6))
		ui.draw_rect(Rect2(bar.position, Vector2(360 * clampf(p, 0.0, 1.0), 18)), Color(1, 0.85, 0.3))
		ui.draw_rect(bar, Color(1, 1, 1, 0.6), false, 2.0)
		if hands > 1: _text(Vector2(mid.x, s.y - 100), "%d lifting together — faster!" % hands, 20, Color(0.6, 1, 0.7))
	if not skill.is_empty():
		var z: float = skill.zone
		ui.draw_circle(mid, 78, Color(0, 0, 0, 0.55))
		ui.draw_arc(mid, 64, 0, TAU, 48, Color(1, 1, 1, 0.5), 4.0)
		ui.draw_arc(mid, 64, (z - 0.07) * TAU - PI / 2.0, (z + 0.07) * TAU - PI / 2.0, 12, Color(0.3, 1, 0.4), 10.0)
		var ang: float = skill.t / 1.2 * TAU - PI / 2.0
		ui.draw_line(mid, mid + Vector2(cos(ang), sin(ang)) * 72, Color(1, 0.3, 0.3), 4.0)
		_text(mid + Vector2(0, 118), "Tap the screen when the needle is in the green", 20)
	if flash_t > 0.0: _text(Vector2(mid.x, s.y * 0.37), flash, 30, Color(1, 0.85, 0.5))
	_draw_sigs(mid)
	_draw_perk()
	_draw_sense(mid)
	_draw_gate(mid)
	_draw_heli(mid)
	_draw_hit(mid)
	_draw_feed(s)
	if my_role == "killer" and rules.ev_kind == 2 and rules.ev_t > 0.0 and remotes.has(rules.ev_n):
		var to: Vector3 = remotes[rules.ev_n].node.position - body.position
		var a := -PI / 2.0 + wrapf(atan2(to.x, -to.z) + yaw, -PI, PI)
		var dir := Vector2(cos(a), sin(a))
		var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 110.0)
		var at: Vector2 = mid + dir * minf(mid.y * 0.78, 270.0)
		var sd := Vector2(-dir.y, dir.x)
		ui.draw_colored_polygon(PackedVector2Array([at + dir * 26.0, at - sd * 15.0, at + sd * 15.0]), Color(1.0, 0.2, 0.15, pulse))
		_text(at + Vector2(0, 34.0), "%s  %d m" % [rules.ev_n, roundi(Vector2(to.x, to.z).length())], 19, Color(1, 0.4, 0.3, pulse), 300.0)
	for sb in _sig_buttons(): # the three quick messages
		var r2: Rect2 = sb[0]
		var i: int = sb[1]
		ui.draw_rect(r2, Color(0.05, 0.04, 0.05, 0.92))
		ui.draw_rect(r2, Color(0.75, 0.16, 0.16, 0.9), false, 2.0)
		NFIcons.draw(ui, SIG_ICON[i], r2.position + Vector2(r2.size.x - 26.0, r2.size.y / 2.0), 24.0, Color(1, 0.35, 0.3))
		ui.draw_string(Net.font, r2.position + Vector2(-8.0, r2.size.y * 0.68), SIG_TEXT[i], HORIZONTAL_ALIGNMENT_CENTER, r2.size.x - 40.0, 21, Color(1, 0.92, 0.88))

## Small portrait per survivor along the top: state, hook timer, how many times they were hooked.
## The killer sees it too — it never says where anybody is.
func _draw_team(s: Vector2) -> void:
	var names: Array = rules.s.keys()
	names.sort()
	var n := names.size()
	if n == 0: return
	var step: float = minf(56.0, (s.x - 420.0) / maxf(float(n), 1.0))
	var x0: float = s.x / 2.0 - (n - 1) * step / 2.0
	for i in n:
		var nm: String = names[i]
		var p: Dictionary = rules.s[nm]
		var st: String = str(p.hp)
		var c := Vector2(x0 + i * step, 30.0)
		var col: Color = STATE_COL.get(st, Color.WHITE)
		var ccol := NFUI.char_col(str(chars.get(nm, "survivor1")))
		if st == "dead": ccol = ccol.darkened(0.55)
		ui.draw_circle(c, 21.0, Color(0.04, 0.035, 0.045, 0.86))
		NFIcons.portrait(ui, c + Vector2(0, 2.0), 26.0, ccol)
		ui.draw_arc(c, 21.0, 0, TAU, 32, col, 2.5)
		if nm == my_name: ui.draw_arc(c, 25.0, 0, TAU, 34, Color(1, 0.85, 0.35, 0.9), 2.0)
		if STATE_ICON.has(st):
			ui.draw_circle(c + Vector2(14.0, 14.0), 9.5, Color(0.04, 0.035, 0.045, 0.95))
			NFIcons.draw(ui, str(STATE_ICON[st]), c + Vector2(14.0, 14.0), 14.0, col)
		if st == "hooked": # how long they have left on the hook, drawn inside the badge
			var full: float = Rules.HOOK_TIME[clampi(int(p.hooks) - 1, 0, Rules.HOOK_TIME.size() - 1)]
			ui.draw_arc(c, 17.5, -PI / 2.0, -PI / 2.0 + TAU * clampf(float(p.t) / full, 0.0, 1.0), 30, Color(1, 0.25, 0.22), 3.5)
			_text(c + Vector2(0.0, 2.0), "%d" % int(p.t), 17, Color(1, 0.75, 0.6), 44.0)
		if int(p.get("car", -1)) >= 0 and st in ["ok", "hurt"]: # in an escape car
			ui.draw_circle(c + Vector2(-14.0, 14.0), 9.5, Color(0.04, 0.035, 0.045, 0.95))
			NFIcons.draw(ui, "car", c + Vector2(-14.0, 14.0), 14.0, Color(0.5, 0.95, 1.0))
		for k in int(p.hooks): # a red pip for every hook survived
			ui.draw_circle(c + Vector2(-15.0 + k * 7.0, 15.5), 2.6, Color(1, 0.3, 0.25))
		var short := nm.substr(0, 7) if nm.length() > 7 else nm
		ui.draw_string(Net.font, c + Vector2(-step / 2.0, 36.0), short, HORIZONTAL_ALIGNMENT_CENTER, step, 14, Color(col, 0.9))

## The falling moon: a red ring that fills over the two minutes and beats in the last thirty seconds.
## The car's speedometer, bottom centre while I drive: a 270-degree dial to 60 km/h with a red
## band at the top, an eased needle, the speed in figures and the gear (D / R).
var speedo_kmh := 0.0
func _draw_speedo(c: Vector2, cr: NFCar) -> void:
	var r := 84.0
	var a0 := deg_to_rad(135.0)
	var sweep := deg_to_rad(270.0)
	ui.draw_circle(c, r + 10.0, Color(0.03, 0.025, 0.025, 0.72))
	ui.draw_arc(c, r + 10.0, 0.0, TAU, 64, Color(0.45, 0.08, 0.06, 0.9), 3.0, true)
	ui.draw_arc(c, r - 4.0, a0 + sweep * (90.0 / 100.0), a0 + sweep, 24, Color(0.85, 0.12, 0.08, 0.85), 7.0, true)
	for v in range(0, 101, 5):
		var ang := a0 + sweep * v / 100.0
		var dir := Vector2(cos(ang), sin(ang))
		var big := v % 10 == 0
		ui.draw_line(c + dir * (r - (14.0 if big else 8.0)), c + dir * r, Color(0.92, 0.88, 0.82, 0.95 if big else 0.6), 3.0 if big else 1.5, true)
		if v % 20 == 0:
			_text(c + dir * (r - 30.0) + Vector2(0, 7), str(v), 15, Color(0.92, 0.88, 0.82))
	var na := a0 + sweep * clampf(speedo_kmh, 0.0, 100.0) / 100.0
	var nd := Vector2(cos(na), sin(na))
	ui.draw_line(c - nd * 10.0, c + nd * (r - 6.0), Color(1.0, 0.25, 0.15), 4.0, true)
	ui.draw_circle(c, 9.0, Color(0.15, 0.03, 0.03))
	ui.draw_arc(c, 9.0, 0.0, TAU, 24, Color(1.0, 0.3, 0.2), 2.0, true)
	_text(c + Vector2(0, 48), "%d" % roundi(speedo_kmh), 30, Color(1, 0.95, 0.88))
	_text(c + Vector2(0, 70), "km/h", 13, Color(0.8, 0.75, 0.7))
	var gear := "R" if cr.speed < -0.3 else str(cr.gear)
	_text(c + Vector2(r + 34.0, 10), gear, 26, Color(1.0, 0.35, 0.25) if gear == "R" else Color(0.5, 1.0, 0.6))

## The countdown before the gates open: a ring emptying round the seconds left, amber, beating on
## every whole second, with what it means under it for each side.
## The rescue helicopter on the HUD: for the last survivor (and the killer) where it is and how long
## it has left; an arrow on the ring to the ladder; while climbing, how far up.
func _draw_heli(mid: Vector2) -> void:
	if heli == null or spectating != "": return
	var st := int(rules.heli.st)
	if st < 1 or st > 3: return
	var mine := str(rules.heli.who) == my_name
	if not mine and my_role != "killer": return
	var col := Color(0.6, 0.85, 1.0)
	var y := 250.0
	if st == 1: _text(Vector2(mid.x, y), ("The rescue helicopter arrives in %d seconds" if mine else "A rescue helicopter is coming — arrives in %d") % ceili(float(rules.heli.t)), 26, col)
	elif st == 2: _text(Vector2(mid.x, y), ("The helicopter is waiting — it leaves in %d seconds!" if mine else "The ladder is down — it leaves in %d, grab it") % ceili(float(rules.heli.t)), 26, Color(1.0, 0.85, 0.4) if mine else Color(1.0, 0.5, 0.4))
	else:
		_text(Vector2(mid.x, y), "Climb! Climb!" if mine else "They're climbing the ladder — catch them!", 28, col)
		var w := 320.0
		ui.draw_rect(Rect2(mid.x - w / 2.0, y + 18.0, w, 12.0), Color(0, 0, 0, 0.6))
		ui.draw_rect(Rect2(mid.x - w / 2.0, y + 18.0, w * clampf(heli_p, 0.0, 1.0), 12.0), col)
		return
	var target: Vector3 = world.heli_spot
	var bd := Vector2(target.x - body.position.x, target.z - body.position.z).length()
	if bd < 5.0: return
	var d := _ring_dir(target)
	var at := mid + d * minf(mid.y * 0.8, 300.0)
	var beat := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
	var c2 := Color(col.r, col.g, col.b, beat)
	ui.draw_circle(at, 25.0, Color(0.02, 0.04, 0.07, 0.85), true, -1.0, true)
	ui.draw_arc(at, 25.0, 0, TAU, 40, c2, 2.5, true)
	NFIcons.draw(ui, "star", at, 24.0, c2)
	var tip := at + d * 35.0
	var sd := Vector2(-d.y, d.x)
	ui.draw_colored_polygon(PackedVector2Array([tip + d * 13.0, tip - sd * 9.0, tip + sd * 9.0]), c2)
	_text(at + Vector2(0, 48), "Helicopter %d m" % int(bd), 18, c2)

func _draw_gate_count(c: Vector2, left: float) -> void:
	var f := clampf(left / Rules.GATE_DELAY, 0.0, 1.0)
	var beat := 1.0 + 0.12 * maxf(0.0, 1.0 - fmod(left, 1.0) * 4.0)
	var r := 44.0 * beat
	ui.draw_circle(c, r + 8.0, Color(0, 0, 0, 0.55))
	ui.draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * f, 64, Color(1.0, 0.62, 0.1), 7.0, true)
	_text(c + Vector2(0, 14), "%d" % ceili(left), int(44 * beat), Color(1.0, 0.85, 0.4))
	var msg := "The gates open in %d seconds — get ready" % ceili(left)
	if my_role == "killer": msg = "The gates open in %d — get there first" % ceili(left)
	_text(c + Vector2(0, 92), msg, 24, Color(1.0, 0.75, 0.35))

func _draw_moon(c: Vector2) -> void:
	var left: float = maxf(rules.doom, 0.0)
	var f: float = clampf(1.0 - left / Rules.DOOM_TIME, 0.0, 1.0)
	var pulse := 1.0
	if left < 30.0: pulse = 0.72 + 0.28 * sin(Time.get_ticks_msec() / 1000.0 * 9.0)
	var r: float = 30.0 + (3.0 * pulse if left < 30.0 else 0.0)
	ui.draw_circle(c, 27.0, Color(0.03, 0.025, 0.035, 0.92))
	# the moon on every map (the Empty Quarter too: the owner wants the moon here, not the sun) —
	# his own moon picture, reddening as the time runs out
	var mt: Texture2D = _map_tex.get("@moon") if _map_tex.has("@moon") else null
	if not _map_tex.has("@moon"):
		mt = load("res://assets/sky/moon.jpg") if ResourceLoader.exists("res://assets/sky/moon.jpg") else null
		_map_tex["@moon"] = mt
	var mcol := Color(1, 1, 1).lerp(Color(1.0, 0.45, 0.35), f * 0.85)
	if mt: ui.draw_texture_rect(mt, Rect2(c - Vector2(24, 24), Vector2(48, 48)), false, mcol)
	else: NFIcons.draw(ui, "moon", c, 38.0, Color(0.96, 0.93, 0.88).lerp(Color(1.0, 0.55, 0.4), f * 0.8))
	ui.draw_arc(c, r, 0, TAU, 44, Color(1, 1, 1, 0.12), 6.0)
	ui.draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * f, 48, Color(1.0, 0.13, 0.1, pulse), 6.0)
	_text(c + Vector2(0, r + 22.0), "%d:%02d" % [int(ceil(left)) / 60, int(ceil(left)) % 60], 22,
		Color(1, 0.45, 0.35) if left < 30.0 else Color(1, 0.85, 0.7))

## The ramp up to the car park's roof: a lit strip with chevrons running toward the top, and the
## word «السطح» on the big map, so you can always see where the way up is.
const ROOF_COL := Color(0.35, 0.9, 1.0)
const CAR_COL := Color(1.0, 0.55, 0.2) # the killer's car on his map

func _draw_roof_ramp(c: Vector2, k: float, u: float, big: bool) -> void:
	var x0: float = NightWorld.GAR_RAMP_X[0]
	var x1: float = NightWorld.GAR_RAMP_X[1]
	var z0: float = NightWorld.GAR_RAMP_Z[0] - 4.0
	var z1: float = NightWorld.GAR_RAMP_Z[1]
	var r := Rect2(c + Vector2(x0, z0) * k, Vector2(x1 - x0, z1 - z0) * k)
	minimap.draw_rect(r, Color(ROOF_COL, 0.28))
	minimap.draw_rect(r, ROOF_COL, false, 1.4 * u)
	for i in 3: # chevrons pointing up the slope (toward +z, the top of the ramp)
		var cy: float = r.position.y + r.size.y * (0.25 + i * 0.25)
		var cx: float = r.position.x + r.size.x / 2.0
		var w: float = r.size.x * 0.32
		minimap.draw_polyline(PackedVector2Array([Vector2(cx - w, cy - w * 0.6), Vector2(cx, cy), Vector2(cx + w, cy - w * 0.6)]),
			ROOF_COL, 1.4 * u)
	if big: _map_text(r.position + Vector2(r.size.x + 6.0, r.size.y * 0.6), "Roof ↑", 16, ROOF_COL)

## A small cyan "up" triangle beside anything that is on the roof.
func _roof_badge(at: Vector2, u: float) -> void:
	minimap.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -4) * u, at + Vector2(3.5, 2.5) * u,
		at + Vector2(-3.5, 2.5) * u]), ROOF_COL)

## A team-mate's quick message: an arrow on a ring around the middle of the screen, pointing at them.
func _draw_sigs(mid: Vector2) -> void:
	for sg in sigs:
		var to: Vector3 = sg.pos - body.position
		var flat := Vector2(to.x, to.z)
		var a := -PI / 2.0 + wrapf(atan2(to.x, -to.z) + yaw, -PI, PI)
		var dir := Vector2(cos(a), sin(a))
		var at: Vector2 = mid + dir * minf(mid.y * 0.62, 210.0)
		var fade: float = clampf(float(sg.t) / 1.5, 0.0, 1.0)
		var col := Color(1.0, 0.85, 0.4, fade) if int(sg.k) != 1 else Color(1.0, 0.35, 0.3, fade)
		ui.draw_circle(at, 21.0, Color(0.04, 0.035, 0.045, 0.75 * fade))
		NFIcons.draw(ui, SIG_ICON[int(sg.k)], at, 26.0, col)
		var tip := at + dir * 30.0
		var sd := Vector2(-dir.y, dir.x)
		ui.draw_colored_polygon(PackedVector2Array([tip + dir * 12.0, tip - sd * 8.0, tip + sd * 8.0]), col)
		var who := str(sg.n)
		var label := "%s — %s (%d m)" % [who, SIG_TEXT[int(sg.k)], roundi(flat.length())] if who != "" else "%s (%d m)" % [SIG_TEXT[int(sg.k)], roundi(flat.length())]
		_text(at + Vector2(0, 26.0), label, 17, col, 300.0)

func _draw_minimap() -> void:
	if scare_t > 0.0: return
	var vs := get_viewport().get_visible_rect().size
	if big_map: # tapped: a large map in the middle of the screen with a legend
		var side := minf(vs.y - 120.0, 560.0)
		var origin := (vs - Vector2(side, side)) / 2.0 - minimap.position
		_draw_map(origin, side, true)
	else:
		_draw_map(Vector2.ZERO, 170.0, false)

func _map_text(pos: Vector2, t: String, size: int, col: Color) -> void:
	minimap.draw_string(Net.font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw_map(o: Vector2, side: float, big: bool) -> void:
	var k := side / (NightWorld.SIZE + NightWorld.MAP_ROAD * 2.0 + 8.0) if big else side / NightWorld.SIZE
	var c := o + Vector2(side, side) / 2.0
	var inside := func(v: Vector2) -> Vector2: return v.clamp(o + Vector2(5, 5), o + Vector2(side - 5.0, side - 5.0)) # out on a road: on the edge
	var u := 1.0 if not big else 2.2 # marker scale
	minimap.draw_rect(Rect2(o, Vector2(side, side)), Color(0.02, 0.03, 0.05, 0.9 if big else 0.6))
	minimap.draw_rect(Rect2(o, Vector2(side, side)), Color(1, 1, 1, 0.5), false, 2.0)
	var wl := NightWorld.WALL * k
	minimap.draw_rect(Rect2(c - Vector2(wl, wl), Vector2(wl, wl) * 2.0), Color(0.2, 0.17, 0.11, 0.55) if world.map_id in ["fareej", "rubkhali"] else (Color(0.12, 0.12, 0.13, 0.6) if world.map_id == "garage" else Color(0.1, 0.13, 0.1, 0.55)))
	if world.map_id == "fareej": # streets
		for st in [[-30.0, -47.0, 150.0, 7.0], [-30.0, 47.0, 150.0, 7.0], [-28.0, 0.0, 142.0, 8.0], [-13.0, 0.0, 7.0, 94.0]]:
			minimap.draw_rect(Rect2(c + Vector2(st[0] - st[2] / 2.0, st[1] - st[3] / 2.0) * k, Vector2(st[2], st[3]) * k), Color(0.32, 0.32, 0.34))
	if world.map_id == "kuwait": # the sea, the Gulf Road, the car park, the Assembly
		var sea_x := NightWorld.KW_SHORE * k
		minimap.draw_rect(Rect2(c + Vector2(sea_x, -wl), Vector2(wl - sea_x, wl * 2.0)), Color(0.05, 0.14, 0.26))
		minimap.draw_rect(Rect2(c + Vector2(NightWorld.KW_SAND * k, -wl), Vector2((NightWorld.KW_SHORE - NightWorld.KW_SAND) * k, wl * 2.0)), Color(0.45, 0.38, 0.25))
		minimap.draw_rect(Rect2(c + Vector2(-NightWorld.KW_ROAD_HALF * k, -wl), Vector2(NightWorld.KW_ROAD_HALF * 2.0 * k, wl * 2.0)), Color(0.3, 0.3, 0.32))
		minimap.draw_rect(Rect2(c + Vector2(-1.8 * k, -wl), Vector2(3.6 * k, wl * 2.0)), Color(0.2, 0.45, 0.2))
		minimap.draw_rect(Rect2(c + Vector2(NightWorld.KW_PARK.x * k, -wl), Vector2((NightWorld.KW_PARK.y - NightWorld.KW_PARK.x) * k, wl * 2.0)), Color(0.22, 0.22, 0.24))
		var asm: Vector3 = NightWorld.KW_ASSEMBLY
		minimap.draw_rect(Rect2(c + Vector2(asm.x - 23.0, asm.z - 40.0) * k, Vector2(46.0, 80.0) * k), Color(0.7, 0.64, 0.52))
		if big: _map_text(c + Vector2(asm.x - 18.0, asm.z) * k, "National Assembly", 15, Color(0.15, 0.12, 0.08))
		minimap.draw_circle(c + Vector2(NightWorld.KW_TOWERS.x, NightWorld.KW_TOWERS.z) * k, 5.0 * u, Color(0.4, 0.65, 1.0))
	if rules.sniper: # «وضع القنّاص»: the tower where the north gate was, the stairs and the rifle
		minimap.draw_rect(Rect2(c + Vector2(-NightWorld.SN_HALF, NightWorld.SN_FACE) * k, Vector2(NightWorld.SN_HALF * 2.0, NightWorld.SN_BACK - NightWorld.SN_FACE) * k), Color(0.45, 0.43, 0.4))
		minimap.draw_line(c + Vector2(NightWorld.SN_STAIR_X0, NightWorld.SN_FACE - 1.3) * k, c + Vector2(NightWorld.SN_TOP_X, NightWorld.SN_FACE - 1.3) * k, Color(1.0, 0.8, 0.2), 2.0 * u)
		var tc := c + Vector2(0.0, (NightWorld.SN_FACE + NightWorld.SN_BACK) / 2.0) * k
		minimap.draw_arc(tc, 6.0 * u, 0, TAU, 20, Color(1, 0.25, 0.2), 1.6 * u)
		minimap.draw_line(tc - Vector2(9, 0) * u, tc + Vector2(9, 0) * u, Color(1, 0.25, 0.2), 1.4 * u)
		minimap.draw_line(tc - Vector2(0, 9) * u, tc + Vector2(0, 9) * u, Color(1, 0.25, 0.2), 1.4 * u)
		if big: _map_text(tc + Vector2(0, -16) * u, "Sniper", 15, Color(1, 0.4, 0.35))
	for i in world.gate_points.size(): # escape roads + gates
		if rules.sniper and i != 0: continue # (the north gate stays shut behind the tower)
		var p: Vector3 = world.gate_points[i][0]
		var out_dir := signf(p.z)
		var open: bool = rules.gates[i].open
		if big: minimap.draw_rect(Rect2(c + Vector2(-NightWorld.LANE_W / 2.0, minf(p.z, p.z + out_dir * NightWorld.MAP_ROAD)) * k, Vector2(NightWorld.LANE_W, NightWorld.MAP_ROAD) * k), Color(0.3, 0.3, 0.3) if not open else Color(0.25, 0.5, 0.3))
		var gpc := c + Vector2(p.x, p.z) * k
		# the owner's gate pictures: red with ↑ for the north one, blue with ↓ for the south; a green
		# ring once it is open
		if not _map_pic(gpc, "gate_n" if p.z < 0.0 else "gate_s", 17.0 * u):
			minimap.draw_circle(gpc, 7.5 * u, Color(0, 0, 0, 0.6))
			NFIcons.draw(minimap, "gate", gpc, 6.5 * u, Color(0.4, 1, 0.5) if open else Color(1, 0.3, 0.25))
		if open: minimap.draw_arc(gpc, 10.0 * u, 0, TAU, 24, Color(0.4, 1, 0.5), 1.8 * u)
		if p.y > 1.0: _roof_badge(gpc + Vector2(0, 11) * u, u)
	minimap.draw_rect(Rect2(c - Vector2(wl, wl), Vector2(wl, wl) * 2.0), Color(0.85, 0.85, 0.8, 0.8), false, 2.0 * u)
	for b in world.buildings:
		minimap.draw_set_transform(c + Vector2(b[0], b[1]) * k, -b[2], Vector2.ONE)
		var r := Rect2(-Vector2(b[3], b[4]) * k / 2.0, Vector2(b[3], b[4]) * k)
		minimap.draw_rect(r, Color(0.5, 0.46, 0.38))
		minimap.draw_rect(r, Color(0.8, 0.76, 0.66), false, 1.0)
		minimap.draw_line(Vector2(-1.0 * k, b[4] * k / 2.0), Vector2(1.0 * k, b[4] * k / 2.0), Color(0.1, 0.1, 0.1), 2.0) # door
	if world.map_id == "garage": # the car park: the stair cores and the cross walls, no market
		for t in world.garage_tiles:
			var tc: int = int(t.c)
			var tr: int = int(t.r)
			if "core" in t.pieces:
				var a0: Vector3 = world._gar(tc, tr, -0.25, -20.0)
				var a1: Vector3 = world._gar(tc, tr, 5.0, 0.0)
				minimap.draw_rect(Rect2(c + Vector2(a0.x, a0.z) * k, Vector2(a1.x - a0.x, a1.z - a0.z) * k), Color(0.45, 0.45, 0.48))
			if "wall_s" in t.pieces:
				var w0: Vector3 = world._gar(tc, tr, -0.2, -20.1)
				var w1: Vector3 = world._gar(tc, tr, 30.2, -20.1)
				minimap.draw_line(c + Vector2(w0.x, w0.z) * k, c + Vector2(w1.x, w1.z) * k, Color(0.5, 0.5, 0.52), 2.0)
		_draw_roof_ramp(c, k, u, big)
	else:
		if world.map_id == "beach": # the pier out over the water to the north gate
			minimap.draw_rect(Rect2(c + Vector2(-NightWorld.PIER_W / 2.0, NightWorld.PIER_FROM) * k,
				Vector2(NightWorld.PIER_W, NightWorld.WALL - NightWorld.PIER_FROM) * k), Color(0.55, 0.4, 0.25))
		var mk: Dictionary = world.market
		minimap.draw_set_transform(c + Vector2(mk.pos.x, mk.pos.z) * k, -mk.yaw, Vector2.ONE)
		minimap.draw_rect(Rect2(-Vector2(mk.w, mk.d) * k / 2.0, Vector2(mk.w, mk.d) * k), Color(0.8, 0.25, 0.25) if world.map_id != "kuwait" else Color(0.75, 0.62, 0.3))
		minimap.draw_rect(Rect2(Vector2(-mk.w / 2.0, mk.d / 2.0) * k, Vector2(mk.w, 13.0) * k), Color(0.25, 0.25, 0.27)) # parking
		minimap.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if world.map_id == "kuwait":
			minimap.draw_circle(c + Vector2(mk.pos.x - 5.0, mk.pos.z) * k, 7.0 * u, Color(0.85, 0.72, 0.35))
			if big: _map_text(c + Vector2(mk.pos.x + 8.0, mk.pos.z + 3.0) * k, "Mosque", 16, Color(1, 0.88, 0.5))
		else:
			_map_pic(c + Vector2(mk.pos.x, mk.pos.z) * k, "market", 18.0 * u)
			if big: _map_text(c + Vector2(mk.pos.x + 8.0, mk.pos.z + 3.0) * k, "Market", 16, Color(1, 0.7, 0.7))
	for i in world.hook_points.size():
		if i >= world.road_hook0: break # the ones along the roads are off the map
		var hp: Vector3 = world.hook_points[i]
		var used := rules.hook_user(i) != ""
		var hc := c + Vector2(hp.x, hp.z) * k
		var col := Color(1, 0.2, 0.2) if used else Color(0.8, 0.35, 0.35)
		if not _map_pic(hc, "hook", 12.0 * u, Color(1, 1, 1) if used else Color(0.85, 0.85, 0.85, 0.85)):
			NFIcons.draw(minimap, "hook", hc, 4.6 * u, col)
		if used: minimap.draw_arc(hc, 7.0 * u, 0, TAU, 18, Color(1, 0.3, 0.3), 1.5)
		if hp.y > 1.0: _roof_badge(hc + Vector2(0, -8) * u, u)
	for i in world.gen_points.size():
		var gp: Vector3 = world.gen_points[i]
		var g: Dictionary = rules.gens[i]
		var gc := c + Vector2(gp.x, gp.z) * k
		var sz := 7.0 * u
		# ⚡ a bolt per generator; survivors see the repair fill a ring round it (the killer only finished ones)
		var gcol := Color(0.4, 1, 0.5) if g.done else Color(1, 0.85, 0.2)
		minimap.draw_circle(gc, sz * 0.95, Color(0, 0, 0, 0.6))
		if my_role == "survivor" and not g.done and float(g.p) > 0.0:
			minimap.draw_arc(gc, sz * 0.95, -PI / 2.0, -PI / 2.0 + TAU * float(g.p), 24, Color(1, 0.85, 0.2), 1.6 * u)
		elif g.done: minimap.draw_arc(gc, sz * 0.95, 0, TAU, 24, gcol, 1.4 * u)
		if not _map_pic(gc, "gen_on" if g.done else "gen_off", sz * 1.7): # the owner's generators, ⚡ on the front
			NFIcons.draw(minimap, "bolt", gc, sz * 0.75, gcol)
		if gp.y > 1.0: _roof_badge(gc + Vector2(0, -sz), u)
	if big: # the big map also shows where to hide and what to drop
		for lp in world.locker_points:
			var lc := c + Vector2(lp[0].x, lp[0].z) * k
			NFIcons.draw(minimap, "locker", lc, 3.6 * u, Color(0.6, 0.7, 0.8, 0.85))
		for i in world.pallet_points.size():
			if rules.pallets[i] >= 2: continue # broken: nothing left there
			var pp: Vector3 = world.pallet_points[i][0]
			NFIcons.draw(minimap, "plank", c + Vector2(pp.x, pp.z) * k, 3.8 * u, Color(0.85, 0.62, 0.35) if rules.pallets[i] == 0 else Color(0.55, 0.42, 0.3))
	if my_role == "killer": # her own traps
		for tr in rules.traps:
			if bool(tr[2]): NFIcons.draw(minimap, "trap", c + Vector2(float(tr[0]), float(tr[1])) * k, 3.6 * u, Color(1, 0.5, 0.35))
	if rules.hatch >= 0 and my_role == "survivor":
		var hp2: Vector3 = world.hatch_points[rules.hatch]
		var hc2 := c + Vector2(hp2.x, hp2.z) * k
		if not _map_pic(hc2, "hatch", 15.0 * u):
			minimap.draw_circle(hc2, 6.5 * u, Color(0, 0, 0, 0.6))
			NFIcons.draw(minimap, "hatch", hc2, 5.5 * u, Color(0.5, 1, 0.7))
	if car and my_role == "killer": # the killer always knows where he left his car
		var cp: Vector2 = inside.call(c + Vector2(car.position.x, car.position.z) * k)
		var cf := Vector2(sin(car.rotation.y), cos(car.rotation.y))
		var cs := Vector2(-cf.y, cf.x)
		minimap.draw_colored_polygon(PackedVector2Array([cp + (cf * 5.0 + cs * 2.6) * u, cp + (cf * 5.0 - cs * 2.6) * u,
			cp + (-cf * 5.0 - cs * 2.6) * u, cp + (-cf * 5.0 + cs * 2.6) * u]), CAR_COL)
		minimap.draw_line(cp + (cf * 2.6 + cs * 2.3) * u, cp + (cf * 2.6 - cs * 2.3) * u, Color(0.1, 0.1, 0.1), 1.4 * u) # windscreen
		if world.map_id == "garage" and car.position.y > 3.0: _roof_badge(cp + Vector2(0, -10) * u, u)
		if big: _map_text(cp + Vector2(9, 5) * u, "Your car", 15, CAR_COL)
	for n in remotes: # survivors see their team; the killer never sees players here
		var r = remotes[n]
		if my_role == "survivor" and r.role == "survivor" and r.node.visible:
			var p: Vector3 = r.node.position
			var rp: Vector2 = inside.call(c + Vector2(p.x, p.z) * k)
			minimap.draw_circle(rp, 3.5 * u, Color(0.4, 0.8, 1))
			if big: _map_text(rp + Vector2(8, 5), n, 15, Color(0.6, 0.85, 1))
	var me: Vector2 = inside.call(c + Vector2(body.position.x, body.position.z) * k)
	var f := Vector2(-sin(yaw), -cos(yaw))
	var sd := Vector2(-f.y, f.x)
	minimap.draw_colored_polygon(PackedVector2Array([me + f * 8.0 * u, me - f * 4.0 * u + sd * 5.0 * u, me - f * 4.0 * u - sd * 5.0 * u]),
		Color(1, 0.3, 0.3) if my_role == "killer" else Color(1, 1, 1))
	if world.power_box != Vector3.INF: # the power box: everyone can find it (yellow, red while it is cut)
		var bp := c + Vector2(world.power_box.x, world.power_box.z) * k
		var on: bool = rules.grid
		var bc := Color(1.0, 0.85, 0.2) if on else Color(1.0, 0.25, 0.2, 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() / 200.0)))
		minimap.draw_rect(Rect2(bp - Vector2(7, 7) * u, Vector2(14, 14) * u), Color(0.05, 0.05, 0.05, 0.9))
		minimap.draw_rect(Rect2(bp - Vector2(7, 7) * u, Vector2(14, 14) * u), bc, false, 1.6 * u)
		NFIcons.draw(minimap, "bolt", bp, 11.0 * u, bc)
		if big: _map_text(bp + Vector2(10, 5) * u, "Power" if on else "Power cut!", 16, bc)
	if world.map_id == "garage" and body.position.y > 3.0: # standing on the roof
		minimap.draw_arc(me, 11.0 * u, 0, TAU, 20, ROOF_COL, 1.6 * u)
		_map_text(o + Vector2(side / 2.0 - (40.0 if big else 26.0), 18.0 if big else 14.0), "On the roof",
			20 if big else 13, ROOF_COL)
	if big:
		var ly := o.y + side + 22.0
		# each entry: [drawn icon or "" + glyph, colour, name]
		var items := [["@gen_off", Color(1, 0.85, 0.2), "Generator"], ["@gen_on", Color(0.4, 1, 0.5), "On"], ["@hook", Color(0.8, 0.35, 0.35), "Hooked"],
			["@gate_n", Color(1, 0.3, 0.25), "North"], ["@gate_s", Color(0.3, 0.6, 1), "South"], ["locker", Color(0.6, 0.7, 0.8), "Locker"], ["plank", Color(0.85, 0.62, 0.35), "Pallet"]]
		if my_role == "survivor": items.append(["@hatch", Color(0.5, 1, 0.7), "Hatch"])
		if world.map_id == "garage":
			items.append(["■", Color(0.45, 0.45, 0.48), "Stairs"]) # the stair cores
			items.append(["▲", ROOF_COL, "On the roof"])
		else: items.append(["■", Color(0.8, 0.25, 0.25), "Market"])
		if world.power_box != Vector3.INF: items.append(["bolt", Color(1.0, 0.85, 0.2), "Power box"])
		if my_role == "killer":
			items.append(["trap", Color(1, 0.5, 0.35), "Your traps"])
			if car: items.append(["■", CAR_COL, "Your car"])
		var lx := o.x
		for it in items:
			if str(it[0]).begins_with("@"): _map_pic(Vector2(lx + 7, ly - 6), str(it[0]).substr(1), 18.0)
			elif str(it[0]).length() > 1: NFIcons.draw(minimap, str(it[0]), Vector2(lx + 7, ly - 6), 7.0, it[1])
			else: _map_text(Vector2(lx, ly), it[0], 18, it[1])
			_map_text(Vector2(lx + 20, ly), it[2], 14, Color(0.9, 0.9, 0.9))
			lx += side / items.size()
	else:
		_map_text(o + Vector2(4, side + 16), "Tap to enlarge", 13, Color(1, 1, 1, 0.45))

# ---------------- context: what each button would do right now ----------------
## Close enough to touch: flat distance, and no more than a storey apart — the car park has a
## generator up on the roof, and you should not be able to work on it from the floor below.
func _near(a: Vector3, b: Vector3, r: float) -> bool:
	return absf(a.y - b.y) < 3.0 and Vector2(a.x - b.x, a.z - b.z).length() < r

func _update_ctx() -> void:
	ctx = {}
	_text_hint = ""
	if rules.over: return
	var pos := body.position
	if my_role == "survivor":
		var me: Dictionary = rules.s.get(my_name, {})
		if me.is_empty(): return
		if me.locker >= 0:
			ctx.interact = {"kind": "locker_out", "label": "Climb", "i": me.locker}
			return
		if my_state == "hooked" and me.hooks == 1: # first hook only: hammer the button to pull yourself off
			ctx.interact = {"kind": "struggle", "label": "Free yourself"}
		if not (my_state in ["ok", "hurt"]) or esc_i >= 0: return
		for n in rules.s:
			var p: Dictionary = rules.s[n]
			if n == my_name: continue
			if p.hp == "hooked" and not rules.eaten(n) and _near(pos, world.hook_points[p.hook_i], 2.9):
				ctx.interact = {"kind": "rescue", "label": "Rescue", "n": n, "need": -1.0}
			if p.hp in ["hurt", "down"] and p.locker < 0 and rules.car_of(n) < 0 and _near(pos, _pos_of(n), 2.6):
				ctx.heal = {"kind": "heal", "n": n, "need": -1.0}
		if not ctx.has("interact"): # «Kiss» (after three shakes of the phone)
			var kt := _kiss_target(pos)
			if kt != "": ctx.interact = {"kind": "kiss", "label": "Kiss", "n": kt}
		if not ctx.has("interact"): # a trap within reach (but not under my feet): spring it with a stick
			for i in rules.traps.size():
				var tr: Array = rules.traps[i]
				if not bool(tr[2]): continue
				var dd := Vector2(float(tr[0]) - pos.x, float(tr[1]) - pos.z).length()
				if dd < 2.0 and dd > 0.8:
					ctx.interact = {"kind": "disarm", "label": "Disarm trap", "i": i}
		if not ctx.has("interact") and heli and int(rules.heli.st) == 2 and str(rules.heli.who) == my_name and _near(pos, heli.ladder_foot(), 2.8):
			ctx.interact = {"kind": "ladder", "label": "Grab the ladder and climb", "i": 0}
		if not ctx.has("interact") and rules.powered: # the escape car past the gate: first one in drives
			for i in mini(world.esc_cars.size(), rules.roads.size()):
				var ec: NFCar = world.esc_cars[i]
				var est := int(rules.roads[i].st)
				if est <= 1 and (i == 0 or not rules.sniper) and absf(ec.speed) < 3.0 and (rules.roads[i].who as Array).size() < Rules.CAR_SEATS and _near(pos, ec.global_position, 3.8):
					ctx.interact = {"kind": "board", "label": "Get in and drive" if est == 0 else "Ride with them", "i": i}
		if not ctx.has("interact"):
			for i in world.locker_points.size():
				if _near(pos, world.locker_points[i][0], 1.9) and rules.locker_user(i) == "":
					ctx.interact = {"kind": "locker_in", "label": "Hide", "i": i}
		if not ctx.has("interact"):
			for i in world.pallet_points.size():
				if rules.pallets[i] == 0 and _near(pos, world.pallet_points[i][0], 2.2):
					ctx.interact = {"kind": "pallet", "label": "Drop", "i": i}
		if not ctx.has("interact"): _door_ctx(pos)
		if not ctx.has("interact") and rules.has_grid and not rules.grid and world.power_box != Vector3.INF and _near(pos, world.power_box, 2.6):
			ctx.interact = {"kind": "pfix", "label": "Turn on the street lights" if rules.grid_mode == 2 else "Fix the power", "i": 0, "need": -1.0}
		if not ctx.has("interact") and rules.has_grid and rules.grid and rules.grid_mode == 1 and world.power_box != Vector3.INF and _near(pos, world.power_box, 2.6):
			if rules.grid_wait > Rules.GRID_GAP - Rules.GRID_OFF_GAP: _text_hint = "The box is cooling — %d s" % ceili(rules.grid_wait - (Rules.GRID_GAP - Rules.GRID_OFF_GAP))
			else: ctx.interact = {"kind": "off", "label": "Switch off the power", "i": 0}
		if not ctx.has("interact") and not rules.powered:
			for i in world.gen_points.size():
				if not rules.gens[i].done and _near(pos, world.gen_points[i], 2.5):
					ctx.interact = {"kind": "rep", "label": "Repair", "i": i, "need": -1.0}
		for w in world.window_points:
			if _near(pos, w[0], 1.7): ctx.vault = {"kind": "vault", "c": w[0], "n": w[1]}
		if not ctx.has("vault"): _kerb_ctx(pos)
		for i in world.pallet_points.size():
			var pp: Array = world.pallet_points[i]
			if rules.pallets[i] == 1 and _near(pos, pp[0], 1.7):
				ctx.vault = {"kind": "vault", "c": pp[0], "n": Basis(Vector3.UP, pp[1]) * Vector3(0, 0, 1)}
		if my_state == "hurt" and me.item: ctx.item = {"kind": "heal", "n": my_name, "need": -1.0}
		if rules.powered:
			for i in world.gate_points.size():
				if world.is_outside_gate(i, pos): _ev({"k": "escape"})
		if rules.hatch >= 0 and _near(pos, world.hatch_points[rules.hatch], 1.5): _ev({"k": "escape", "h": true})
	elif driving:
		if rules.stun <= 0.0:
			ctx.interact = {"kind": "car_out", "label": "Get out"}
			if rules.carrying != "": # a survivor in the back: pull up at a hook and hang them straight away
				for i in world.hook_points.size():
					if rules.hook_user(i) == "" and _near(pos, world.hook_points[i], 4.0):
						ctx.interact = {"kind": "car_hook", "label": "Get out and hook", "i": i}
	elif sniping: # lying on the roof with the rifle: the one thing to do is get up
		ctx.interact = {"kind": "rifle_off", "label": "Stand up"}
	elif rules.stun <= 0.0:
		if rules.sniper and rules.carrying == "" and world.snipe_rifle != Vector3.INF and _near(pos, world.snipe_rifle, 2.6):
			ctx.interact = {"kind": "rifle", "label": "Take the rifle"}
			return
		if rules.carrying != "":
			for i in world.hook_points.size():
				if rules.hook_user(i) == "" and _near(pos, world.hook_points[i], 3.2):
					ctx.interact = {"kind": "hook", "label": "Hook", "i": i}
			if not ctx.has("interact") and car and _car_near(pos) > -2: # throw them in the back
				ctx.interact = {"kind": "car_in", "label": "Put them in the car", "p": _car_near(pos)}
			return
		for n in rules.s:
			if rules.s[n].hp == "down" and _near(pos, _pos_of(n), 2.7): ctx.interact = {"kind": "pickup", "label": "Pick up", "n": n}
		if not ctx.has("interact"):
			for i in world.locker_points.size():
				if _near(pos, world.locker_points[i][0], 2.1): ctx.interact = {"kind": "search", "label": "Search", "i": i}
		if not ctx.has("interact"):
			for i in world.pallet_points.size():
				if rules.pallets[i] == 1 and _near(pos, world.pallet_points[i][0], 2.4):
					ctx.interact = {"kind": "break", "label": "Break", "i": i, "need": 2.0}
		if not ctx.has("interact"):
			for w in world.window_points:
				if _near(pos, w[0], 1.7): ctx.interact = {"kind": "vault", "label": "Vault", "c": w[0], "n": w[1]}
		if not ctx.has("interact"): _door_ctx(pos)
		if not ctx.has("interact") and rules.has_grid and rules.grid and world.power_box != Vector3.INF and _near(pos, world.power_box, 2.6):
			if rules.grid_cuts >= Rules.GRID_CUTS: pass # both cuts used
			elif rules.grid_wait > 0.0: _text_hint = "The box is cooling — %d s" % ceili(rules.grid_wait)
			else: ctx.interact = {"kind": "cut", "label": "Cut the power (%d/%d)" % [rules.grid_cuts + 1, Rules.GRID_CUTS], "i": 0}
		if not ctx.has("interact") and car and _car_near(pos) > -2:
			ctx.interact = {"kind": "car_in", "label": "Get in", "p": _car_near(pos)}

## A doorway within reach becomes the interact button.
func _door_ctx(pos: Vector3) -> void:
	for i in world.door_points.size():
		if i >= world.door_nodes.size() or world.door_nodes[i] == null: continue
		if not _near(pos, world.door_points[i][0], 2.0): continue
		var shut: bool = rules.doors[i] if i < rules.doors.size() else false
		ctx.interact = {"kind": "door", "label": "Open the door" if shut else "Shut the door", "i": i, "on": not shut}
		return

# ---------------- actions ----------------
## The round camera's field of view for what I am doing now, plus «مجال الرؤية».
## Through the scope the view turns slower, as much slower as it is magnified (and a touch more).
func _look_k() -> float:
	return 1.0 / (float(NFSniper.ZOOMS[scope]) * 1.15) if (sniping and scope > 0) else 1.0

func _base_fov() -> float:
	if sniping and scope > 0: return (80.0 + Gfx.fov_add) / float(NFSniper.ZOOMS[scope])
	if driving: return (78.0 if car_inside else 74.0) + Gfx.fov_add
	if esc_i >= 0: return 74.0 + Gfx.fov_add
	return (80.0 if my_role == "killer" else 70.0) + Gfx.fov_add

func _press(id: String, touch: int) -> void:
	pop[id] = 0.16 # the button gives a little under the thumb
	match id:
		"sprint":
			sprint = not sprint
			if sprint: crouch = false
		"crouch":
			crouch = not crouch
			if crouch: sprint = false
		"nitro":
			if esc_i >= 0 and not esc_nitro.get(esc_i, false) and rules.roads[esc_i].drv == my_name:
				esc_nitro[esc_i] = true
				var ecn: NFCar = world.esc_cars[esc_i]
				ecn.nitro = NFCar.NITRO_TIME
				_shake(0.45)
				NFHaptics.pulse("impact")
				_flash("Nitro!")
		"gun": # up with it, then the shot once the arms are there (at once if it is already up)
			if my_gun and my_gun.visible and my_gun.raise < 0.8:
				gun_aim = maxf(gun_aim, 1.6)
				if gun_pending < 0.0: gun_pending = 0.16
			else: _shoot()
		"vanish":
			if Dev.unlocked and Dev.vanish_tool:
				vanished = not vanished
				_flash("Vanished — nobody can see you" if vanished else "You're visible again")
				NFHaptics.pulse("tick")
		"trap":
			if my_role == "killer" and trap_cd <= 0.0 and rules.carrying == "" and not driving:
				var rd_i := world.road_at(body.position)
				var xz := [snappedf(body.position.x, 0.01), snappedf(body.position.z, 0.01), snappedf(body.position.y, 0.01)]
				if rd_i >= 0:
					if int(rules.roads[rd_i].st) <= 1: _ev({"k": "spike", "i": rd_i, "p": xz})
				else: _ev({"k": "trap", "p": xz})
				trap_cd = 2.0
				NFHaptics.pulse("tick")
		"gear":
			if driving and car:
				car.gear = car.gear % NFCar.GEAR_TOP.size() + 1 # 1 -> 2 -> 3 -> back to 1
				_flash(["First gear — up to 40 km/h", "Second gear — up to 70 km/h", "Third gear — up to 90 km/h"][car.gear - 1])
				NFHaptics.pulse("hook")
		"next":
			var alive := _others_alive()
			if alive.size() > 0: spectating = alive[(alive.find(spectating) + 1) % alive.size()]
		"light":
			if battery > 0.0 or light_on:
				light_on = not light_on
				_sfx("torch_on" if light_on else "torch_off", null, -8.0)
		"attack":
			if sniping:
				_snipe_fire()
				return
			if driving: # at the wheel this button switches the camera: the seat or behind the car
				_car_view(not car_inside)
				return
			if attack_cd <= 0.0 and rules.stun <= 0.0 and rules.carrying == "" and not driving:
				attack_t = 1.1
				attack_cd = 2.4
				_sfx("swing%d" % randi_range(1, 2), null, -4.0, randf_range(0.95, 1.05))
				hit_sent = false
				rig.play("attack", 2.0)
		"power":
			if sniping: # x4 -> x8 -> off
				scope = (scope + 1) % NFSniper.ZOOMS.size()
				main_cam.fov = _base_fov()
				NFHaptics.pulse("tick")
				return
			if driving: # at the wheel this is the radio
				if car.radio:
					car.set_radio(not car.radio_on)
					_flash("Radio on — everyone hears it when you get close" if car.radio_on else "Radio off")
			else: _ev({"k": "power"})
		"sig": # open / close the three quick messages
			sig_open = not sig_open
			sig_close = 6.0
		"vault":
			if ctx.has("vault"): _start_vault(ctx.vault)
		_:
			var c = ctx.get(id)
			if c == null or not hold.is_empty(): return
			match str(c.kind):
				"struggle":
					_ev({"k": "struggle"})
					if Time.get_ticks_msec() > struggle_snd: # a grunt now and then, not on every tap
						struggle_snd = Time.get_ticks_msec() + randi_range(700, 1300)
						_sfx(("struggle_m%d" if chars.get(my_name, "") in MALE else "struggle_f%d") % randi_range(1, 3), null, -6.0)
				"locker_in": _ev({"k": "locker", "i": c.i, "on": true})
				"locker_out": _ev({"k": "locker", "i": c.i, "on": false})
				"pallet": _ev({"k": "pallet", "i": c.i})
				"cut":
					_ev({"k": "cut"})
					NFHaptics.pulse("tick")
				"off": # Halloween: a survivor plunges the map into the dark
					_ev({"k": "off"})
					NFHaptics.pulse("tick")
				"door": _ev({"k": "door", "i": c.i, "on": c.get("on", true)})
				"board": _ev({"k": "board", "i": c.i})
				"ladder": # the rescue helicopter's rope ladder
					_ev({"k": "ladder"})
					NFHaptics.pulse("grab")
				"disarm":
					_ev({"k": "disarm", "i": c.i})
					NFHaptics.pulse("tick")
				"pickup": _ev({"k": "pickup", "n": c.n})
				"kiss":
					_ev({"k": "kiss", "n": c.n})
					kiss_mode = 0.0
				"hook": _ev({"k": "hook", "i": c.i})
				"search": _ev({"k": "search", "i": c.i})
				"vault": _start_vault(c)
				"car_in":
					if int(c.get("p", -1)) >= 0: world.take_parked(int(c.p)) # a parked car: the two swap
					_enter_car()
				"car_out": _exit_car()
				"rifle": _snipe_start()
				"rifle_off": _snipe_stop()
				"car_hook": # the hook first, while the server still has me at the car, then out
					_ev({"k": "hook", "i": c.i})
					_exit_car()
				_:
					hold = {"btn": id, "kind": c.kind, "touch": touch, "t": 0.0, "need": float(c.get("need", -1.0)), "i": int(c.get("i", -1)), "n": str(c.get("n", ""))}
					if c.kind == "rep":
						next_skill = randf_range(3.0, 6.0)
						_ev({"k": "rep", "i": c.i, "on": true})
					elif c.kind == "heal": _ev({"k": "heal", "n": c.n, "on": true})
					elif c.kind == "pfix": _ev({"k": "pfix", "on": true})
					elif c.kind == "rescue": _ev({"k": "rescue", "n": c.n, "on": true})

func _end_hold() -> void:
	if hold.is_empty(): return
	if hold.kind == "rep": _ev({"k": "rep", "i": hold.i, "on": false})
	elif hold.kind == "heal": _ev({"k": "heal", "n": hold.n, "on": false})
	elif hold.kind == "pfix": _ev({"k": "pfix", "on": false})
	elif hold.kind == "rescue": _ev({"k": "rescue", "n": hold.n, "on": false})
	hold = {}
	skill = {}

func _update_hold(delta: float) -> void:
	if hold.is_empty(): return
	var c = ctx.get(hold.btn)
	if c == null or str(c.kind) != hold.kind or int(c.get("i", -1)) != hold.i or str(c.get("n", "")) != hold.n or stick_vec.length() > 0.3:
		_end_hold()
		return
	if hold.need > 0.0: # timed action: fires when the bar fills
		hold.t += delta
		if hold.t >= hold.need:
			if hold.kind == "break": _ev({"k": "break", "i": hold.i})
			hold = {}
	elif hold.kind == "rep":
		if skill.is_empty():
			next_skill -= delta
			if next_skill <= 0.0: skill = {"t": 0.0, "zone": randf_range(0.4, 0.85)}
		else:
			skill.t += delta
			if skill.t > 1.2:
				_ev({"k": "skill", "i": hold.i, "ok": false})
				_flash("Missed! The generator blew")
				skill = {}
				next_skill = randf_range(4.0, 8.0)

func _skill_tap() -> void:
	var ok: bool = absf(float(skill.t) / 1.2 - float(skill.zone)) <= 0.07
	_ev({"k": "skill", "i": hold.i, "ok": ok})
	_flash("Great!" if ok else "Wrong! The generator blew")
	skill = {}
	next_skill = randf_range(4.0, 8.0)

## Kuwait City: at the edge of a sidewalk, the median or the corniche the jump button lights up and
## hops you up onto it (or down off it). Walking up the kerb works too: it has a ramp of collision.
func _kerb_ctx(pos: Vector3) -> void:
	for k in world.kerbs:
		var c: Vector3 = k[0]
		var hw: float = float(k[1]) / 2.0
		if absf(pos.z - c.z) > float(k[2]) / 2.0: continue
		for sx in [-1.0, 1.0]:
			var ex: float = c.x + sx * hw
			if absf(pos.x - ex) < 0.9:
				ctx.vault = {"kind": "vault", "c": Vector3(ex, float(k[3]), pos.z), "n": Vector3(sx, 0, 0)}
				return

func _start_vault(c: Dictionary) -> void:
	if not vault.is_empty() or attack_t > 0.0: return
	_sfx("vault", null, -6.0)
	var center: Vector3 = c.c
	var normal: Vector3 = c.n
	var side := 1.0 if (body.position - center).dot(normal) >= 0.0 else -1.0
	var to := center - normal * side * 1.25
	to.y = center.y + 0.05
	var dur := 1.7 if my_role == "killer" else (0.7 if sprint else 1.0)
	if _perk() == "nimble": dur *= NIMBLE_VAULT # «Light Feet» (Crimson Adventurer)
	vault = {"from": body.position, "to": to, "t": 0.0, "dur": dur}

func _input(e: InputEvent) -> void:
	if not started or rules.over: return
	if loading != null: return # the loading screen eats everything
	if (e is InputEventScreenTouch or e is InputEventMouseButton) and e.pressed and Gfx.in_ui(e.position): return
	if (e is InputEventScreenTouch or e is InputEventMouseButton) and e.pressed and _dev_ui(e.position): return
	if Gfx.menu_open: return
	if (e is InputEventScreenTouch or e is InputEventMouseButton) and e.pressed:
		for sb in _sig_buttons():
			if (sb[0] as Rect2).has_point(e.position):
				_send_sig(int(sb[1]))
				return
	var half := get_viewport().get_visible_rect().size.x / 2.0
	if e is InputEventScreenTouch:
		if e.pressed:
			if big_map or Rect2(minimap.position, minimap.size).has_point(e.position): # tap the map to open / close it
				big_map = not big_map
				return
			if not skill.is_empty() and e.index != stick_id:
				_skill_tap()
				return
			for b in _buttons():
				if e.position.distance_to(b[0]) < b[1] + 8.0:
					_press(b[3], e.index)
					return
			if e.position.x < half and stick_id < 0:
				stick_id = e.index; stick_origin = e.position; stick_vec = Vector2.ZERO
			elif e.position.x >= half and look_id < 0:
				look_id = e.index
		else:
			if e.index == stick_id: stick_id = -1; stick_vec = Vector2.ZERO
			if e.index == look_id: look_id = -1
			if not hold.is_empty() and e.index == hold.touch: _end_hold()
	elif e is InputEventScreenDrag:
		if e.index == stick_id:
			stick_vec = ((e.position - stick_origin) / 70.0).limit_length(1.0)
			if stick_vec.length() < 0.12: stick_vec = Vector2.ZERO # dead zone
		elif e.index == look_id:
			yaw -= e.relative.x * 0.006 * Gfx.look_sens * _look_k()
			pitch = clampf(pitch - e.relative.y * 0.004 * Gfx.look_sens * _look_k(), -0.9, 0.5)
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * 0.003 * Gfx.look_sens * _look_k()
		pitch = clampf(pitch - e.relative.y * 0.003 * Gfx.look_sens * _look_k(), -0.9, 0.5)

func me_locker() -> int:
	return rules.s[my_name].locker if rules.s.has(my_name) else -1

## Hanging on the hook by the hands: lifted off the ground and still.
func _hook_pose(r: CharacterRig, dt: float) -> void:
	r.position.y = lerpf(r.position.y, world.hook_hang_y if world else 0.62, 1.0 - exp(-10.0 * dt)) # the gallows hangs you lower
	r.rotation = Vector3.ZERO
	r.play("hang", 0.6)

func _yaw_of(n: String) -> float:
	if n == my_name: return rig.rotation.y
	var r = remotes.get(n)
	return r.rig.rotation.y if r else 0.0

## Where a carried survivor sits: lying across the killer's arms, just in front of his chest.
func _carry_spot() -> Vector3:
	if _in_car(rules.killer): # slumped in his passenger seat
		return car.seat_spot()
	var ky := _yaw_of(rules.killer)
	return _pos_of(rules.killer) + Basis(Vector3.UP, ky) * Vector3(0, 0, 0.5)

## Is this player at the wheel of the car (me, or a remote killer whose `st` says "drive")?
func _in_car(n: String) -> bool:
	if car == null or n == "": return false
	if n == my_name: return driving
	return remotes.has(n) and remotes[n].anim == "drive"

# ---------------- per-frame ----------------
## The rescue helicopter: build it when the map is ready, fly it with the rules' row, and keep the
## climb smooth between the snapshots (the rules say how far up she is; this phone moves her there).
var climb_hands := {}
func _climbing(n: String) -> bool:
	return heli != null and int(rules.heli.st) == 3 and str(rules.heli.who) == n

func _step_heli(dt: float) -> void:
	if world == null or not world.ready_done or world.heli_spot == Vector3.INF: return
	if heli == null:
		heli = NFHeli.new()
		world.add_child(heli)
		var away := Vector3(world.heli_spot.x, 0, world.heli_spot.z)
		if world.map_id == "kuwait": away = Vector3(1, 0, -0.3) # in over the sea
		elif away.length() < 1.0: away = Vector3(1, 0, 0)
		heli.setup(world.heli_spot, away.normalized())
	var st := int(rules.heli.st)
	heli.step(dt, rules.heli, Rules.HELI_COME)
	if st == 3:
		heli_p = minf(heli_p + dt / Rules.CLIMB_TIME, float(rules.heli.p) + 0.06)
		heli_p = maxf(heli_p, float(rules.heli.p) - 0.06)
	elif st != 4:
		heli_p = 0.0
	if st != heli_st_seen:
		heli_st_seen = st

## A climber on the ladder: feet on the rungs between its foot and the top, facing it, both hands on
## the rungs above the head taking turns, the walk-made `climb` clip moving the legs.
func _climb_pose(key: String, nd: Node3D, rg: CharacterRig, _dt: float) -> void:
	var foot: Vector3 = heli.ladder_foot()
	var top: Vector3 = heli.ladder_top() - Vector3(0, 1.75, 0)
	var face: Vector3 = heli.ladder_face()
	var feet := foot.lerp(top, clampf(heli_p, 0.0, 1.0)) - face * 0.32
	nd.global_position = feet
	rg.position.y = 0.0
	rg.rotation = Vector3(0, atan2(face.x, face.z), 0)
	rg.play("climb" if rg.has("climb") else "walk", 0.8)
	var right := face.cross(Vector3.UP).normalized()
	var phase := fmod(heli_p * Rules.CLIMB_TIME * 1.6, 1.0) < 0.5
	var lh: Vector3 = heli.rung_at(feet.y + (1.95 if phase else 1.65)) - right * 0.19
	var rh: Vector3 = heli.rung_at(feet.y + (1.65 if phase else 1.95)) + right * 0.19
	rg.reach(lh, rh, feet + Vector3(0, 1.0, 0) - right * 0.6 - face * 0.4, feet + Vector3(0, 1.0, 0) + right * 0.6 - face * 0.4)
	climb_hands[key] = true

## «المسعف»: whoever picked it carries the first-aid kit (assets/props/medkit.glb) in the left hand,
## hanging from the handle, on every phone; put away while carried, hooked, down, in a car or a
## locker, out or dead.
var kits := {}
func _step_kits() -> void:
	if not ResourceLoader.exists("res://assets/props/medkit.glb"): return
	for n in rules.perk:
		if str(rules.perk[n]) != "aid": continue
		var rg: CharacterRig = rig if n == my_name else (remotes[n].rig if remotes.has(n) else null)
		var nd: Node3D = body if n == my_name else (remotes[n].node if remotes.has(n) else null)
		if rg == null or nd == null: continue
		if not kits.has(n):
			var ps := load("res://assets/props/medkit.glb") as PackedScene
			if ps == null: return
			var k := ps.instantiate() as Node3D
			add_child(k)
			kits[n] = k
		var kit: Node3D = kits[n]
		var st: String = rules.hp(n)
		var show: bool = nd.visible and rg.visible and st in ["ok", "hurt"] and rules.car_of(n) < 0 and int(rules.s[n].get("locker", -1)) < 0
		kit.visible = show
		if not show: continue
		var hand := rg.bone_at("LeftHand")
		# hanging straight down from the hand, turned with the body; the handle (its top) in the palm
		kit.global_transform = Transform3D(Basis(Vector3.UP, rg.global_rotation.y + PI / 2.0), hand + Vector3(0, -0.235, 0))

func _process(dt: float) -> void:
	if not started: return
	_step_guns(dt)
	if rules:
		_step_kits()
		_step_heli(dt)
		if not _climbing(my_name) and climb_hands.has("me") and rig:
			climb_hands.erase("me")
			rig.reach_clear()
	if rules and rules.has_grid and world.ready_done and world.grid_off == rules.grid: world.set_grid(rules.grid)
	if rules: world.round_t = rules.clock
	if rules and theme == "sunset": _sunset_calls()
	if loading != null: # the map is still being built: keep the tip screen up
		if not is_instance_valid(loading): loading = null
		else:
			loading.progress(float(world.build_step) / float(NightWorld.BUILD_STEPS))
			if world.ready_done and bot and not bot_baked: # her map is read while the tip screen is still up
				bot_baked = true
				bot.bake()
			elif world.ready_done and loading.shown > 0.9:
				loading.finish()
				Gfx.quiet(5.0) # the first seconds of play: shaders seen for the first time
	if bot and not bot_baked and world.ready_done:
		bot_baked = true
		bot.bake()
	if blood == null and world.ready_done: # the owner's blood models (scripts/blood.gd)
		blood = NFBlood.new()
		blood.name = "Blood"
		world.add_child(blood)
		blood.setup(world, [body.get_rid()])
	if catdog == null and blood != null: # the owner's cat and dog, once a round
		catdog = NFCatDog.new()
		catdog.name = "CatDog"
		world.add_child(catdog)
		catdog.setup(world, rules, blood, _cam_pos, _survivor_spots, [body.get_rid()])
	if gorilla == null and catdog != null: # then his gorilla tears the head off a horse and eats it
		gorilla = GorillaScript.new()
		gorilla.name = "Gorilla"
		world.add_child(gorilla)
		gorilla.setup(world, catdog, blood, _cam_pos, [body.get_rid()])
	if kiss == null and world.ready_done:
		kiss = KissScript.new()
		kiss.name = "Kiss"
		world.add_child(kiss)
		kiss.setup(_rig_of, _node_of, rules)
	if feast == null and blood != null:
		feast = FeastScript.new()
		feast.name = "Feast"
		world.add_child(feast)
		feast.setup(world, rules, blood, _cam_pos, _rig_of, _feast_bite)
	if ravens == null and world.ready_done and world.map_id != "garage": # the owner's ravens
		ravens = NFRavens.new()
		ravens.name = "Ravens"
		ravens.listeners = func() -> Array:
			var out := [body.global_position]
			for n in remotes: out.append((remotes[n].node as Node3D).global_position)
			return out
		world.add_child(ravens)
		ravens.setup(world.raven_perches(), 4 if Gfx.weak else 7, 3, int(rules.ev_at * 1000.0) + rules.ev_kind)
	flash_t = maxf(flash_t - dt, 0.0)
	for k in pop.keys(): pop[k] = maxf(float(pop[k]) - dt, 0.0)
	hit_t = maxf(hit_t - dt, 0.0)
	trap_cd = maxf(trap_cd - dt, 0.0)
	gun_cd = maxf(gun_cd - dt, 0.0)
	_step_fin(dt)
	snap_sent = maxf(snap_sent - dt, 0.0)
	sense_t += dt
	_feed_watch(dt)
	_shake_watch(dt)
	_beast_try_step(dt)
	if scare_t > 0.0: # short close-up of the killer's face, then back to my own camera
		scare_t -= dt
		if scare_t <= 0.0: _end_scare()
		else: _aim_scare()
	if sig_open:
		sig_close -= dt
		if sig_close <= 0.0: sig_open = false
	for i in range(sigs.size() - 1, -1, -1):
		sigs[i].t -= dt
		if sigs[i].t <= 0.0: sigs.remove_at(i)
	for i in boom_t.keys(): boom_t[i] = maxf(boom_t[i] - dt, 0.0)
	ui.queue_redraw()
	minimap.queue_redraw()
	var kpos := _pos_of(rules.killer) if rules.killer != "" else Vector3.ZERO
	var w := 1.0 - exp(-12.0 * dt)
	noise = 0.0
	if car == null and world.drive_car: car = world.drive_car
	if car and my_role == "killer" and not car_told and loading == null:
		car_told = true
		_flash("Your car is waiting on the roof — go up the ramp to it" if world.map_id == "garage" else "Your car is close — get in and run them down")
	_car_pass(dt)
	if car and not driving and not (rules.killer != "" and remotes.has(rules.killer) and remotes[rules.killer].anim == "drive"):
		car.driven = false # nobody at the wheel: lights off, it stays where it was left
		car.park(dt)
	_esc_cars(dt)
	_tools(dt)
	for n in remotes:
		var r = remotes[n]
		var st: String = rules.hp(n)
		var anim: String = r.anim
		var target: Vector3 = r.pos
		var lift := 0.0
		var face: float = r.yaw
		var seated: bool = st == "carried" and _in_car(rules.killer)
		r.node.scale = Vector3.ONE * (NFCar.VICTIM_SCALE if seated else 1.0)
		if seated: # in his passenger seat, slumped, every part of them inside the car
			target = _carry_spot(); anim = "slump"; face = car.rotation.y
		elif st == "carried":
			target = _carry_spot(); lift = 0.12; anim = "carried"
			face = _yaw_of(rules.killer) + PI / 2.0
		elif st == "hooked" or _kept(n): # (what «الوحش» left of them stays on his hook)
			target = world.hook_points[_hook_at(n)] + Vector3(0, 0, 0.9)
		elif anim == "drive": pass # seated at the wheel (placed below, once the car has moved)
		elif anim in ["edrive", "eride"]: anim = "drive" # in an escape car (placed below)
		elif st == "dead" or (st == "down" and anim != "crawl"): anim = "dying"
		elif st == "hurt" and anim == "idle": anim = "injured"
		var was: Vector3 = r.node.position
		r.node.position = r.node.position.lerp(target, w)
		# how fast they really move here: the legs keep up with it (a faster player — the developer
		# tools' speed — runs with quicker strides instead of gliding over the ground)
		var gone := Vector2(r.node.position.x - was.x, r.node.position.z - was.z).length()
		r.spd = lerpf(float(r.get("spd", 0.0)), gone / maxf(dt, 0.001), 1.0 - exp(-8.0 * dt))
		var stride := 1.0
		if NATURAL.has(anim) and float(r.spd) > 0.3:
			stride = snappedf(clampf(float(r.spd) / float(NATURAL[anim]), 0.75, 2.6), 0.05)
		elif anim == "carry" and float(r.spd) > 0.3:
			stride = snappedf(clampf(float(r.spd) / 1.4, 0.8, 2.6), 0.05)
		if anim == "crawl" and float(r.spd) < 0.15: stride = 0.0001 # lying still (the sniper aiming)
		if r.role == "killer" and rules.sniper: # her rifle, in front of her while she lies on the roof
			var lying: bool = anim == "crawl"
			if lying and r.get("rifle") == null:
				r.rifle = NFSniper.rifle()
				r.rig.add_child(r.rifle)
				r.rifle.position = Vector3(0.12, 0.3, 0.75)
				r.rifle.scale = Vector3.ONE * 1.1
			if r.get("rifle") != null: (r.rifle as Node3D).visible = lying and r.node.visible
			if world.rifle_stand: world.rifle_stand.visible = not lying
		if st == "hooked" or _kept(n):
			_hook_pose(r.rig, dt)
		elif _climbing(n): # up the helicopter's rope ladder, on every phone the same
			_climb_pose(n, r.node, r.rig, dt)
		else:
			if climb_hands.has(n):
				climb_hands.erase(n)
				r.rig.reach_clear()
			r.rig.position.y = lerpf(r.rig.position.y, lift, w)
			r.rig.rotation = Vector3(0, lerp_angle(r.rig.rotation.y, face, w), 0)
			_lean_rig(r.rig, dt, float(r.spd), anim)
			if hit_anim.get(n, 0.0) <= 0.0 and not _kissing(n): r.rig.play(anim, stride) # (a kiss poses them itself)
		_update_bleed(r.bleed, st == "hooked", dt)
		# far away or behind the camera: the skeleton is posed less often (see CharacterRig.set_anim_rate)
		var vc := get_viewport().get_camera_3d()
		if vc and is_instance_valid(r.rig):
			var rp: Vector3 = (r.node as Node3D).global_position + Vector3(0, 1.0, 0)
			var dc := vc.global_position.distance_to(rp)
			var seen := vc.is_position_in_frustum(rp) or dc < 4.0
			(r.rig as CharacterRig).set_anim_rate(1 if (seen and dc < 30.0) else (2 if (seen and dc < 70.0) else (4 if seen else 6)))
		# women gasp "oof" now and then while limping around injured
		if st == "hurt" and r.node.visible and anim in ["walk", "injured", "run"]:
			oof_t[n] = oof_t.get(n, 1.5) - dt
			if oof_t[n] <= 0.0:
				oof_t[n] = randf_range(2.2, 4.0)
				var gr := ("groan%d" if chars.get(n, "") in MALE else "oof%d") % randi_range(1, 3)
				_sfx(gr, r.node.position + Vector3(0, 1.5, 0), 2.0)
		r.node.visible = st != "escaped" and not (rules.s.has(n) and rules.s[n].locker >= 0)
		if _kept(n): r.node.visible = true
		if r.role == "killer" and car and (r.anim == "drive") != car_remote: # he got in / out: the door opens and shuts here too
			car_remote = r.anim == "drive"
			if car_remote and Vector2(car.position.x - r.pos.x, car.position.z - r.pos.z).length() > 2.5:
				world.take_parked(world.nearest_parked(r.pos, 3.0)) # she took a parked car: the same swap here
			car.begin("in" if car_remote else "out")
		if r.role == "killer" and car: car.set_radio(r.lit) # his `f` is the radio switch, in the car or out of it
		if r.role == "killer" and car and r.anim == "drive": # at the wheel: the car follows him, she sits in it
			car.driven = true
			car.follow(r.pos, r.yaw, dt)
			r.node.visible = car.seated() > 0.55
			r.node.position = car.driver_spot()
			r.node.scale = Vector3.ONE * NFCar.VICTIM_SCALE
			r.rig.rotation = Vector3(0, car.rotation.y, 0)
			var gp := car.grips()
			r.rig.reach(gp[0], gp[1], gp[2], gp[3])
		elif r.role == "killer":
			r.rig.reach_clear()
		var rc := rules.car_of(n)
		if r.role == "survivor" and rc >= 0 and rc < world.esc_cars.size(): # in an escape car: at the wheel or beside it
			var ec: NFCar = world.esc_cars[rc]
			var seat: int = (rules.roads[rc].who as Array).find(n)
			r.node.visible = seat >= 0 and seat < ec.seats and ec.seated() > 0.4 # six seats: everyone in it shows
			r.node.scale = Vector3.ONE * NFCar.VICTIM_SCALE
			r.node.position = ec.seat_at(seat)
			r.rig.position = Vector3.ZERO
			r.rig.rotation = Vector3(0, ec.rotation.y, 0)
			r.rig.play("drive")
			if seat == 0:
				var eg := ec.grips()
				r.rig.reach(eg[0], eg[1], eg[2], eg[3])
			else: r.rig.reach_clear()
		elif r.role == "survivor" and (r.get("gun") == null or not (r.gun as NFGun).visible):
			if st == "hurt" and r.node.visible: _wound_pose(r.rig, true, false) # a hand on the wound
			else:
				r.rig.set_meta("hurt", false)
				if r.rig.get_meta("clutch", false): r.rig.set_meta("clutch", false)
				r.rig.reach_clear() # (their pistol holds the arms otherwise)
		if r.role == "survivor":
			var bk := 0
			if r.node.visible and rules.car_of(n) < 0: bk = 1 if st == "hurt" else (2 if st == "down" else 0)
			_blood_trail(n, r.node.position, bk)
		if r.torch: r.torch.visible = r.lit and st in ["ok", "hurt"] and rules.car_of(n) < 0
		if bool(r.get("v", false)): # vanished (developer tools on their phone): nothing of them shows here
			r.node.visible = false
			if r.torch: r.torch.visible = false
		# footsteps are 3D and depend on the ground; the killer also gets scratch marks and the detection indicator
		var moving: bool = r.node.visible and anim in ["run", "walk", "injured", "carry"]
		var ghost: bool = rules.perk.get(n, "") == "ghost" and my_role == "killer" # «خطوة شبح»
		var sk := ""
		if r.role == "killer":
			sk = "beast" if chars.get(n, "killer") == "killer2" else "killer"
			if sk == "killer" and my_role == "survivor" and body.position.distance_to(r.node.position) < TERROR_RADIUS: sk = "approach" # coming for me
		elif st == "hurt": sk = "hurt"
		_steps(r.steps, r.node.position, moving, anim == "run", 4.0 if r.role == "killer" else (-14.0 if ghost else 0.0), sk)
		if anim == "run" and r.node.visible and my_role == "killer" and r.role == "survivor" and not ghost:
			r.step -= dt
			if r.step <= 0.0:
				r.step = 0.3
				_drop_mark(r.node.position)
			var to: Vector3 = r.node.position - body.position
			var lvl := clampf(1.0 - to.length() / 26.0, 0.0, 1.0)
			if lvl > noise:
				noise = lvl
				noise_dir = wrapf(atan2(to.x, -to.z) + yaw, -PI, PI)
	if Dev.unlocked or my_role == "survivor": _update_esp() # the team's names and see-through (and the hidden tools)
	for m in marks:
		if m.t > 0.0:
			m.t -= dt
			m.node.scale = Vector3.ONE * clampf(m.t / 2.0, 0.0, 1.0)
			if m.t <= 0.0: m.node.visible = false
	# world visuals + sounds follow the rules state
	for i in rules.gens.size():
		var g: Dictionary = rules.gens[i]
		if g.done: world.set_gen_done(i)
		var run: AudioStreamPlayer3D = gen_audio[i]
		var ending: bool = g.p >= 0.85 and not g.done # about to start: loud engine + flickering lamps
		var want_run: bool = g.p > 0.01
		if want_run != run.playing:
			if want_run: run.play()
			else: run.stop()
		run.volume_db = 4.0 if ending else (-7.0 if g.done else lerpf(-18.0, -8.0, g.p / 0.85))
		run.pitch_scale = 1.0 if (ending or g.done) else lerpf(0.75, 0.95, g.p / 0.85)
		# the killer only notices the flicker from within 8 m
		if i < world.gen_nodes.size(): world.gen_nodes[i].blink = ending and (my_role != "killer" or body.position.distance_to(world.gen_points[i]) < 8.0)
	for i in rules.gates.size(): world.set_gate_state(i, rules.gates[i].open)
	if rules.hatch != last_hatch:
		last_hatch = rules.hatch
		world.set_hatch(rules.hatch)
		if rules.hatch >= 0:
			_flash("An escape hatch opened! Find it" if my_role == "survivor" else "An escape hatch opened — don't let them reach it")
	world.set_market_dark(rules.killer != "" and world.in_market(kpos))
	world.set_killer_at(kpos if rules.killer != "" else Vector3(9999, 0, 9999))
	_round_event(dt)
	_adhan()
	# the countdown before the gates open: blinking gate lights, a tick each second, one call at the start
	if rules.gate_t >= 0.0 and not rules.powered:
		world.gate_warn(rules.gate_t)
		if gate_count_last < 0.0:
			_flash("Generators done — the gates open in %d seconds" % ceili(rules.gate_t))
			for g in world.gate_points: _sfx("gate", g[0] + Vector3(0, 3, 0), 2.0)
		if gate_count_last >= 0.0 and ceili(rules.gate_t) < ceili(gate_count_last): NFHaptics.pulse("tick")
		gate_count_last = rules.gate_t
	elif gate_count_last >= 0.0:
		gate_count_last = -1.0
		if not rules.powered: world.gate_warn(-1.0)
	if rules.powered and not was_powered:
		was_powered = true
		world.set_blood_moon(true)
		world.set_sirens(true) # the police hear the gates open: every siren starts at once
		for g in world.gate_points: _sfx("gate", g[0] + Vector3(0, 3, 0), 8.0)
		_sfx("gate", null, -12.0)
		doom_music.play()
		if my_role == "survivor": # past each gate an escape car waits; the last gate is 600 m down the road
			_flash("The gates are open — get in the escape car behind the gate; the last gate is 600 m on")
		else: _flash("The gates are open — they'll escape by car behind the gate, chase them in yours")
	# survivors feel the killer coming: heartbeat inside the terror radius, heavy breathing when he is very close
	danger = 0.0
	var kdist := 999.0
	# while she drives, none of the "she is close" sounds: no heartbeat, breathing or chase music on
	# anyone's phone (the engine and the radio are what give the car away). On foot, all of it as before.
	var k_driving: bool = driving or (car_remote and my_role != "killer")
	# a vanished killer (the developer tools) gives nothing away either: no heartbeat, no breathing, no chase
	var k_gone: bool = remotes.has(rules.killer) and bool(remotes[rules.killer].get("v", false))
	if my_role == "survivor" and rules.killer != "" and remotes.has(rules.killer) and my_state in ["ok", "hurt", "down", "hooked"] and not k_driving and not k_gone:
		kdist = body.position.distance_to(kpos)
		danger = clampf(1.0 - kdist / TERROR_RADIUS, 0.0, 1.0)
	if grade: # the screen tightens and reddens as he closes in
		var pulse: float = danger * (0.55 + 0.45 * sin(Time.get_ticks_msec() / 1000.0 * 4.0))
		if my_state in ["down", "hooked"]: pulse = maxf(pulse, 0.5)
		(grade.material as ShaderMaterial).set_shader_parameter("pulse", clampf(pulse, 0.0, 1.0))
	if danger > 0.05 and my_state in ["ok", "hurt", "down"]: # one small buzz per heartbeat
		heart_beat -= dt * lerpf(1.1, 2.2, danger)
		if heart_beat <= 0.0:
			heart_beat = 1.0
			NFHaptics.pulse_scaled("beat", danger)
	var fade := 1.0 - exp(-4.0 * dt)
	var want_heart: AudioStream = sounds.get("heart_fast") if danger > 0.6 and sounds.get("heart_fast") else sounds.heart
	if heart.stream != want_heart:
		heart.stream = want_heart
		if danger > 0.0: heart.play()
	if danger > 0.0 and not heart.playing: heart.play()
	heart.volume_db = lerpf(heart.volume_db, lerpf(-16.0, 4.0, danger) if danger > 0.0 else -60.0, fade)
	heart.pitch_scale = lerpf(0.92, 1.12, danger) if heart.stream == sounds.heart else lerpf(0.95, 1.1, danger)
	if heart.playing and danger <= 0.0 and heart.volume_db < -50.0: heart.stop()
	var hiding: bool = my_role == "survivor" and rules.s.has(my_name) and rules.s[my_name].locker >= 0
	var panting: bool = danger > 0.55 or (hiding and danger > 0.2) or (my_state == "hurt" and my_role == "survivor")
	var male: bool = chars.get(my_name, "") in MALE # the owner: men and women each have their own breathing
	var want_breath: AudioStream = sounds.get("breath_m" if male else "breath_f", sounds.breath)
	if hiding and sounds.get("breath_hide"): want_breath = sounds.breath_hide
	elif my_state == "hurt" and danger <= 0.55: want_breath = sounds.get("breath_hurt_m" if male else "breath_hurt", want_breath)
	if breath.stream != want_breath:
		breath.stream = want_breath
		if panting: breath.play()
	if panting and not breath.playing: breath.play()
	var b_db := lerpf(-8.0, 3.0, (danger - 0.55) / 0.45) if danger > 0.55 else (-12.0 if hiding else -14.0)
	breath.volume_db = lerpf(breath.volume_db, b_db if panting else -60.0, fade)
	_step_beds(dt, danger)
	if breath.playing and not panting and breath.volume_db < -50.0: breath.stop()
	# chase music: the killer sees a survivor / a survivor is seen by the killer
	los_t -= dt
	if los_t <= 0.0:
		los_t = 0.2
		if k_driving or vanished: # vanished (the developer tools): no proximity music on my own phone either
			pass
		elif my_role == "killer":
			var look := Vector3(-sin(yaw), 0, -cos(yaw))
			for n in remotes:
				var r = remotes[n]
				if r.role != "survivor" or not r.node.visible or not rules.free_now(n): continue
				var to: Vector3 = r.node.position - body.position
				if to.length() < 24.0 and look.dot(to.normalized()) > 0.35 and _line_of_sight(r.node.position): chase_hold = 6.0
				elif to.length() < CHASE_NEAR: chase_hold = maxf(chase_hold, 3.0) # one of them is right by her
		elif my_state in ["ok", "hurt", "down"] and me_locker() < 0 and (kdist < CHASE_NEAR or (kdist < 26.0 and _line_of_sight(kpos))):
			chase_hold = maxf(chase_hold, 4.0) # she is close (on foot): the music, seen or not
	chase_hold = 0.0 if (k_driving or vanished) else maxf(chase_hold - dt, 0.0)
	var chasing := chase_hold > 0.0 and not rules.over
	_beast_cry(chasing, dt)
	if chasing and not chase_music.playing: chase_music.play()
	chase_music.volume_db = lerpf(chase_music.volume_db, -6.0 if chasing else -60.0, 1.0 - exp(-2.5 * dt))
	if chase_music.playing and not chasing and chase_music.volume_db < -50.0: chase_music.stop()
	amb.volume_db = lerpf(amb.volume_db, -30.0 if chasing else -13.0, fade)
	# the end of the world: the moon grows in the sky for two minutes, then lands
	if rules.powered and rules.doom >= 0.0:
		var near := 1.0 - rules.doom / Rules.DOOM_TIME
		world.set_moon_near(near)
		var rumble := clampf((near - 0.75) / 0.25, 0.0, 1.0)
		if impact_t >= 0.0: rumble = maxf(1.0 - impact_t / 3.0, 0.0) * 2.5
		if main_cam:
			main_cam.h_offset = randf_range(-1.0, 1.0) * 0.07 * rumble
			main_cam.v_offset = randf_range(-1.0, 1.0) * 0.07 * rumble
		if near > 0.45: NFHaptics.pulse_scaled("rumble", (near - 0.45) / 0.55) # it keeps getting closer
		if rules.doom <= 0.0 and impact_t < 0.0:
			impact_t = 0.0
			_sfx("impact", null, 2.0)
			NFHaptics.pulse("impact")
			_shake(1.0)
			_flash("The moon hit the ground")
	if impact_t >= 0.0: impact_t += dt
	amb.volume_db = minf(amb.volume_db, -40.0) if doom_music.playing else amb.volume_db
	if rules.over and results == null and (impact_t < 0.0 or impact_t > 3.5): _show_results()

func _physics_process(delta: float) -> void:
	if not started: return
	for n in hit_anim.keys(): # the one-shot flinch, if the clip exists
		hit_anim[n] = hit_anim[n] - delta
		if hit_anim[n] <= 0.0: hit_anim.erase(n)
	if offline:
		for e in rules.tick(delta): _on_event(e)
	if bot and world.ready_done: bot.step(delta)
	match_time += delta
	escape_banner = maxf(escape_banner - delta, 0.0)
	my_state = rules.hp(my_name) if my_role == "survivor" else "ok"
	if my_state == "escaped" and last_state != "escaped":
		escape_banner = 4.0
		slowmo = 1.1
		NFHaptics.pulse("escape")
	if my_state == "carried" and last_state != "carried": # he just picked me up
		_start_scare()
		NFHaptics.pulse("grab")
		_shake(0.6)
	if offline and my_role == "survivor" and my_state in ["escaped", "dead"] and escape_banner <= 0.0 and last_state == my_state:
		rules.over = true # trial mode: the round is just me (after the banner has shown)
	# out of the round (escaped or dead): watch a teammate who is still inside
	if my_state in ["escaped", "dead"]:
		var alive := _others_alive()
		if not (spectating in alive): spectating = alive[0] if alive.size() > 0 else ""
	else: spectating = ""
	var me: Dictionary = rules.s.get(my_name, {})
	var locker: int = me.locker if not me.is_empty() else -1
	var was_in := esc_i
	esc_i = rules.car_of(my_name) if my_role == "survivor" else -1
	if esc_i >= world.esc_cars.size(): esc_i = -1
	if esc_i != was_in:
		if was_in >= 0: _esc_leave(was_in)
		if esc_i >= 0: _esc_enter(esc_i)
	_update_ctx()
	_update_hold(delta)
	attack_t = maxf(attack_t - delta, 0.0)
	attack_cd = maxf(attack_cd - delta, 0.0)
	boost_t = maxf(boost_t - delta, 0.0)
	_camera_feel(delta)
	# states where I don't control my body
	var pinned := true
	if spectating != "":
		body.position = _pos_of(spectating)
		rig.visible = false
	elif my_state == "carried" and _in_car(rules.killer): # thrown into his passenger seat
		body.position = _carry_spot()
		rig.position.y = 0.0
		rig.rotation.y = car.rotation.y
		rig.play("slump")
	elif my_state == "carried":
		body.position = _carry_spot()
		rig.position.y = 0.12
		rig.rotation.y = _yaw_of(rules.killer) + PI / 2.0
		rig.play("carried")
	elif my_state == "dead" and _kept(my_name): # what «الوحش» left of me, on his hook
		body.position = world.hook_points[_hook_at(my_name)] + Vector3(0, 0, 0.9)
		_hook_pose(rig, delta)
	elif my_state == "hooked":
		if last_state != "hooked": hook_cam = 2.6
		body.position = world.hook_points[me.hook_i] + Vector3(0, 0, 0.9)
		_hook_pose(rig, delta)
	elif _climbing(my_name): # up the helicopter's rope ladder (the rules count the climb)
		_climb_pose("me", body, rig, delta)
	elif esc_i >= 0:
		_esc_ride(delta)
	elif locker >= 0:
		body.position = world.locker_points[locker][0]
	elif driving:
		_drive(delta)
	elif not vault.is_empty():
		vault.t += delta
		var f: float = clampf(vault.t / vault.dur, 0.0, 1.0)
		var p: Vector3 = (vault.from as Vector3).lerp(vault.to, f)
		p.y += sin(f * PI) * 1.15
		body.position = p
		var dv: Vector3 = (vault.to as Vector3) - (vault.from as Vector3)
		rig.rotation.y = atan2(dv.x, dv.z)
		rig.play("vault", 1.17 / float(vault.dur))
		if f >= 1.0: vault = {}
	else:
		pinned = false
	if my_state != "carried" and my_state != "hooked" and not driving and esc_i < 0: rig.position.y = 0.0
	rig.scale = Vector3.ONE * (NFCar.VICTIM_SCALE if ((my_state == "carried" and _in_car(rules.killer)) or driving or esc_i >= 0) else 1.0)
	if last_state == "hooked" and my_state != "hooked": rig.rotation = Vector3.ZERO
	if last_locker >= 0 and locker < 0 and my_state in ["ok", "hurt"]: # stepped out of a locker
		var lp: Array = world.locker_points[last_locker]
		body.position = lp[0] + Basis(Vector3.UP, lp[1]) * Vector3(0, 0, 1.1)
	last_locker = locker
	if my_role == "survivor": rig.visible = locker < 0 and my_state != "escaped" and spectating == "" and (esc_i < 0 or esc_vis)
	cshape.disabled = pinned or my_state in ["dead", "escaped"]
	if pinned:
		body.velocity = Vector3.ZERO
	else:
		_move(delta)
	if flash_light: # flashlight follows where I look; the battery drains while it is on
		if light_on:
			battery = maxf(battery - delta * 100.0 / 150.0, 0.0)
			if battery <= 0.0 or not (my_state in ["ok", "hurt"]) or locker >= 0: light_on = false
		flash_light.visible = light_on
		flash_light.rotation = Vector3(pitch * 0.7 + 0.05, yaw, 0)
		if light_on and battery < 12.0: flash_light.light_energy = 7.0 * (0.4 + 0.6 * absf(sin(Time.get_ticks_msec() / 90.0))) # dying battery flickers
		else: flash_light.light_energy = 7.0
	_update_bleed(my_bleed, my_state == "hooked", delta)
	var spd := Vector2(body.velocity.x, body.velocity.z).length()
	if my_state == "hurt" and spd > 0.5 and not pinned:
		oof_t[my_name] = oof_t.get(my_name, 1.5) - delta
		if oof_t[my_name] <= 0.0:
			oof_t[my_name] = randf_range(2.2, 4.0)
			_sfx(("groan%d" if chars.get(my_name, "") in MALE else "oof%d") % randi_range(1, 3), null, -3.0)
	var my_sk := ""
	if my_role == "killer": my_sk = "beast" if chars.get(my_name, "killer") == "killer2" else "killer"
	elif my_state == "hurt": my_sk = "hurt"
	_steps(my_steps, body.position, not pinned and spd > 0.4 and not crouch and body.is_on_floor(), spd > 2.6, -8.0, my_sk)
	last_state = my_state
	if not offline and spectating == "" and my_state != "escaped": # spectators stop reporting a position
		send_t -= delta
		if send_t <= 0.0:
			send_t = 1.0 / 15.0
			var p := body.position
			Net.send({"t": "st", "p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(rig.rotation.y, 0.01)], "a": "drive" if driving else (("edrive" if rules.roads[esc_i].drv == my_name else "eride") if esc_i >= 0 else rig.current),
					"f": 1 if (light_on or (my_role == "killer" and car != null and car.radio_on)
						or (esc_i >= 0 and (world.esc_cars[esc_i] as NFCar).nitro > 0.0)) else 0, "v": 1 if vanished else 0,
					"g": (0 if my_gun == null or not my_gun.visible else (2 if gun_aim > 0.0 else 1)), "gp": snappedf(_gun_pitch(), 0.05)}) # the killer has no torch: f is his radio

# ---------------- the killer's car ----------------
func _enter_car() -> void:
	if car == null or driving or my_role != "killer": return
	_end_hold()
	attack_t = 0.0
	vault = {}
	driving = true
	car_leaving = 0.0
	car.driven = true
	car.begin("in") # door open, in, door shut, key
	car.speed = 0.0
	body.velocity = Vector3.ZERO
	body.position = car.position
	arm.add_excluded_object(car.get_rid())
	_car_view(car_inside)
	yaw = car.rotation.y + PI
	pitch = -0.08 if car_inside else -0.26
	car_look = 1.0
	NFHaptics.pulse("hook")

## Getting out: the key comes out and the door opens; he steps out half a second later.
func _exit_car() -> void:
	if not driving or car_leaving > 0.0: return
	car_leaving = NFCar.SEQ_OUT.out
	car.begin("out")

## My own body at the wheel: in the seat, hands on the rim (NFReach). Seen from the chase camera;
## from the seat it is hidden on my phone (the camera is where her head is) and the gloves show
## instead. Everyone else always sees her sitting there.
func _sit_driver() -> void:
	rig.visible = not car_inside and car.seated() > 0.55 and (car_leaving <= 0.0 or car_leaving > 0.2)
	rig.scale = Vector3.ONE * NFCar.VICTIM_SCALE
	rig.position = car.driver_spot() - body.global_position
	rig.rotation = Vector3(0, car.rotation.y, 0)
	rig.play("drive")
	var gp := car.grips()
	rig.reach(gp[0], gp[1], gp[2], gp[3])

## The car I am standing by: -1 the driving car, 0.. a parked car (world.parked), -2 none.
func _car_near(pos: Vector3) -> int:
	var d_car := 99.0
	if _near(pos, car.position, 3.6): d_car = Vector2(pos.x - car.position.x, pos.z - car.position.z).length()
	var i := world.nearest_parked(pos, 3.6)
	if i >= 0:
		var q := world.parked_at(i)
		if Vector2(pos.x - q.x, pos.z - q.z).length() < d_car: return i
	return -1 if d_car < 99.0 else -2

## Where the camera is while he climbs in or out: outside the open driver's door.
func _door_eye() -> Vector3:
	return car.global_transform * Vector3(1.55, 1.7, 0.3)

## Out on the driver's side if there is room, then the other side, then behind or in front.
func _leave_car() -> void:
	if not driving: return
	car_leaving = 0.0
	rig.reach_clear() # her own body back to first person: hidden, full size
	rig.visible = false
	rig.position = Vector3.ZERO
	rig.scale = Vector3.ONE
	rig.play("idle")
	var spot := car.position + Vector3(0, 2.4, 0) # nowhere else: climb out onto the roof
	var space := world.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.exclude = [car.get_rid(), body.get_rid()]
	for off in [Vector3(1.9, 0, 0.4), Vector3(-1.9, 0, 0.4), Vector3(0, 0, -3.4), Vector3(0, 0, 3.5), Vector3(2.7, 0, -1.6), Vector3(-2.7, 0, -1.6)]:
		var p: Vector3 = car.global_transform * off
		var ray := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.4, 0), p + Vector3(0, -3.0, 0))
		ray.exclude = [car.get_rid(), body.get_rid()]
		var g := space.intersect_ray(ray)
		if g.is_empty(): continue
		var at: Vector3 = g.position
		q.transform = Transform3D(Basis(), at + Vector3(0, 1.0, 0))
		if space.intersect_shape(q, 1).is_empty():
			spot = at + Vector3(0, 0.05, 0)
			break
	driving = false
	car.driven = false
	car.speed = 0.0
	car.velocity = Vector3.ZERO
	body.position = spot
	body.velocity = Vector3.ZERO
	arm.remove_excluded_object(car.get_rid())
	car.show_inside(false)
	cam_pivot.position = Vector3(0, 1.6, 0)
	arm.spring_length = 0.0 # back to first person
	arm.position.y = 0.2
	main_cam.fov = 80.0 + Gfx.fov_add
	yaw = car.rotation.y + PI

## In the driver's seat looking out over the bonnet, or behind the car.
func _car_view(seat: bool) -> void:
	car_inside = seat
	car.show_inside(seat)
	arm.spring_length = 0.0 if seat else 6.8
	arm.position.y = 0.0 if seat else 1.0
	main_cam.fov = (78.0 if seat else 74.0) + Gfx.fov_add
	if not seat: cam_pivot.position = Vector3(0, 1.6, 0)

## At the wheel: the stick is the pedal and the steering (up = gas, down = brake and reverse,
## sideways = steer), and the camera rides behind. A survivor in the car's way is hit.
func _drive(delta: float) -> void:
	var move := stick_vec
	if move == Vector2.ZERO:
		move = Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	if rules.over or rules.stun > 0.0: move = Vector2.ZERO # a dropped pallet stops the car too
	if car.seated() < 1.0 or car_leaving > 0.0: move = Vector2.ZERO # not until the door is shut
	car.driven = true
	car.drive(-move.y, move.x, delta)
	body.position = car.position
	body.velocity = car.velocity
	rig.rotation.y = car.rotation.y # what the others get as my yaw: the car's heading
	speedo_kmh = lerpf(speedo_kmh, absf(car.speed) * 3.6, 1.0 - exp(-10.0 * delta)) # the needle, eased
	_sit_driver()
	if car_inside:
		# climbing in: from outside the open door to the seat; getting out: the other way
		var k := smoothstep(0.2, 0.85, car.seated())
		if car_leaving > 0.0: k = smoothstep(0.0, 1.0, car_leaving / NFCar.SEQ_OUT.out)
		cam_pivot.position = _door_eye().lerp(car.eye(), k) - body.global_position
	if car_leaving > 0.0:
		car_leaving -= delta
		if car_leaving <= 0.0:
			_leave_car()
			return
	if car.bump > 0.0: # crashed into something
		_shake(0.25 + car.bump * 0.7)
		NFHaptics.pulse_scaled("hit", car.bump)
		car.bump = 0.0
	# the camera swings back behind the car a moment after I stop looking around
	car_look += delta
	if look_id >= 0: car_look = 0.0
	if car_look > 0.9:
		var k := 1.0 - exp(-2.5 * delta)
		yaw = lerp_angle(yaw, car.rotation.y + PI, k)
		pitch = lerpf(pitch, -0.08 if car_inside else -0.26, k)
	for n in ram_cd.keys():
		ram_cd[n] -= delta
		if ram_cd[n] <= 0.0: ram_cd.erase(n)
	esc_ram_cd = maxf(esc_ram_cd - delta, 0.0)
	if esc_ram_cd <= 0.0 and not rules.over and car.seated() >= 1.0: # her car into an escape car: caught
		var inv0 := car.global_transform.affine_inverse()
		for i in mini(world.esc_cars.size(), rules.roads.size()):
			if int(rules.roads[i].st) != 1: continue
			var ep: Vector3 = inv0 * (world.esc_cars[i] as NFCar).global_position
			if absf(ep.x) < 2.7 and absf(ep.z) < 5.3 and absf(ep.y) < 3.0:
				esc_ram_cd = 2.0
				_ev({"k": "ram", "i": i})
				_shake(0.7)
				NFHaptics.pulse("hit")
				break
	if absf(car.speed) < NFCar.RAM_SPEED or rules.stun > 0.0 or rules.over: return
	var inv := car.global_transform.affine_inverse()
	for n in remotes:
		var r = remotes[n]
		if r.role != "survivor" or not rules.free_now(n) or ram_cd.has(n): continue
		var lp: Vector3 = inv * (r.node.position as Vector3)
		if absf(lp.x) < 1.35 and absf(lp.z) < 3.0 and absf(lp.y) < 2.5:
			ram_cd[n] = 2.0
			_ev({"k": "hit", "n": n}) # the same hit as a swing: hurt, then down
			car.speed *= 0.6
			_shake(0.45)
			NFHaptics.pulse("hit")

## The owner's pass-by clip, when the car goes past a survivor at speed: on that survivor's
## phone (he is the one it goes past) and at the wheel (the driver hears himself fly past them).
## Its loudest moment is 1.2 s in, so it starts when the car is about that far from passing.
func _car_pass(dt: float) -> void:
	pass_cd -= dt
	if car == null or not car.driven or pass_cd > 0.0 or absf(car.speed) < 6.0: return
	var who := []
	if driving:
		for n in remotes:
			if remotes[n].role == "survivor" and rules.free_now(n): who.append(remotes[n].node.position)
	elif my_role == "survivor" and my_state in ["ok", "hurt"]:
		who.append(body.global_position)
	var v := car.forward() * car.speed
	for p in who:
		var rel: Vector3 = (p as Vector3) - car.global_position
		rel.y = 0.0
		var t := rel.dot(v) / v.length_squared()       # seconds until it is level with them
		var miss := (rel - v * t).length()              # how close it goes by
		if (t > 0.3 and t < 1.6 and miss < 7.0) or rel.length() < 4.0:
			car.whoosh()
			pass_cd = 5.0
			return

## Leaving the round in the middle of a slow-motion moment must not leave the whole game slowed.
func _exit_tree() -> void:
	Engine.time_scale = 1.0

# ---------------- the final shot ----------------
## If nobody is left on their feet (or in an escape car) after `who` went down, slow the world down
## and circle them for a moment: everyone's phone, the killer's too. Once per round.
func _final_check(who: String) -> void:
	if fin_done or rules.over or not rules.s.has(who): return
	for n in rules.s:
		if rules.s[n].hp in ["ok", "hurt"] or rules.car_of(n) >= 0: return
	if rules.s.size() < 2 and not offline: return
	fin_done = true
	fin_who = who
	_sfx("final", null, -2.0)
	fin_t = FIN_TIME
	fin_ang = _yaw_of(who) + PI * 0.6
	if fin_cam == null:
		fin_cam = Camera3D.new()
		fin_cam.fov = 52.0
		fin_cam.near = 0.05
		add_child(fin_cam)
	if main_cam and main_cam.environment: fin_cam.environment = main_cam.environment
	fin_cam.current = true
	_aim_fin(0.0)
	NFHaptics.pulse("impact")

func _aim_fin(dt: float) -> void:
	var at := _pos_of(fin_who) + Vector3(0, 0.7, 0)
	fin_ang += dt * 1.6
	var off := Vector3(sin(fin_ang), 0.0, cos(fin_ang)) * 3.4 + Vector3(0, 1.5, 0)
	var q := PhysicsRayQueryParameters3D.create(at, at + off) # keep the camera out of walls
	q.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	fin_cam.global_position = (hit.position as Vector3).lerp(at, 0.12) if not hit.is_empty() else at + off
	fin_cam.look_at(at, Vector3.UP)

func _step_fin(dt: float) -> void:
	if fin_t <= 0.0: return
	fin_t = maxf(fin_t - dt, 0.0)
	Engine.time_scale = FIN_SCALE if fin_t > 0.0 else 1.0
	if fin_t > 0.0: _aim_fin(dt)
	else:
		fin_cam.current = false
		if main_cam and results == null and scare_t <= 0.0: main_cam.current = true

# ---------------- perks and the killer's tools ----------------
## My own perk id (Rules.PERK by character), "" for the killer.
func _perk() -> String:
	return str(rules.perk.get(my_name, "")) if rules else ""

## Seconds I am still held by a trap.
## The developer tools' speed: how much quicker the legs may go so a faster player still looks like running.
func _fast() -> float:
	return Dev.speed if (Dev.unlocked and Dev.speed > 1.0) else 1.0

func _held() -> float:
	return float(rules.s[my_name].get("held", 0.0)) if (rules and rules.s.has(my_name)) else 0.0

## My perk, under the minimap: its icon and name (and «مستخدمة» once a one-time one is spent).
func _draw_perk() -> void:
	var pk := _perk()
	if pk == "" or spectating != "" or my_state in ["dead", "escaped"]: return
	var info: Array = Rules.PERK_INFO.get(pk, ["", "", "star"])
	var me: Dictionary = rules.s.get(my_name, {})
	var spent: bool = (pk == "tough" and not bool(me.get("shield", true))) or (pk == "rise" and bool(me.get("risen", false)))
	var at := minimap.position + Vector2(0.0, minimap.size.y + 12.0)
	var box := Rect2(at, Vector2(170.0, 34.0))
	ui.draw_rect(box, Color(0.03, 0.03, 0.04, 0.62))
	var col := Color(0.6, 0.6, 0.62) if spent else Color(1.0, 0.82, 0.45)
	ui.draw_rect(box, Color(col, 0.6), false, 1.5)
	NFIcons.draw(ui, str(info[2]), at + Vector2(152.0, 17.0), 20.0, col)
	_text(at + Vector2(74.0, 24.0), str(info[0]) + ("  (used)" if spent else ""), 16, col, 140.0)
	var held := _held()
	if held > 0.0: # caught in a trap: a ring that empties
		var mid := get_viewport().get_visible_rect().size / 2.0
		ui.draw_arc(mid + Vector2(0, 90), 34.0, -PI / 2.0, -PI / 2.0 + TAU * held / Rules.HELD_TIME, 32, Color(1, 0.4, 0.3), 6.0, true)
		NFIcons.draw(ui, "trap", mid + Vector2(0, 90), 34.0, Color(1, 0.5, 0.4))
		_text(mid + Vector2(0, 148), "Caught in a trap — %.0f" % ceilf(held), 22, Color(1, 0.6, 0.5))

## «عين الليل»: while she is within SENSE_R, a red arrow on the ring points at her, pulsing.
func _draw_sense(mid: Vector2) -> void:
	if _perk() != "sense" or my_state not in ["ok", "hurt", "down"] or rules.killer == "" or spectating != "": return
	var kp: Vector3 = car.global_position if (car and car_remote) else _pos_of(rules.killer)
	var dd := kp.distance_to(body.position)
	if dd > Rules.SENSE_R: return
	var d := _ring_dir(kp)
	var r := minf(mid.y * 0.62, 230.0)
	var at := mid + d * r
	var a := 0.55 + 0.45 * sin(sense_t * 7.0)
	var col := Color(1.0, 0.18, 0.15, a)
	NFIcons.draw(ui, "eye", at, 26.0, col)
	var tip := at + d * 30.0
	var sd := Vector2(-d.y, d.x)
	ui.draw_colored_polygon(PackedVector2Array([tip + d * 12.0, tip - sd * 8.0, tip + sd * 8.0]), col)
	_text(at + Vector2(0, 38.0), "%d m" % roundi(dd), 16, col, 120.0)

## The traps and the spike strips, on every phone: a node per slot shown where the rules say;
## survivors only see a trap from close by (the killer sees all of hers). My own phone tells the
## rules when I walk into one, and the escape car's driver when it goes over the spikes.
func _tools(_dt: float) -> void:
	if world == null or rules == null: return
	while trap_nodes.size() < rules.traps.size(): trap_nodes.append(_make_trap())
	for i in trap_nodes.size():
		var nd: Node3D = trap_nodes[i]
		var tr: Array = rules.traps[i] if i < rules.traps.size() else [0.0, 0.0, false, 0.0]
		var at := Vector3(float(tr[0]), float(tr[3]) if tr.size() > 3 else 0.0, float(tr[1]))
		if not nd.has_meta("at") or (nd.get_meta("at") as Vector3) != at: # newly laid: set down on the floor where she stood
			nd.set_meta("at", at)
			nd.position = _ground_at(at)
		var near := Vector2(at.x - body.position.x, at.z - body.position.z).length()
		nd.visible = bool(tr[2]) and (my_role == "killer" or near < 7.0)
		if bool(tr[2]):
			if my_role == "survivor" and snap_sent <= 0.0 and rules.free_now(my_name) and near < 0.75 and absf(nd.position.y - body.position.y) < 1.4:
				snap_sent = 1.0
				_ev({"k": "snap", "i": i})
	while spike_nodes.size() < rules.spikes.size(): spike_nodes.append(_make_spikes())
	for i in spike_nodes.size():
		var sn: Node3D = spike_nodes[i]
		var sp: Array = rules.spikes[i] if i < rules.spikes.size() else [0.0, 0.0, false]
		sn.visible = bool(sp[2]) and i < world.gate_points.size()
		if not sn.visible: continue
		var gp: Vector3 = world.gate_points[i][0]
		sn.position = Vector3(float(sp[0]), gp.y + 0.02, float(sp[1]))
		sn.rotation.y = float(world.gate_points[i][1])
		# the escape car's driver: over it?
		if esc_i == i and rules.roads[i].drv == my_name and not esc_popped.get(i, false):
			var ec: NFCar = world.esc_cars[i]
			var lp: Vector3 = sn.global_transform.affine_inverse() * ec.global_position
			if absf(lp.z) < 1.6 and absf(lp.x) < 3.0 + 1.0:
				esc_popped[i] = true
				_ev({"k": "pop", "i": i})

## The floor right under a point where someone stood (y): a short ray down through it.
func _ground_at(at: Vector3) -> Vector3:
	var from := at + Vector3(0, 1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -30.0, 0))
	q.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3) + Vector3(0, 0.02, 0) if not hit.is_empty() else Vector3(at.x, world.height(at.x, at.z) + 0.02, at.z)

## A bear trap: a dark plate, a ring of jaws, a row of teeth and a chain.
func _make_trap() -> Node3D:
	var nd := Node3D.new()
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.32, 0.3, 0.28)
	metal.metallic = 0.85
	metal.roughness = 0.38
	var plate := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.16; pm.bottom_radius = 0.18; pm.height = 0.04
	pm.material = metal
	plate.mesh = pm
	plate.position.y = 0.02
	nd.add_child(plate)
	for side in [-1.0, 1.0]: # the two jaws, open flat on the ground
		var jaw := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.3; tm.outer_radius = 0.34
		tm.rings = 18; tm.ring_segments = 6
		tm.material = metal
		jaw.mesh = tm
		jaw.scale = Vector3(1.0, 1.0, 0.55)
		jaw.position = Vector3(0, 0.03, side * 0.02)
		nd.add_child(jaw)
	var tooth := BoxMesh.new()
	tooth.size = Vector3(0.025, 0.07, 0.025)
	tooth.material = metal
	for k in 16:
		var a := k * TAU / 16.0
		var t := MeshInstance3D.new()
		t.mesh = tooth
		t.position = Vector3(cos(a) * 0.32, 0.07, sin(a) * 0.32 * 0.55)
		nd.add_child(t)
	var glint := OmniLight3D.new() # a faint glint, so a careful survivor can spot it
	glint.light_color = Color(0.9, 0.85, 0.7)
	glint.light_energy = 0.25
	glint.omni_range = 1.2
	glint.position.y = 0.3
	nd.add_child(glint)
	nd.visible = false
	add_child(nd)
	return nd

## A strip of spikes across half the lane, the way it was laid.
func _make_spikes() -> Node3D:
	var nd := Node3D.new()
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.4, 0.38, 0.36)
	metal.metallic = 0.8
	metal.roughness = 0.35
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(6.0, 0.05, 0.35)
	bm.material = metal
	bar.mesh = bm
	bar.position.y = 0.025
	nd.add_child(bar)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0; cone.bottom_radius = 0.05; cone.height = 0.16
	cone.radial_segments = 6; cone.rings = 1
	cone.material = metal
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone
	mm.instance_count = 48
	for k in 48:
		mm.set_instance_transform(k, Transform3D(Basis(), Vector3(-2.9 + (k / 2) * 0.25, 0.12, -0.09 + (k % 2) * 0.18)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	nd.add_child(mmi)
	nd.visible = false
	add_child(nd)
	return nd

# ---------------- the road chase: the survivors' escape car ----------------
## Every phone runs every escape car the same way: the door and the key when the first one gets
## in, then it follows whoever drives it, and it stops dead when it is caught.
func _esc_cars(dt: float) -> void:
	if world.esc_cars.is_empty() or rules.roads.is_empty(): return
	while esc_seen.size() < world.esc_cars.size(): esc_seen.append(0)
	esc_warn = maxf(esc_warn - dt, 0.0)
	for i in mini(world.esc_cars.size(), rules.roads.size()):
		var ec: NFCar = world.esc_cars[i]
		var rd: Dictionary = rules.roads[i]
		var st := int(rd.st)
		# behind a shut gate nobody can see or reach it: no drawing, no shadows, no work until then
		var awake: bool = (rules.powered or st > 0) and (i == 0 or not rules.sniper)
		if ec.visible != awake: ec.visible = awake
		if not awake: continue
		if st != int(esc_seen[i]):
			if st == 1: ec.begin("in") # the door, the key, the engine
			elif st == 2 and int(esc_seen[i]) == 1: # caught: a dead stop, the door flies open, out they go
				ec.speed = 0.0
				ec.velocity = Vector3.ZERO
				ec.begin("out")
				if body.position.distance_to(ec.global_position) < 40.0: _shake(0.8)
			esc_seen[i] = st
		var drv := str(rd.drv)
		ec.limit = NightWorld.ESC_TOP * (0.45 if bool(rd.get("flat", false)) else 1.0) # burst tyres: it crawls
		if st == 1 and drv == my_name and esc_i == i: continue # I drive it (_esc_ride)
		if st == 1 and remotes.has(drv) and remotes[drv].anim == "edrive":
			ec.driven = true
			ec.flame_on = remotes[drv].lit # the driver's flag is the nitro
			ec.follow(remotes[drv].pos, remotes[drv].yaw, dt)
		else:
			ec.driven = st == 1
			ec.park(dt)

## Into an escape car: no torch, nothing held, the camera well back behind the car.
func _esc_enter(i: int) -> void:
	var ec: NFCar = world.esc_cars[i]
	_end_hold()
	vault = {}
	crouch = false
	sprint = false
	light_on = false
	sig_open = false
	esc_arrived = false
	body.velocity = Vector3.ZERO
	arm.add_excluded_object(ec.get_rid())
	arm.position.y = 1.1
	main_cam.fov = _base_fov()
	yaw = ec.rotation.y + PI
	pitch = -0.24
	car_look = 1.0
	NFHaptics.pulse("hook")
	if rules.roads[i].drv == my_name: _flash("You're driving — floor it to the last gate, %d m and two minutes" % roundi(NightWorld.ROAD_LEN))
	else: _flash("You're riding — %s is driving" % str(rules.roads[i].drv))

## Out of it: through the last gate (escaped), or thrown onto the road beside it when caught.
func _esc_leave(i: int) -> void:
	var ec: NFCar = world.esc_cars[i]
	arm.remove_excluded_object(ec.get_rid())
	arm.position.y = 0.3
	main_cam.fov = _base_fov()
	rig.reach_clear()
	rig.position = Vector3.ZERO
	rig.rotation = Vector3(0, ec.rotation.y, 0)
	rig.scale = Vector3.ONE
	rig.play("dying")
	esc_vis = true
	if my_state != "down": return
	var g: Array = world.gate_points[i]
	var gp: Vector3 = g[0]
	var side := Basis(Vector3.UP, float(g[1])) * Vector3(1, 0, 0)
	var k: int = maxi((rules.roads[i].who as Array).find(my_name), 0)
	var lat := (ec.global_position - gp).dot(side)
	var p: Vector3 = ec.global_position + side * (-2.4 if lat > 0.0 else 2.4) + ec.forward() * (1.2 - k * 1.4)
	var lat2 := clampf((p - gp).dot(side), -NightWorld.LANE_W / 2.0 + 0.8, NightWorld.LANE_W / 2.0 - 0.8)
	p += side * (lat2 - (p - gp).dot(side))
	body.position = Vector3(p.x, gp.y + 0.1, p.z)
	body.velocity = Vector3.ZERO
	_shake(0.9)

## In an escape car: the driver drives it (the stick as in the killer's car: up is the gas), the
## rest ride along; the camera sits behind it and swings back there after a look round. At the
## last gate the driver's phone tells the rules, and everyone in the car is out.
func _esc_ride(delta: float) -> void:
	var ec: NFCar = world.esc_cars[esc_i]
	var rd: Dictionary = rules.roads[esc_i]
	var seat: int = (rd.who as Array).find(my_name)
	if rd.drv == my_name and int(rd.st) == 1:
		var move := stick_vec
		if move == Vector2.ZERO:
			move = Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
				float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
		if rules.over or ec.seated() < 1.0: move = Vector2.ZERO # not until the key has turned
		ec.driven = true
		ec.drive(-move.y, move.x, delta)
		speedo_kmh = lerpf(speedo_kmh, absf(ec.speed) * 3.6, 1.0 - exp(-10.0 * delta))
		if ec.bump > 0.0: # into a barrier or the wall
			_shake(0.25 + ec.bump * 0.7)
			NFHaptics.pulse_scaled("hit", ec.bump)
			ec.bump = 0.0
		if not esc_arrived and world.road_left(esc_i, ec.global_position) < 6.0:
			esc_arrived = true
			_ev({"k": "arrive", "i": esc_i})
	body.position = ec.global_position
	body.velocity = Vector3.ZERO
	esc_vis = seat >= 0 and seat < ec.seats and ec.seated() > 0.4
	rig.position = ec.seat_at(seat) - body.global_position
	rig.rotation = Vector3(0, ec.rotation.y, 0)
	rig.play("drive")
	if seat == 0:
		var gp := ec.grips()
		rig.reach(gp[0], gp[1], gp[2], gp[3])
	else: rig.reach_clear()
	# she is right behind: a buzz, so the driver feels it without looking back
	if car and car.driven and esc_warn <= 0.0 and car.global_position.distance_to(ec.global_position) < 22.0:
		esc_warn = 1.2
		NFHaptics.pulse("beat")
	car_look += delta
	if look_id >= 0: car_look = 0.0
	if car_look > 0.9:
		var k := 1.0 - exp(-2.5 * delta)
		yaw = lerp_angle(yaw, ec.rotation.y + PI, k)
		pitch = lerpf(pitch, -0.24, k)

## The road to show on the HUD: the car I am in, the road I am standing on, the car of the one I
## watch; for the killer, an escape car on its way.
func _road_view() -> int:
	if world == null or rules.roads.is_empty() or world.esc_cars.is_empty(): return -1
	if my_role == "survivor":
		if esc_i >= 0: return esc_i
		if spectating != "": return rules.car_of(spectating)
		if my_state in ["ok", "hurt", "down", "carried", "hooked"]: return world.road_at(body.position)
		return -1
	for i in rules.roads.size():
		if int(rules.roads[i].st) == 1: return i
	return -1

## The road panel, where the moon ring sits otherwise: the metres left to the last gate in big
## figures, the road's clock, and a strip from gate to gate with the car (and her, if she is on it).
func _draw_road(i: int, mid: Vector2) -> void:
	var rd: Dictionary = rules.roads[i]
	var st := int(rd.st)
	var ec: NFCar = world.esc_cars[i]
	# the car's distance for whoever is in it (or watches someone in it, or chases it); on foot, my own
	var in_car := esc_i == i or my_role == "killer" or (spectating != "" and rules.car_of(spectating) == i)
	var at: Vector3 = ec.global_position if in_car else (_pos_of(spectating) if spectating != "" else body.position)
	var left := world.road_left(i, at)
	var c := Vector2(mid.x, 112.0)
	var box := Rect2(c - Vector2(230.0, 54.0), Vector2(460.0, 128.0))
	ui.draw_rect(box, Color(0.02, 0.03, 0.03, 0.74))
	var col := Color(0.55, 1.0, 0.62)
	var t: float = float(rd.t)
	var urgent: bool = st == 1 and t < 30.0
	if urgent: col = Color(1.0, 0.45 + 0.25 * sin(Time.get_ticks_msec() / 160.0), 0.3)
	ui.draw_rect(box, Color(col, 0.75), false, 2.0)
	if my_role == "killer":
		_text(c + Vector2(0, -28), "Escape car — distance left", 18, Color(1, 0.6, 0.5))
	else:
		_text(c + Vector2(0, -28), "to the last gate", 18, Color(0.85, 1, 0.88))
	_text(c + Vector2(0, 20), "%d m" % roundi(left), 50, col)
	var clock := "%d:%02d" % [int(ceil(t)) / 60, int(ceil(t)) % 60]
	match st:
		0: _text(c + Vector2(0, 50), "The car is waiting — the first one in drives", 17, Color(0.85, 0.95, 0.9))
		1: _text(c + Vector2(0, 50), "Time %s" % clock, 24, col)
		2: _text(c + Vector2(0, 50), "The car was caught" if str(rd.why) == "ram" else "Time's up", 22, Color(1, 0.4, 0.3))
		3: _text(c + Vector2(0, 50), "They made it!", 22, Color(0.5, 1, 0.6))
	# the strip: gate on the right (Arabic reads that way), the last gate on the left
	var a := Vector2(c.x + 200.0, c.y + 64.0)
	var b := Vector2(c.x - 200.0, c.y + 64.0)
	ui.draw_line(a, b, Color(1, 1, 1, 0.25), 6.0, true)
	var f := clampf(1.0 - left / NightWorld.ROAD_LEN, 0.0, 1.0)
	ui.draw_line(a, a.lerp(b, f), col, 6.0, true)
	ui.draw_circle(b, 7.0, Color(0.5, 1, 0.6))
	NFIcons.draw(ui, "car", a.lerp(b, f) + Vector2(0, -2), 22.0, Color(0.5, 0.95, 1.0))
	if car and rules.killer != "": # her, when she is on the same road
		var kp: Vector3 = car.global_position if (driving or car_remote) else _pos_of(rules.killer)
		if world.road_at(kp) == i:
			var kf := clampf(1.0 - world.road_left(i, kp) / NightWorld.ROAD_LEN, 0.0, 1.0)
			ui.draw_circle(a.lerp(b, kf), 7.0, Color(1.0, 0.25, 0.2))
			if my_role == "survivor" and in_car and kf > f - 0.06 and kf <= f + 0.01:
				_text(c + Vector2(0, 104), "The killer is behind you!", 24, Color(1, 0.35, 0.3))

func _move(delta: float) -> void:
	var frozen: bool = rules.over or my_state in ["dead", "escaped"] or not hold.is_empty() or _kissing(my_name) or (my_role == "killer" and rules.stun > 0.0) or _held() > 0.0
	var move := stick_vec
	if move == Vector2.ZERO:
		move = Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))).limit_length(1.0)
	if frozen: move = Vector2.ZERO
	var speed: float = RUN[my_role] if (sprint or my_role == "killer") else WALK[my_role]
	if crouch: speed = CROUCH_SPEED
	if my_state == "down": speed = 0.45 # crawling
	if my_role == "killer" and rules.carrying != "": speed = CARRY_SPEED
	if sniping: speed = 1.0 # crawling on her belly with the rifle
	elif my_role == "killer" and world.on_stairs(body.position): speed = minf(speed, 2.2) # step by step up the stairs
	if boost_t > 0.0: speed *= 1.5
	if Dev.unlocked and Dev.speed > 1.0: speed *= Dev.speed
	var dir := Basis(Vector3.UP, yaw) * Vector3(move.x, 0, move.y)
	var target := dir.normalized() * speed * clampf(move.length() * 1.3, 0.0, 1.0) if move.length() > 0.05 else Vector3.ZERO
	if my_role == "killer" and not driving: rig.rotation.y = yaw + PI # first person: the body faces where I look
	if attack_t > 0.75: # short lunge at the start of the swing
		target = Basis(Vector3.UP, rig.rotation.y) * Vector3(0, 0, 1) * 6.4
	elif attack_t > 0.0:
		target *= 0.3 # recovery slowdown after a swing
	var grounded := body.is_on_floor()
	var rate := (ACCEL if target != Vector3.ZERO else DECEL) * (1.0 if grounded else 0.3)
	var hv := Vector3(body.velocity.x, 0, body.velocity.z).move_toward(target, rate * delta)
	body.velocity.x = hv.x
	body.velocity.z = hv.z
	body.velocity.y = -2.0 if grounded else body.velocity.y - 22.0 * delta
	var on_line := Vector3.INF
	if my_role == "killer" and world.sniper and not driving and not is_nan(world.stair_y(body.global_position)):
		on_line = world.stair_step(body.global_position, hv * delta) # the tower's stairs: walk the stair line itself
	if on_line != Vector3.INF:
		body.global_position = on_line
		body.velocity.y = 0.0
	else:
		body.move_and_slide()
	var flat := Vector2(body.velocity.x, body.velocity.z)
	var v := flat.length()
	if my_gun and my_gun.visible and my_gun.raise > 0.3: # aiming: she turns to where the camera looks
		var cam := get_viewport().get_camera_3d()
		if cam:
			var cf := -cam.global_basis.z
			rig.rotation.y = lerp_angle(rig.rotation.y, atan2(cf.x, cf.z), 14.0 * delta)
	elif my_role != "killer" and v > 0.25:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(flat.x, flat.y), 12.0 * delta)
	if driving or esc_i >= 0: rig.rotation.x = 0.0; rig.rotation.z = 0.0
	else: _lean_rig(rig, delta, Vector2(body.velocity.x, body.velocity.z).length(), str(rig.current))
	# killer hit check during the swing
	if my_role == "killer" and attack_t > 0.45 and attack_t < 0.95 and not hit_sent:
		var fwd := Basis(Vector3.UP, rig.rotation.y) * Vector3(0, 0, 1)
		for n in remotes:
			var r = remotes[n]
			if r.role != "survivor" or not rules.free_now(n): continue
			var to: Vector3 = r.node.position - body.position
			to.y = 0.0
			if to.length() < 2.5 and (to.length() < 0.7 or fwd.dot(to.normalized()) > 0.45):
				hit_sent = true
				_ev({"k": "hit", "n": n})
				break
	if my_role == "killer" and not driving: _killer_eye(delta, v)
	# animation (a running flinch keeps the rig until it is done)
	if hit_anim.get(my_name, 0.0) > 0.0: return
	if _kissing(my_name): return # the kiss poses me (scripts/kiss.gd)
	if sniping: # prone: the crawl while she moves, held still while she lies and aims
		rig.play("crawl", clampf(v / NATURAL.crawl, 0.5, 1.6) if v > 0.15 else 0.0001)
		return
	if my_role == "killer" and v > 0.25 and world.on_stairs(body.position) and rig.has("climb"):
		rig.play("climb", clampf(v / NATURAL.climb, 0.7, 2.2))
		return
	if my_state == "dead" and _kept(my_name):
		rig.play("hang", 0.6)
	elif my_state == "dead":
		rig.play("dying")
	elif my_state == "down":
		if v > 0.1: rig.play("crawl", 1.0)
		elif rig.current != "crawl": rig.play("dying")
		else: rig.play("crawl", 0.0001)
	elif attack_t > 0.0:
		pass # the swing plays through
	elif not hold.is_empty():
		var tp := body.position
		match hold.kind:
			"rep": tp = world.gen_points[hold.i]
			"pfix": tp = world.power_box
			"heal":
				if hold.n != my_name: tp = _pos_of(hold.n)
			"rescue": tp = world.hook_points[rules.s[hold.n].hook_i] if rules.s[hold.n].hook_i >= 0 else tp
			"break": tp = world.pallet_points[hold.i][0]
		if tp != body.position and my_role != "killer":
			rig.rotation.y = lerp_angle(rig.rotation.y, atan2(tp.x - body.position.x, tp.z - body.position.z), 10.0 * delta)
		rig.play("repair" if hold.kind in ["rep", "heal"] else "hide")
	elif crouch:
		if v > 0.25: rig.play("crouchwalk", clampf(v / NATURAL.crouchwalk, 0.5, 1.6))
		else: rig.play("hide")
	elif v > 0.25:
		if my_role == "killer" and rules.carrying != "":
			rig.play("carry", clampf(v / 1.4, 0.8, 2.6))
		elif v > 4.3 and rig.has("sprint"): # the real sprint clip, when there is one
			rig.play("sprint", snappedf(clampf(v / NATURAL.sprint, 0.75, 1.5 * _fast()), 0.05))
		elif v > 2.6:
			rig.play("run", snappedf(clampf(v / NATURAL.run, 0.7, 1.7 * _fast()), 0.05))
		elif my_state == "hurt": rig.play("injured", clampf(v / NATURAL.injured, 0.6, 1.6))
		else: rig.play("walk", clampf(v / NATURAL.walk, 0.6, 1.7))
	else:
		rig.play("idle")
	if my_role == "survivor" and esc_i < 0:
		_wound_pose(rig, my_state == "hurt", my_gun != null and my_gun.visible)
		_blood_trail(my_name, body.global_position, 1 if my_state == "hurt" else (2 if my_state == "down" else 0))
