extends RefCounted
## Pure selection only. Layouts must already reflect the current task membership.
const Layout = preload("res://scripts/model/combat_layout.gd")

static func before_start(attackers: Array, defenders: Array, layouts: Dictionary) -> Array:
	var result: Array = []
	if attackers.is_empty() or defenders.is_empty():
		return result
	var potential: Rect2 = Layout.potential_bounds(attackers + defenders)
	for id in layouts:
		if Layout.overlaps(potential, Layout.manager_bounds(layouts[id])):
			result.append(id)
	return result

static func after_resize(task_id: int, layouts: Dictionary) -> Array:
	var result: Array = []
	if not layouts.has(task_id):
		return result
	var source: Rect2 = Layout.manager_bounds(layouts[task_id])
	for id in layouts:
		if id != task_id and Layout.overlaps(source, Layout.manager_bounds(layouts[id])):
			result.append(id)
	return result

## CalculatePotentialBounds reads transform.position before entering combat.
## This planar adapter admits only proven ground samples: source preview retains
## Y (half-height .5), so elevated bounds must not silently become ground bounds.
## Fallback preserves the existing settled model until full 3D geometry is ported.
static func current_ground_records(records: Array, sampler: Callable) -> Array:
	var result: Array = []
	for unit in records:
		var copy: Dictionary = unit.duplicate(true)
		if sampler.is_valid():
			var pose: Variant = sampler.call(int(unit.id))
			if pose is Vector3 and pose.is_finite() and pose.y == 0.0:
				copy.position = Vector2(pose.x, pose.z)
		result.append(copy)
	return result
