extends Node
## A character's maps as the game really loads them: «حارسة الليل» (survivor6) keeps her maps as
## lossless PNGs beside the GLB, each with a committed .import asking for high-quality compression.
## Checks the size the engine imported, the compressed format (BC7 here on desktop; the iPhone build
## takes the ASTC copy, which must exist in .godot/imported), mipmaps, and anisotropic filtering.

var bad := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: bad += 1

func _ready() -> void:
	var fmt_name := {Image.FORMAT_BPTC_RGBA: "BC7 (high quality)", Image.FORMAT_DXT1: "DXT1 (low)",
		Image.FORMAT_DXT5: "DXT5", Image.FORMAT_RGTC_RG: "BC5 (normal map)", Image.FORMAT_ETC2_RGB8: "ETC2",
		Image.FORMAT_ASTC_4x4: "ASTC 4x4", Image.FORMAT_RGBA8: "RGBA8 (uncompressed)", Image.FORMAT_RGB8: "RGB8 (uncompressed)"}
	var imported := []
	for f in DirAccess.get_files_at("res://.godot/imported"): imported.append(f)
	for hi in [false, true]:
		var rig := CharacterRig.new()
		add_child(rig)
		rig.setup("survivor6", ["idle"], hi)
		var file: String = "survivor6_hi" if hi else "survivor6"
		var side := 4096 if hi else 2048
		print(file, ": ", rig.model.scene_file_path.get_file())
		check(rig.model.scene_file_path.get_file() == file + ".glb", "the %s model is loaded" % file)
		var mat: StandardMaterial3D = null
		var tris := 0
		for mi in rig.model.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh
			for s in m.get_surface_count():
				tris += m.surface_get_array_index_len(s) / 3
				if mat == null: mat = (mi as MeshInstance3D).get_active_material(s) as StandardMaterial3D
		print("   triangles: ", tris)
		check(mat != null, "a material")
		if mat == null: continue
		for slot in [["albedo", mat.albedo_texture, "_col.png"], ["normal", mat.normal_texture, "_nrm.png"],
				["roughness", mat.roughness_texture, "_mr.png"], ["metallic", mat.metallic_texture, "_mr.png"]]:
			var t: Texture2D = slot[1]
			check(t != null, "%s map present" % slot[0])
			if t == null: continue
			var img := t.get_image()
			print("   %s: %s  %dx%d  %s  mipmaps %s" % [slot[0], t.resource_path.get_file(), t.get_width(), t.get_height(),
				fmt_name.get(img.get_format(), str(img.get_format())), img.has_mipmaps()])
			check(t.resource_path.ends_with(file + slot[2]), "%s comes from the lossless %s%s" % [slot[0], file, slot[2]])
			check(t.get_width() == side and t.get_height() == side, "%s imported at full size %d" % [slot[0], side])
			check(img.has_mipmaps(), "%s has mipmaps" % slot[0])
			check(img.get_format() != Image.FORMAT_DXT1 and img.get_format() != Image.FORMAT_ETC2_RGB8, "%s is not the low-quality compression" % slot[0])
			var astc := false
			for f in imported:
				if (f as String).begins_with(file + slot[2] + "-") and (f as String).ends_with(".astc.ctex"): astc = true
			check(astc, "%s has its ASTC copy for the iPhone" % slot[0])
		check(mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC, "anisotropic filtering")
		check(rig.has("idle") and rig.skeleton != null, "rigged, plays idle")
		rig.queue_free()
	print("tex check: ", "FAILED %d" % bad if bad else "all good")
	get_tree().quit(1 if bad else 0)
