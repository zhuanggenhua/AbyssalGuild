extends SceneTree
const Visual = preload("res://scripts/ui/visual_assets.gd")
const Cache = preload("res://scripts/ui/private_alpha_cache.gd")
func _init(): call_deferred("run")
func run() -> void:
	var visual := Visual.new(); assert(visual.load_manifest() == OK)
	var cache := Cache.new(); var count := 0; var faults := 0
	var first_guid := ""; var first_bytes := PackedByteArray()
	for guid in visual.manifest.assets:
		var entry: Dictionary = visual.manifest.assets[guid]
		if entry.get("kind") != "png" or entry.get("texture_importer", {}).get("alpha_usage") != 2: continue
		var path: String = visual.root_path + entry.path
		var remap := ConfigFile.new(); assert(remap.load(path + ".import") == OK)
		var resource := ResourceLoader.load(path, "Texture2D") as Texture2D; assert(resource != null)
		var expected: Image = Visual.apply_texture_alpha(resource.get_image(), entry.texture_importer)
		if expected == null: continue
		if first_guid.is_empty(): first_guid = guid; first_bytes = expected.get_data()
		var image := cache.image(guid, entry, remap); assert(image != null)
		assert(image.get_data() == expected.get_data() and image.get_mipmap_count() == expected.get_mipmap_count())
		assert(image.get_width() == expected.get_width() and image.get_height() == expected.get_height() and image.get_format() == expected.get_format())
		assert(visual.texture(guid).get_image().get_data() == expected.get_data()); count += 1
		if faults == 0:
			var good: Dictionary = cache._entries[guid].duplicate(true)
			for field in ["source_sha256", "ctex_sha256", "payload_sha256", "rgba_sha256", "path", "importer", "decoded_size"]:
				cache._entries[guid] = good.duplicate(true); cache._entries[guid][field] = null
				assert(cache.image(guid, entry, remap) == null)
				visual.texture_cache.clear(); visual.private_alpha_cache = cache
				assert(visual.texture(guid).get_image().get_data() == expected.get_data()); faults += 1
			cache._entries[guid] = good
	# Overlay only in this private probe process: the original PCK remains unchanged.
	var manifest_faults := 0
	var original_index = JSON.parse_string(FileAccess.get_file_as_string(Cache.INDEX))
	var forged_index: Dictionary = original_index.duplicate(true)
	var forged_raw := first_bytes.duplicate(); forged_raw[0] ^= 255
	var forged_payload := forged_raw.compress(FileAccess.COMPRESSION_DEFLATE)
	forged_index.entries[first_guid].payload_sha256 = Cache.digest(forged_payload)
	forged_index.entries[first_guid].rgba_sha256 = Cache.digest(forged_raw)
	var cases := ["{", "null", JSON.stringify({"schema":1,"engine":Cache.VERSION,"engine_hash":Cache.ENGINE_HASH,"algorithm":Cache.ALGORITHM,"entries":{first_guid:{"path":"res://malicious.gd"}}}), JSON.stringify(forged_index)]
	for text in cases:
		var file := FileAccess.open("user://bad-alpha-index.json", FileAccess.WRITE); file.store_string(text); file.close()
		var overlay := "user://alpha-overlay-%d.pck" % manifest_faults
		var pack := PCKPacker.new(); assert(pack.pck_start(overlay) == OK)
		assert(pack.add_file(Cache.INDEX, "user://bad-alpha-index.json") == OK)
		if manifest_faults == 3:
			file = FileAccess.open("user://forged-alpha.bin", FileAccess.WRITE); file.store_buffer(forged_payload); file.close()
			assert(pack.add_file(Cache.ROOT + first_guid + ".bin", "user://forged-alpha.bin") == OK)
		assert(pack.flush() == OK); assert(ProjectSettings.load_resource_pack(overlay, true))
		var fallback := Visual.new(); assert(fallback.load_manifest() == OK)
		assert(fallback.texture(first_guid).get_image().get_data() == first_bytes)
		assert(fallback.private_alpha_cache._entries.is_empty())
		manifest_faults += 1
	print("PRIVATE ALPHA CACHE PCK: PASS (", count, " exact images; ", faults, " fallback cases; ", manifest_faults, " packed manifest faults)")
	quit()
