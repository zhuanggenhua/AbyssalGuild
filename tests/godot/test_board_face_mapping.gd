extends SceneTree
## Real private FBX geometry/admission checks, not a rendered-pixel or Unity GI test.
const Assets = preload("res://scripts/ui/visual_assets.gd")
const Binder = preload("res://scripts/ui/source_flat_board_lighting.gd")
const Lit = preload("res://scripts/ui/source_lit_material.gd")
const SOURCE_COMMIT := "a11a89b04cea8370476f2559b639bb9b4cbc08d8"
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): result.append_array(meshes(child))
	return result
func cull_back(material: Material) -> bool:
	return material is ShaderMaterial and material.shader != null and material.shader.code.contains("cull_back") and not material.shader.code.contains("cull_disabled")
func skip(reason: String) -> void:
	print("Board face mapping: SKIP (" + reason + ")")
	quit(0)
func run() -> void:
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		print("NOT RUN: requires --rendering-method gl_compatibility")
		quit(2)
		return
	var assets := Assets.new()
	if assets.load_manifest() != OK or assets.load_render_pipeline(SOURCE_COMMIT) != OK:
		skip("licensed manifest/render-pipeline cache unavailable")
		return
	var board_contracts := 0
	var card_contracts := 0
	for guid in assets.manifest.materials:
		var source: Dictionary = assets.manifest.materials[guid]
		if guid in ["76d4c733b9083064a8bf5154b4fe7014", "d04e9c516d1ba6645ae976067e7c6e7c", "2a957bfe9bd95794d85ea3ac8ce8c30b", "dcf05d26f2bab694c9b90635f359a786"]:
			board_contracts += 1
			var contract: Dictionary = source.get("source_lit", {})
			check(contract.get("schema_version") == 3 and contract.get("render_face") == 2 and contract.get("double_sided") == false and contract.get("cull_mode") == "back" and contract.get("normal_policy") == "inverse_transpose_no_face_flip", "board face contract " + str(source.get("name", "")))
			check(contract.get("graph_sha256") == "ecac38c65d483b39fdb2d6032cfbb0bad6d3d856b5183ea657da8c455a1ce0fe", "locked SimpleLit graph hash")
		if source.get("shader_source_path", "") == "Shaders/Card.shadergraph":
			card_contracts += 1
			var contract: Dictionary = source.get("source_lit", {})
			check(contract.get("schema_version") == 2 and contract.get("double_sided") == true and contract.get("graph_sha256") == "c4142dcadb5dbed427edcfba2657e93beb0457247c3120f27c2e9e530e70e368", "Card graph original schema2 untouched")
	check(board_contracts == 4 and card_contracts > 0, "four source boards and existing Card contracts checked")
	var path := "res://assets/imported/Models/Board.fbx"
	var remap := ConfigFile.new()
	if remap.load(path + ".import") != OK or not FileAccess.file_exists(str(remap.get_value("remap", "path", ""))):
		skip("licensed Board.fbx import cache unavailable")
		return
	var packed := load(path) as PackedScene
	if packed == null:
		skip("licensed Board.fbx PackedScene unavailable")
		return
	var raw := packed.instantiate()
	var raw_meshes := meshes(raw)
	check(raw_meshes.size() == 1, "locked FBX has one mesh")
	if raw_meshes.size() != 1:
		raw.free()
		quit(1)
		return
	var original_indices: Array = []
	var original_normals: Array = []
	for surface in raw_meshes[0].mesh.get_surface_count():
		var arrays := raw_meshes[0].mesh.surface_get_arrays(surface)
		original_indices.append(arrays[Mesh.ARRAY_INDEX].duplicate())
		original_normals.append(arrays[Mesh.ARRAY_NORMAL].duplicate())
	var card_path := "res://scripts/ui/shaders/card_surface.gdshader"
	var original_card_bytes := FileAccess.get_file_as_bytes(card_path)
	check(FileAccess.get_sha256(card_path) == "e2dc6690c979c952b7227d991b55259d8f41929f328eb104b023b1a95d720c88", "Card fragment matches baseline bytes")
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = 1
	environment.ambient_light_color = Color(.3,.4,.5)
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.shadow_enabled = true
	viewport.add_child(light)
	var binder := Binder.new()
	root.add_child(binder)
	for scene in ["Main", "Island"]:
		for boost in [0.0, 1.0]:
			var label := "%s boost%.0f" % [scene, boost]
			var board := assets.create_board_mesh(scene, boost)
			if board == null:
				binder.free()
				viewport.free()
				raw.free()
				skip("licensed scene board binding unavailable: " + label)
				return
			viewport.add_child(board)
			var nodes := meshes(board)
			check(nodes.size() == 1, label + " one real FBX mesh")
			if nodes.size() != 1:
				board.free()
				continue
			var mesh := nodes[0]
			check(is_equal_approx(mesh.global_basis.determinant(), -1.0), label + " expected coordinate reflection")
			check(mesh.mesh.get_surface_count() == 2, label + " both source surfaces")
			check(is_equal_approx(mesh.get_blend_shape_value(0), boost), label + " actual boost morph")
			var originals: Array[Material] = []
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_surface_override_material(surface)
				originals.append(material)
				check(material != null and material.get_meta("source_board_cull", "") == "back", label + " source cull metadata " + str(surface))
				check(cull_back(material), label + " source surface Cull.Back " + str(surface))
				var arrays := mesh.mesh.surface_get_arrays(surface)
				check(arrays[Mesh.ARRAY_INDEX] == original_indices[surface], label + " unchanged FBX indices " + str(surface))
				check(arrays[Mesh.ARRAY_NORMAL] == original_normals[surface], label + " unchanged imported normals " + str(surface))
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL].duplicate()
				var shapes := mesh.mesh.surface_get_blend_shape_arrays(surface)
				if not shapes.is_empty():
					var shape_vertices: PackedVector3Array = shapes[0][Mesh.ARRAY_VERTEX]
					var shape_normals: PackedVector3Array = shapes[0][Mesh.ARRAY_NORMAL]
					for i in vertices.size():
						if shape_vertices.size() == vertices.size():
							vertices[i] = vertices[i].lerp(shape_vertices[i], boost) if mesh.mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED else vertices[i] + shape_vertices[i] * boost
						if shape_normals.size() == normals.size():
							normals[i] = normals[i].lerp(shape_normals[i], boost) if mesh.mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED else normals[i] + shape_normals[i] * boost
				var normal_matrix := mesh.global_basis.inverse().transposed()
				var normals_up := true
				for normal in normals:
					normals_up = normals_up and (normal_matrix * normal).normalized().dot(Vector3.UP) > .999
				check(normals_up, label + " inverse-transpose normals +Y " + str(surface))
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var triangles_match := true
				var triangles := 0
				for i in range(0, indices.size(), 3):
					var a := mesh.global_transform * vertices[indices[i]]
					var b := mesh.global_transform * vertices[indices[i+1]]
					var c := mesh.global_transform * vertices[indices[i+2]]
					var cross_normal := (b-a).cross(c-a)
					if cross_normal.length_squared() < .000000001: continue
					triangles += 1
					var normal := (normal_matrix * normals[indices[i]]).normalized()
					triangles_match = triangles_match and cross_normal.normalized().dot(normal) > .999
				check(triangles > 0 and triangles_match, label + " mirrored triangle geometric normals match " + str(surface))
			binder.bind(board, environment)
			check(binder.active_count() == 2, label + " flat binder admits both surfaces")
			for surface in 2:
				check(cull_back(mesh.get_surface_override_material(surface)), label + " flat replacement Cull.Back " + str(surface))
			var extra := DirectionalLight3D.new()
			viewport.add_child(extra)
			binder.refresh()
			check(binder.active_count() == 0, label + " multi light fallback")
			for surface in 2: check(mesh.get_surface_override_material(surface) == originals[surface] and cull_back(originals[surface]), label + " fallback original Cull.Back identity " + str(surface))
			extra.free()
			binder.refresh()
			mesh.transparency = .5
			binder.refresh()
			check(binder.active_count() == 0 and mesh.get_surface_override_material(0) == originals[0], label + " transparency restores original")
			mesh.transparency = 0
			binder.refresh()
			var foreign := ShaderMaterial.new()
			foreign.shader = Shader.new()
			foreign.shader.code = "shader_type spatial; void fragment(){ ALBEDO=vec3(0.5); }"
			mesh.set_surface_override_material(0, foreign)
			binder.refresh()
			check(mesh.get_surface_override_material(0) == foreign, label + " unknown external material untouched")
			binder.clear()
			check(mesh.get_surface_override_material(0) == foreign and mesh.get_surface_override_material(1) == originals[1], label + " clear respects ownership and original")
			board.free()
	check(FileAccess.get_file_as_bytes(card_path) == original_card_bytes, "Card shader bytes unchanged by board pipeline")
	binder.free()
	viewport.free()
	raw.free()
	print("Board face mapping: %d checks, %d failures; actual FBX structure, no pixel claims" % [checks, failures])
	quit(1 if failures else 0)
