extends RefCounted
## Explicit Unity world +Z -> Godot world -Z conversion, including camera forward.
static func configuration(scene: Dictionary) -> Dictionary:
	for source in scene.get("cameras", []):
		if not bool(source.get("resolved_pose", false)):
			continue
		for key in ["orthographic", "field_of_view", "near", "far", "fov_axis"]:
			if source.get(key) == null:
				return {}
		if int(source.fov_axis) != 0:
			return {} # Horizontal/physical camera conversion is not implemented.
		var pose_result := reflected_pose(source.get("transform_chain", []))
		if pose_result.is_empty():
			return {}
		var pose: Transform3D = pose_result.transform
		if float(source.near) <= 0 or float(source.far) <= float(source.near):
			return {}
		if float(source.field_of_view) <= 0 or float(source.field_of_view) >= 180:
			return {}
		if bool(source.orthographic) and float(source.get("orthographic_size", 0.0)) <= 0:
			return {}
		return {"transform": pose, "projection": Camera3D.PROJECTION_ORTHOGONAL if bool(source.orthographic) else Camera3D.PROJECTION_PERSPECTIVE,
			"fov": float(source.field_of_view), "near": float(source.near), "far": float(source.far),
			"size": float(source.get("orthographic_size", 0.0)) * 2.0,
			"source": source, "coordinate_conversion": "reflect_world_z"}
	return {}

static func apply(camera: Camera3D, scene: Dictionary) -> bool:
	var config := configuration(scene)
	if config.is_empty():
		return false
	camera.projection = config.projection
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = config.fov
	camera.near = config.near
	camera.far = config.far
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		camera.size = config["size"]
	camera.global_transform = config.transform
	return true

static func reflected_pose(chain: Array) -> Dictionary:
	if chain.is_empty():
		return {}
	var pose := Transform3D.IDENTITY
	for transform in chain:
		var position: Dictionary = transform.get("m_LocalPosition", {})
		var rotation: Dictionary = transform.get("m_LocalRotation", {})
		var scale: Dictionary = transform.get("m_LocalScale", {})
		if position.size() < 3 or rotation.size() < 4 or scale.size() < 3:
			return {}
		# Reflection S * R * S is quaternion (-x,-y,z,w).
		var quaternion := Quaternion(-float(rotation.x), -float(rotation.y), float(rotation.z), float(rotation.w))
		if quaternion.length_squared() < 0.0001:
			return {}
		var local := Transform3D(Basis(quaternion.normalized()).scaled(Vector3(float(scale.x), float(scale.y), float(scale.z))), Vector3(float(position.x), float(position.y), -float(position.z)))
		pose = pose * local
	return {"transform": pose}
