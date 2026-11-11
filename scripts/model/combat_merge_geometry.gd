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
