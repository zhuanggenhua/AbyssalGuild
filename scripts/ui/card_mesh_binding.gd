extends RefCounted
## Instantiates only the audited one-mesh card family, never a filename guess.
const SourceCamera = preload("res://scripts/ui/source_camera.gd")
const CardSurface = preload("res://scripts/ui/card_surface.gd")

static func create(assets, appearance: Dictionary) -> MeshInstance3D:
	var prefab: Dictionary = appearance.get("prefab", {})
	var pose := SourceCamera.reflected_pose(prefab.get("transform_chain", []))
	if pose.is_empty():
		return null
	var packed: PackedScene = assets.model_scene(str(prefab.get("mesh", {}).get("guid", "")))
	if packed == null:
		return null
	var surface := CardSurface.create(assets, appearance)
	if surface == null:
		return null
	var instance := packed.instantiate()
	var meshes: Array[Dictionary] = []
	_collect_meshes(instance, Transform3D.IDENTITY, meshes)
	if meshes.size() != 1 or meshes[0].mesh.get_surface_count() != 1:
		instance.free()
		return null # Do not silently select another model or material slot.
	var mesh: Mesh = meshes[0].mesh
	var arrays := mesh.surface_get_arrays(0)
	if arrays[Mesh.ARRAY_TEX_UV] == null or arrays[Mesh.ARRAY_TEX_UV].is_empty():
		instance.free()
		return null
	var result := MeshInstance3D.new()
	result.name = "SourceCardMesh"
	result.mesh = mesh
	# Unity FBX handedness flips X; this project reflects Unity world Z.
	# Together they rotate Godot's directly imported mesh 180 degrees about Y.
	var bridge := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	result.transform = pose.transform * bridge * meshes[0].transform
	result.material_override = surface
	result.set_meta("mesh_to_card", bridge * meshes[0].transform)
	result.set_meta("source_mesh_guid", str(prefab.get("mesh", {}).get("guid", "")))
	result.set_meta("source_coordinate_conversion", "fbx_to_reflected_unity")
	instance.free()
	return result

static func _collect_meshes(node: Node, parent: Transform3D, result: Array[Dictionary]) -> void:
	var pose := parent
	if node is Node3D:
		pose = parent * node.transform
	if node is MeshInstance3D and node.mesh != null:
		result.append({"mesh": node.mesh, "transform": pose})
	for child in node.get_children():
		_collect_meshes(child, pose, result)
