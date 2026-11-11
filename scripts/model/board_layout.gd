extends RefCounted
## Source-derived XZ placement. Vector2.y means Unity Z, not screen Y.
## This helper never changes Session, recipes, or live scene nodes.
const DEFAULT_STEP := Vector3(0.0, 0.002, -0.18)
const DEFAULT_MARGIN := Vector2(0.1, 0.1)
const DEFAULT_ITERATIONS := 8
const SPAWN_ATTACH_RADIUS := 1.0
const DROP_ATTACH_RADIUS := 0.25

static func card_size(collider_size: Vector3, margin: Vector2 = DEFAULT_MARGIN) -> Vector2:
	# CardInstance.Size uses local BoxCollider.size, without transform scale.
	return Vector2(collider_size.x, collider_size.z) + margin

static func prefab_card_size(prefab: Dictionary, margin: Vector2 = DEFAULT_MARGIN) -> Vector2:
	for document in prefab.get("documents", []):
		if document.get("object_type", "") == "BoxCollider":
			var size: Dictionary = document.get("fields", {}).get("m_Size", {})
			return card_size(Vector3(float(size.get("x", 0)), float(size.get("y", 0)), float(size.get("z", 0))), margin)
	return Vector2.ZERO # Missing source collider must not silently invent a size.

static func stack_state(id: int, position: Vector2, top_size: Vector2, count: int, locked: bool = false, step: Vector3 = DEFAULT_STEP) -> Dictionary:
	return {"id": id, "position": position, "size": top_size, "count": count, "locked": locked, "step": step}

static func full_depth(stack: Dictionary) -> float:
	if int(stack.count) <= 0:
		return 0.0
	return stack.size.y + (int(stack.count) - 1) * absf(stack.step.z)

static func stack_bounds(stack: Dictionary) -> Rect2:
	var half_size := Vector2(stack.size.x, full_depth(stack)) * 0.5
	var center: Vector2 = stack.position + Vector2(0, (int(stack.count) - 1) * stack.step.z * 0.5)
	return Rect2(center - half_size, half_size * 2.0)

static func card_position(stack: Dictionary, index: int) -> Vector3:
	return Vector3(stack.position.x, 0, stack.position.y) + stack.step * index

static func pack_draw_position(pack_position: Vector3) -> Vector3:
	return pack_position + Vector3(0, 0.1, 0)

static func _unity_clamp(value: float, minimum: float, maximum: float) -> float:
	# Match Mathf.Clamp even if an oversized stack makes minimum > maximum.
	if value < minimum:
		return minimum
	elif value > maximum:
		return maximum
	return value

static func clamp_to_bounds(position: Vector2, stack: Dictionary, board: Rect2) -> Vector2:
	if stack.is_empty():
		return position
	var half_width: float = stack.size.x * 0.5
	var half_depth: float = stack.size.y * 0.5
	return Vector2(_unity_clamp(position.x, board.position.x + half_width, board.end.x - half_width),
		_unity_clamp(position.y, board.position.y + full_depth(stack) - half_depth, board.end.y - half_depth))

static func enforce_placement(position: Vector2, stack: Dictionary, board: Rect2, top_margin: float = 1.5) -> Vector2:
	if stack.is_empty():
		return position
	var result := clamp_to_bounds(position, stack, board)
	result.y = minf(result.y, board.end.y - top_margin - stack.size.y * 0.5)
	return result

static func is_point_valid(position: Vector2, stack: Dictionary, board: Rect2, top_margin: float = 1.5) -> bool:
	# Source deliberately checks only the top card depth, not the whole stack.
	var half_size: Vector2 = Vector2.ZERO if stack.is_empty() else stack.size * 0.5
	return position.x >= board.position.x + half_size.x and position.x <= board.end.x - half_size.x \
		and position.y >= board.position.y + half_size.y and position.y <= board.end.y - half_size.y - top_margin

static func clamp_rect(position: Vector2, size: Vector2, board: Rect2, top_margin: float = 1.5) -> Vector2:
	return enforce_placement(position, stack_state(-1, position, size, 1), board, top_margin)

static func separation(a: Rect2, b: Rect2) -> Vector2:
	var delta := a.get_center() - b.get_center()
	var penetration := (a.size + b.size) * 0.5 - delta.abs()
	if penetration.x <= 0 or penetration.y <= 0:
		return Vector2.ZERO
	# Unity Mathf.Sign(0) is +1; Godot signf(0) is 0. Ties choose Z.
	if penetration.x < penetration.y:
		return Vector2(penetration.x * (1.0 if delta.x >= 0 else -1.0), 0)
	return Vector2(0, penetration.y * (1.0 if delta.y >= 0 else -1.0))

static func _translate(stack: Dictionary, offset: Vector2, board: Rect2, top_margin: float) -> void:
	stack.position = enforce_placement(stack.position + offset, stack, board, top_margin)

static func resolve_overlaps(stacks: Array, combat_rects: Array, board: Rect2, top_margin: float = 1.5, max_iterations: int = DEFAULT_ITERATIONS) -> Dictionary:
	# Copy input; preserve registration order. Rects are already world-space XZ.
	var result: Array = stacks.duplicate(true)
	var iterations := 0
	var any_overlap := true
	while iterations < max_iterations and any_overlap:
		iterations += 1
		any_overlap = false
		for rect in combat_rects:
			for stack in result:
				if stack.locked or int(stack.count) <= 0:
					continue
				var push := separation(stack_bounds(stack), rect)
				if push != Vector2.ZERO:
					_translate(stack, push, board, top_margin)
					any_overlap = true
		for i in range(result.size()):
			var a: Dictionary = result[i]
			for j in range(i + 1, result.size()):
				var b: Dictionary = result[j]
				if a.id == b.id or int(a.count) <= 0 or int(b.count) <= 0 or (a.locked and b.locked):
					continue
				var push := separation(stack_bounds(a), stack_bounds(b))
				if push == Vector2.ZERO:
					continue
				if a.locked:
					_translate(b, -push, board, top_margin)
				elif b.locked:
					_translate(a, push, board, top_margin)
				else:
					_translate(a, push * 0.5, board, top_margin)
					_translate(b, -push * 0.5, board, top_margin)
				any_overlap = true
	return {"stacks": result, "iterations": iterations, "separated_last_pass": any_overlap}

static func enforce_board_limits(stacks: Array, combat_rects: Array, board: Rect2, top_margin: float = 1.5, max_iterations: int = DEFAULT_ITERATIONS) -> Dictionary:
	var result: Array = stacks.duplicate(true)
	var moved := false
	for stack in result:
		if stack.locked or int(stack.count) <= 0:
			continue
		var valid := enforce_placement(stack.position, stack, board, top_margin)
		if stack.position.distance_squared_to(valid) > 0.001:
			stack.position = valid
			moved = true
	if moved:
		return resolve_overlaps(result, combat_rects, board, top_margin, max_iterations)
	return {"stacks": result, "iterations": 0, "separated_last_pass": false}

static func sphere_intersects_aabb(center: Vector3, radius: float, bounds: AABB) -> bool:
	# Optional broad phase for unrotated colliders. Do NOT use margin-expanded Size.
	var nearest := center.clamp(bounds.position, bounds.end)
	return center.distance_squared_to(nearest) <= radius * radius

static func choose_attach_candidate(position: Vector3, candidates: Array, own_stack_id: int, ignored_stack_id: int = -1, refuse_all: bool = false) -> int:
	# Candidate order MUST be overlap-hit order, not distance-to-stack-root order.
	# Each entry: id, eligible (external recipe/stack rules), card_positions:Array[Vector3].
	# Broad phase is caller-owned Physics.OverlapSphere equivalent, using raw colliders.
	if refuse_all:
		return -1
	var checked: Dictionary = {}
	var best_id := -1
	var best_distance := INF
	for candidate in candidates:
		var id: int = int(candidate.id)
		if id == own_stack_id or id == ignored_stack_id or not bool(candidate.get("eligible", false)) or checked.has(id):
			continue
		checked[id] = true
		var closest := INF
		for card_pos in candidate.get("card_positions", []):
			closest = minf(closest, position.distance_squared_to(card_pos))
		if closest < best_distance:
			best_distance = closest
			best_id = id
	return best_id
