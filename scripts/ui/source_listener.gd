extends AudioListener3D
## Independent listener, never derived from native camera projection offsets.
## Caller supplies actual source-world pose, including transform animation.
const Coordinates = preload("res://scripts/ui/listener_coordinates.gd")
func apply_source_pose(origin: Vector3, orientation: Quaternion) -> bool:
	if not origin.is_finite() or not orientation.is_finite() or is_zero_approx(orientation.length_squared()): return false
	global_transform = Coordinates.pose(origin, orientation)
	make_current()
	return true
