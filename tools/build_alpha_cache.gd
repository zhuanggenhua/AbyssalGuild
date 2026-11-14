extends SceneTree
## Run only after verified licensed import, with the matching official editor.
const Visual = preload("res://scripts/ui/visual_assets.gd")
const Cache = preload("res://scripts/ui/private_alpha_cache.gd")
func _init(): call_deferred("run")
func run() -> void:
	if not Cache.engine_matches(Engine.get_version_info()): quit(1); return
	var visual := Visual.new()
	if visual.load_manifest() != OK: quit(1); return
	if DirAccess.make_dir_recursive_absolute(Cache.ROOT) != OK: quit(1); return
	var entries := {}
	for guid in visual.manifest.assets:
		var entry: Dictionary = visual.manifest.assets[guid]
		if entry.get("kind") != "png" or entry.get("texture_importer", {}).get("alpha_usage") != 2: continue
		if not Cache.hex_id(guid, 32): quit(1); return
		var path: String = visual.root_path + entry.path
		if FileAccess.get_sha256(path) != entry.sha256: quit(1); return
		var remap := ConfigFile.new()
		if remap.load(path + ".import") != OK: quit(1); return
		var resource := ResourceLoader.load(path, "Texture2D") as Texture2D
		if resource == null: quit(1); return
		var image: Image = Visual.apply_texture_alpha(resource.get_image(), entry.texture_importer)
		if image == null: continue # Never turn a source rejection into a cached success.
		var raw := image.get_data()
		if raw.size() != Cache.byte_count(image.get_width(), image.get_height(), image.has_mipmaps()): continue
		var compressed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
		if compressed.is_empty() or compressed.size() > Cache.MAX_BYTES: continue
		var ctex: String = remap.get_value("remap", "path", "")
		var bound := {"source_sha256": entry.sha256, "importer": entry.texture_importer,
			"ctex_sha256": FileAccess.get_sha256(ctex), "path": guid + ".bin",
			"width": image.get_width(), "height": image.get_height(), "mipmaps": image.has_mipmaps(),
			"decoded_size": raw.size(), "rgba_sha256": Cache.digest(raw), "payload_sha256": Cache.digest(compressed)}
		var file := FileAccess.open(Cache.ROOT + guid + ".bin", FileAccess.WRITE)
		if file == null: quit(1); return
		file.store_buffer(compressed); file.close()
		# Exact byte and mip invariant checked before the index admits the payload.
		var verifier := Cache.new(); verifier._loaded = true; verifier._entries = {guid: bound}
		var decoded := verifier.image(guid, entry, remap)
		if decoded == null or decoded.get_data() != raw or decoded.get_mipmap_count() != image.get_mipmap_count(): quit(1); return
		entries[guid] = bound
	var index := {"schema": 1, "engine": Cache.VERSION, "engine_hash": Cache.ENGINE_HASH, "algorithm": Cache.ALGORITHM, "entries": entries}
	var file := FileAccess.open(Cache.INDEX, FileAccess.WRITE)
	if file == null: quit(1); return
	file.store_string(JSON.stringify(index, "", true)); file.close()
	print("PRIVATE ALPHA CACHE BUILD: PASS (", entries.size(), " exact images)")
	quit()
