extends SceneTree
## Packs an in-game update (see scripts/patch.gd):
##   godot --headless --path . --script res://tools/make_patch.gd -- changed.txt out.pck
## `changed.txt` holds the project's files changed since the IPA's build (one res-relative path a line,
## from `git diff --name-only`). Scripts, shaders and plain files go in as they are; an imported file
## (sound, picture, model) goes in as its `.import` plus what the import made in .godot/imported (the
## desktop-only S3TC / BPTC copies are left out). The script class list and the UID table always go in.
## Exits 2 if something changed that only a new IPA can carry (project.godot, a .tscn / .tres, the export
## settings), 3 if nothing in the list belongs in a patch.

const SKIP_DIRS := ["tools/", "server/", ".github/", "build/", ".godot/"]
const SKIP_EXT := ["md", "py", "cpp", "js", "yml", "sh"]
const NEED_IPA := ["project.godot", "export_presets.cfg"]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- changed.txt out.pck")
		quit(1)
		return
	var lines := FileAccess.get_file_as_string(args[0]).split("\n", false)
	var files := {} # res path -> source path on disk
	var need_ipa := []
	for raw in lines:
		var p := raw.strip_edges()
		if p == "" or p.begins_with("."): continue
		var skip := false
		for d in SKIP_DIRS: skip = skip or p.begins_with(d)
		if skip or p.get_extension() in SKIP_EXT: continue
		if p in NEED_IPA or p.get_extension() in ["tscn", "tres"]:
			need_ipa.append(p)
			continue
		if p.ends_with(".import"): p = p.trim_suffix(".import") # a changed import setting: the asset again
		var res := "res://" + p
		if FileAccess.file_exists(res + ".import"):
			_add_imported(res, files)
		elif FileAccess.file_exists(res):
			files[res] = res
		# (a deleted file stays in the game: a patch can only add or replace)
	if not need_ipa.is_empty():
		print("NEEDS IPA: ", need_ipa)
		quit(2)
		return
	if files.is_empty():
		print("nothing to patch")
		quit(3)
		return
	for extra in ["res://.godot/global_script_class_cache.cfg", "res://.godot/uid_cache.bin"]:
		if FileAccess.file_exists(extra): files[extra] = extra
	var pk := PCKPacker.new()
	if pk.pck_start(args[1]) != OK:
		print("cannot write ", args[1])
		quit(1)
		return
	for target in files:
		var src := ProjectSettings.globalize_path(str(files[target]))
		if pk.add_file(str(target), src) != OK:
			print("cannot add ", target)
			quit(1)
			return
		print("  + ", target)
	pk.flush(false)
	print("PATCH %d files -> %s" % [files.size(), args[1]])
	quit(0)

func _add_imported(res: String, files: Dictionary) -> void:
	files[res + ".import"] = res + ".import"
	var c := ConfigFile.new()
	if c.load(res + ".import") != OK: return
	var dest = c.get_value("deps", "dest_files", [])
	for d in dest:
		var f := str(d)
		if ".s3tc." in f or ".bptc." in f: continue # desktop GPUs only
		if FileAccess.file_exists(f): files[f] = f
	# the remap's own paths (some importers write path= only)
	for k in c.get_section_keys("remap") if c.has_section("remap") else []:
		if str(k).begins_with("path"):
			var f := str(c.get_value("remap", k))
			if ".s3tc." in f or ".bptc." in f: continue
			if FileAccess.file_exists(f): files[f] = f
