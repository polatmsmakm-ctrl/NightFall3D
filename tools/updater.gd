extends Node
## The in-game updater (scripts/patch.gd, tools/make_patch.gd, the server's /patch.json): a pack replaces
## a file and adds a new script with a class name; make_patch packs a script, a sound and a picture with
## what their import made; the phone finds a newer patch on the real server, downloads it, checks it and
## saves it; at the next start it is mounted; a patch for another build is thrown away.
var tree: SceneTree
var bad := 0

func frames(n: int) -> void:
	for i in n: await tree.process_frame

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func _ready() -> void:
	tree = get_tree()
	check(get_node_or_null("/root/Patch") != null and get_tree().root.get_child(0).name == "Patch", "the updater is the first thing to start")
	check(FileAccess.get_file_as_string("res://tools/patch_probe.txt").strip_edges() == "v1", "the probe file says v1")
	# ---- a pack replaces a file and adds a script with a new class name ----
	var dir := "user://patchtest"
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir + "/probe.txt", "v2\n")
	_write(dir + "/new.gd", "class_name NFPatchProbe\nextends RefCounted\nfunc hi() -> String:\n\treturn \"new class\"\n")
	_write(dir + "/user.gd", "extends RefCounted\nfunc f() -> String:\n\treturn NFPatchProbe.new().hi()\n")
	var pk := PCKPacker.new()
	pk.pck_start(dir + "/t.pck")
	pk.add_file("res://tools/patch_probe.txt", dir + "/probe.txt")
	pk.add_file("res://tools/patch_new.gd", dir + "/new.gd")
	pk.add_file("res://tools/patch_user.gd", dir + "/user.gd")
	pk.flush()
	check(ProjectSettings.load_resource_pack(dir + "/t.pck", true), "the pack mounts")
	check(FileAccess.get_file_as_string("res://tools/patch_probe.txt").strip_edges() == "v2", "and its file replaces the game's (%s)" % FileAccess.get_file_as_string("res://tools/patch_probe.txt").strip_edges())
	var s = load("res://tools/patch_new.gd")
	check(s != null and s.new().hi() == "new class", "a new script in it runs")
	var known := false
	for c in ProjectSettings.get_global_class_list(): known = known or str(c.get("class", "")) == "NFPatchProbe"
	print("  info a new class_name from a patch is %s by name" % ("known" if known else "NOT known"))
	# ---- make_patch: a script, a sound, a picture ----
	_write(dir + "/changed.txt", "scripts/patch.gd\nassets/sfx/heart_fast.ogg\nassets/animals/cat_col.jpg\ntools/smoke.gd\nCLAUDE.md\n")
	var out := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/make_patch.gd", "--",
		ProjectSettings.globalize_path(dir + "/changed.txt"), ProjectSettings.globalize_path(dir + "/p.pck")], out, true)
	var txt := "\n".join(out)
	print(txt.substr(0, 1500))
	check(code == 0 and FileAccess.file_exists(dir + "/p.pck"), "make_patch wrote a pack (exit %d)" % code)
	check("res://scripts/patch.gd" in txt and "heart_fast.ogg.import" in txt and "cat_col.jpg.import" in txt, "with the script and the two assets' imports")
	check(".godot/imported/heart_fast.ogg" in txt and ".godot/imported/cat_col.jpg" in txt, "and what their import made")
	check(not ("smoke.gd" in txt) and not ("CLAUDE" in txt), "but not the tests or the notes")
	check(not (".s3tc." in txt), "and no desktop-only textures")
	_write(dir + "/ipa.txt", "project.godot\nscripts/main.gd\n")
	out = []
	code = OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/make_patch.gd", "--",
		ProjectSettings.globalize_path(dir + "/ipa.txt"), ProjectSettings.globalize_path(dir + "/q.pck")], out, true)
	check(code == 2, "project.godot changed: it says a new IPA is needed (exit %d)" % code)
	# ---- the whole way: the real server, the phone downloads it ----
	var sp := ProjectSettings.globalize_path("res://server/patches")
	var pck_bytes := FileAccess.get_file_as_bytes(dir + "/t.pck")
	var f := FileAccess.open(sp + "/test_7.pck", FileAccess.WRITE)
	f.store_buffer(pck_bytes)
	f.close()
	var sha := FileAccess.get_sha256(sp + "/test_7.pck")
	_write(sp + "/patch.json", JSON.stringify({"base": "cibase", "ver": 7, "file": "test_7.pck", "size": pck_bytes.size(), "sha256": sha, "note": "تجربة"}))
	var pid := OS.create_process("node", [ProjectSettings.globalize_path("res://server/server.js")])
	await get_tree().create_timer(2.0).timeout
	Net.url = "ws://127.0.0.1:8080"
	Patch.build_id = "cibase"
	Patch.applied = 0
	Patch.state = ""
	Patch.check()
	for i in 400:
		await tree.process_frame
		if Patch.state in ["ready", "error", "latest", ""] and i > 5: break
	check(Patch.state == "ready", "the phone found update 7 on the server and downloaded it (%s %s)" % [Patch.state, Patch.err])
	var c := ConfigFile.new()
	c.load(Patch.STATE)
	check(int(c.get_value("p", "ver", 0)) == 7 and FileAccess.file_exists(Patch.DIR + "/test_7.pck"), "saved for the next start")
	check(FileAccess.get_sha256(Patch.DIR + "/test_7.pck") == sha, "the file is whole (SHA-256)")
	# a wrong checksum is refused
	_write(sp + "/patch.json", JSON.stringify({"base": "cibase", "ver": 8, "file": "test_7.pck", "size": pck_bytes.size(), "sha256": "00", "note": ""}))
	Patch.applied = 7
	Patch.state = ""
	Patch.check()
	for i in 400:
		await tree.process_frame
		if Patch.state in ["ready", "error", "latest"] and i > 5: break
	check(Patch.state == "error", "a broken download is refused (%s)" % Patch.state)
	# the next start: the saved patch is mounted, for this build only
	_write("res://build_id.txt", "cibase")
	var p2 = load("res://scripts/patch.gd").new()
	check(p2.applied == 7 and p2.mounted == "test_7.pck", "next start: update 7 is mounted before anything else (%d)" % p2.applied)
	p2.free()
	_write("res://build_id.txt", "another")
	var p3 = load("res://scripts/patch.gd").new()
	check(p3.applied == 0 and not FileAccess.file_exists(Patch.DIR + "/test_7.pck"), "a new IPA: the old build's patch is thrown away")
	p3.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://build_id.txt"))
	DirAccess.remove_absolute(sp + "/patch.json")
	DirAccess.remove_absolute(sp + "/test_7.pck")
	OS.kill(pid)
	print("UPDATER %s %d" % ["PASS" if bad == 0 else "FAIL", bad])
	get_tree().quit(1 if bad else 0)

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
