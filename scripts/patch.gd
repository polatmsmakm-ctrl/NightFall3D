extends Node
## In-game updates (autoload `Patch`, the FIRST autoload): the owner's friends get new code, sounds and
## models without Sideloadly. The IPA carries its build id (`res://build_id.txt`, the commit it was built
## from, written by build-ipa.yml). `.github/workflows/patch.yml` packs every file changed since that
## commit into one `.pck` (`tools/make_patch.gd`) and puts it with `patch.json` in `server/patches/`,
## which the Render server hands out (`/patch.json`, `/patches/<file>`).
##
## At start, before any other script is loaded, the pack saved last time is mounted over the game's own
## files (`ProjectSettings.load_resource_pack(..., true)`), so every later script, sound and model comes
## from it. Then, from the menu, the phone asks the server for `patch.json`; a newer patch for this same
## build is downloaded (a bar at the top of the screen), checked (size and SHA-256), saved, and the
## player is asked to close and reopen the game. A patch made for another build is never loaded: a new
## IPA starts clean.
##
## What a patch can carry: scripts, shaders, sounds, pictures, models (anything under res:// that is not
## project.godot, a .tscn / .tres, or an export setting). Those need a new IPA.

const DIR := "user://patch"
const STATE := "user://patch/state.cfg"
const CHECK_DELAY := 2.5

var build_id := ""        # the commit the IPA was built from ("" when run from the editor / CI)
var applied := 0          # the patch version mounted at start (0: none)
var mounted := ""         # its file
var state := ""           # "" / "checking" / "downloading" / "ready" / "error" / "latest"
var progress := 0.0       # 0..1 while downloading
var offered := 0          # the version the server offers
var size := 0             # its size in bytes
var note := ""            # what is new (from patch.json, Arabic, shown on the bar)
var err := ""

var _http: HTTPRequest
var _ui: CanvasLayer
var _bar: Control
var _manifest := {}
var _t := 0.0
var _asked := false

func _init() -> void:
	if FileAccess.file_exists("res://build_id.txt"):
		build_id = FileAccess.get_file_as_string("res://build_id.txt").strip_edges()
	var c := ConfigFile.new()
	if build_id == "" or c.load(STATE) != OK: return
	if str(c.get_value("p", "base", "")) != build_id: # a new IPA: the old patch belongs to the old build
		_clear()
		return
	var f := str(c.get_value("p", "file", ""))
	var v := int(c.get_value("p", "ver", 0))
	if f == "" or v <= 0 or not FileAccess.file_exists(DIR + "/" + f): return
	if ProjectSettings.load_resource_pack(DIR + "/" + f, true):
		applied = v
		mounted = f
		note = str(c.get_value("p", "note", ""))
	else: # a broken file must never keep the game from starting
		_clear()

func _clear() -> void:
	var d := DirAccess.open(DIR)
	if d == null: return
	for f in d.get_files(): d.remove(f)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 30.0
	add_child(_http)
	_http.request_completed.connect(_on_done)
	_ui = CanvasLayer.new()
	_ui.layer = 120
	add_child(_ui)
	_bar = Control.new()
	_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	_ui.add_child(_bar)

## The server's address, from the game's own WebSocket address (wss://host -> https://host).
func base_url() -> String:
	var u := "wss://nightfall3d-server.onrender.com"
	var net = get_node_or_null("/root/Net")
	if net and "url" in net: u = str(net.url)
	u = u.replace("wss://", "https://").replace("ws://", "http://")
	return u.trim_suffix("/")

func check() -> void:
	if build_id == "" or state in ["checking", "downloading", "ready"]: return
	state = "checking"
	err = ""
	if _http.request(base_url() + "/patch.json?b=" + build_id) != OK:
		state = "error"

func _process(dt: float) -> void:
	if not _asked and build_id != "":
		_t += dt
		if _t > CHECK_DELAY:
			_asked = true
			check()
	if state == "downloading" and size > 0:
		progress = clampf(float(_http.get_downloaded_bytes()) / float(size), 0.0, 1.0)
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP if (state == "ready" and not _in_round()) else Control.MOUSE_FILTER_IGNORE
	_bar.queue_redraw()

func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if state == "checking":
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			state = "" # no patch published, or the server is asleep: try again next launch
			return
		var j = JSON.parse_string(body.get_string_from_utf8())
		if typeof(j) != TYPE_DICTIONARY or str(j.get("base", "")) != build_id or int(j.get("ver", 0)) <= applied:
			state = "latest"
			return
		_manifest = j
		offered = int(j.ver)
		size = int(j.get("size", 0))
		note = str(j.get("note", ""))
		state = "downloading"
		progress = 0.0
		DirAccess.make_dir_recursive_absolute(DIR)
		_http.download_file = DIR + "/download.tmp"
		if _http.request(base_url() + "/patches/" + str(j.file)) != OK:
			_fail("ما قدرت أبدأ التحميل")
		return
	if state == "downloading":
		_http.download_file = ""
		var tmp := DIR + "/download.tmp"
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_fail("انقطع التحميل — يرجع يحاول المرة الجاية")
			return
		var got := FileAccess.get_sha256(tmp)
		if str(_manifest.get("sha256", "")) != "" and got != str(_manifest.sha256):
			_fail("الملف وصل ناقص — يرجع يحاول المرة الجاية")
			return
		var fname := str(_manifest.file)
		var d := DirAccess.open(DIR)
		for f in d.get_files(): # keep only the one just downloaded (and the one mounted now)
			if f != "download.tmp" and f != mounted and f != "state.cfg": d.remove(f)
		d.rename("download.tmp", fname)
		var c := ConfigFile.new()
		c.set_value("p", "base", build_id)
		c.set_value("p", "ver", offered)
		c.set_value("p", "file", fname)
		c.set_value("p", "note", note)
		c.save(STATE)
		state = "ready"

func _fail(why: String) -> void:
	state = "error"
	err = why
	DirAccess.remove_absolute(DIR + "/download.tmp")

## A round in progress: the "close and reopen" box waits for its end.
func _in_round() -> bool:
	var s := get_tree().current_scene
	return s != null and "started" in s and bool(s.started) and "results" in s and s.results == null

func _draw_bar() -> void:
	if state not in ["downloading", "ready", "error"]: return
	var font: Font = ThemeDB.fallback_font
	var net = get_node_or_null("/root/Net")
	if net and "font" in net and net.font: font = net.font
	var s := _bar.get_viewport_rect().size
	if state == "downloading" or state == "error" or _in_round():
		var w := minf(560.0, s.x * 0.5)
		var r := Rect2(Vector2((s.x - w) / 2.0, 8.0), Vector2(w, 40.0))
		_bar.draw_rect(r, Color(0.03, 0.02, 0.03, 0.86))
		_bar.draw_rect(r, Color(0.7, 0.12, 0.1, 0.9), false, 2.0)
		var t := ""
		if state == "downloading":
			_bar.draw_rect(Rect2(r.position + Vector2(4, 30), Vector2((w - 8.0) * progress, 6.0)), Color(0.9, 0.2, 0.15))
			t = "تحديث جديد — %d%%  (%.1f MB)" % [int(progress * 100.0), size / 1048576.0]
		elif state == "error": t = err
		else: t = "التحديث جاهز — يتركّب أول ما تخلص الجولة"
		_bar.draw_string(font, Vector2(r.position.x, r.position.y + 24.0), t, HORIZONTAL_ALIGNMENT_CENTER, w, 18, Color(1, 0.92, 0.88))
		return
	# ready, in the menu: a box in the middle with one button
	_bar.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.6))
	var bw := minf(620.0, s.x * 0.7)
	var box := Rect2(Vector2((s.x - bw) / 2.0, s.y * 0.3), Vector2(bw, 240.0))
	_bar.draw_rect(box, Color(0.05, 0.03, 0.04, 0.97))
	_bar.draw_rect(box, Color(0.75, 0.12, 0.1), false, 3.0)
	_bar.draw_string(font, box.position + Vector2(0, 52), "التحديث %d نزل" % offered, HORIZONTAL_ALIGNMENT_CENTER, bw, 30, Color(1, 0.95, 0.9))
	if note != "": _bar.draw_string(font, box.position + Vector2(20, 96), note, HORIZONTAL_ALIGNMENT_CENTER, bw - 40.0, 19, Color(0.85, 0.82, 0.8))
	_bar.draw_string(font, box.position + Vector2(0, 140), "سكّر اللعبة وافتحها عشان يشتغل", HORIZONTAL_ALIGNMENT_CENTER, bw, 21, Color(1, 0.85, 0.5))
	var btn := Rect2(box.position + Vector2(bw / 2.0 - 120.0, 166.0), Vector2(240.0, 52.0))
	_bar.draw_rect(btn, Color(0.55, 0.08, 0.07))
	_bar.draw_string(font, btn.position + Vector2(0, 35), "سكّر اللعبة الحين", HORIZONTAL_ALIGNMENT_CENTER, 240.0, 22, Color.WHITE)
	_btn = btn

var _btn := Rect2()

func _input(e: InputEvent) -> void:
	if state != "ready" or _in_round() or _btn.size == Vector2.ZERO: return
	var p := Vector2.INF
	if e is InputEventScreenTouch and e.pressed: p = e.position
	elif e is InputEventMouseButton and e.pressed: p = e.position
	if p == Vector2.INF: return
	get_viewport().set_input_as_handled()
	if _btn.has_point(p): get_tree().quit()
