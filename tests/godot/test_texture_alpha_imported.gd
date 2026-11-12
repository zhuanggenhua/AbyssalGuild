extends SceneTree
## Private-input integration test. Requires all imported textures and their caches.
const Assets = preload("res://scripts/ui/visual_assets.gd")

func _init() -> void:
	var started := Time.get_ticks_msec()
	var assets = Assets.new()
	assert(assets.load_manifest() == OK, "Private visual manifest required")
	var verified := 0
	for guid in assets.manifest.assets:
		var entry: Dictionary = assets.manifest.assets[guid]
		if entry.get("kind", "") != "png":
			continue
		var importer: Dictionary = entry.get("texture_importer", {})
		assert(importer.has("alpha_usage"), "Reimport private texture metadata: " + str(entry.path))
		if int(importer.alpha_usage) != 2:
			continue
		var config := ConfigFile.new()
		assert(config.load(assets.root_path + str(entry.path) + ".import") == OK, "Texture import remap required: " + str(entry.path))
		var cache_path: String = str(config.get_value("remap", "path", ""))
		assert(not cache_path.is_empty() and FileAccess.file_exists(cache_path), "Texture cache required: " + str(entry.path))
		assert(ResourceLoader.exists(assets.root_path + str(entry.path), "Texture2D"), "Cached texture resource required: " + str(entry.path))
		var texture: Texture2D = assets.texture(str(guid))
		assert(texture != null, "Alpha conversion failed: " + str(entry.path))
		var image := texture.get_image()
		assert(image != null and image.get_format() == Image.FORMAT_RGBA8, "Converted RGBA8 required: " + str(entry.path))
		var pixels := image.get_data()
		for index in range(0, image.get_width() * image.get_height() * 4, 4):
			assert(pixels[index] == pixels[index + 1] and pixels[index] == pixels[index + 2], "Non-gray imported source: " + str(entry.path))
			assert(pixels[index] == pixels[index + 3], "Imported alpha differs from grayscale: " + str(entry.path))
		assert(not bool(importer.get("mipmaps", false)) or image.has_mipmaps(), "Converted mipmaps required: " + str(entry.path))
		verified += 1
	assert(verified == 115, "Expected all 115 locked-source grayscale-alpha textures")
	print("Imported texture alpha cached pixels: PASS (115 textures; ", Time.get_ticks_msec() - started, " ms)")
	quit()
