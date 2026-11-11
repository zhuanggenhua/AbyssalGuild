extends RefCounted
## Pure source-world X/Z geometry. No session mutation, timers or animations.
const Board = preload("res://scripts/model/board_layout.gd")
const MARGIN := Vector2(0.1, 0.1) # CombatRect.Margin is static readonly in source.

static func required_size(attacker_count: int, defender_count: int, card_size: Vector2, margin: Vector2 = MARGIN) -> Vector2:
	var cell := card_size + margin
	return Vector2(cell.x * maxi(attacker_count, defender_count), cell.y * 2.0) + margin * 2.0

static func _basis(fields: Dictionary) -> Basis:
	var q: Dictionary = fields.get("m_LocalRotation", {})
	var scale: Dictionary = fields.get("m_LocalScale", {})
	var rotation := Quaternion(float(q.get("x", 0)), float(q.get("y", 0)), float(q.get("z", 0)), float(q.get("w", 1))).normalized()
	return Basis(rotation).scaled_local(Vector3(float(scale.get("x", 1)), float(scale.get("y", 1)), float(scale.get("z", 1))))

static func _hierarchy_basis(documents: Array, transform_id: String) -> Dictionary:
	var visited: Dictionary = {}
	var result := Basis.IDENTITY
	while transform_id != "0":
		if visited.has(transform_id):
			return {"ok": false, "error": "Cyclic prefab transform hierarchy"}
		visited[transform_id] = true
		var found: Dictionary = {}
		for document in documents:
			if str(document.get("file_id", "")) == transform_id:
				found = document
				break
		if found.is_empty():
			return {"ok": false, "error": "Missing prefab ancestor transform"}
		var fields: Dictionary = found.get("fields", {})
		result = _basis(fields) * result
		transform_id = str(fields.get("m_Father", {}).get("fileID", "0"))
	return {"ok": true, "basis": result}

static func _component_transform(prefab: Dictionary, component_class: String) -> Dictionary:
	var documents: Array = prefab.get("documents", [])
	for document in documents:
		if document.get("script_class", "") != component_class:
			continue
		var game_object: String = str(document.get("fields", {}).get("m_GameObject", {}).get("fileID", ""))
		for transform in documents:
			if transform.get("object_type", "") in ["Transform", "RectTransform"] and str(transform.get("fields", {}).get("m_GameObject", {}).get("fileID", "")) == game_object:
				var result: Dictionary = _hierarchy_basis(documents, str(transform.file_id))
				result["fields"] = transform.fields
				return result
	return {"ok": false, "error": "Missing " + component_class + " transform"}

## Resolve geometry from private imported data, never guessed card/prefab dimensions.
## The caller supplies per-fighter CardInstance.Size (Board.prefab_card_size).
static func imported_config(data: Dictionary, scene_name: String) -> Dictionary:
	var rect_guid: String = ""
	for scene in data.get("scenes", []):
		if scene.get("name", "") == scene_name:
			for document in scene.get("documents", []):
				if document.get("script_class", "") == "CombatManager":
					rect_guid = str(document.get("fields", {}).get("combatRectPrefab", {}).get("guid", ""))
	if rect_guid.is_empty():
		return {"ok": false, "error": "Scene has no CombatManager rectangle reference"}
	var rect: Dictionary = {}
	var canvas: Dictionary = {}
	for prefab in data.get("referenced_prefabs", []):
		if str(prefab.get("guid", "")) == rect_guid:
			rect = _component_transform(prefab, "CombatRect")
		for document in prefab.get("documents", []):
			if document.get("script_class", "") == "WorldCanvas":
				if not canvas.is_empty():
					return {"ok": false, "error": "Ambiguous WorldCanvas prefabs"}
				canvas = _component_transform(prefab, "WorldCanvas")
	if not rect.get("ok", false) or not canvas.get("ok", false):
		return {"ok": false, "error": "Missing imported combat rectangle or canvas transform"}
	var basis: Basis = canvas.basis * rect.basis
	var axis_x := Vector2(basis.x.x, basis.x.z)
	var axis_y := Vector2(basis.y.x, basis.y.z)
	if absf(axis_x.cross(axis_y)) < 0.000001:
		return {"ok": false, "error": "Combat canvas does not span the board plane"}
	var pivot: Dictionary = rect.fields.get("m_Pivot", {})
	return {"ok": true, "axis_x": axis_x, "axis_y": axis_y, "scale": Vector2(basis.x.length(), basis.y.length()), "pivot": Vector2(float(pivot.get("x", 0.5)), float(pivot.get("y", 0.5)))}

## Unit records: {id:int, position:Vector2, size:Vector2, faction:int}.
## Attackers remain the negative row even when they are mobs.
static func initialize(attackers: Array, defenders: Array, config: Dictionary, board: Rect2, top_margin: float) -> Dictionary:
	if attackers.is_empty() or defenders.is_empty() or not config.get("ok", false):
		return {}
	var center := Vector2.ZERO
	for unit in attackers + defenders:
		center += unit.position
	center /= attackers.size() + defenders.size()
	var size := required_size(attackers.size(), defenders.size(), attackers[0].size)
	center = Board.clamp_rect(center, size * config.scale, board, top_margin)
	var state := {"center": center, "cell": attackers[0].size + MARGIN, "config": config.duplicate(true)}
	return update_layout(state, attackers, defenders)

static func update_layout(previous: Dictionary, attackers: Array, defenders: Array) -> Dictionary:
	if previous.is_empty() or (attackers.is_empty() and defenders.is_empty()):
		return {}
	var state: Dictionary = previous.duplicate(true)
	var first: Dictionary = attackers[0] if not attackers.is_empty() else defenders[0]
	state["size"] = required_size(attackers.size(), defenders.size(), first.size)
	state["positions"] = {}
	state["has_player"] = false
	state["attackers"] = []
	state["defenders"] = []
	for side in [0, 1]:
		var row: Array = attackers if side == 0 else defenders
		var offset: float = -(row.size() - 1) * state.cell.x * 0.5
		var row_y: float = state.cell.y * (-0.5 if side == 0 else 0.5)
		for i in row.size():
			var unit: Dictionary = row[i]
			if int(unit.faction) == 1:
				state.has_player = true
			state.positions[unit.id] = state.center + state.config.axis_x * (offset + i * state.cell.x) + state.config.axis_y * row_y
			state["attackers" if side == 0 else "defenders"].append(unit.id)
	state["bounds"] = manager_bounds(state)
	return state

## CombatManager uses sizeDelta times lossyScale, centered on transform.position;
## it does not compute rotated corner AABBs or account for a noncenter pivot.
static func manager_bounds(state: Dictionary) -> Rect2:
	var size: Vector2 = state.size * state.config.scale
	return Rect2(state.center - size * 0.5, size)

static func contains(state: Dictionary, position: Vector2) -> bool:
	if state.is_empty():
		return false
	var transform := Transform2D(state.config.axis_x, state.config.axis_y, state.center)
	var local: Vector2 = transform.affine_inverse() * position
	var minimum: Vector2 = -state.config.pivot * state.size
	# Unity Rect.Contains includes minimum, excludes maximum.
	return local.x >= minimum.x and local.y >= minimum.y and local.x < minimum.x + state.size.x and local.y < minimum.y + state.size.y

static func overlaps(a: Rect2, b: Rect2) -> bool:
	# Bounds.Intersects includes touching edges, unlike the separation solver.
	return a.position.x <= b.end.x and a.end.x >= b.position.x and a.position.y <= b.end.y and a.end.y >= b.position.y

static func potential_bounds(units: Array) -> Rect2:
	if units.is_empty():
		return Rect2()
	var center := Vector2.ZERO
	var players: int = 0
	for unit in units:
		center += unit.position
		if int(unit.faction) == 1:
			players += 1
	center /= units.size()
	# Source preview uses player-vs-other counts and NO canvas scaling/clamping.
	var size := required_size(players, units.size() - players, units[0].size)
	return Rect2(center - size * 0.5, size)

static func can_ai_join(position: Vector2, state: Dictionary, attack_radius: float) -> bool:
	return not state.is_empty() and position.distance_to(state.center) <= attack_radius * 1.5

static func drop_result(card_id: int, position: Vector2, state: Dictionary, player_is_attacker: bool, card_size: Vector2, board: Rect2, top_margin: float) -> Dictionary:
	if state.is_empty() or not state.positions.has(card_id):
		return {"flee": false, "position": position}
	if not contains(state, position) and player_is_attacker and card_id in state.attackers:
		return {"flee": true, "position": Board.enforce_placement(position, Board.stack_state(card_id, position, card_size, 1), board, top_margin)}
	return {"flee": false, "position": state.positions[card_id]}

## EndCombat uses CURRENT positions (not cached slots), creates singleton stacks,
## then clamps each independently. It does not spread survivors into a new grid.
static func survivor_positions(units: Array, board: Rect2, top_margin: float) -> Dictionary:
	var result: Dictionary = {}
	for unit in units:
		result[unit.id] = Board.enforce_placement(unit.position, Board.stack_state(unit.id, unit.position, unit.size, 1), board, top_margin)
	return result

## Dictionary iteration order is combat registration order, as in the manager.
static func task_at_position(layouts: Dictionary, position: Vector2) -> int:
	for id in layouts:
		if contains(layouts[id], position):
			return int(id)
	return -1

static func closest_relevant_combat(layouts: Dictionary, position: Vector2, aggro_radius: float) -> int:
	var best_id: int = -1
	var best_distance: float = aggro_radius * aggro_radius
	for id in layouts:
		var state: Dictionary = layouts[id]
		if state.is_empty() or not state.get("has_player", false):
			continue
		var distance: float = position.distance_squared_to(state.center)
		if distance < best_distance:
			best_distance = distance
			best_id = int(id)
	return best_id
