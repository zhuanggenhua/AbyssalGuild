extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Layout = preload("res://scripts/model/combat_layout.gd")
const Geometry = preload("res://scripts/model/combat_merge_geometry.gd")
var checks: int = 0
var failures: int = 0
var session
var layouts: Dictionary = {}
var pre_calls: int = 0
var resize_calls: int = 0
var resized_center := Vector2.ZERO
var cfg := {"ok": true, "axis_x": Vector2.RIGHT, "axis_y": Vector2.DOWN, "scale": Vector2.ONE, "pivot": Vector2(0.5, 0.5)}
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func fresh() -> void:
	var catalog = Catalog.new()
	catalog.configure({"cards": [{"guid": "p", "fields": {"category": 2, "faction": 1}}, {"guid": "m", "fields": {"category": 9, "faction": 2}}]})
	session = Session.new()
	session.configure(catalog, 123)
	layouts.clear()
	pre_calls = 0
	resize_calls = 0
	session.combat.start_overlap_selector = _before_start
	session.combat.resize_overlap_selector = _after_resize
func records(ids: Array) -> Array:
	var result: Array = []
	for id in ids:
		result.append({"id": id, "position": session.cards[id].position, "size": Vector2(1, 2), "faction": int(session.catalog.fields(session.cards[id].definition_guid).faction)})
	return result
func sync_geometry() -> void:
	layouts.clear()
	for id in session.combat.tasks:
		var task: Dictionary = session.combat.tasks[id]
		var previous: Dictionary = task.get("layout", {})
		if not previous.is_empty(): previous.config = cfg
		var layout: Dictionary = Layout.initialize(records(task.attackers), records(task.defenders), cfg, Rect2(-100, -100, 200, 200), 0) if previous.is_empty() else Layout.update_layout(previous, records(task.attackers), records(task.defenders))
		task.layout = layout
		layouts[id] = layout
		for card in layout.positions: session.cards[card].position = layout.positions[card]
func _before_start(a: Array, d: Array) -> Array:
	pre_calls += 1
	sync_geometry()
	return Geometry.before_start(records(a), records(d), layouts)
func _after_resize(id: int) -> Array:
	resize_calls += 1
	sync_geometry()
	resized_center = layouts[id].center
	return Geometry.after_resize(id, layouts)
func spawn(guid: String, x: float) -> int:
	return session.spawn_card(guid, Vector2(x, 0))
func expected_rng(draws: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.state = session.rng.state
	for i in draws: rng.randf_range(0, 0.5)
	return rng.state
func _init() -> void:
	fresh()
	var p: int = spawn("p", 0)
	var m: int = spawn("m", 0)
	var first: int = session.combat.start_combat([p], [m])
	sync_geometry()
	var p2: int = spawn("p", 0)
	var m2: int = spawn("m", 0)
	var expected: int = expected_rng(4)
	var ended: Array = []
	session.event_occurred.connect(func(kind: String, _payload: Dictionary):
		if kind == "combat_ended": ended.append(kind))
	var merged: int = session.combat.start_combat([m2], [p2], false)
	check(merged > first and session.combat.tasks.size() == 1, "pre-start overlap creates one replacement")
	check(session.combat.tasks[merged].player_is_attacker and session.combat.tasks[merged].attackers == [p2, p] and session.combat.tasks[merged].defenders == [m2, m], "new fighters first, faction normalize mob initiation")
	check(session.rng.state == expected, "pre-start merging draws exactly once per final fighter")
	check(pre_calls == 2, "internal merge creation never recursively calls selector")
	check(ended.is_empty() and session.stacks.is_empty(), "merge cleanup neither emits end nor returns survivors")
	check(not session.combat.tasks[merged].has("layout"), "replacement layout is fresh, not stale old center")
	sync_geometry()
	var saved: Dictionary = session.combat.save_state()
	var staged: Dictionary = session.combat.stage_state(JSON.parse_string(JSON.stringify(saved)), session.cards)
	check(staged.ok, "merged snapshot validates cached geometry")
	var center: Vector2 = session.combat.tasks[merged].layout.center
	session.combat.apply_state(staged)
	sync_geometry()
	check(session.combat.tasks[merged].layout.center == center, "restored layout keeps center and rebuilds derived bounds")
	var far_p: int = spawn("p", 20)
	var far_m: int = spawn("m", 20)
	expected = expected_rng(2)
	var far: int = session.combat.start_combat([far_p], [far_m])
	check(far > merged and session.combat.tasks.size() == 2 and session.rng.state == expected, "nonoverlap creates unchanged independent fight")
	fresh()
	p = spawn("p", 0)
	m = spawn("m", 0)
	first = session.combat.start_combat([m], [p], false)
	p2 = spawn("p", 4)
	m2 = spawn("m", 4)
	far = session.combat.start_combat([p2], [m2])
	sync_geometry()
	center = session.combat.tasks[first].layout.center
	var entrants: Array = []
	for i in 6: entrants.append(spawn("p", -20))
	expected = expected_rng(6 + 10) # Enter each joiner, then reinitialize final group.
	check(session.combat.add_combatants(first, entrants), "join succeeds before resize merge")
	check(session.combat.tasks.size() == 1 and resize_calls == 1, "resize overlap merges once")
	check(resized_center == center, "resize selector uses cached center, not entrant position average")
	check(session.rng.state == expected, "join draws follow source enter-then-merge sequence")
	merged = session.combat.membership[p]
	check(session.combat.tasks[merged].attackers == [p] + entrants + [p2], "resized source initial fighters precede other registered task")
	check(session.combat.tasks[merged].player_is_attacker and session.stacks.is_empty(), "resized mob initiated fight normalizes without survivor stacks")
	var invalid_p: int = spawn("p", 50)
	var invalid_m: int = spawn("m", 50)
	var rng_before: int = session.rng.state
	var next_before: int = session.combat._next_id
	session.combat.start_overlap_selector = func(_a: Array, _d: Array): return [999999]
	check(session.combat.start_combat([invalid_p], [invalid_m]) == -1 and session.rng.state == rng_before and session.combat._next_id == next_before, "unknown selector IDs fail without mutation or RNG")
	for bad in [null, {}, ["1"], [1.5]]:
		session.combat.start_overlap_selector = func(_a: Array, _d: Array): return bad
		check(session.combat.start_combat([invalid_p], [invalid_m]) == -1, "malformed selector output rejected")
	check(session.combat.merge_combats([merged], [999999], []) == -1 and session.combat.tasks.has(merged), "invalid explicit additional fighters do not destroy old task")
	var recursion: Array = []
	session.combat.start_overlap_selector = func(a: Array, d: Array):
		recursion.append(session.combat.start_combat(a, d))
		return []
	check(session.combat.start_combat([invalid_p], [invalid_m]) > 0 and recursion == [-1], "selector cannot recursively create combat")
	var extra: int = spawn("p", 60)
	var keep_task: int = session.combat.membership[invalid_p]
	session.combat.resize_overlap_selector = func(_id: int): return [999999]
	check(session.combat.add_combatants(keep_task, [extra]) and session.combat.membership[extra] == keep_task, "invalid resize selection retains successful entrant without merging")
	var stale_p: int = spawn("p", 80)
	var stale_m: int = spawn("m", 80)
	rng_before = session.rng.state
	session.combat.start_overlap_selector = func(_a: Array, _d: Array):
		session._remove_card(stale_p)
		return []
	check(session.combat.start_combat([stale_p], [stale_m]) == -1 and session.rng.state == rng_before, "input removed during callback revalidated before task creation")
	var before_order: Array = session.combat.tasks.keys()
	var expected_players: Array = []
	for id in before_order: expected_players.append_array(session.combat.tasks[id].attackers)
	var reverse_ids: Array = before_order.duplicate()
	reverse_ids.reverse()
	reverse_ids.append(before_order[0])
	var unified: int = session.combat.merge_combats(reverse_ids)
	check(unified > 0 and session.combat.tasks[unified].attackers == expected_players, "explicit duplicate/reordered task IDs retain registration order")
	# Pure inclusive-edge geometry and registration-order selection.
	var left := {"center": Vector2.ZERO, "size": Vector2(2, 2), "config": cfg}
	var right := {"center": Vector2(2, 0), "size": Vector2(2, 2), "config": cfg}
	check(Geometry.after_resize(4, {4: left, 9: right}) == [9], "resize overlap includes exact edge contact")
	check(Geometry.after_resize(0, {4: left}).is_empty(), "missing resized layout yields no candidates")
	print("Combat merge checks: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
