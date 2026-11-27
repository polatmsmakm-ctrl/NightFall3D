extends RefCounted
## A trail for crashes (the owner: "still crashing when getting the second generator"). The iPhone gives
## the game no chance to report a crash, so the game writes down the last few things it did, to a small
## file, as it does them. If the game was killed in the middle of a round, the trail does not end with
## "ok", and the next launch keeps it: the menu shows it on the owner's phone (developer tools unlocked).
## The engine's own errors go in too, as "ERR ..." (scripts/err_log.gd), and the menu shows the last
## session's errors even when it did not crash.
## No class_name (an in-game update can carry it): `const Crumbs := preload("res://scripts/crumbs.gd")`.

const FILE := "user://crumbs.txt"
const KEEP := 30
const MAX_ERRS := 12 # engine errors written per session (an error repeated every frame must not flood it)
const NO_GORILLA := "user://no_gorilla" # the gorilla's scene crashed this phone: off here for that update only

static var lines := PackedStringArray()
static var last_crash := ""   # the previous session's trail, if it ended in a crash
static var last_errs := PackedStringArray() # the previous session's engine errors, crash or not
static var _read := false
static var _m := Mutex.new()
static var _queued := PackedStringArray() # errors from other threads, written on the main thread
static var _errs := 0
static var _last_err := ""
static var _busy := false

## Write one step down (and keep only the last KEEP).
static func mark(what: String) -> void:
	_take()
	_m.lock()
	if _busy: # an error while writing the file itself
		_m.unlock()
		return
	_busy = true
	for q in _queued: _add(q)
	_queued.clear()
	_add(what)
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
		f.close()
	_busy = false
	_m.unlock()

static func _add(what: String) -> void:
	lines.append("%s %s" % [Time.get_time_string_from_system(), what])
	if lines.size() > KEEP: lines = lines.slice(lines.size() - KEEP)

## An engine error (from err_log.gd, any thread). Written at once on the main thread, so it is in the
## file even if the game dies on the next line.
static func err(text: String) -> void:
	if text == "": return
	_m.lock()
	var skip := _busy or _errs >= MAX_ERRS or text == _last_err
	if not skip:
		_errs += 1
		_last_err = text
	var main := OS.get_thread_caller_id() == OS.get_main_thread_id()
	if not skip and not main: _queued.append("ERR " + text.substr(0, 200))
	_m.unlock()
	if not skip and main: mark("ERR " + text.substr(0, 200))

## The previous session's file, read once before this session writes over it.
static func _take() -> void:
	if _read: return
	_read = true
	if not FileAccess.file_exists(FILE): return
	var t := FileAccess.get_file_as_string(FILE).strip_edges()
	for l in t.split("\n"):
		if " ERR " in l: last_errs.append(l)
	if t != "" and not t.ends_with(" ok"):
		last_crash = t
		var tail := t.substr(maxi(t.rfind("\n"), 0))
		if "gorilla:" in tail: # it died building or playing the gorilla: never again on this phone
			var f := FileAccess.open(NO_GORILLA, FileAccess.WRITE)
			if f:
				f.store_string(str(_update())) # the update it crashed on: a newer one tries again
				f.close()

## True while the gorilla stays off on this phone: it crashed here on this same update. The file used
## to have no number in it (it stayed off for good, even after Update 4 fixed the crash): that counts as
## an older update, so the gorilla comes back.
static func _update() -> int: # the update mounted now (the Patch autoload; 0 if none)
	var ml := Engine.get_main_loop() as SceneTree
	var p: Node = ml.root.get_node_or_null("Patch") if ml else null
	return int(p.get("applied")) if p else 0

static func gorilla_off() -> bool:
	if not FileAccess.file_exists(NO_GORILLA): return false
	var t := FileAccess.get_file_as_string(NO_GORILLA).strip_edges()
	if t.is_valid_int() and int(t) == _update(): return true
	DirAccess.remove_absolute(NO_GORILLA)
	return false

## Once per launch: what the last session was doing when it stopped, if it did not stop cleanly.
static func launch() -> String:
	if not _read:
		_take()
		mark("launch ok")
	listen()
	return last_crash

## Start recording the engine's errors (once; Godot 4.5's Logger). From the menu (launch) and the
## round's start: the Patch autoload cannot, it runs before the update it would come in is mounted.
static var _listening := false
static func listen() -> void:
	if _listening or not ClassDB.class_exists("Logger"): return
	_listening = true
	var s = load("res://scripts/err_log.gd")
	if s: OS.add_logger(s.new())
