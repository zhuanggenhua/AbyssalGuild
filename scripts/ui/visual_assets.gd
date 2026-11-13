extends RefCounted
## Optional private media bindings with generated-geometry fallback.
var manifest: Dictionary = {}
var root_path: String = "res://assets/imported/"
var render_pipeline: Dictionary = {}
var texture_cache: Dictionary = {}
var model_cache: Dictionary = {}

func load_manifest(path: String = "res://assets/imported/manifest.json") -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1:
		return ERR_PARSE_ERROR
	for section in ["assets", "materials", "prefabs", "scenes"]:
		if not parsed.get(section, {}) is Dictionary:
			return ERR_PARSE_ERROR
	for value in parsed.get("assets", {}).values():
		if not value is Dictionary:
			return ERR_PARSE_ERROR
		var relative: String = str(value.get("path", ""))
		if relative.is_empty() or relative.is_absolute_path() or relative.contains("..") or relative.contains(":") or relative.contains("\\"):
			return ERR_PARSE_ERROR
	manifest = parsed
	root_path = path.get_base_dir() + "/"
	texture_cache.clear()
	model_cache.clear()
	return OK

func load_render_pipeline(expected_commit: String, path: String = "res://assets/imported/render_pipeline.json") -> Error:
	render_pipeline = {}
	if not FileAccess.file_exists(path) or not FileAccess.file_exists(path + ".sha256"): return ERR_FILE_NOT_FOUND
	if FileAccess.get_sha256(path) != FileAccess.get_file_as_string(path + ".sha256").strip_edges(): return ERR_INVALID_DATA
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1 or expected_commit.is_empty() or parsed.get("source_commit", "") != expected_commit:
		return ERR_INVALID_DATA
	for key in ["pipelines", "renderers", "inputs"]:
		if not parsed.get(key) is Dictionary: return ERR_INVALID_DATA
	if not parsed.get("qualities") is Array: return ERR_INVALID_DATA
	if parsed.get("target_platform", "") != "Standalone" or OS.get_name() not in ["Linux", "Windows", "macOS"]: return ERR_UNAVAILABLE
	render_pipeline = parsed
	return OK

func texture(guid: String) -> Texture2D:
	if texture_cache.has(guid):
		return texture_cache[guid]
	var entry: Dictionary = manifest.get("assets", {}).get(guid, {})
	if entry.get("kind", "") != "png":
		return null
	var relative: String = str(entry.get("path", ""))
	if relative.is_absolute_path() or relative.contains(".."):
		return null
	var path: String = root_path + relative
	# Imported/exported resources first; fresh private copies can work before editor import.
	var remap := ConfigFile.new()
	var has_cache: bool = remap.load(path + ".import") == OK and FileAccess.file_exists(str(remap.get_value("remap", "path", "")))
	if has_cache and ResourceLoader.exists(path, "Texture2D"):
		var resource = ResourceLoader.load(path, "Texture2D")
		if resource is Texture2D:
			var mapped: Texture2D = _imported_texture(resource, entry.get("texture_importer", {}))
			if mapped != null:
				texture_cache[guid] = mapped
			return mapped
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	var mapped_image := apply_texture_alpha(image, entry.get("texture_importer", {}))
	if mapped_image == null:
		return null
	var loaded := ImageTexture.create_from_image(mapped_image)
	texture_cache[guid] = loaded
	return loaded

func _imported_texture(resource: Texture2D, importer: Dictionary) -> Texture2D:
	var usage: int = int(importer.get("alpha_usage", 1)) if importer.get("alpha_usage") != null else 1
	if usage == 1:
		return resource
	var mapped := apply_texture_alpha(resource.get_image(), importer)
	return ImageTexture.create_from_image(mapped) if mapped != null else null

static func apply_texture_alpha(image: Image, importer: Dictionary) -> Image:
	# Unity TextureImporterAlphaSource: None=0, FromInput=1, FromGrayScale=2.
	# Run for cached Texture2D images AND uncached PNGs, never mutate private originals.
	if image == null:
		return null
	var usage: int = int(importer.get("alpha_usage", 1)) if importer.get("alpha_usage") != null else 1
	if usage == 1:
		return image
	if usage not in [0, 2]:
		return null
	var result := image.duplicate() as Image
	if result.is_compressed() and result.decompress() != OK:
		return null
	result.clear_mipmaps()
	result.convert(Image.FORMAT_RGBA8)
	var pixels := result.get_data()
	for index in range(0, pixels.size(), 4):
		if usage == 2 and (pixels[index] != pixels[index + 1] or pixels[index] != pixels[index + 2]):
			# Audited source inputs are grayscale; do not invent colored luminance weights.
			return null
		pixels[index + 3] = pixels[index] if usage == 2 else 255
	result = Image.create_from_data(result.get_width(), result.get_height(), false, Image.FORMAT_RGBA8, pixels)
	if bool(importer.get("mipmaps", false)):
		result.generate_mipmaps()
	return result

func scene_configuration(scene_name: String = "Main") -> Dictionary:
	return manifest.get("scenes", {}).get(scene_name, {})

func appearance(category: int, is_pack: bool, fields: Dictionary = {}, scene_name: String = "Main") -> Dictionary:
	var scene := scene_configuration(scene_name)
	var guid: String = str(scene.get("categories", {}).get(str(category), ""))
	if is_pack:
		guid = str(scene.get("packPrefab", ""))
	elif category == 9 and bool(fields.get("isAggressive", false)):
		guid = str(scene.get("aggressiveMobPrefab", guid))
	var prefab: Dictionary = manifest.get("prefabs", {}).get(guid, {})
	var materials: Array = prefab.get("materials", [])
	var mat: Dictionary = {}
	if not materials.is_empty():
		mat = manifest.get("materials", {}).get(str(materials[0].get("guid", "")), {})
	return {"prefab": prefab, "material": mat, "art_guid": str(fields.get("artTexture", {}).get("guid", ""))}

static func source_color(values: Dictionary, fallback: Color = Color.WHITE) -> Color:
	return Color(float(values.get("r", fallback.r)), float(values.get("g", fallback.g)), float(values.get("b", fallback.b)), float(values.get("a", fallback.a)))

func apply_scene(camera: Camera3D, board: MeshInstance3D, scene_name: String = "Main", apply_camera: bool = false) -> void:
	var config := scene_configuration(scene_name)
	# Preserve the working HUD framing by default. Unity orthographic size is half-height.
	if apply_camera and not config.get("cameras", []).is_empty():
		var source: Dictionary = config.cameras[0]
		if bool(source.get("orthographic", false)):
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.keep_aspect = Camera3D.KEEP_HEIGHT
			camera.size = float(source.get("orthographic_size", 10)) * 2.0
	for guid in config.get("boards", []):
		for renderer in manifest.get("prefabs", {}).get(guid, {}).get("renderers", []):
			for reference in renderer.get("materials", []):
				var source: Dictionary = manifest.get("materials", {}).get(reference.get("guid", ""), {})
				if not str(source.get("name", "")).begins_with("Body"):
					continue
				var material := StandardMaterial3D.new()
				material.albedo_color = source_color(source.get("colors", {}).get("_Color", {}))
				board.material_override = material
				return

func board_local_rect(scene_name: String, normalized_boost: float = 0.0) -> Rect2:
	# Bounds of actual vertices, not the morph-expanded mesh.get_aabb().
	var bounds: Array[Vector3] = []
	for guid in scene_configuration(scene_name).get("boards", []):
		var mesh_guid: String = str(manifest.get("prefabs", {}).get(guid, {}).get("mesh", {}).get("guid", ""))
		var entry: Dictionary = manifest.get("assets", {}).get(mesh_guid, {})
		var path: String = root_path + str(entry.get("path", ""))
		var remap := ConfigFile.new()
		if remap.load(path + ".import") != OK or not FileAccess.file_exists(str(remap.get_value("remap", "path", ""))):
			continue
		var packed = ResourceLoader.load(path, "PackedScene")
		if not packed is PackedScene:
			continue
		var instance = packed.instantiate()
		_collect_board_vertices(instance, Transform3D.IDENTITY, clampf(normalized_boost, 0, 1), bounds)
		instance.free()
	if bounds.is_empty():
		return Rect2()
	var result := Rect2(Vector2(bounds[0].x, bounds[0].z), Vector2.ZERO)
	for vertex in bounds:
		result = result.expand(Vector2(vertex.x, vertex.z))
	return result

func _collect_board_vertices(node: Node, parent_transform: Transform3D, weight: float, result: Array[Vector3]) -> void:
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * node.transform
	if node is MeshInstance3D and node.mesh is ArrayMesh:
		var mesh: ArrayMesh = node.mesh
		for surface in mesh.get_surface_count():
			var base: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var shapes: Array = mesh.surface_get_blend_shape_arrays(surface)
			var target: PackedVector3Array = PackedVector3Array()
			for shape in mesh.get_blend_shape_count():
				if mesh.get_blend_shape_name(shape) == "Scale" and shape < shapes.size():
					target = shapes[shape][Mesh.ARRAY_VERTEX]
			for index in base.size():
				var vertex: Vector3 = base[index]
				if target.size() == base.size():
					if mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED:
						vertex = vertex.lerp(target[index], weight)
					else:
						vertex += target[index] * weight
				result.append(transform * vertex)
	for child in node.get_children():
		_collect_board_vertices(child, transform, weight, result)

func create_board_mesh(scene_name: String, normalized_boost: float = 0.0) -> Node3D:
	# Private FBX resource only. Missing imports return null, never a fabricated model.
	for guid in scene_configuration(scene_name).get("boards", []):
		var prefab: Dictionary = manifest.get("prefabs", {}).get(guid, {})
		var mesh_guid: String = str(prefab.get("mesh", {}).get("guid", ""))
		var entry: Dictionary = manifest.get("assets", {}).get(mesh_guid, {})
		if entry.get("kind", "") != "fbx":
			continue
		var path: String = root_path + str(entry.get("path", ""))
		var remap := ConfigFile.new()
		if remap.load(path + ".import") != OK or not FileAccess.file_exists(str(remap.get_value("remap", "path", ""))):
			continue
		var packed = ResourceLoader.load(path, "PackedScene")
		if not packed is PackedScene:
			continue
		var instance = packed.instantiate()
		if not instance is Node3D:
			instance.free()
			continue
		instance.name = "SourceBoard"
		var chain: Array = scene_configuration(scene_name).get("board_poses", {}).get(guid, [])
		if chain.is_empty():
			instance.free()
			continue # Never substitute an unoverridden prefab transform.
		var pose: Transform3D = preload("res://scripts/ui/craft_progress_view.gd").effective_transform(chain)
		instance.transform = pose * Transform3D(Basis.from_scale(Vector3(1,1,-1)),Vector3.ZERO) * instance.transform
		instance.set_meta("source_prefab_guid", guid)
		_apply_board_materials(instance, prefab.get("materials", []))
		update_board_mesh_boost(instance, normalized_boost)
		return instance
	return null

func _apply_board_materials(node: Node, references: Array) -> void:
	if node is MeshInstance3D:
		for surface in mini(node.mesh.get_surface_count(), references.size()):
			var reference: Dictionary = references[surface]
			var source: Dictionary = manifest.get("materials", {}).get(reference.get("guid", ""), {})
			if source.is_empty():
				continue
			var material := StandardMaterial3D.new()
			material.resource_name = str(source.get("name", "SourceMaterial"))
			material.albedo_color = source_color(source.get("colors", {}).get("_Color", {}))
			# SimpleLit graph: _Color -> BaseColor; fixed smoothness 0, metallic 0.
			# StandardMaterial preserves these inputs, not Unity/Godot BRDF parity.
			material.roughness = 1.0
			material.metallic = 0.0
			node.set_surface_override_material(surface, material)
	for child in node.get_children():
		_apply_board_materials(child, references)

func update_board_mesh_boost(board_node: Node, normalized_boost: float) -> void:
	if board_node is MeshInstance3D and board_node.mesh is ArrayMesh:
		for index in board_node.mesh.get_blend_shape_count():
			if board_node.mesh.get_blend_shape_name(index) == "Scale":
				board_node.set_blend_shape_value(index, clampf(normalized_boost, 0, 1))
	for child in board_node.get_children():
		update_board_mesh_boost(child, normalized_boost)

func camera_configuration(scene_name: String = "Main") -> Dictionary:
	return preload("res://scripts/ui/source_camera.gd").configuration(scene_configuration(scene_name))

func apply_source_camera(camera: Camera3D, scene_name: String = "Main") -> bool:
	return preload("res://scripts/ui/source_camera.gd").apply(camera, scene_configuration(scene_name))

func directional_light_configuration(scene_name: String = "Main") -> Dictionary:
	for light in scene_configuration(scene_name).get("lights", []):
		var fields: Dictionary = light.get("fields", {})
		if int(fields.get("m_Type", -1)) != 1 or not fields.has("m_Intensity") or not fields.has("m_Color"):
			continue
		var pose := preload("res://scripts/ui/source_camera.gd").reflected_pose(light.get("transform_chain", []))
		if pose.is_empty():
			continue
		return {"transform": pose.transform, "color": source_color(fields.m_Color),
			"intensity": float(fields.m_Intensity), "shadows": fields.get("m_Shadows", {})}
	return {}

func apply_source_light(light: DirectionalLight3D, scene_name: String = "Main") -> bool:
	var config := directional_light_configuration(scene_name)
	if config.is_empty():
		return false
	light.global_transform = config.transform
	light.light_color = config.color
	light.light_energy = config.intensity
	light.shadow_enabled = int(config.shadows.get("m_Type", 0)) != 0
	light.shadow_opacity = float(config.shadows.get("m_Strength", 1.0))
	return true

func model_scene(guid: String) -> PackedScene:
	if model_cache.has(guid):
		return model_cache[guid]
	var entry: Dictionary = manifest.get("assets", {}).get(guid, {})
	if entry.get("kind", "") != "fbx":
		return null
	var relative: String = str(entry.get("path", ""))
	if relative.is_empty() or relative.is_absolute_path() or relative.contains("..") or relative.contains(":") or relative.contains("\\"):
		return null
	var path := root_path + relative
	var remap := ConfigFile.new()
	# A copied FBX without an editor import is not a loadable runtime scene.
	if remap.load(path + ".import") != OK or not FileAccess.file_exists(str(remap.get_value("remap", "path", ""))):
		return null
	if not ResourceLoader.exists(path, "PackedScene"):
		return null
	var packed = ResourceLoader.load(path, "PackedScene")
	if not packed is PackedScene:
		return null
	model_cache[guid] = packed
	return packed

func create_card_mesh(appearance_data: Dictionary) -> MeshInstance3D:
	return preload("res://scripts/ui/card_mesh_binding.gd").create(self, appearance_data)

func create_equipment_panel(metadata: Dictionary) -> Node3D:
	return preload("res://scripts/ui/equipment_panel_view.gd").create(self, metadata)

func create_projectile(combat_type: int, scene_name: String = "Main") -> Sprite3D:
	var record: Dictionary = scene_configuration(scene_name).get("combat", {}).get("projectiles", {}).get(str(combat_type), {})
	return preload("res://scripts/ui/combat_sprite_binding.gd").projectile(self, record)

func create_hit_popup(kind: String, damage_text: String, advantage: int, scene_name: String = "Main") -> Node3D:
	var record: Dictionary = scene_configuration(scene_name).get("combat", {}).get("hit_ui", {})
	return preload("res://scripts/ui/combat_sprite_binding.gd").hit_popup(self, record, kind, damage_text, advantage)

func puff_configuration(scene_name: String = "Main") -> Dictionary:
	# The importer resolves this scene's CardManager -> CardSettings -> Puff.
	var record: Dictionary = scene_configuration(scene_name).get("puff", {})
	if not preload("res://scripts/ui/puff_simulation.gd").is_supported(record):
		return {}
	return record.duplicate(true)

func create_puff(scene_name: String, presentation_seed: int) -> Node3D:
	var view = preload("res://scripts/ui/puff_view.gd").new()
	if not view.configure(self, puff_configuration(scene_name), presentation_seed):
		view.free()
		return null
	return view

func create_scene_background(scene_name: String) -> Node3D:
	return preload("res://scripts/ui/source_world.gd").background(self, scene_configuration(scene_name))

func apply_source_environment(environment: Environment, scene_name: String) -> bool:
	return preload("res://scripts/ui/source_world.gd").environment(environment, scene_configuration(scene_name))

func progress_configuration(scene_name: String) -> Dictionary:
	var result: Dictionary = scene_configuration(scene_name).get("progress", {}).duplicate(true)
	result["world_canvas_chain"] = scene_configuration(scene_name).get("world_canvas_chain", [])
	return result
