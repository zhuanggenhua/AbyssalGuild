extends SceneTree
const VisualAssets = preload("res://scripts/ui/visual_assets.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const CardSurface = preload("res://scripts/ui/card_surface.gd")
const SourceCamera = preload("res://scripts/ui/source_camera.gd")

func _init() -> void:
	call_deferred("run")

func pose(position: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"m_LocalPosition": {"x": position.x, "y": position.y, "z": position.z},
		"m_LocalRotation": {"x": 0, "y": 0, "z": 0, "w": 1}, "m_LocalScale": {"x": 1, "y": 1, "z": 1}}

func synthetic_scene(extra_mesh: bool = false) -> PackedScene:
	var node := Node3D.new()
	node.position = Vector3(1, 0, 2)
	var holder := Node3D.new()
	holder.position = Vector3(0, 3, 0)
	node.add_child(holder)
	holder.owner = node
	var mesh_node := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-2,0,-1), Vector3(2,0,-1), Vector3(0,0,1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(0.5,1)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_node.mesh = mesh
	holder.add_child(mesh_node)
	mesh_node.owner = node
	if extra_mesh:
		var extra := mesh_node.duplicate()
		node.add_child(extra)
		extra.owner = node
	var packed := PackedScene.new()
	assert(packed.pack(node) == OK)
	node.free()
	return packed

func synthetic_assets():
	var assets = VisualAssets.new()
	assets.manifest = {"scenes": {"Main": {"categories": {"1": "prefab"}, "packPrefab": "prefab"}},
		"prefabs": {"prefab": {"mesh": {"guid": "mesh"}, "transform_chain": [pose(Vector3(4,5,6))],
			"size": {"x": 4, "y": 0, "z": 2}, "materials": [{"guid": "material"}],
			"title": {"transform_chain": [pose(Vector3(0, 0, 0.75))], "color": {"r": 0.8,"g": 0.7,"b": 0.6,"a": 1}, "rect_size": {"x": 3}}}},
		"materials": {"material": {"name": "SyntheticSurface", "shader_source_path": "Shaders/Card.shadergraph",
			"textures": {"_BaseTex": {"m_Texture": {"guid": "base"}}, "_OverlayTex": {"m_Texture": {"guid": "default_art"}}},
			"colors": {"_OverlayTint": {"r": 0.2, "g": 0.4, "b": 0.6, "a": 0.8}, "_OverlayOffset": {"r": 0.13, "g": 0.27}},
			"floats": {"_OverlayScale": 0.5, "_FlashAmount": 0.3}}}}
	for key in ["base", "default_art", "specific_art"]:
		var image := Image.create(2,2,false,Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		assets.texture_cache[key] = ImageTexture.create_from_image(image)
	assets.model_cache["mesh"] = synthetic_scene()
	return assets

func run() -> void:
	var assets = synthetic_assets()
	var appearance: Dictionary = assets.appearance(1, false, {"artTexture": {"guid": "specific_art"}})
	var card = CardView.new()
	card.configure(7, "Synthetic", 1, false, assets, {"artTexture": {"guid": "specific_art"}})
	assert(card.body.mesh is ArrayMesh)
	assert(card.body.name == "SourceCardMesh")
	assert(card.body.position.is_equal_approx(Vector3(3,8,-8)))
	assert(card.body.basis.is_equal_approx(Basis(Vector3.UP, PI)))
	assert(not card.has_node("SourceArt"))
	assert(card.caption.position.is_equal_approx(Vector3(0,0,-0.75)))
	assert(card.caption.autowrap_mode == TextServer.AUTOWRAP_OFF)
	assert(card.caption.font.get_height(card.caption.font_size) * card.caption.pixel_size <= 0.20001)
	assert(card.caption.modulate.is_equal_approx(Color(0.8,0.7,0.6,1)))
	assert(card.material is StandardMaterial3D) # Public fallback/highlight state stays compatible.
	assert(card.source_material.resource_name == "SyntheticSurface")
	assert(card.source_material.get_shader_parameter("base_texture") == assets.texture_cache.base)
	assert(card.source_material.get_shader_parameter("overlay_texture") == assets.texture_cache.specific_art)
	assert(card.source_material.get_shader_parameter("overlay_offset").is_equal_approx(Vector2(0.13,0.27)))
	assert(is_equal_approx(card.source_material.get_shader_parameter("overlay_scale"), 0.5))
	assert(is_equal_approx(card.source_material.get_shader_parameter("flash_amount"), 0.3))
	assert(card.source_material.get_shader_parameter("overlay_tint").is_equal_approx(Color(0.2,0.4,0.6,0.8)))
	assert(collision_size(card).is_equal_approx(Vector3(4,0.02,2)))
	card.highlight(true)
	assert(card.material.emission_enabled)
	assert(card.source_material.get_shader_parameter("selection_emission") == Vector3.ZERO) # No invented source emission.
	card.highlight(false)
	assert(not card.material.emission_enabled)
	assert(card.source_material.get_shader_parameter("selection_emission") == Vector3.ZERO)
	var other := assets.create_card_mesh(appearance)
	assert(other.material_override != card.source_material) # No shared per-card flashing/selection state.
	assert(other.mesh == card.body.mesh) # Geometry can be shared without copying licensed vertices.
	other.free()
	card.free()

	var default_surface := CardSurface.create(assets, assets.appearance(1, false))
	assert(default_surface.get_shader_parameter("overlay_texture") == assets.texture_cache.default_art)
	assert(CardSurface.overlay_sample_uv(Vector2(0.38,0.48), Vector2(0.13,0.27),0.5).is_equal_approx(Vector2(0.5,0.5)))
	assert(CardSurface.overlay_sample_uv(Vector2(0.13,0.23), Vector2(0.13,0.27),0.5).is_equal_approx(Vector2.ZERO))
	assert(CardSurface.compose_sample(Color(0.2,0.3,0.4,1), Color.WHITE, Color.WHITE,0.0,0.0).is_equal_approx(Color(0.2,0.3,0.4,1)))
	assert(CardSurface.compose_sample(Color.BLACK, Color(1,0,0,0.5), Color(0.4,1,1,1),1.0,0.0).is_equal_approx(Color(0.2,0,0,1)))
	assert(CardSurface.compose_sample(Color.BLACK, Color.BLACK, Color.WHITE,1.0,1.0).is_equal_approx(Color(1.5,1.5,1.5,1)))

	assets.model_cache["mesh"] = synthetic_scene(true)
	assert(assets.create_card_mesh(appearance) == null)
	assets.model_cache["mesh"] = synthetic_scene()
	var wrong_shader: Dictionary = appearance.duplicate(true)
	wrong_shader.material.shader_source_path = "Shaders/Other.shadergraph"
	assert(assets.create_card_mesh(wrong_shader) == null)
	var invalid_scale: Dictionary = appearance.duplicate(true)
	invalid_scale.material.floats._OverlayScale = 0
	assert(assets.create_card_mesh(invalid_scale) == null)
	var no_pose: Dictionary = appearance.duplicate(true)
	no_pose.prefab.transform_chain = []
	assert(assets.create_card_mesh(no_pose) == null)
	assets.texture_cache.erase("base")
	assert(assets.create_card_mesh(appearance) == null)
	var fallback = CardView.new()
	fallback.configure(8, "Missing media", 1, false, assets, {"artTexture": {"guid": "specific_art"}})
	assert(fallback.body.mesh is BoxMesh)
	assert(fallback.has_node("SourceArt"))
	assert(fallback.source_material == null)
	assert(collision_size(fallback).is_equal_approx(Vector3(4,0.02,2)))
	fallback.highlight(true)
	fallback.free()
	assets.model_cache.clear()
	assert(assets.model_scene("missing") == null)
	assets.manifest["assets"] = {"missing": {"kind": "fbx", "path": "Models/missing.fbx"}}
	assert(assets.model_scene("missing") == null)
	assets.manifest.assets.missing.path = "../escape.fbx"
	assert(assets.model_scene("missing") == null)
	print("Card mesh synthetic bindings: PASS (pose, UV math, textures, per-card materials, collider, fallback)")
	test_private()
	quit()

func collision_size(card: Node) -> Vector3:
	for child in card.get_children():
		if child is StaticBody3D:
			assert(int(child.get_meta("card_id")) == card.card_id)
			return child.get_child(0).shape.size
	return Vector3.ZERO

func test_private() -> void:
	var assets = VisualAssets.new()
	if assets.load_manifest() != OK:
		print("Source card/pack mesh: SKIP (private manifest unavailable)")
		return
	var initial: Dictionary = assets.appearance(1, false)
	if initial.prefab.get("mesh", {}).is_empty() or initial.prefab.get("transform_chain", []).is_empty():
		print("Source card/pack mesh: SKIP (regenerate private visual manifest)")
		return
	if assets.model_scene(str(initial.prefab.mesh.guid)) == null:
		print("Source card/pack mesh: SKIP (Godot FBX import cache unavailable)")
		return
	var count := 0
	for scene in ["Main", "Island"]:
		var config: Dictionary = assets.scene_configuration(scene)
		for category in config.get("categories", {}):
			inspect_private_card(assets, int(category), false, {}, scene)
			count += 1
		inspect_private_card(assets, 9, false, {"isAggressive": true}, scene)
		inspect_private_card(assets, 0, true, {}, scene)
		count += 2
	# Definitions override the material's placeholder art, as in source initialization.
	if FileAccess.file_exists("res://data/stackcraft.json"):
		var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/stackcraft.json"))
		for section in ["cards", "packs"]:
			for definition in catalog.get(section, []):
				var fields: Dictionary = definition.get("fields", {})
				var art_guid: String = str(fields.get("artTexture", {}).get("guid", ""))
				if art_guid.is_empty():
					continue
				var category: int = int(fields.get("category", 0))
				inspect_private_card(assets, category, section == "packs", fields, "Main")
				count += 1
	print("Source card/pack mesh: PASS (%d bindings; actual cached FBX and texture resources, no rendered acceptance)" % count)

func inspect_private_card(assets, category: int, is_pack: bool, fields: Dictionary, scene: String) -> void:
	var appearance: Dictionary = assets.appearance(category, is_pack, fields, scene)
	var card = CardView.new()
	card.configure(100, "Private binding test", category, is_pack, assets, fields, scene)
	assert(card.source_material != null, "Complete private inputs must bind the actual mesh")
	assert(card.body.mesh is ArrayMesh)
	assert(card.body.mesh.get_surface_count() == 1)
	assert(card.body.transform.is_equal_approx(Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)))
	var dimensions: Dictionary = appearance.prefab.size
	var vertices: PackedVector3Array = card.body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = card.body.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var bounds := AABB(card.body.transform * vertices[0], Vector3.ZERO)
	var min_x_uv := Vector2(10,10)
	var max_x_uv := Vector2(-10,-10)
	for index in vertices.size():
		var vertex: Vector3 = card.body.transform * vertices[index]
		bounds = bounds.expand(vertex)
		if vertex.x < min_x_uv.x:
			min_x_uv = Vector2(vertex.x, uv[index].x)
		if vertex.x > max_x_uv.x:
			max_x_uv = Vector2(vertex.x, uv[index].x)
		# Top PNG row points toward reflected source +Z, i.e. Godot -Z.
		assert(is_equal_approx(uv[index].y, vertex.z / float(dimensions.z) + 0.5))
	assert(min_x_uv.y < max_x_uv.y, "Original art must not be mirrored")
	assert(bounds.size.is_equal_approx(Vector3(float(dimensions.x),0,float(dimensions.z))))
	assert(collision_size(card).is_equal_approx(Vector3(float(dimensions.x),0.02,float(dimensions.z))))
	var expected_title := SourceCamera.reflected_pose(appearance.prefab.title.transform_chain)
	assert(card.caption.position.is_equal_approx(expected_title.transform.origin))
	assert(card.caption.modulate.is_equal_approx(assets.source_color(appearance.prefab.title.color)))
	var base_guid: String = str(appearance.material.textures._BaseTex.m_Texture.guid)
	var art_guid: String = str(appearance.art_guid)
	if art_guid.is_empty():
		art_guid = str(appearance.material.textures._OverlayTex.m_Texture.guid)
	assert(card.source_material.get_shader_parameter("base_texture") == assets.texture(base_guid))
	assert(card.source_material.get_shader_parameter("overlay_texture") == assets.texture(art_guid))
	assert(card.source_material.get_shader_parameter("overlay_offset").is_equal_approx(Vector2(float(appearance.material.colors._OverlayOffset.r),float(appearance.material.colors._OverlayOffset.g))))
	assert(is_equal_approx(card.source_material.get_shader_parameter("overlay_scale"),float(appearance.material.floats._OverlayScale)))
	card.free()
