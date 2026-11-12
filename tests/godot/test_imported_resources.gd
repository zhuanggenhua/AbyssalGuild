extends SceneTree
## Private-only gate. Unlike portable suites, missing imports always fail here.
const VisualAssets = preload("res://scripts/ui/visual_assets.gd")
const Catalog = preload("res://scripts/model/catalog.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var catalog = Catalog.new()
	assert(catalog.load_file() == OK, "Private catalog must load")
	for group in ["cards", "packs", "settings"]:
		assert(not catalog.data.get(group, []).is_empty(), "Private catalog group must not be empty: " + group)
	var assets = VisualAssets.new()
	assert(assets.load_manifest() == OK, "Private visual manifest must load")
	assert(assets.manifest.get("missing", ["missing report"]).is_empty(), "No missing private assets allowed")
	var counts := {"png": 0, "wav": 0, "fbx": 0}
	for guid in assets.manifest.assets:
		var entry: Dictionary = assets.manifest.assets[guid]
		var path: String = assets.root_path + str(entry.path)
		var remap := ConfigFile.new()
		assert(remap.load(path + ".import") == OK, "Import sidecar is required: " + path)
		var cached: String = str(remap.get_value("remap", "path", ""))
		assert(cached.begins_with("res://.godot/imported/"), "Must use disposable project import cache: " + path)
		assert(FileAccess.file_exists(cached), "Imported cache must exist: " + path)
		var resource = ResourceLoader.load(path)
		match str(entry.kind):
			"png":
				assert(resource is CompressedTexture2D, "PNG must load through cache, not ImageTexture fallback")
				var runtime: Texture2D = assets.texture(guid)
				assert(runtime != null and runtime.get_size() == resource.get_size(), "Runtime texture retains imported dimensions")
				if int(entry.get("texture_importer", {}).get("alpha_usage", 1)) == 1:
					assert(runtime == resource, "FromInput alpha retains the cached PNG resource")
				else:
					assert(runtime is ImageTexture and runtime != resource, "Source-generated alpha is derived from imported pixels")
					assert(assets.texture(guid) == runtime, "Converted texture is cached and reused")
			"wav":
				assert(resource is AudioStreamWAV and resource.get_length() > 0, "WAV must import as nonempty audio")
			"fbx":
				assert(resource is PackedScene, "FBX must import as a scene")
				assert(assets.model_scene(guid) == resource, "Runtime model binding must use imported FBX")
			_:
				assert(false, "Unsupported manifest asset kind")
		counts[entry.kind] += 1
	for kind in counts:
		assert(counts[kind] > 0, "Private manifest must include " + kind)
	for scene in ["Main", "Island"]:
		var config: Dictionary = assets.scene_configuration(scene)
		assert(not config.get("categories", {}).is_empty(), "Private categories required for " + scene)
		assert(not config.get("boards", []).is_empty(), "Private board required for " + scene)
		assert(not str(config.get("packPrefab", "")).is_empty(), "Private pack required for " + scene)
	print("Private imported resources: PASS (%d PNG, %d WAV, %d FBX)" % [counts.png, counts.wav, counts.fbx])
	quit()
