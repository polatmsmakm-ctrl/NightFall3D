extends Node
## Hidden developer tools (autoload "Dev").
## Locked by default: nothing of this exists on a phone that has not unlocked it, and the unlock
## is only ever kept locally in user://dev.cfg. Never relayed, never sent to the server.

signal changed

const PATH := "user://dev.cfg"
const TAPS := 15     # taps needed on the version text
const GAP := 1.0     # seconds: a slower tap restarts the count

var unlocked := false
var esp := false      # see-through outlines of the other players
var speed := 1.0      # 1.0 .. 2.0 movement multiplier
var _taps := 0
var _last := -99.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var c := ConfigFile.new()
	if c.load(PATH) == OK: unlocked = bool(c.get_value("d", "on", false))

## One tap on the version text. Returns true on the tap that unlocks, so the caller can open the menu.
func tap() -> bool:
	if unlocked: return true
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last > GAP: _taps = 0
	_last = now
	_taps += 1
	if _taps < TAPS: return false
	_taps = 0
	unlocked = true
	var c := ConfigFile.new()
	c.set_value("d", "on", true)
	c.save(PATH)
	changed.emit()
	return true

func set_esp(on: bool) -> void:
	esp = on
	changed.emit()

func set_speed(v: float) -> void:
	speed = clampf(v, 1.0, 2.0)
	changed.emit()
