extends SceneTree
const Layout = preload("res://scripts/model/combat_layout.gd")
var checks: int = 0
var failures: int = 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func unit(id: int, pos: Vector2, faction: int = 1, size: Vector2 = Vector2(1, 2)) -> Dictionary:
	return {"id": id, "position": pos, "faction": faction, "size": size}
func _init() -> void:
	var cfg := {"ok": true, "axis_x": Vector2.RIGHT, "axis_y": Vector2.DOWN, "scale": Vector2.ONE, "pivot": Vector2(0.5, 0.5)}
	var board := Rect2(-10, -10, 20, 20)
	var attackers := [unit(1, Vector2(-2, 0)), unit(2, Vector2(2, 0))]
	var defenders := [unit(3, Vector2(0, 3), 2)]
	check(Layout.required_size(2, 1, Vector2(1, 2)).is_equal_approx(Vector2(2.4, 4.4)), "size includes cell and outer margins")
	var state: Dictionary = Layout.initialize(attackers, defenders, cfg, board, 1.5)
	check(state.center == Vector2(0, 1), "initial center averages every unit")
	check(state.positions[1].is_equal_approx(Vector2(-0.55, -0.05)) and state.positions[2].is_equal_approx(Vector2(0.55, -0.05)), "attacker row centered horizontally at negative Z")
	check(state.positions[3].is_equal_approx(Vector2(0, 2.05)), "short defender row independently centered")
	check(state.bounds.size.is_equal_approx(Vector2(2.4, 4.4)), "world bounds reflect full fight footprint")
	check(Layout.contains(state, state.bounds.position), "minimum corner included")
	check(not Layout.contains(state, state.bounds.end), "maximum corner excluded")
	check(Layout.overlaps(state.bounds, Rect2(state.bounds.end, Vector2.ONE)), "merge bounds include edge contact")
	check(not Layout.overlaps(state.bounds, Rect2(state.bounds.end + Vector2(0.01, 0), Vector2.ONE)), "separated rectangles do not merge")
	check(Layout.can_ai_join(state.center + Vector2(3, 0), state, 2) and not Layout.can_ai_join(state.center + Vector2(3.01, 0), state, 2), "AI join radius is inclusive 1.5 times attack radius")
	check(Layout.drop_result(1, Vector2(20, 20), state, true, Vector2(1, 2), board, 1.5).position == Vector2(9.5, 7.5), "flee position clamps to board and top margin")
	check(Layout.drop_result(1, Vector2(20, 20), state, true, Vector2(1, 2), board, 1.5).flee, "player attacker outside can flee")
	check(not Layout.drop_result(1, Vector2(20, 20), state, false, Vector2(1, 2), board, 1.5).flee, "mob initiated fight cannot flee")
	check(Layout.drop_result(3, Vector2(20, 20), state, true, Vector2(1, 2), board, 1.5).position == state.positions[3], "defender snaps back to slot")
	var enlarged := [unit(1, Vector2.ZERO, 1, Vector2(3, 4))]
	var updated: Dictionary = Layout.update_layout(state, enlarged, defenders)
	check(updated.cell == state.cell and updated.size.is_equal_approx(Vector2(3.3, 8.4)), "resize keeps original cell spacing but recomputes rectangle")
	check(updated.center == state.center and state.positions.size() == 3, "resize neither recenters nor mutates previous state")
	var near_edge: Dictionary = Layout.initialize([unit(4, Vector2(10, 10))], defenders, cfg, board, 1.5)
	check(is_equal_approx(near_edge.center.y, 6.3), "initial rectangle honors top margin")
	var preview: Rect2 = Layout.potential_bounds(attackers + defenders)
	check(preview.get_center() == Vector2(0, 1) and preview.size.is_equal_approx(Vector2(2.4, 4.4)), "potential fight bounds use faction counts")
	var survivors: Dictionary = Layout.survivor_positions([unit(1, Vector2(20, 20)), unit(2, Vector2(20, 20))], board, 1.5)
	check(survivors[1] == survivors[2] and survivors[1] == Vector2(9.5, 7.5), "survivors clamp actual positions without invented spread")
	check(Layout.initialize([], defenders, cfg, board, 1.5).is_empty(), "empty initial side rejected")
	check(Layout.task_at_position({5: state, 6: state}, state.center) == 5, "join chooses first containing combat in registration order")
	check(Layout.closest_relevant_combat({5: state}, state.center + Vector2(5, 0), 5) == -1, "AI aggro comparison excludes exact radius")
	check(Layout.closest_relevant_combat({5: state}, state.center + Vector2(4.9, 0), 5) == 5, "AI seeks nearby fight involving players")
	var neutral_state: Dictionary = state.duplicate(true)
	neutral_state.has_player = false
	check(Layout.closest_relevant_combat({5: neutral_state}, state.center, 5) == -1, "AI ignores fight without player involvement")
	_test_import()
	if FileAccess.file_exists("res://data/stackcraft.json"):
		var imported = JSON.parse_string(FileAccess.get_file_as_string("res://data/stackcraft.json"))
		for scene_name in ["Main", "Island"]:
			check(Layout.imported_config(imported, scene_name).ok, "private imported transform chain resolves: " + scene_name)
	print("Combat layout checks: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
func _test_import() -> void:
	var data := {"scenes": [{"name": "Test", "documents": [{"script_class": "CombatManager", "fields": {"combatRectPrefab": {"guid": "rect"}}}]}], "referenced_prefabs": [
		{"guid": "rect", "documents": [
			{"script_class": "CombatRect", "fields": {"m_GameObject": {"fileID": "r"}}},
			{"object_type": "RectTransform", "file_id": "rt", "fields": {"m_GameObject": {"fileID": "r"}, "m_Father": {"fileID": "0"}, "m_LocalScale": {"x": 2, "y": 3, "z": 1}, "m_Pivot": {"x": 0.5, "y": 0.5}}}]},
		{"guid": "canvas", "documents": [
			{"script_class": "WorldCanvas", "fields": {"m_GameObject": {"fileID": "c"}}},
			{"object_type": "RectTransform", "file_id": "ct", "fields": {"m_GameObject": {"fileID": "c"}, "m_Father": {"fileID": "0"}, "m_LocalRotation": {"x": 0.7071068, "y": 0, "z": 0, "w": 0.7071068}}}]}]}
	var cfg: Dictionary = Layout.imported_config(data, "Test")
	check(cfg.ok and cfg.axis_x.is_equal_approx(Vector2(2, 0)) and cfg.axis_y.is_equal_approx(Vector2(0, 3)), "import quaternion and scales map local XY onto XZ")
	var state: Dictionary = Layout.initialize([unit(1, Vector2.ZERO)], [unit(2, Vector2.ZERO, 2)], cfg, Rect2(-50, -50, 100, 100), 0)
	check(state.bounds.size.is_equal_approx(Vector2(2.6, 13.2)) and state.positions[1].is_equal_approx(Vector2(0, -3.15)), "scaled target slots and rectangle")
	check(not Layout.imported_config(data, "Missing").ok, "missing source config does not invent geometry")
	data.referenced_prefabs[1].documents[1].fields.m_Father.fileID = "ct"
	check(not Layout.imported_config(data, "Test").ok, "cyclic transform input rejected")
