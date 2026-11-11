extends RefCounted
## No independent animation clock. The model owns effect timing and stage progress.
static func sample(state: Dictionary) -> Variant:
	if state.is_empty() or not state.get("from_position") is Vector3 or not state.get("to_position") is Vector3: return null
	var duration: float = float(state.get("duration", 0))
	var t: float = 1.0 if duration <= 0 else clampf(float(state.get("elapsed", 0))/duration, 0, 1)
	# Explicit default-tween OutQuad approximation; never delays model effects.
	var eased: float = 1.0 - (1.0-t)*(1.0-t)
	return state.from_position.lerp(state.to_position, eased)

static func apply(state: Dictionary, views: Dictionary) -> void:
	var id: int = int(state.get("card_id", -1))
	var point: Variant = sample(state)
	if point is Vector3 and views.has(id) and is_instance_valid(views[id]):
		views[id].position = Vector3(point.x, point.y, -point.z)
