extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func fresh(catalog = null, scene_name: String = "Main"):
	if catalog == null:
		catalog = Catalog.new()
		catalog.configure({"cards": [
			{"guid": "p", "script_class": "CardDefinition", "fields": {"id": "p", "category": 2, "faction": 1, "combatType": 1}},
			{"guid": "m", "script_class": "CardDefinition", "fields": {"id": "m", "category": 9, "faction": 2, "combatType": 1}}
		]})
	var s = Session.new()
	s.configure(catalog, 42, scene_name)
	return s
func fixture(s, player: String = "p", mob: String = "m") -> Array:
	var p: int = s.spawn_card(player)
	var m: int = s.spawn_card(mob)
	var later: int = s.spawn_card(player)
	var id: int = s.combat.start_combat([p], [m])
	check(s.combat.add_combatants(id, [later]), "late attacker joins")
	return [p, m, later, id]
func tied_actor(s, ids: Array) -> int:
	var task: Dictionary = s.combat.tasks[ids[3]]
	task.erase("execution")
	task.progress[ids[0]] = 0.0
	task.progress[ids[1]] = 100.0
	task.progress[ids[2]] = 100.0
	s.combat.resolve_turn(ids[3])
	return int(task.execution.actor)
func _init() -> void:
	_test_constructor()
	_test_join_visibility()
	var s = fresh()
	var ids := fixture(s)
	var task: Dictionary = s.combat.tasks[ids[3]]
	check(task.combatants == ids.slice(0, 3), "historical join order crosses factions")
	check(tied_actor(s, ids) == ids[1], "earlier defender wins progress tie over late attacker")
	task.erase("execution")
	s.combat.dragged[ids[1]] = true
	check(tied_actor(s, ids) == ids[2], "dragged earlier actor is skipped without reordering")
	s.combat.dragged.clear()
	task.erase("execution")
	var snapshot: Dictionary = Codec.capture(s)
	var restored = fresh(s.catalog)
	check(Codec.restore(restored, JSON.parse_string(JSON.stringify(snapshot))).ok, "order survives JSON checkpoint")
	check(restored.combat.tasks[ids[3]].combatants == ids.slice(0, 3), "restored interleaved join order retained")
	check(tied_actor(restored, ids) == ids[1], "restored tie chooses historical defender")
	var before: Dictionary = Codec.capture(restored)
	var malformed: Array = [null, "order", [], [ids[0], ids[1]], [ids[0], ids[1], ids[1]], [ids[0], ids[1], 9999], [ids[0], ids[1], true], [ids[0], ids[1], 1.5], [ids[0], ids[1], ids[2], ids[2]]]
	for order in malformed:
		var bad: Dictionary = snapshot.duplicate(true)
		bad.session.combat.tasks[0].combatants = order
		check(not Codec.restore(restored, bad).ok, "invalid explicit order rejected: " + str(order))
		check(Codec.capture(restored) == before, "invalid explicit order preserves entire state and RNG")
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.session.combat.tasks[0].erase("combatants")
	check(Codec.restore(restored, legacy).ok, "legacy combat snapshot accepted")
	check(restored.combat.tasks[ids[3]].combatants == [ids[0], ids[2], ids[1]], "legacy fallback uses previous grouped order")
	check(tied_actor(restored, ids) == ids[2], "legacy does not invent unavailable join history")
	check(Codec.capture(restored).session.combat.tasks[0].combatants == [ids[0], ids[2], ids[1]], "legacy resave persists fallback explicitly")
	# Nonterminal fleeing removes the old slot; rejoining appends at the tail.
	s.combat.flee(ids[0])
	check(task.combatants == [ids[1], ids[2]], "flee removes historical slot")
	s.combat.add_combatants(ids[3], [ids[0], ids[0]])
	check(task.combatants == [ids[1], ids[2], ids[0]], "rejoin appended once, duplicate addition ignored")
	s.combat.remove_combatant(ids[2])
	check(task.combatants == [ids[1], ids[0]], "external removal preserves remaining order")
	# Merge constructs a fresh source faction-grouped list, not concatenated history.
	var extra: int = s.spawn_card("m")
	var player: int = s.spawn_card("p")
	var other: int = s.combat.start_combat([player], [extra])
	var merged: int = s.combat.merge_combats([ids[3], other])
	var merged_task: Dictionary = s.combat.tasks[merged]
	check(merged_task.combatants == merged_task.attackers + merged_task.defenders, "merge starts fresh faction-grouped source order")
	# Lethal cleanup removes the dead combatant before the scaled death wait.
	merged_task.progress[player] = 10000.0
	s.combat.resolve_turn(merged)
	var target: int = merged_task.execution.target
	s.cards[target].health = 0
	merged_task.execution.phase = "return"
	merged_task.execution.remaining = 0.0
	s.combat.tick(0.0, 0.1)
	check(target not in merged_task.combatants and target not in merged_task.progress, "death cleanup removes both order and progress")
	check(Codec.restore(fresh(s.catalog), Codec.capture(s)).ok, "post-death order checkpoint validates")
	_test_private()
	print("Combat order checks: ", checks, "; failures: ", failures)
	quit(0 if failures == 0 else 1)
func _test_private() -> void:
	if not FileAccess.file_exists("res://data/stackcraft.json"):
		print("SKIP: private source combat order checks (source data unavailable)")
		return
	var catalog = Catalog.new()
	check(catalog.load_file() == OK, "private catalog loads")
	var player := ""
	var mob := ""
	for entry in catalog.data.get("cards", []):
		var f: Dictionary = entry.get("fields", {})
		if int(f.get("combatType", 0)) not in [0, 1]: continue
		if int(f.get("category", 0)) == 2 and int(f.get("faction", 0)) == 1: player = str(entry.guid)
		if int(f.get("category", 0)) == 9 and int(f.get("faction", 0)) == 2: mob = str(entry.guid)
	check(not player.is_empty() and not mob.is_empty(), "actual melee player and mob available")
	if player.is_empty() or mob.is_empty(): return
	for scene_name in ["Main", "Island"]:
		var s = fresh(catalog, scene_name)
		var ids := fixture(s, player, mob)
		check(tied_actor(s, ids) == ids[1], "actual source cards preserve late-join tie order in " + scene_name)
		var restored = fresh(catalog, scene_name)
		check(Codec.restore(restored, JSON.parse_string(JSON.stringify(Codec.capture(s)))).ok, "actual source in-flight order checkpoint restores")
		check(tied_actor(restored, ids) == ids[1], "actual source tie order survives Continue")

func _test_constructor() -> void:
	var s = fresh()
	var attackers: Array = [s.spawn_card("p"), s.spawn_card("p")]
	var defenders: Array = [s.spawn_card("m"), s.spawn_card("m")]
	var ordered: Array = attackers + defenders
	var expected := RandomNumberGenerator.new()
	expected.state = s.rng.state
	var progress: Dictionary = {}
	for id in ordered: progress[id] = expected.randf_range(0.0, 0.5)
	var constructor_state: int = expected.state
	var seen: Array = []
	var observer := func(kind: String, payload: Dictionary):
		if kind != "combat_entered": return
		var task: Dictionary = s.combat.tasks[payload.combat_id]
		check(task.combatants == ordered, "first and later entry observe full constructor order")
		check(task.progress == progress, "all progress exists before entry; attacker then defender RNG")
		check(s.rng.state == (constructor_state if seen.is_empty() else expected.state), "constructor consumes all draws before callback RNG")
		check(s.cards[payload.card_id].stack_id == -1 and s.combat.membership.has(payload.card_id), "entry still follows detach and membership")
		seen.append(payload.card_id)
		check(s.rng.randf() == expected.randf(), "callback RNG cannot interleave initial progress draws")
	s.event_occurred.connect(observer)
	var task_id: int = s.combat.start_combat(attackers, defenders)
	s.event_occurred.disconnect(observer)
	check(seen == ordered and s.rng.state == expected.state, "exactly one entry and one initial progress draw per member")
	var before: int = s.rng.state
	check(s.combat.start_combat(attackers, defenders) == -1 and s.rng.state == before, "invalid already-entered start draws nothing")
	check(s.combat.start_combat([], defenders) == -1 and s.rng.state == before, "empty start draws nothing")
	var recruit: int = s.spawn_card("p")
	expected.state = s.rng.state
	var join_seen: Array = []
	var join_observer := func(kind: String, payload: Dictionary):
		if kind != "combat_entered": return
		join_seen.append(payload.card_id)
		check(not s.combat.tasks[task_id].progress.has(recruit), "AddCombatants still enters before initializing progress")
		check(s.rng.randf() == expected.randf(), "join callback precedes its progress RNG")
	s.event_occurred.connect(join_observer)
	check(s.combat.add_combatants(task_id, [recruit]), "join remains available")
	s.event_occurred.disconnect(join_observer)
	check(join_seen == [recruit] and s.combat.tasks[task_id].progress[recruit] == expected.randf_range(0.0, 0.5), "join draws exactly once after entry")
	check(s.rng.state == expected.state, "join RNG state preserved")
	var snapshot: Dictionary = Codec.capture(s)
	var restored = fresh(s.catalog)
	check(Codec.restore(restored, snapshot).ok and Codec.capture(restored) == snapshot, "restore preserves progress and RNG without constructor draws")

func _test_join_visibility() -> void:
	var s = fresh()
	var p: int = s.spawn_card("p")
	var m: int = s.spawn_card("m")
	var p1: int = s.spawn_card("p")
	var m1: int = s.spawn_card("m")
	var p2: int = s.spawn_card("p")
	var id: int = s.combat.start_combat([m], [p], false)
	var task: Dictionary = s.combat.tasks[id]
	var expected := RandomNumberGenerator.new()
	expected.state = s.rng.state
	var entries: Array = []
	var recruits: Array = [p1,m1,p2]
	var prior_progress: Dictionary = task.progress.duplicate()
	var observer := func(kind: String, payload: Dictionary):
		if kind != "combat_entered": return
		var incoming: int = int(payload.card_id)
		entries.append(incoming)
		check(task.combatants == [m,p] + recruits.slice(0,entries.size()), "both source lists admit current recruit at entry, not any later recruit")
		check(incoming in task.defenders if incoming in [p1,p2] else incoming in task.attackers, "side list precedes entry including reversed player orientation")
		check(s.combat.membership.get(incoming,-1) == id and s.cards[incoming].stack_id == -1, "entry observes ordinary source membership/detach")
		check(task.progress == prior_progress and not task.progress.has(incoming), "old and prior incoming progress exist; current recruit not randomized yet")
		check(s.rng.randf() == expected.randf(),"callback RNG still precedes this recruit's progress draw")
		prior_progress[incoming] = expected.randf_range(0.0,0.5)
	var selected: Array = []
	s.combat.resize_overlap_selector = func(task_id: int):
		selected.append(task_id)
		check(task.combatants == [m,p] + recruits and task.progress == prior_progress, "resize observes all valid recruits and their source-ordered draws")
		return []
	s.event_occurred.connect(observer)
	check(s.combat.add_combatants(id,[p1,p1,-1,m1,m1,p2]), "all valid factions added; invalid and duplicate entries skipped")
	s.event_occurred.disconnect(observer)
	check(entries == recruits and selected == [id], "three ordered entry boundaries, then one resize")
	check(s.rng.state == expected.state, "only one progress draw per admitted recruit")
