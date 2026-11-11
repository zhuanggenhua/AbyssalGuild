extends RefCounted
## Optional private media bindings with generated-geometry fallback.
var manifest: Dictionary = {}
var root_path: String = "res://assets/imported/"
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
			texture_cache[guid] = resource
			return resource
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	var loaded := ImageTexture.create_from_image(image)
	texture_cache[guid] = loaded
	return loaded

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
			# Source board shader is not recreated; preserve material-slot/color mapping.
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
