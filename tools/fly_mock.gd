extends Node
## A stand-in for main.gd with only what NFFlight (and the endings) need, over a Moon world that is
## configured and lit but not built: the rocket chase can be photographed without the whole map (which
## takes more memory than the software renderer has).
var rules: Rules
var world: NightWorld
var flight: NFFlight
var my_role := "survivor"
var my_name := "P"
var spectating := ""
var body: CharacterBody3D
var stick_vec := Vector2.ZERO
var remotes := {}
var offline := true
var bot = null
var main_cam: Camera3D
var over_hold := false
var rig: CharacterRig

## Eight aboard, each in their own seat (the cabin shots): me and seven others with their characters.
func crew() -> void:
	var cs := ["survivor1", "survivor2", "survivor3", "survivor5", "survivor6", "survivor7", "survivor8", "survivor9"]
	var who := ["P", "B", "C", "D", "E", "F", "G", "H"]
	for i in 8:
		var rg := CharacterRig.new()
		rg.setup(cs[i], CharacterRig.ANIMS, false, false)
		if i == 0:
			body.add_child(rg)
			rig = rg
		else:
			var nd := Node3D.new()
			add_child(nd)
			nd.add_child(rg)
			remotes[who[i]] = {"node": nd, "rig": rg}
	rules.fl.who = who

func setup(seed := 4242) -> void:
	world = NightWorld.new()
	world.configure("moon", seed, "normal")
	add_child(world)
	world._build_environment()
	var we := WorldEnvironment.new()
	we.environment = world.env
	add_child(we)
	var ps: PackedScene = load("res://assets/props/moon_rocket_ship.glb")
	world.rocket = ps.instantiate() as Node3D
	world.rocket.position = NightWorld.MOON_ROCKET + Vector3(0, 0.5, 0)
	world.add_child(world.rocket)
	world.kship_spot = Vector3(-36.0, 0.0, -NightWorld.WALL - 58.0)
	rules = Rules.new()
	rules.moon = true
	rules.setup(5, 2, 0, 0, [{"name": "P", "role": "survivor", "char": "survivor1"}, {"name": "B", "role": "survivor", "char": "survivor2"},
		{"name": "K", "role": "killer", "char": "killer4"}], seed)
	body = CharacterBody3D.new()
	add_child(body)
	main_cam = Camera3D.new()
	add_child(main_cam)
	flight = NFFlight.new()
	add_child(flight)
	flight.setup(self, seed)

## Straight into the flight: P steering, B on the boost, the clock at `c`.
func fly(c := 6.0) -> void:
	rules.powered = true
	rules.fl = {"st": 2, "t": Rules.FLIGHT_TIME - c, "c": c, "who": ["P", "B"], "pil": "P", "bst": "B", "b": false, "e": 1.0, "dm": 0.0, "kd": 0.0, "ks": false, "hits": [], "why": ""}

func _process(dt: float) -> void:
	if rules == null: return
	if int(rules.fl.st) == 2 and not over_hold:
		rules.fl.c = float(rules.fl.c) + dt
		rules.fl.t = maxf(float(rules.fl.t) - dt, 0.0)
		rules.fl.dm = maxf(float(rules.fl.dm) - dt, 0.0)
	flight.step(dt)

func _physics_process(dt: float) -> void:
	if flight and flight.me_mode() != "": flight.step_me(dt)

func _ev(d: Dictionary) -> void:
	for e in rules.handle(d, my_name): _on_event(e)

func _on_event(e: Dictionary) -> void:
	flight.on_event(e)

func _sfx(_n: String, _at = null, _db := 0.0, _p := 1.0) -> void:
	pass
