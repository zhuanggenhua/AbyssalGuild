extends RefCounted
## Resolve direct serialized TradeManager placement without depending on the view.
## Unresolved prefab instances return null, never guessed world coordinates.
static func vendor_position(catalog, scene_name: String, pack_guid: String, board_bounds: Variant = null, top_margin: float = 1.5) -> Variant:
	for scene in catalog.data.get("scenes", []):
		if str(scene.get("name", "")) != scene_name:
			continue
		var documents: Array = scene.get("documents", [])
		for document in documents:
			if document.get("script_class", "") != "TradeManager":
				continue
			var fields: Dictionary = document.get("fields", {})
			var offered: Array = fields.get("offeredPacks", [])
			var index := -1
			for i in range(offered.size()):
				if catalog.ref_guid(offered[i]) == pack_guid:
					index = i
					break
			if index < 0:
				continue
			var object_id := str(fields.get("m_GameObject", {}).get("fileID", ""))
			var transform_id := ""
			for component in documents:
				if component.get("object_type", "") == "Transform" and str(component.get("fields", {}).get("m_GameObject", {}).get("fileID", "")) == object_id:
					transform_id = str(component.get("file_id", ""))
			var transform: Variant = _world_transform(documents, transform_id, [])
			if transform == null:
				return null
			if board_bounds is Rect2:
				transform.origin = Vector3(board_bounds.get_center().x, 0, board_bounds.end.y - top_margin * 0.5)
			var spacing := float(fields.get("spacing", 1.1))
			# Buyer is zone zero; each offered entry occupies a zone even if locked.
			var local_x := -offered.size() * spacing * 0.5 + (index + 1) * spacing
			var position: Vector3 = transform * Vector3(local_x, 0, 0) + _vector(fields.get("spawnOffset", {"z": -1.4}))
			return Vector2(position.x, position.z)
	return null

static func _vector(value: Dictionary, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	return Vector3(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)), float(value.get("z", fallback.z)))

static func _world_transform(documents: Array, id: String, visited: Array) -> Variant:
	if id.is_empty() or id == "0" or id in visited:
		return null
	visited.append(id)
	for document in documents:
		if document.get("object_type", "") != "Transform" or str(document.get("file_id", "")) != id:
			continue
		var fields: Dictionary = document.get("fields", {})
		var q: Dictionary = fields.get("m_LocalRotation", {})
		var rotation := Quaternion(float(q.get("x", 0)), float(q.get("y", 0)), float(q.get("z", 0)), float(q.get("w", 1)))
		var local := Transform3D(Basis(rotation).scaled_local(_vector(fields.get("m_LocalScale", {}), Vector3.ONE)), _vector(fields.get("m_LocalPosition", {})))
		var parent_id := str(fields.get("m_Father", {}).get("fileID", "0"))
		if parent_id == "0":
			return local
		var parent: Variant = _world_transform(documents, parent_id, visited)
		return null if parent == null else parent * local
	return null
