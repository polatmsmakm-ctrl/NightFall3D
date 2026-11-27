extends Node
## The "second generator" crash: on the owner's iPhone load("res://assets/chars/gorilla.glb") came back
## empty and the release engine crashed on .instantiate() of nothing. A model that will not load must
## never crash a round, and the engine's own reason must land in the crash trail.

const Crumbs := preload("res://scripts/crumbs.gd")
var bad := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func _ready() -> void:
	Crumbs.listen()
	check(ClassDB.class_exists("Logger"), "Godot has the Logger class (4.5)")
	# a character whose model will not load: falls back to another model, says so, does not crash
	var r := CharacterRig.new()
	add_child(r)
	r.setup("survivor99")
	check(r.failed != "" and r.model != null and r.skeleton != null, "a missing survivor model falls back (%s)" % r.failed)
	# anything else (the gorilla) gives up with no model
	var g := CharacterRig.new()
	add_child(g)
	g.setup("nothing_here")
	check(g.failed != "" and g.model == null and g.skeleton == null, "a missing creature model gives up cleanly")
	var trail := "\n".join(Crumbs.lines)
	check("model failed to load: res://assets/chars/survivor99.glb" in trail, "the failure is in the crash trail")
	# the engine's own error text comes in through the logger
	var _r = load("res://assets/chars/not_a_model.glb")
	await get_tree().process_frame
	trail = "\n".join(Crumbs.lines)
	check(" ERR " in trail, "the engine's error is in the trail")
	print(trail)
	# the model test on the developer page
	var m := GameMenu.new() # not added to the tree: only its function is wanted
	var t: String = m._model_test()
	m.free()
	print(t)
	check("OK  gorilla.glb" in t, "the model test loads the gorilla here")
	print("safety: %d failed" % bad)
	get_tree().quit()
