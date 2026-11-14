extends Node
## Audio buses and the volume settings (autoload "Aud").
## Everything that makes a sound goes to one of two buses under Master:
##   Music — the ambient bed, the chase track, the campfire, the doomsday track
##   SFX   — footsteps, generators, gates, screams, heartbeat, breathing, rope, UI clicks
## The three volumes are 0..1, applied live and saved in user://audio.cfg.

signal changed

const PATH := "user://audio.cfg"
const MUSIC := "Music"
const SFX := "SFX"

var master := 1.0
var music := 0.9
var sfx := 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_load()
	apply()

func _ensure_buses() -> void:
	for n in [MUSIC, SFX]:
		if AudioServer.get_bus_index(n) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, n)
			AudioServer.set_bus_send(i, "Master")

func _db(v: float) -> float:
	return -80.0 if v <= 0.005 else linear_to_db(clampf(v, 0.0, 1.0))

func apply() -> void:
	AudioServer.set_bus_volume_db(0, _db(master))
	AudioServer.set_bus_mute(0, master <= 0.005)
	for pair in [[MUSIC, music], [SFX, sfx]]:
		var i := AudioServer.get_bus_index(str(pair[0]))
		if i >= 0:
			AudioServer.set_bus_volume_db(i, _db(float(pair[1])))
			AudioServer.set_bus_mute(i, float(pair[1]) <= 0.005)
	changed.emit()

## Called while the slider is being dragged, so it has to stay cheap.
func set_vol(which: String, v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	match which:
		"master": master = v
		"music": music = v
		"sfx": sfx = v
	apply()
	save()

func get_vol(which: String) -> float:
	match which:
		"music": return music
		"sfx": return sfx
	return master

func _load() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK: return
	master = clampf(float(c.get_value("a", "master", master)), 0.0, 1.0)
	music = clampf(float(c.get_value("a", "music", music)), 0.0, 1.0)
	sfx = clampf(float(c.get_value("a", "sfx", sfx)), 0.0, 1.0)

func save() -> void:
	var c := ConfigFile.new()
	c.set_value("a", "master", snappedf(master, 0.01))
	c.set_value("a", "music", snappedf(music, 0.01))
	c.set_value("a", "sfx", snappedf(sfx, 0.01))
	c.save(PATH)
