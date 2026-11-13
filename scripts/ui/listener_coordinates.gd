extends RefCounted
## Source-grounded coordinate conversion only. No attenuation/backend defaults.
static func position(source: Vector3) -> Vector3:
	return Vector3(source.x, source.y, -source.z)
static func rotation(source: Quaternion) -> Quaternion:
	return Quaternion(-source.x, -source.y, source.z, source.w).normalized()
static func pose(source_origin: Vector3, source_rotation: Quaternion) -> Transform3D:
	return Transform3D(Basis(rotation(source_rotation)), position(source_origin))
static func slot_position(state: Dictionary) -> Vector3:
	return position(state.get("world_position", Vector3.ZERO))
