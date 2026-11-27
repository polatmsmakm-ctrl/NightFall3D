extends RefCounted
## A trail for crashes (the owner: "still crashing when getting the second generator"). The iPhone gives
## the game no chance to report a crash, so the game writes down the last few things it did, to a small
## file, as it does them. If the game was killed in the middle of a round, the trail does not end with
## "ok", and the next launch keeps it: the menu shows it on the owner's phone (developer tools unlocked).
## No class_name (an in-game update can carry it): `const Crumbs := preload("res://scripts/crumbs.gd")`.

const FILE := "user://crumbs.txt"
const KEEP := 30
const NO_GORILLA := "user://no_gorilla" # the gorilla's scene crashed this phone once: it stays off here

static var lines := PackedStringArray()
static var last_crash := ""   # the previous session's trail, if it ended in a crash
static var _read := false

## Write one step down (and keep only the last KEEP).
static func mark(what: String) -> void:
	lines.append("%s %s" % [Time.get_time_string_from_system(), what])
	if lines.size() > KEEP: lines = lines.slice(lines.size() - KEEP)
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
		f.close()

## Once per launch: what the last session was doing when it stopped, if it did not stop cleanly.
static func launch() -> String:
	if _read: return last_crash
	_read = true
	if FileAccess.file_exists(FILE):
		var t := FileAccess.get_file_as_string(FILE).strip_edges()
		if t != "" and not t.ends_with(" ok"):
			last_crash = t
			var tail := t.substr(maxi(t.rfind("\n"), 0))
			if "gorilla:" in tail: # it died building or playing the gorilla: never again on this phone
				var f := FileAccess.open(NO_GORILLA, FileAccess.WRITE)
				if f: f.close()
	lines = PackedStringArray()
	mark("launch ok")
	return last_crash
