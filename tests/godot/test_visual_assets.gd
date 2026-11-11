extends SceneTree
const VisualAssets = preload("res://scripts/ui/visual_assets.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
func _init() -> void:
	call_deferred("run")

func run() -> void:
	var assets = VisualAssets.new()
	assets.manifest = {"scenes": {"Main": {"categories": {"1": "prefab"}}}, "prefabs": {"prefab": {"size": {"x": 0.8, "y": 0, "z": 1}, "materials": [{"guid": "mat"}]}}, "materials": {"mat": {"colors": {"_Color": {"r": 0.2, "g": 0.3, "b": 0.4, "a": 1}}}}}
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	assets.texture_cache["art"] = ImageTexture.create_from_image(image)
	var card = CardView.new()
	card.configure(1, "Synthetic", 1, false, assets, {"artTexture": {"guid": "art"}})
	assert(card.has_node("SourceArt"))
	assert(card.body.mesh.size.is_equal_approx(Vector3(0.8, 0.02, 1)))
	assert(card.material.albedo_color.is_equal_approx(Color(0.2, 0.3, 0.4, 1)))
	assert(assets.appearance(1, false, {"artTexture": {"guid": "art"}}).art_guid == "art")
	var mesh := ArrayMesh.new()
	mesh.add_blend_shape("Scale")
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1,0,-1), Vector3(1,0,-1), Vector3(0,0,1)])
	var morph: Array = []
	morph.resize(Mesh.ARRAY_MAX)
	morph[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-2,0,-2), Vector3(2,0,-2), Vector3(0,0,2)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [morph])
	mesh.surface_set_material(0, StandardMaterial3D.new())
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = mesh
	root.add_child(mesh_node)
	var vertices: Array[Vector3] = []
	assets._collect_board_vertices(mesh_node, Transform3D.IDENTITY, 0.5, vertices)
	assert(vertices[0].is_equal_approx(Vector3(-1.5,0,-1.5)))
	assets.update_board_mesh_boost(mesh_node, 0.5)
	assert(is_equal_approx(mesh_node.get_blend_shape_value(0), 0.5))
	assets.update_board_mesh_boost(mesh_node, 2.0)
	assert(is_equal_approx(mesh_node.get_blend_shape_value(0), 1.0))
	assert(assets.create_board_mesh("Missing") == null)
	mesh_node.free()
	card.free()
	print("Visual source bindings: PASS")
	quit()
